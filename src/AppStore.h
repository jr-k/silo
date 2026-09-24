#pragma once

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QSet>
#include <QVariantList>

#include <memory>

class SessionStore;

struct SiloNode {
    QString id;
    QString name;
    // Leaf payload: "web" (url), "ssh" (ssh://user@host:port) or "file" (local path).
    QString type = QStringLiteral("web");
    QString url;
    bool folder = false;
    // Leaf icon: iconType is "" (default globe), "emoji" or "image".
    QString iconType;
    QString iconValue;
    QString color;
    // Type-specific settings (ssh: auth = "" | "password" | "key", keyPath)
    QVariantMap options;
    QList<std::shared_ptr<SiloNode>> children;
};

struct SiloWorkspace {
    QString id;
    QString name;
    QString color;
    QString iconType;
    QString iconValue;
    QList<std::shared_ptr<SiloNode>> roots;
};

class WorkspaceModel final : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles { IdRole = Qt::UserRole + 1, NameRole, ColorRole, IconTypeRole, IconValueRole, CurrentRole };
    explicit WorkspaceModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void setItems(const QList<SiloWorkspace> *items, const QString &currentId);

private:
    const QList<SiloWorkspace> *m_items = nullptr;
    QString m_currentId;
};

class TreeModel final : public QAbstractListModel
{
    Q_OBJECT
public:
    struct Row {
        std::shared_ptr<SiloNode> node;
        int depth = 0;
        bool expanded = false;
        bool hasChildren = false;
    };
    enum Roles { IdRole = Qt::UserRole + 1, NameRole, KindRole, UrlRole, DepthRole, ExpandedRole, HasChildrenRole,
                 IconTypeRole, IconValueRole, ColorRole, TypeRole };
    explicit TreeModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void setRows(QList<Row> rows);
    void refreshNode(const QString &id);
    int indexOfNode(const QString &id) const;
    QString nodeIdAt(int row) const;

private:
    QList<Row> m_rows;
};

class DirectoryModel final : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles { IdRole = Qt::UserRole + 1, NameRole, KindRole, UrlRole, ChildCountRole,
                 IconTypeRole, IconValueRole, ColorRole, TypeRole };
    explicit DirectoryModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    // When `hasParent` is set, row 0 is a virtual ".." entry (kind "parent")
    // whose nodeId is the parent folder id (empty string for the root).
    void setItems(QList<std::shared_ptr<SiloNode>> items, bool hasParent = false,
                  const QString &parentId = {});
    void refreshNode(const QString &id);

private:
    int offset() const { return m_hasParent ? 1 : 0; }

    QList<std::shared_ptr<SiloNode>> m_items;
    bool m_hasParent = false;
    QString m_parentId;
};

class AppStore final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel *workspaceModel READ workspaceModel CONSTANT)
    Q_PROPERTY(QAbstractItemModel *treeModel READ treeModel CONSTANT)
    Q_PROPERTY(QAbstractItemModel *directoryModel READ directoryModel CONSTANT)
    Q_PROPERTY(QString currentWorkspaceId READ currentWorkspaceId NOTIFY currentWorkspaceChanged)
    Q_PROPERTY(QString currentWorkspaceName READ currentWorkspaceName NOTIFY currentWorkspaceChanged)
    Q_PROPERTY(QString currentWorkspaceColor READ currentWorkspaceColor NOTIFY currentWorkspaceChanged)
    Q_PROPERTY(QString currentWorkspaceIconType READ currentWorkspaceIconType NOTIFY currentWorkspaceChanged)
    Q_PROPERTY(QString currentWorkspaceIconValue READ currentWorkspaceIconValue NOTIFY currentWorkspaceChanged)
    Q_PROPERTY(QString currentFolderId READ currentFolderId NOTIFY currentFolderChanged)
    Q_PROPERTY(QString currentFolderName READ currentFolderName NOTIFY breadcrumbsChanged)
    Q_PROPERTY(QVariantList breadcrumbs READ breadcrumbs NOTIFY breadcrumbsChanged)
    Q_PROPERTY(int revision READ revision NOTIFY dataChanged)
    // True while the system clipboard holds a pasteable node payload (see copyToClipboard).
    Q_PROPERTY(bool clipboardHasNodes READ clipboardHasNodes NOTIFY clipboardChanged)

