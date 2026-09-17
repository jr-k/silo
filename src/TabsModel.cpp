#include "TabsModel.h"

#include "AppStore.h"
#include "SessionStore.h"

#include <QJsonArray>
#include <QSettings>

// ------------------------------------------------------------------ TabsModel

TabsModel::TabsModel(AppStore *store, SessionStore *session, const QString &workspaceId,
                     QObject *parent)
    : QAbstractListModel(parent), m_store(store), m_session(session), m_workspaceId(workspaceId)
{
    connect(this, &TabsModel::countChanged, this, &TabsModel::persist);
    connect(this, &TabsModel::currentIndexChanged, this, &TabsModel::persist);
    restore();
}

void TabsModel::persist() const
{
    if (m_restoring || !m_session || m_workspaceId.isEmpty())
        return;
    QStringList ids;
    for (const auto &tab : m_tabs)
        ids.append(tab.nodeId);
    m_session->setTabs(m_workspaceId, ids, m_currentIndex);
    if (qEnvironmentVariableIsSet("SILO_DEBUG_TABS"))
        qDebug() << "tabs persist" << m_workspaceId << ids << m_currentIndex;
}

void TabsModel::restore()
{
    if (!m_store || !m_session || m_workspaceId.isEmpty())
        return;

    QStringList ids;
    int current = -1;
    const QJsonObject saved = m_session->tabs(m_workspaceId);
    if (!saved.isEmpty()) {
        for (const auto &value : saved.value(QStringLiteral("ids")).toArray())
            ids.append(value.toString());
        current = saved.value(QStringLiteral("current")).toInt(-1);
    } else {
        // Tabs saved by earlier versions lived in QSettings: migrate them once.
        QSettings settings;
        const QString legacy = QStringLiteral("tabs/") + m_workspaceId + QLatin1Char('/');
        ids = settings.value(legacy + QStringLiteral("ids")).toStringList();
        current = settings.value(legacy + QStringLiteral("current"), -1).toInt();
        settings.remove(QStringLiteral("tabs/") + m_workspaceId);
    }

    m_restoring = true;
    for (const QString &id : ids) {
        const QVariantMap info = m_store->nodeInfo(id);
        if (info.isEmpty() || info.value(QStringLiteral("folder")).toBool())
            continue; // node vanished since last session
        openTab(id, info.value(QStringLiteral("name")).toString(),
                info.value(QStringLiteral("url")).toString(), false);
    }
    setCurrentIndex(current);
    m_restoring = false;
    persist(); // drop ids that no longer resolve (and complete the migration)
}

int TabsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_tabs.size());
}

QVariant TabsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_tabs.size())
        return {};
    const auto &tab = m_tabs.at(index.row());
    switch (role) {
    case NodeIdRole: return tab.nodeId;
    case TitleRole: return tab.title;
    case UrlRole: return tab.url;
    default: return {};
    }
}

QHash<int, QByteArray> TabsModel::roleNames() const
{
    return {{NodeIdRole, "tabNodeId"}, {TitleRole, "tabTitle"}, {UrlRole, "tabUrl"}};
}

void TabsModel::setCurrentIndex(int index)
{
    const int clamped = m_tabs.isEmpty() ? -1 : qBound(0, index, int(m_tabs.size()) - 1);
    if (clamped == m_currentIndex)
        return;
    m_currentIndex = clamped;
    emit currentIndexChanged();
}

QString TabsModel::currentNodeId() const
{
    return m_currentIndex >= 0 && m_currentIndex < m_tabs.size() ? m_tabs.at(m_currentIndex).nodeId
                                                                  : QString();
}

int TabsModel::indexOfNode(const QString &nodeId) const
{
    for (qsizetype i = 0; i < m_tabs.size(); ++i) {
        if (m_tabs.at(i).nodeId == nodeId)
            return int(i);
    }
    return -1;
}

QString TabsModel::nodeIdAt(int index) const
{
    return index >= 0 && index < m_tabs.size() ? m_tabs.at(index).nodeId : QString();
}

int TabsModel::openTab(const QString &nodeId, const QString &title, const QString &url, bool activate)
{
    int index = indexOfNode(nodeId);
    if (index < 0) {
        index = int(m_tabs.size());
        beginInsertRows({}, index, index);
        m_tabs.append({nodeId, title, url});
        endInsertRows();
        emit countChanged();
    }
    if (activate)
        setCurrentIndex(index);
    return index;
}

void TabsModel::closeTab(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return;
    // Remember it for reopenClosed(); a node closed twice is only kept once
    static constexpr int kMaxClosed = 20;
    const Tab closing = m_tabs.at(index);
    m_closed.removeIf([&closing](const ClosedTab &c) { return c.tab.nodeId == closing.nodeId; });
    m_closed.prepend({closing, index});
    while (m_closed.size() > kMaxClosed)
        m_closed.removeLast();
    emit closedCountChanged();

    beginRemoveRows({}, index, index);
    m_tabs.removeAt(index);
    endRemoveRows();
    emit countChanged();

    if (m_tabs.isEmpty()) {
        m_currentIndex = -1;
        emit currentIndexChanged();
    } else if (index < m_currentIndex) {
        --m_currentIndex;
        emit currentIndexChanged();
    } else if (index == m_currentIndex) {
        m_currentIndex = qMin(index, int(m_tabs.size()) - 1);
        emit currentIndexChanged();
    }
}

