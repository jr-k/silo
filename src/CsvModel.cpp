#include "CsvModel.h"

#include <QCollator>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QStringDecoder>
#include <QUrl>

#include <algorithm>

namespace {
constexpr qint64 kMaxBytes = 32 * 1024 * 1024;
constexpr int kMaxRows = 200000;

QString expandPath(const QString &path)
{
    QString p = path.trimmed();
    if (p.startsWith(QStringLiteral("file://")))
        p = QUrl(p).toLocalFile();
    if (p.startsWith(QStringLiteral("~/")))
        p = QDir::homePath() + p.mid(1);
    return p;
}

QChar detectDelimiter(const QString &text)
{
    // Score candidates on the first lines: the delimiter that yields the most
    // consistent field count (and more than one field) wins.
    const QList<QChar> candidates{QLatin1Char(','), QLatin1Char(';'), QLatin1Char('\t'), QLatin1Char('|')};
    QChar best = QLatin1Char(',');
    double bestScore = -1;
    const QStringList lines = text.left(20000).split(QLatin1Char('\n'), Qt::SkipEmptyParts).mid(0, 20);
    for (const QChar candidate : candidates) {
        QList<int> counts;
        for (const QString &line : lines)
            counts.append(int(line.count(candidate)));
        if (counts.isEmpty())
            continue;
        const int first = counts.first();
        if (first == 0)
            continue;
        int consistent = 0;
        for (int count : counts)
            consistent += count == first;
        const double score = double(consistent) / counts.size() * 1000 + first;
        if (score > bestScore) {
            bestScore = score;
            best = candidate;
        }
    }
    return best;
}
} // namespace

CsvModel::CsvModel(QObject *parent) : QAbstractTableModel(parent) {}

int CsvModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_visible.size());
}

int CsvModel::columnCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_columns;
}

QVariant CsvModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_visible.size() || index.column() >= m_columns)
        return {};
    if (role != Qt::DisplayRole)
        return {};
    const QStringList &row = m_rows.at(m_visible.at(index.row()));
    return index.column() < row.size() ? row.at(index.column()) : QString();
}

QVariant CsvModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if (role != Qt::DisplayRole)
        return {};
    return orientation == Qt::Horizontal ? QVariant(headerText(section)) : QVariant(section + 1);
}

QHash<int, QByteArray> CsvModel::roleNames() const
{
    return {{Qt::DisplayRole, "display"}};
}

QString CsvModel::delimiterName() const
{
    switch (m_delimiter.unicode()) {
    case '\t': return QStringLiteral("Tab");
    case ';': return QStringLiteral("Semicolon");
    case '|': return QStringLiteral("Pipe");
    default: return QStringLiteral("Comma");
    }
}

void CsvModel::setSource(const QString &source)
{
    if (m_source == source)
        return;
    m_source = source;
    reload();
}

void CsvModel::reload()
{
    beginResetModel();
    m_rows.clear();
    m_visible.clear();
    m_columns = 0;
    m_truncated = false;
    m_sortColumn = -1;
    m_sortDescending = false;
    m_crlf = false;
    m_trailingNewline = true;
    m_bom = false;
    if (m_dirty) {
        m_dirty = false;
        emit dirtyChanged();
    }

    QFile file(expandPath(m_source));
    if (file.open(QIODevice::ReadOnly)) {
        QByteArray bytes = file.read(kMaxBytes);
        m_truncated = file.bytesAvailable() > 0;
        if (bytes.startsWith("\xEF\xBB\xBF")) {
            bytes.remove(0, 3);
            m_bom = true;
        }
        QStringDecoder decoder(QStringDecoder::Utf8);
        QString text = decoder.decode(bytes);
        if (decoder.hasError())
            text = QString::fromLatin1(bytes);
        parse(text);
    }
    rebuildVisible();
    endResetModel();
    emit sourceChanged();
    emit sortChanged();
    emit layoutChanged();
}

