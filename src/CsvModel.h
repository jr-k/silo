#pragma once

#include <QAbstractTableModel>
#include <QList>
#include <QString>
#include <QStringList>

// Table model over a delimited text file (CSV / TSV / semicolon). Detects the
// delimiter, optionally treats the first row as header, filters rows on a
// search string and sorts by column (numeric when the column looks numeric).
class CsvModel : public QAbstractTableModel
{
    Q_OBJECT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool hasHeader READ hasHeader WRITE setHasHeader NOTIFY hasHeaderChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QString delimiter READ delimiter NOTIFY sourceChanged)
    Q_PROPERTY(QString delimiterName READ delimiterName NOTIFY sourceChanged)
    Q_PROPERTY(int totalRows READ totalRows NOTIFY sourceChanged)
    Q_PROPERTY(int columns READ columns NOTIFY sourceChanged)
    Q_PROPERTY(int visibleRows READ visibleRows NOTIFY layoutChanged)
    Q_PROPERTY(int sortColumn READ sortColumn NOTIFY sortChanged)
    Q_PROPERTY(bool sortDescending READ sortDescending NOTIFY sortChanged)
    Q_PROPERTY(bool truncated READ truncated NOTIFY sourceChanged)
    // Edits pending a write to disk (see save())
    Q_PROPERTY(bool dirty READ dirty NOTIFY dirtyChanged)

public:
    explicit CsvModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    int columnCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString source() const { return m_source; }
    void setSource(const QString &source);
    bool hasHeader() const { return m_hasHeader; }
    void setHasHeader(bool hasHeader);
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    QString delimiter() const { return QString(m_delimiter); }
    QString delimiterName() const;
    int totalRows() const { return int(m_rows.size()) - (m_hasHeader && !m_rows.isEmpty() ? 1 : 0); }
    int visibleRows() const { return int(m_visible.size()); }
    int columns() const { return m_columns; }
    int sortColumn() const { return m_sortColumn; }
    bool sortDescending() const { return m_sortDescending; }
    bool truncated() const { return m_truncated; }

    Q_INVOKABLE QString headerText(int column) const;
    // Click on a header: sort ascending, then descending, then back to file order.
    Q_INVOKABLE void toggleSort(int column);
    Q_INVOKABLE void reload();
    // Suggested pixel width for a column, from its longest visible sample.
    Q_INVOKABLE int columnWidth(int column, int minimum = 72, int maximum = 360) const;
    // Row as tab-separated text (for copying)
    Q_INVOKABLE QString rowText(int row) const;
    Q_INVOKABLE QString cellText(int row, int column) const;
    bool dirty() const { return m_dirty; }

    // --- editing (row indices are visible rows; the file is not touched until save())
    Q_INVOKABLE bool setCell(int row, int column, const QString &text);
    Q_INVOKABLE bool setHeader(int column, const QString &text);
    // Insert an empty row before the visible row (row == visibleRows appends).
    Q_INVOKABLE int insertRowAt(int row);
    Q_INVOKABLE bool removeRowAt(int row);
    Q_INVOKABLE void insertColumnAt(int column);
    Q_INVOKABLE bool removeColumnAt(int column);
    // Serialise back to the source file with the detected delimiter and line
    // endings. Returns "" or an error message. No-op on truncated files.
    Q_INVOKABLE QString save();

signals:
    void sourceChanged();
    void hasHeaderChanged();
    void filterChanged();
    void sortChanged();
    void layoutChanged();
    void dirtyChanged();

private:
    void parse(const QString &text);
    void rebuildVisible();
    void markDirty();
    void resetLayout();
    QString serialize() const;
    QString quoteField(const QString &field) const;
    int firstDataRow() const { return m_hasHeader && !m_rows.isEmpty() ? 1 : 0; }
    static bool looksNumeric(const QString &text, double *value);

    QString m_source;
    QList<QStringList> m_rows;
    QList<int> m_visible;
    int m_columns = 0;
    QChar m_delimiter = QLatin1Char(',');
    bool m_hasHeader = true;
    bool m_headerExplicit = false;
    bool m_truncated = false;
    bool m_crlf = false;
    bool m_trailingNewline = true;
    bool m_bom = false;
    bool m_dirty = false;
    QString m_filter;
    int m_sortColumn = -1;
    bool m_sortDescending = false;
};