void TabsModel::closeOthers(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return;
    for (int i = int(m_tabs.size()) - 1; i >= 0; --i) {
        if (i != index)
            closeTab(i);
    }
}

void TabsModel::closeAll()
{
    for (int i = int(m_tabs.size()) - 1; i >= 0; --i)
        closeTab(i);
}

void TabsModel::updateTab(const QString &nodeId, const QString &title, const QString &url)
{
    const int index = indexOfNode(nodeId);
    if (index < 0)
        return;
    auto &tab = m_tabs[index];
    if (tab.title == title && tab.url == url)
        return;
    tab.title = title;
    tab.url = url;
    emit dataChanged(this->index(index), this->index(index));
}

bool TabsModel::reopenClosed()
{
    while (!m_closed.isEmpty()) {
        const ClosedTab closed = m_closed.takeFirst();
        emit closedCountChanged();
        // Already open again (from the tree): just show it
        const int existing = indexOfNode(closed.tab.nodeId);
        if (existing >= 0) {
            setCurrentIndex(existing);
            return true;
        }
        // Item deleted meanwhile: nothing to bring back, try the one before
        const QVariantMap info = m_store ? m_store->nodeInfo(closed.tab.nodeId) : QVariantMap();
        if (info.isEmpty() || info.value(QStringLiteral("folder")).toBool())
            continue;
        const int index = qBound(0, closed.index, int(m_tabs.size()));
        beginInsertRows({}, index, index);
        m_tabs.insert(index, {closed.tab.nodeId, info.value(QStringLiteral("name")).toString(),
                              info.value(QStringLiteral("url")).toString()});
        endInsertRows();
        emit countChanged();
        if (m_currentIndex >= index) {
            // Keep the same tab active until we switch below (persist sees a coherent index)
            ++m_currentIndex;
        }
        setCurrentIndex(index);
        return true;
    }
    return false;
}

void TabsModel::activateNext()
{
    if (m_tabs.isEmpty())
        return;
    setCurrentIndex((m_currentIndex + 1) % int(m_tabs.size()));
}

void TabsModel::activatePrevious()
{
    if (m_tabs.isEmpty())
        return;
    setCurrentIndex((m_currentIndex - 1 + int(m_tabs.size())) % int(m_tabs.size()));
}

// -------------------------------------------------------------------- TabsHub

TabsHub::TabsHub(AppStore *store, SessionStore *session, QObject *parent)
    : QAbstractListModel(parent), m_store(store), m_session(session)
{
    connect(store, &AppStore::currentWorkspaceChanged, this,
            [this] { switchTo(m_store->currentWorkspaceId()); });
    connect(store, &AppStore::workspaceDeleted, this, [this](const QString &id) {
        remove(id);
        m_session->forgetTabs(id);
    });
    switchTo(store->currentWorkspaceId());
}

int TabsHub::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_entries.size());
}

QVariant TabsHub::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_entries.size())
        return {};
    const auto &entry = m_entries.at(index.row());
    switch (role) {
    case WorkspaceIdRole: return entry.workspaceId;
    case TabsRole: return QVariant::fromValue<QObject *>(entry.tabs);
    default: return {};
    }
}

QHash<int, QByteArray> TabsHub::roleNames() const
{
    return {{WorkspaceIdRole, "workspaceId"}, {TabsRole, "tabs"}};
}

TabsModel *TabsHub::current() const
{
    return m_currentRow >= 0 && m_currentRow < m_entries.size() ? m_entries.at(m_currentRow).tabs
                                                                 : nullptr;
}

QString TabsHub::currentWorkspaceId() const
{
    return m_currentRow >= 0 && m_currentRow < m_entries.size()
               ? m_entries.at(m_currentRow).workspaceId
               : QString();
}

int TabsHub::rowOf(const QString &workspaceId) const
{
    for (qsizetype i = 0; i < m_entries.size(); ++i) {
        if (m_entries.at(i).workspaceId == workspaceId)
            return int(i);
    }
    return -1;
}

TabsModel *TabsHub::forWorkspace(const QString &workspaceId)
{
    if (workspaceId.isEmpty())
        return nullptr;
    int row = rowOf(workspaceId);
    if (row < 0) {
        row = int(m_entries.size());
        beginInsertRows({}, row, row);
        m_entries.append({workspaceId, new TabsModel(m_store, m_session, workspaceId, this)});
        endInsertRows();
    }
    return m_entries.at(row).tabs;
}

void TabsHub::switchTo(const QString &workspaceId)
{
    forWorkspace(workspaceId);
    const int row = rowOf(workspaceId);
    if (row == m_currentRow)
        return;
    m_currentRow = row;
    emit currentChanged();
}

void TabsHub::remove(const QString &workspaceId)
{
    const int row = rowOf(workspaceId);
    if (row < 0)
        return;
    TabsModel *tabs = m_entries.at(row).tabs;
    beginRemoveRows({}, row, row);
    m_entries.removeAt(row);
    endRemoveRows();
    tabs->deleteLater();
    if (m_currentRow == row) {
        m_currentRow = -1;
        emit currentChanged();
    } else if (m_currentRow > row) {
        --m_currentRow;
        emit currentChanged();
    }
}