// RFC 4180-ish parser: quoted fields may contain delimiters, doubled quotes and newlines.
void CsvModel::parse(const QString &text)
{
    m_delimiter = detectDelimiter(text);
    m_crlf = text.contains(QStringLiteral("\r\n"));
    m_trailingNewline = text.isEmpty() || text.endsWith(QLatin1Char('\n')) || text.endsWith(QLatin1Char('\r'));
    QStringList row;
    QString field;
    bool quoted = false;
    const qsizetype size = text.size();
    for (qsizetype i = 0; i < size; ++i) {
        const QChar c = text.at(i);
        if (quoted) {
            if (c == QLatin1Char('"')) {
                if (i + 1 < size && text.at(i + 1) == QLatin1Char('"')) {
                    field.append(QLatin1Char('"'));
                    ++i;
                } else {
                    quoted = false;
                }
            } else {
                field.append(c);
            }
            continue;
        }
        if (c == QLatin1Char('"') && field.isEmpty()) {
            quoted = true;
        } else if (c == m_delimiter) {
            row.append(field);
            field.clear();
        } else if (c == QLatin1Char('\n') || c == QLatin1Char('\r')) {
            if (c == QLatin1Char('\r') && i + 1 < size && text.at(i + 1) == QLatin1Char('\n'))
                ++i;
            row.append(field);
            field.clear();
            if (!(row.size() == 1 && row.first().isEmpty())) {
                m_columns = qMax(m_columns, int(row.size()));
                m_rows.append(row);
                if (m_rows.size() >= kMaxRows) {
                    m_truncated = true;
                    return;
                }
            }
            row.clear();
        } else {
            field.append(c);
        }
    }
    if (!field.isEmpty() || !row.isEmpty()) {
        row.append(field);
        m_columns = qMax(m_columns, int(row.size()));
        m_rows.append(row);
    }

    // Header heuristic (unless the user chose): the first row has no numeric
    // cell while the second one has at least one.
    if (!m_headerExplicit && m_rows.size() >= 2) {
        double value = 0;
        bool firstNumeric = false, secondNumeric = false;
        for (const QString &cell : m_rows.at(0))
            firstNumeric |= looksNumeric(cell, &value);
        for (const QString &cell : m_rows.at(1))
            secondNumeric |= looksNumeric(cell, &value);
        const bool header = !firstNumeric;
        Q_UNUSED(secondNumeric);
        if (header != m_hasHeader) {
            m_hasHeader = header;
            emit hasHeaderChanged();
        }
    }
}

bool CsvModel::looksNumeric(const QString &text, double *value)
{
    QString t = text.trimmed();
    if (t.isEmpty())
        return false;
    t.remove(QLatin1Char(' '));
    if (t.count(QLatin1Char(',')) == 1 && !t.contains(QLatin1Char('.')))
        t.replace(QLatin1Char(','), QLatin1Char('.'));
    bool ok = false;
    const double v = t.toDouble(&ok);
    if (ok && value)
        *value = v;
    return ok;
}

void CsvModel::setHasHeader(bool hasHeader)
{
    m_headerExplicit = true;
    if (m_hasHeader == hasHeader)
        return;
    m_hasHeader = hasHeader;
    emit hasHeaderChanged();
    beginResetModel();
    rebuildVisible();
    endResetModel();
    emit layoutChanged();
}

void CsvModel::setFilter(const QString &filter)
{
    if (m_filter == filter)
        return;
    m_filter = filter;
    emit filterChanged();
    beginResetModel();
    rebuildVisible();
    endResetModel();
    emit layoutChanged();
}

void CsvModel::toggleSort(int column)
{
    if (column < 0 || column >= m_columns)
        return;
    if (m_sortColumn != column) {
        m_sortColumn = column;
        m_sortDescending = false;
    } else if (!m_sortDescending) {
        m_sortDescending = true;
    } else {
        m_sortColumn = -1;
        m_sortDescending = false;
    }
    emit sortChanged();
    beginResetModel();
    rebuildVisible();
    endResetModel();
    emit layoutChanged();
}

