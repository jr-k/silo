#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>

class AppStore;
class SessionStore;

// Open browser tabs of one workspace (Working mode). Rows are inserted/removed
// individually (never reset) so QML delegates (WebEngineViews) stay alive.
// The set (order + active tab) is persisted in session.json until the user
// closes the tabs, so a restart brings the Live layout back.
class TabsModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(QString currentNodeId READ currentNodeId NOTIFY currentIndexChanged)
    Q_PROPERTY(QString workspaceId READ workspaceId CONSTANT)
    // Tabs closed during this run, most recent first (for "reopen closed tab")
    Q_PROPERTY(int closedCount READ closedCount NOTIFY closedCountChanged)
    // False: tabs follow the tree order (new tabs slot in at their tree position,
    // reordering the tree reorders the tabs). True: the user dragged tabs around
    // and their order is kept as is until syncOrder() is called.
    Q_PROPERTY(bool manualOrder READ manualOrder NOTIFY manualOrderChanged)

public:
    enum Roles { NodeIdRole = Qt::UserRole + 1, TitleRole, UrlRole };

    struct Tab {
        QString nodeId;
        QString title;
        QString url;
    };

    // Restores the persisted tab set of the workspace right away.
    TabsModel(AppStore *store, SessionStore *session, const QString &workspaceId,
              QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return int(m_tabs.size()); }
    int currentIndex() const { return m_currentIndex; }
    void setCurrentIndex(int index);
    QString currentNodeId() const;
    QString workspaceId() const { return m_workspaceId; }

    // Opens a tab for the node, or activates the existing one. Returns its index.
    Q_INVOKABLE int openTab(const QString &nodeId, const QString &title, const QString &url,
                            bool activate = true);
    Q_INVOKABLE void closeTab(int index);
    Q_INVOKABLE void closeOthers(int index);
    Q_INVOKABLE void closeAll();
    Q_INVOKABLE int indexOfNode(const QString &nodeId) const;
    Q_INVOKABLE QString nodeIdAt(int index) const;
    Q_INVOKABLE void updateTab(const QString &nodeId, const QString &title, const QString &url);
    Q_INVOKABLE void activateNext();
    Q_INVOKABLE void activatePrevious();
    int closedCount() const { return int(m_closed.size()); }
    // Brings back the most recently closed tab (at its old position) and
    // activates it. Tabs whose item was deleted since are skipped. Returns
    // false when there is nothing left to reopen.
    Q_INVOKABLE bool reopenClosed();

    bool manualOrder() const { return m_manualOrder; }
    // Drag reordering: moves the tab at `from` so it ends up at `to`, and
    // switches to manual order.
    Q_INVOKABLE void moveTab(int from, int to);
    // Puts the tabs back in tree order and follows the tree again.
    Q_INVOKABLE void syncOrder();

signals:
    void countChanged();
    void currentIndexChanged();
    void closedCountChanged();
    void manualOrderChanged();

private:
    void persist() const;
    void restore();
    // Position a tab for `nodeId` should take to respect the tree order.
    int orderedPosition(const QString &nodeId) const;
    // Reorders the tabs to the tree order (rows are moved, never reset).
    void sortByTree();
    void setManualOrder(bool manual);

    QList<Tab> m_tabs;
    struct ClosedTab {
        Tab tab;
        int index;
    };
    QList<ClosedTab> m_closed; // most recent first, capped
    int m_currentIndex = -1;
    bool m_manualOrder = false;
    AppStore *m_store = nullptr;
    SessionStore *m_session = nullptr;
    QString m_workspaceId;
    bool m_restoring = false;
};

// One live TabsModel per workspace, created on first visit and kept in memory
// so switching workspaces never unloads the pages. Rows are workspaces.
class TabsHub final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(TabsModel *current READ current NOTIFY currentChanged)
    Q_PROPERTY(QString currentWorkspaceId READ currentWorkspaceId NOTIFY currentChanged)
    Q_PROPERTY(int currentRow READ currentRow NOTIFY currentChanged)

public:
    enum Roles { WorkspaceIdRole = Qt::UserRole + 1, TabsRole };

    TabsHub(AppStore *store, SessionStore *session, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    TabsModel *current() const;
    QString currentWorkspaceId() const;
    int currentRow() const { return m_currentRow; }

    // Returns the workspace's model, creating (and restoring) it on first use.
    Q_INVOKABLE TabsModel *forWorkspace(const QString &workspaceId);

signals:
    void currentChanged();

private:
    struct Entry {
        QString workspaceId;
        TabsModel *tabs;
    };

    int rowOf(const QString &workspaceId) const;
    void switchTo(const QString &workspaceId);
    void remove(const QString &workspaceId);

    QList<Entry> m_entries;
    int m_currentRow = -1;
    AppStore *m_store = nullptr;
    SessionStore *m_session = nullptr;
};