public:
    explicit AppStore(SessionStore *session, QObject *parent = nullptr);

    QAbstractItemModel *workspaceModel() { return &m_workspaceModel; }
    QAbstractItemModel *treeModel() { return &m_treeModel; }
    QAbstractItemModel *directoryModel() { return &m_directoryModel; }

    QString currentWorkspaceId() const { return m_currentWorkspaceId; }
    QString currentWorkspaceName() const;
    QString currentWorkspaceColor() const;
    QString currentWorkspaceIconType() const;
    QString currentWorkspaceIconValue() const;
    QString currentFolderId() const { return m_currentFolderId; }
    QString currentFolderName() const;
    QVariantList breadcrumbs() const;
    int revision() const { return m_revision; }

    Q_INVOKABLE QVariantList searchWorkspaces(const QString &query) const;
    Q_INVOKABLE QString parentIdOf(const QString &id) const;
    Q_INVOKABLE QVariantList currentChildIds() const;
    // Items (leaves) of a folder as {id, name, url}; empty id = workspace root.
    Q_INVOKABLE QVariantList collectItems(const QString &folderId, bool recursive) const;
    Q_INVOKABLE QVariantMap nodeInfo(const QString &id) const;
    // Visible tree rows (for keyboard navigation in the sidebar).
    Q_INVOKABLE int treeIndexOf(const QString &id) const { return m_treeModel.indexOfNode(id); }
    Q_INVOKABLE QString treeNodeIdAt(int row) const { return m_treeModel.nodeIdAt(row); }
    Q_INVOKABLE bool isExpanded(const QString &id) const { return m_expandedIds.contains(id); }
    Q_INVOKABLE void selectWorkspace(const QString &id);
    Q_INVOKABLE void addWorkspace(const QString &name, const QString &color,
                                  const QString &iconType, const QString &iconValue);
    Q_INVOKABLE void updateWorkspace(const QString &id, const QString &name, const QString &color,
                                     const QString &iconType, const QString &iconValue);
    Q_INVOKABLE void deleteWorkspace(const QString &id);
    Q_INVOKABLE QVariantMap workspaceInfo(const QString &id) const;
    Q_INVOKABLE int workspaceCount() const { return int(m_workspaces.size()); }
    Q_INVOKABLE void openFolder(const QString &id);
    Q_INVOKABLE void openParentFolder();
    Q_INVOKABLE void toggleExpanded(const QString &id);
    Q_INVOKABLE QString addFolder(const QString &name = QStringLiteral("New folder"));
    Q_INVOKABLE QString addItem(const QString &name, const QString &url,
                                const QString &iconType = {}, const QString &iconValue = {},
                                const QString &color = {}, const QString &type = QStringLiteral("web"),
                                const QVariantMap &options = {});
    Q_INVOKABLE void renameNode(const QString &id, const QString &name);
    Q_INVOKABLE void setFolderColor(const QString &id, const QString &color);
    Q_INVOKABLE void updateItem(const QString &id, const QString &name, const QString &url,
                                const QString &iconType = {}, const QString &iconValue = {},
                                const QString &color = {}, const QString &type = {},
                                const QVariantMap &options = {});
    // Applies the same icon (type, value, background) to every leaf item of the
    // list; folders and unknown ids are skipped. Empty iconType = default icon.
    Q_INVOKABLE void setItemsIcon(const QVariantList &ids, const QString &iconType,
                                  const QString &iconValue, const QString &color);
    Q_INVOKABLE void deleteNodes(const QVariantList &ids);
    Q_INVOKABLE void moveNodes(const QVariantList &ids, const QString &destinationId);
    // Reordering. Moves the nodes into `destinationId` (empty = workspace root)
    // right before the child `beforeId` (empty = at the end); nodes already in
    // the destination are repositioned. The moved nodes keep their tree order.
    Q_INVOKABLE void insertNodes(const QVariantList &ids, const QString &destinationId,
                                 const QString &beforeId);
    // Drops the nodes next to `anchorId`, as its siblings (before or after it).
    Q_INVOKABLE void moveNodesRelative(const QVariantList &ids, const QString &anchorId, bool after);
    // Leaf item ids of a workspace in tree (depth-first) order; used to keep the
    // Live tabs in the same order as the sidebar.
    QStringList itemOrder(const QString &workspaceId) const;
    // System clipboard. copyToClipboard() puts the nodes of the current workspace
    // (folders with their subtree, image icons embedded as data: URLs) on the
    // clipboard as text:
    //   {"format": "silo-nodes", "version": 1, "nodes": [<node>…]}
    // where <node> follows the library / workspace-file schema. pasteFromClipboard()
    // deep-copies such a payload — or the roots of an exported workspace file — into
    // the destination folder of the current workspace (empty id = root) with fresh
    // ids and returns the ids of the new top-level copies. Any JSON in that shape
    // can be pasted, so a hand-written list of items imports just as well.
    // SSH passwords never travel through the clipboard: a copy made from this
    // library gets them back through the original ids when pasted here.
    bool clipboardHasNodes() const { return m_clipboardHasNodes; }
    // Re-reads the clipboard. macOS only reports external changes when the app comes
    // back to the front, so menus offering "Paste" call this as they open.
    Q_INVOKABLE void refreshClipboardState();
    Q_INVOKABLE void copyToClipboard(const QVariantList &ids);
    Q_INVOKABLE QVariantList pasteFromClipboard(const QString &destinationId);

    // Per-node secrets (ssh passwords), kept out of library.json in a 0600 secrets.json.
    Q_INVOKABLE QString secret(const QString &id) const;
    Q_INVOKABLE void setSecret(const QString &id, const QString &value);

    // Workspace transfer as a self-contained JSON file (tree, icons embedded as data
    // URLs and, optionally, ssh passwords). Import creates a new workspace with fresh ids.
    // Both return {ok, error} plus, on success, workspace details (id, name, counts...).
    Q_INVOKABLE QVariantMap workspaceSummary(const QString &id) const;
    Q_INVOKABLE QVariantMap exportWorkspace(const QString &id, const QUrl &fileUrl, bool includeSecrets) const;
    Q_INVOKABLE QVariantMap inspectWorkspaceFile(const QUrl &fileUrl) const;
    Q_INVOKABLE QVariantMap importWorkspace(const QUrl &fileUrl, bool includeSecrets);

    // Folder holding library.json / session.json (SILO_DATA_DIR overrides the platform default).
    static QString dataDirectory();
    Q_INVOKABLE QString dataPath() const { return dataDirectory(); }
    // Where the web profile (cookies, site storage, cache) lives when
    // SILO_DATA_DIR is set, so a test instance never touches the real one.
    // Empty otherwise: QtWebEngine keeps its platform default.
    Q_INVOKABLE QString webStoragePath() const;