void CsvModel::rebuildVisible()
{
    m_visible.clear();
    const QString needle = m_filter.trimmed();
    for (int i = firstDataRow(); i < m_rows.size(); ++i) {
        if (needle.isEmpty()) {
            m_visible.append(i);
            continue;
        }
        for (const QString &cell : m_rows.at(i)) {
            if (cell.contains(needle, Qt::CaseInsensitive)) {
                m_visible.append(i);
                break;
            }
        }
    }

    if (m_sortColumn < 0)
        return;
    const int column = m_sortColumn;
    // Numeric sort when every non-empty cell parses as a number.
    bool numeric = true;
    QHash<int, double> numbers;
    for (int rowIndex : m_visible) {
        const QStringList &row = m_rows.at(rowIndex);
        const QString cell = column < row.size() ? row.at(column) : QString();
        if (cell.trimmed().isEmpty())
            continue;
        double value = 0;
        if (!looksNumeric(cell, &value)) {
            numeric = false;
            break;
        }
        numbers.insert(rowIndex, value);
    }
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    auto cellOf = [&](int rowIndex) -> QString {
        const QStringList &row = m_rows.at(rowIndex);
        return column < row.size() ? row.at(column) : QString();
    };
    std::stable_sort(m_visible.begin(), m_visible.end(), [&](int a, int b) {
        int cmp;
        if (numeric) {
            const bool aEmpty = !numbers.contains(a), bEmpty = !numbers.contains(b);
            if (aEmpty != bEmpty)
                return bEmpty; // empties last, whatever the direction
            const double va = numbers.value(a), vb = numbers.value(b);
            cmp = va < vb ? -1 : va > vb ? 1 : 0;
        } else {
            cmp = collator.compare(cellOf(a), cellOf(b));
        }
        return m_sortDescending ? cmp > 0 : cmp < 0;
    });
}

QString CsvModel::headerText(int column) const
{
    if (column < 0 || column >= m_columns)
        return {};
    if (m_hasHeader && !m_rows.isEmpty()) {
        const QStringList &row = m_rows.first();
        const QString text = column < row.size() ? row.at(column).trimmed() : QString();
        if (!text.isEmpty())
            return text;
    }
    // Spreadsheet-style letters: A, B, …, Z, AA, AB…
    QString name;
    int n = column;
    do {
        name.prepend(QChar(QLatin1Char('A').unicode() + n % 26));
        n = n / 26 - 1;
    } while (n >= 0);
    return name;
}

int CsvModel::columnWidth(int column, int minimum, int maximum) const
{
    int longest = headerText(column).size();
    const int sample = qMin(int(m_visible.size()), 200);
    for (int i = 0; i < sample; ++i) {
        const QStringList &row = m_rows.at(m_visible.at(i));
        if (column < row.size())
            longest = qMax(longest, int(row.at(column).size()));
    }
    return qBound(minimum, longest * 7 + 24, maximum);
}

QString CsvModel::rowText(int row) const
{
    if (row < 0 || row >= m_visible.size())
        return {};
    return m_rows.at(m_visible.at(row)).join(QLatin1Char('\t'));
}

QString CsvModel::cellText(int row, int column) const
{
    if (row < 0 || row >= m_visible.size())
        return {};
    const QStringList &cells = m_rows.at(m_visible.at(row));
    return column >= 0 && column < cells.size() ? cells.at(column) : QString();
}

// ---------------------------------------------------------------- editing

void CsvModel::markDirty()
{
    if (m_dirty)
        return;
    m_dirty = true;
    emit dirtyChanged();
}

void CsvModel::resetLayout()
{
    beginResetModel();
    rebuildVisible();
    endResetModel();
    emit layoutChanged();
}

bool CsvModel::setCell(int row, int column, const QString &text)
{
    if (m_truncated || row < 0 || row >= m_visible.size() || column < 0 || column >= m_columns)
        return false;
    QStringList &cells = m_rows[m_visible.at(row)];
    while (cells.size() <= column)
        cells.append(QString());
    if (cells.at(column) == text)
        return false;
    cells[column] = text;
    markDirty();
    const QModelIndex idx = index(row, column);
    emit dataChanged(idx, idx, {Qt::DisplayRole});
    return true;
}

bool CsvModel::setHeader(int column, const QString &text)
{
    if (m_truncated || !m_hasHeader || m_rows.isEmpty() || column < 0 || column >= m_columns)
        return false;
    QStringList &cells = m_rows[0];
    while (cells.size() <= column)
        cells.append(QString());
    if (cells.at(column) == text)
        return false;
    cells[column] = text;
    markDirty();
    emit headerDataChanged(Qt::Horizontal, column, column);
    return true;
}

