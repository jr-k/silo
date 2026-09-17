#pragma once

#include <QAbstractListModel>
#include <QJsonObject>
#include <QObject>
#include <QSet>
#include <QVariantList>

#include <memory>

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

public:
    explicit AppStore(QObject *parent = nullptr);

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
    Q_INVOKABLE void updateItem(const QString &id, const QString &name, const QString &url,
                                const QString &iconType = {}, const QString &iconValue = {},
                                const QString &color = {}, const QString &type = {},
                                const QVariantMap &options = {});
    Q_INVOKABLE void deleteNodes(const QVariantList &ids);
    Q_INVOKABLE void moveNodes(const QVariantList &ids, const QString &destinationId);
    // Deep-copies the nodes (folders with their whole subtree) into the destination
    // folder (empty id = workspace root). Returns the ids of the new top-level copies.
    Q_INVOKABLE QVariantList copyNodes(const QVariantList &ids, const QString &destinationId);

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

signals:
    void currentWorkspaceChanged();
    void workspaceDeleted(const QString &id);
    void currentFolderChanged();
    void breadcrumbsChanged();
    void dataChanged();

private:
    using NodePtr = std::shared_ptr<SiloNode>;

    WorkspaceModel m_workspaceModel;
    TreeModel m_treeModel;
    DirectoryModel m_directoryModel;
    QList<SiloWorkspace> m_workspaces;
    QString m_currentWorkspaceId;
    QString m_currentFolderId;
    QSet<QString> m_expandedIds;
    int m_revision = 0;

    SiloWorkspace *currentWorkspace();
    const SiloWorkspace *currentWorkspace() const;
    NodePtr findNode(const QString &id) const;
    NodePtr findNode(const QString &id, const QList<NodePtr> &nodes) const;
    NodePtr findParent(const QString &id) const;
    NodePtr findParent(const QString &id, const QList<NodePtr> &nodes, const NodePtr &parent) const;
    QList<NodePtr> *currentChildren();
    bool detachNode(const QString &id, QList<NodePtr> &nodes, NodePtr &result);
    bool contains(const NodePtr &node, const QString &id) const;
    void appendTreeRows(const QList<NodePtr> &nodes, int depth, QList<TreeModel::Row> &rows) const;
    void rebuildModels();
    void load();
    void save() const;
    QString storagePath() const;
    void loadSecrets() const;
    void saveSecrets() const;
    void forgetSecrets(const NodePtr &node);

    mutable QHash<QString, QString> m_secrets;
    mutable bool m_secretsLoaded = false;
    static QJsonObject nodeToJson(const NodePtr &node);
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