signals:
    void currentWorkspaceChanged();
    void workspaceDeleted(const QString &id);
    void currentFolderChanged();
    void breadcrumbsChanged();
    void dataChanged();
    void clipboardChanged();

private:
    using NodePtr = std::shared_ptr<SiloNode>;

    WorkspaceModel m_workspaceModel;
    TreeModel m_treeModel;
    DirectoryModel m_directoryModel;
    QList<SiloWorkspace> m_workspaces;
    QString m_currentWorkspaceId;
    QString m_currentFolderId;
    QSet<QString> m_expandedIds;
    SessionStore *m_session = nullptr;
    int m_revision = 0;
    bool m_clipboardHasNodes = false;

    SiloWorkspace *currentWorkspace();
    const SiloWorkspace *currentWorkspace() const;
    NodePtr findNode(const QString &id) const;
    NodePtr findNode(const QString &id, const QList<NodePtr> &nodes) const;
    NodePtr findParent(const QString &id) const;
    NodePtr findParent(const QString &id, const QList<NodePtr> &nodes, const NodePtr &parent) const;
    QList<NodePtr> *currentChildren();
    bool detachNode(const QString &id, QList<NodePtr> &nodes, NodePtr &result);
    bool contains(const NodePtr &node, const QString &id) const;
    // Ids of every node of the workspace in depth-first order (folders included).
    static void collectOrder(const QList<NodePtr> &nodes, QStringList &out, bool leavesOnly);
    // Validates a move of `ids` into `destinationId` and returns the nodes to
    // move, deduplicated and sorted by their current tree order. Empty if invalid.
    QList<QString> movableNodes(const QVariantList &ids, const QString &destinationId, NodePtr &destination);
    // Nodes of the current workspace for `ids`, in the given order, without duplicates
    // and without nodes whose ancestor is listed too (it brings them along anyway).
    QList<NodePtr> topLevelNodes(const QVariantList &ids) const;
    // Appends fresh-id deep copies of `sources` to the destination folder of the
    // current workspace ("Name copy" on a name clash). Passwords come from `secrets`
    // (exported workspace payload) or from this library, keyed by the source ids.
    QVariantList insertCopies(const QList<NodePtr> &sources, const QString &destinationId,
                              const QJsonObject &secrets);
    // Reads a clipboard / workspace-file payload; false when the text is neither.
    static bool parseClipboardNodes(const QString &text, QJsonArray &nodes, QJsonObject &secrets);
    void appendTreeRows(const QList<NodePtr> &nodes, int depth, QList<TreeModel::Row> &rows) const;
    void rebuildModels();
    void load();
    void save() const;
    void loadExpandedState();
    void saveExpandedState() const;
    void expandFolder(const QString &id);
    QString storagePath() const;
    void loadSecrets() const;
    void saveSecrets() const;
    void forgetSecrets(const NodePtr &node);

    mutable QHash<QString, QString> m_secrets;
    mutable bool m_secretsLoaded = false;
    static QJsonObject nodeToJson(const NodePtr &node);
    // nodeToJson with image icons embedded as data: URLs (clipboard, workspace files).
    static QJsonObject nodeToTransferJson(const NodePtr &node);
    static NodePtr nodeFromJson(const QJsonObject &object);

    // Transfer helpers
    static QJsonObject workspaceToJson(const SiloWorkspace &workspace);
    static SiloWorkspace workspaceFromJson(const QJsonObject &object);
    static bool parseWorkspaceFile(const QUrl &fileUrl, QJsonObject &document, QString &error);
    static void countNodes(const QList<NodePtr> &nodes, int &folders, int &items);
    static QString embedIcon(const QString &value);
    static QString materializeIcon(const QString &value);
    void adoptWorkspace(SiloWorkspace workspace);
};