int CsvModel::insertRowAt(int row)
{
    if (m_truncated)
        return -1;
    if (m_rows.isEmpty()) {
        // Empty document: the first row becomes the header when one is expected
        m_rows.append(QStringList{QString()});
        if (m_hasHeader)
            m_rows.append(QStringList{QString()});
        m_columns = 1;
        markDirty();
        resetLayout();
        emit sourceChanged();
        return int(m_visible.size()) - 1;
    }
    row = qBound(0, row, int(m_visible.size()));
    // Insert in file order right before the visible row (or after the last one)
    int position;
    if (row < m_visible.size())
        position = m_visible.at(row);
    else if (!m_visible.isEmpty())
        position = m_visible.last() + 1;
    else
        position = int(m_rows.size());
    QStringList cells;
    for (int i = 0; i < qMax(1, m_columns); ++i)
        cells.append(QString());
    m_rows.insert(position, cells);
    m_columns = qMax(m_columns, int(cells.size()));
    markDirty();
    // Show the new row where it was asked for, even with a filter or sort on
    for (int &v : m_visible)
        if (v >= position)
            ++v;
    beginInsertRows({}, row, row);
    m_visible.insert(row, position);
    endInsertRows();
    emit sourceChanged();
    emit layoutChanged();
    return row;
}

bool CsvModel::removeRowAt(int row)
{
    if (m_truncated || row < 0 || row >= m_visible.size())
        return false;
    const int position = m_visible.at(row);
    beginRemoveRows({}, row, row);
    m_visible.removeAt(row);
    m_rows.removeAt(position);
    for (int &v : m_visible)
        if (v > position)
            --v;
    endRemoveRows();
    markDirty();
    emit sourceChanged();
    emit layoutChanged();
    return true;
}

void CsvModel::insertColumnAt(int column)
{
    if (m_truncated)
        return;
    column = qBound(0, column, m_columns);
    beginResetModel();
    for (QStringList &cells : m_rows) {
        while (cells.size() < column)
            cells.append(QString());
        cells.insert(column, QString());
    }
    if (m_rows.isEmpty())
        m_rows.append(QStringList{QString()});
    ++m_columns;
    if (m_sortColumn >= column)
        ++m_sortColumn;
    rebuildVisible();
    endResetModel();
    markDirty();
    emit sourceChanged();
    emit sortChanged();
    emit layoutChanged();
}

bool CsvModel::removeColumnAt(int column)
{
    if (m_truncated || column < 0 || column >= m_columns || m_columns <= 1)
        return false;
    beginResetModel();
    for (QStringList &cells : m_rows)
        if (column < cells.size())
            cells.removeAt(column);
    --m_columns;
    if (m_sortColumn == column) {
        m_sortColumn = -1;
        m_sortDescending = false;
    } else if (m_sortColumn > column) {
        --m_sortColumn;
    }
    rebuildVisible();
    endResetModel();
    markDirty();
    emit sourceChanged();
    emit sortChanged();
    emit layoutChanged();
    return true;
}

QString CsvModel::quoteField(const QString &field) const
{
    const bool needsQuotes = field.contains(m_delimiter) || field.contains(QLatin1Char('"'))
                             || field.contains(QLatin1Char('\n')) || field.contains(QLatin1Char('\r'))
                             || field.startsWith(QLatin1Char(' ')) || field.endsWith(QLatin1Char(' '));
    if (!needsQuotes)
        return field;
    QString quoted = field;
    quoted.replace(QLatin1Char('"'), QStringLiteral("\"\""));
    return QLatin1Char('"') + quoted + QLatin1Char('"');
}

QString CsvModel::serialize() const
{
    const QString newline = m_crlf ? QStringLiteral("\r\n") : QStringLiteral("\n");
    QString out;
    for (int r = 0; r < m_rows.size(); ++r) {
        const QStringList &cells = m_rows.at(r);
        QStringList fields;
        fields.reserve(cells.size());
        for (const QString &cell : cells)
            fields.append(quoteField(cell));
        out += fields.join(m_delimiter);
        if (r + 1 < m_rows.size() || m_trailingNewline)
            out += newline;
    }
    return out;
}

QString CsvModel::save()
{
    if (m_truncated)
        return QStringLiteral("File too large to edit");
    QSaveFile file(expandPath(m_source));
    if (!file.open(QIODevice::WriteOnly))
        return file.errorString();
    QByteArray bytes;
    if (m_bom)
        bytes.append("\xEF\xBB\xBF", 3);
    bytes.append(serialize().toUtf8());
    if (file.write(bytes) != bytes.size() || !file.commit())
        return file.errorString().isEmpty() ? QStringLiteral("Write failed") : file.errorString();
    if (m_dirty) {
        m_dirty = false;
        emit dirtyChanged();
    }
    return {};
}
