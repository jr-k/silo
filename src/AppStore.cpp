#include "AppStore.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMimeDatabase>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>

#include <functional>

namespace {
const auto kTransferFormat = QStringLiteral("silo-workspace");
constexpr int kTransferVersion = 1;
constexpr qint64 kMaxEmbeddedIconBytes = 2 * 1024 * 1024;

QString localPathOf(const QUrl &url)
{
    if (url.isLocalFile())
        return url.toLocalFile();
    // QML may hand over a bare path or a file:// string.
    const QString text = url.toString();
    return text.startsWith(QStringLiteral("file:")) ? QUrl(text).toLocalFile() : text;
}
} // namespace

WorkspaceModel::WorkspaceModel(QObject *parent) : QAbstractListModel(parent) {}

int WorkspaceModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() || !m_items ? 0 : m_items->size();
}

QVariant WorkspaceModel::data(const QModelIndex &index, int role) const
{
    if (!m_items || !index.isValid() || index.row() >= m_items->size())
        return {};
    const auto &workspace = m_items->at(index.row());
    switch (role) {
    case IdRole: return workspace.id;
    case NameRole: return workspace.name;
    case ColorRole: return workspace.color;
    case IconTypeRole: return workspace.iconType;
    case IconValueRole: return workspace.iconValue;
    case CurrentRole: return workspace.id == m_currentId;
    default: return {};
    }
}

QHash<int, QByteArray> WorkspaceModel::roleNames() const
{
    return {{IdRole, "workspaceId"}, {NameRole, "workspaceName"}, {ColorRole, "workspaceColor"},
            {IconTypeRole, "iconType"}, {IconValueRole, "iconValue"}, {CurrentRole, "isCurrent"}};
}

void WorkspaceModel::setItems(const QList<SiloWorkspace> *items, const QString &currentId)
{
    beginResetModel();
    m_items = items;
    m_currentId = currentId;
    endResetModel();
}

TreeModel::TreeModel(QObject *parent) : QAbstractListModel(parent) {}

int TreeModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant TreeModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const auto &row = m_rows.at(index.row());
    switch (role) {
    case IdRole: return row.node->id;
    case NameRole: return row.node->name;
    case KindRole: return row.node->folder ? QStringLiteral("folder") : QStringLiteral("item");
    case UrlRole: return row.node->url;
    case DepthRole: return row.depth;
    case ExpandedRole: return row.expanded;
    case HasChildrenRole: return row.hasChildren;
    case IconTypeRole: return row.node->iconType;
    case IconValueRole: return row.node->iconValue;
    case ColorRole: return row.node->color;
    case TypeRole: return row.node->type;
    default: return {};
    }
}

QHash<int, QByteArray> TreeModel::roleNames() const
{
    return {{IdRole, "nodeId"}, {NameRole, "nodeName"}, {KindRole, "nodeKind"},
            {UrlRole, "nodeUrl"}, {DepthRole, "depth"}, {ExpandedRole, "isExpanded"},
            {HasChildrenRole, "hasChildren"}, {IconTypeRole, "nodeIconType"},
            {IconValueRole, "nodeIconValue"}, {ColorRole, "nodeColor"}, {TypeRole, "nodeType"}};
}

void TreeModel::setRows(QList<Row> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}

void TreeModel::refreshNode(const QString &id)
{
    for (qsizetype i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).node->id == id) {
            emit dataChanged(index(i), index(i));
            return;
        }
    }
}

int TreeModel::indexOfNode(const QString &id) const
{
    for (qsizetype i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).node->id == id)
            return int(i);
    }
    return -1;
}

QString TreeModel::nodeIdAt(int row) const
{
    return row >= 0 && row < m_rows.size() ? m_rows.at(row).node->id : QString();
}

DirectoryModel::DirectoryModel(QObject *parent) : QAbstractListModel(parent) {}

int DirectoryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size()) + offset();
}

QVariant DirectoryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size() + offset())
        return {};

    if (m_hasParent && index.row() == 0) {
        switch (role) {
        case IdRole: return m_parentId;
        case NameRole: return QStringLiteral("..");
        case KindRole: return QStringLiteral("parent");
        case UrlRole: return QString();
        case ChildCountRole: return 0;
        case IconTypeRole:
        case IconValueRole:
        case ColorRole:
        case TypeRole: return QString();
        default: return {};
        }
    }

    const auto &node = m_items.at(index.row() - offset());
    switch (role) {
    case IdRole: return node->id;
    case NameRole: return node->name;
    case KindRole: return node->folder ? QStringLiteral("folder") : QStringLiteral("item");
    case UrlRole: return node->url;
    case ChildCountRole: return node->children.size();
    case IconTypeRole: return node->iconType;
    case IconValueRole: return node->iconValue;
    case ColorRole: return node->color;
    case TypeRole: return node->type;
    default: return {};
    }
}

QHash<int, QByteArray> DirectoryModel::roleNames() const
{
    return {{IdRole, "nodeId"}, {NameRole, "nodeName"}, {KindRole, "nodeKind"},
            {UrlRole, "nodeUrl"}, {ChildCountRole, "childCount"}, {IconTypeRole, "nodeIconType"},
            {IconValueRole, "nodeIconValue"}, {ColorRole, "nodeColor"}, {TypeRole, "nodeType"}};
}

void DirectoryModel::setItems(QList<std::shared_ptr<SiloNode>> items, bool hasParent,
                              const QString &parentId)
{
    beginResetModel();
    m_items = std::move(items);
    m_hasParent = hasParent;
    m_parentId = parentId;
    endResetModel();
}

void DirectoryModel::refreshNode(const QString &id)
{
    for (qsizetype i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i)->id == id) {
            const int row = int(i) + offset();
            emit dataChanged(index(row), index(row));
            return;
        }
    }
}

AppStore::AppStore(QObject *parent)
    : QObject(parent), m_workspaceModel(this), m_treeModel(this), m_directoryModel(this)
{
    load();
    rebuildModels();
}

QString AppStore::currentWorkspaceName() const
{
    const auto *workspace = currentWorkspace();
    return workspace ? workspace->name : QStringLiteral("Silo");
}

QString AppStore::currentWorkspaceColor() const
{
    const auto *workspace = currentWorkspace();
    return workspace ? workspace->color : QStringLiteral("#176E61");
}

QString AppStore::currentWorkspaceIconType() const
{
    const auto *workspace = currentWorkspace();
    return workspace ? workspace->iconType : QStringLiteral("emoji");
}

QString AppStore::currentWorkspaceIconValue() const
{
    const auto *workspace = currentWorkspace();
    return workspace ? workspace->iconValue : QStringLiteral("📦");
}

QString AppStore::currentFolderName() const
{
    const auto node = findNode(m_currentFolderId);
    return node ? node->name : currentWorkspaceName();
}

QVariantList AppStore::breadcrumbs() const
{
    QVariantList result;
    if (m_currentFolderId.isEmpty())
        return result;

    QList<NodePtr> path;
    std::function<bool(const QList<NodePtr> &)> walk = [&](const QList<NodePtr> &nodes) {
        for (const auto &node : nodes) {
            path.append(node);
            if (node->id == m_currentFolderId)
                return true;
            if (walk(node->children))
                return true;
            path.removeLast();
        }
        return false;
    };
    const auto *workspace = currentWorkspace();
    if (workspace && walk(workspace->roots)) {
        for (const auto &node : path)
            result.append(QVariantMap{{QStringLiteral("id"), node->id},
                                      {QStringLiteral("name"), node->name},
                                      {QStringLiteral("color"), node->color}});
    }
    return result;
}

QVariantList AppStore::searchWorkspaces(const QString &query) const
{
    QVariantList result;
    const QString needle = query.trimmed();
    for (const auto &workspace : m_workspaces) {
        if (!needle.isEmpty() && !workspace.name.contains(needle, Qt::CaseInsensitive))
            continue;
        result.append(QVariantMap{
            {QStringLiteral("id"), workspace.id},
            {QStringLiteral("name"), workspace.name},
            {QStringLiteral("color"), workspace.color},
            {QStringLiteral("iconType"), workspace.iconType},
            {QStringLiteral("iconValue"), workspace.iconValue},
            {QStringLiteral("isCurrent"), workspace.id == m_currentWorkspaceId}
        });
    }
    return result;
}

QString AppStore::parentIdOf(const QString &id) const
{
    const auto parent = findParent(id);
    return parent ? parent->id : QString();
}

QVariantList AppStore::currentChildIds() const
{
    QVariantList ids;
    const auto *workspace = currentWorkspace();
    if (!workspace)
        return ids;
    const auto folder = findNode(m_currentFolderId);
    const auto &children = folder ? folder->children : workspace->roots;
    for (const auto &node : children)
        ids.append(node->id);
    return ids;
}

QVariantList AppStore::collectItems(const QString &folderId, bool recursive) const
{
    QVariantList result;
    const auto *workspace = currentWorkspace();
    if (!workspace)
        return result;

    const QList<NodePtr> *children = nullptr;
    if (folderId.isEmpty()) {
        children = &workspace->roots;
    } else if (const auto folder = findNode(folderId); folder && folder->folder) {
        children = &folder->children;
    }
    if (!children)
        return result;

    std::function<void(const QList<NodePtr> &)> visit = [&](const QList<NodePtr> &nodes) {
        for (const auto &node : nodes) {
            if (node->folder) {
                if (recursive)
                    visit(node->children);
            } else {
                result.append(QVariantMap{{QStringLiteral("id"), node->id},
                                          {QStringLiteral("name"), node->name},
                                          {QStringLiteral("url"), node->url},
                                          {QStringLiteral("type"), node->type},
                                          {QStringLiteral("iconType"), node->iconType},
                                          {QStringLiteral("iconValue"), node->iconValue},
                                          {QStringLiteral("color"), node->color}});
            }
        }
    };
    visit(*children);
    return result;
}

QVariantMap AppStore::nodeInfo(const QString &id) const
{
    const auto node = findNode(id);
    if (!node)
        return {};
    return {{QStringLiteral("id"), node->id},
            {QStringLiteral("name"), node->name},
            {QStringLiteral("url"), node->url},
            {QStringLiteral("type"), node->type},
            {QStringLiteral("folder"), node->folder},
            {QStringLiteral("iconType"), node->iconType},
            {QStringLiteral("iconValue"), node->iconValue},
            {QStringLiteral("color"), node->color},
            {QStringLiteral("options"), node->options}};
}

QVariantMap AppStore::workspaceInfo(const QString &id) const
{
    for (const auto &workspace : m_workspaces) {
        if (workspace.id == id) {
            return {{QStringLiteral("id"), workspace.id},
                    {QStringLiteral("name"), workspace.name},
                    {QStringLiteral("color"), workspace.color},
                    {QStringLiteral("iconType"), workspace.iconType},
                    {QStringLiteral("iconValue"), workspace.iconValue}};
        }
    }
    return {};
}

void AppStore::selectWorkspace(const QString &id)
{
    if (id == m_currentWorkspaceId)
        return;
    const auto found = std::find_if(m_workspaces.cbegin(), m_workspaces.cend(),
                                    [&](const auto &workspace) { return workspace.id == id; });
    if (found == m_workspaces.cend())
        return;
    m_currentWorkspaceId = id;
    m_currentFolderId.clear();
    m_expandedIds.clear();
    QSettings().setValue(QStringLiteral("currentWorkspaceId"), id);
    rebuildModels();
    emit currentWorkspaceChanged();
    emit currentFolderChanged();
    emit breadcrumbsChanged();
}

void AppStore::addWorkspace(const QString &name, const QString &color,
                            const QString &iconType, const QString &iconValue)
{
    SiloWorkspace workspace;
    workspace.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    workspace.name = name.trimmed().isEmpty() ? QStringLiteral("Untitled workspace") : name.trimmed();
    workspace.color = color;
    workspace.iconType = iconType;
    workspace.iconValue = iconValue;
    adoptWorkspace(std::move(workspace));
}

// Appends a fully built workspace, makes it current and persists everything.
void AppStore::adoptWorkspace(SiloWorkspace workspace)
{
    m_currentWorkspaceId = workspace.id;
    m_workspaces.append(std::move(workspace));
    m_currentFolderId.clear();
    m_expandedIds.clear();
    QSettings().setValue(QStringLiteral("currentWorkspaceId"), m_currentWorkspaceId);
    save();
    rebuildModels();
    emit currentWorkspaceChanged();
    emit currentFolderChanged();
    emit breadcrumbsChanged();
}

void AppStore::updateWorkspace(const QString &id, const QString &name, const QString &color,
                               const QString &iconType, const QString &iconValue)
{
    for (auto &workspace : m_workspaces) {
        if (workspace.id != id)
            continue;
        if (!name.trimmed().isEmpty())
            workspace.name = name.trimmed();
        workspace.color = color;
        workspace.iconType = iconType;
        workspace.iconValue = iconValue;
        save();
        // Workspace rows are read through the store, not edited in place: a reset is fine.
        m_workspaceModel.setItems(&m_workspaces, m_currentWorkspaceId);
        ++m_revision;
        emit dataChanged();
        if (id == m_currentWorkspaceId) {
            emit currentWorkspaceChanged();
            emit breadcrumbsChanged();
        }
        return;
    }
}

void AppStore::deleteWorkspace(const QString &id)
{
    if (m_workspaces.size() <= 1)
        return;
    const auto found = std::find_if(m_workspaces.begin(), m_workspaces.end(),
                                    [&](const auto &workspace) { return workspace.id == id; });
    if (found == m_workspaces.end())
        return;
    m_workspaces.erase(found);
    if (id == m_currentWorkspaceId) {
        m_currentWorkspaceId = m_workspaces.first().id;
        m_currentFolderId.clear();
        m_expandedIds.clear();
        QSettings().setValue(QStringLiteral("currentWorkspaceId"), m_currentWorkspaceId);
    }
    save();
    rebuildModels();
    emit workspaceDeleted(id);
    emit currentWorkspaceChanged();
    emit currentFolderChanged();
    emit breadcrumbsChanged();
}

void AppStore::openFolder(const QString &id)
{
    if (!id.isEmpty()) {
        const auto node = findNode(id);
        if (!node || !node->folder)
            return;
        m_expandedIds.insert(id);
    }
    m_currentFolderId = id;
    rebuildModels();
    emit currentFolderChanged();
    emit breadcrumbsChanged();
}

void AppStore::openParentFolder()
{
    if (m_currentFolderId.isEmpty())
        return;
    const auto parent = findParent(m_currentFolderId);
    openFolder(parent ? parent->id : QString());
}

void AppStore::toggleExpanded(const QString &id)
{
    if (m_expandedIds.contains(id))
        m_expandedIds.remove(id);
    else
        m_expandedIds.insert(id);
    rebuildModels();
}

QString AppStore::addFolder(const QString &name)
{
    auto node = std::make_shared<SiloNode>();
    node->id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    node->name = name.trimmed().isEmpty() ? QStringLiteral("New folder") : name.trimmed();
    node->folder = true;
    if (auto *children = currentChildren())
        children->append(node);
    save();
    rebuildModels();
    return node->id;
}

QString AppStore::addItem(const QString &name, const QString &url, const QString &iconType,
                          const QString &iconValue, const QString &color, const QString &type,
                          const QVariantMap &options)
{
    auto node = std::make_shared<SiloNode>();
    node->id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    node->name = name.trimmed().isEmpty() ? QStringLiteral("Untitled item") : name.trimmed();
    node->type = type.isEmpty() ? QStringLiteral("web") : type;
    node->url = url.trimmed();
    node->iconType = iconType;
    node->iconValue = iconValue;
    node->color = color;
    node->options = options;
    if (auto *children = currentChildren())
        children->append(node);
    save();
    rebuildModels();
    return node->id;
}

void AppStore::renameNode(const QString &id, const QString &name)
{
    const auto node = findNode(id);
    if (!node || name.trimmed().isEmpty())
        return;
    node->name = name.trimmed();
    save();
    // In-place update: a model reset would destroy the delegate being edited.
    m_treeModel.refreshNode(id);
    m_directoryModel.refreshNode(id);
    ++m_revision;
    emit dataChanged();
    emit breadcrumbsChanged();
}

void AppStore::setFolderColor(const QString &id, const QString &color)
{
    const auto node = findNode(id);
    if (!node || !node->folder || node->color == color)
        return;
    node->color = color;
    save();
    m_treeModel.refreshNode(id);
    m_directoryModel.refreshNode(id);
    ++m_revision;
    emit dataChanged();
    emit breadcrumbsChanged();
}

void AppStore::updateItem(const QString &id, const QString &name, const QString &url,
                          const QString &iconType, const QString &iconValue, const QString &color,
                          const QString &type, const QVariantMap &options)
{
    const auto node = findNode(id);
    if (!node || node->folder || name.trimmed().isEmpty())
        return;
    node->name = name.trimmed();
    if (!type.isEmpty())
        node->type = type;
    node->url = url.trimmed();
    node->iconType = iconType;
    node->iconValue = iconValue;
    node->color = color;
    node->options = options;
    save();
    m_treeModel.refreshNode(id);
    m_directoryModel.refreshNode(id);
    ++m_revision;
    emit dataChanged();
}

void AppStore::deleteNodes(const QVariantList &ids)
{
    QSet<QString> idSet;
    for (const auto &id : ids)
        idSet.insert(id.toString());
    if (idSet.isEmpty())
        return;

    std::function<void(QList<NodePtr> &)> remove = [&](QList<NodePtr> &nodes) {
        for (qsizetype i = nodes.size() - 1; i >= 0; --i) {
            if (idSet.contains(nodes.at(i)->id)) {
                forgetSecrets(nodes.at(i));
                nodes.removeAt(i);
            } else {
                remove(nodes[i]->children);
            }
        }
    };
    if (auto *workspace = currentWorkspace())
        remove(workspace->roots);
    if (idSet.contains(m_currentFolderId) || (!m_currentFolderId.isEmpty() && !findNode(m_currentFolderId)))
        m_currentFolderId.clear();
    for (const auto &id : idSet)
        m_expandedIds.remove(id);
    save();
    rebuildModels();
    emit currentFolderChanged();
    emit breadcrumbsChanged();
}

QVariantList AppStore::copyNodes(const QVariantList &ids, const QString &destinationId)
{
    auto *workspace = currentWorkspace();
    if (!workspace)
        return {};
    NodePtr destination;
    if (!destinationId.isEmpty()) {
        destination = findNode(destinationId);
        if (!destination || !destination->folder)
            return {};
    }
    auto *target = destination ? &destination->children : &workspace->roots;

    // Keep order, drop duplicates and nodes already covered by a copied ancestor.
    QList<NodePtr> sources;
    for (const auto &value : ids) {
        const auto node = findNode(value.toString());
        if (!node)
            continue;
        bool covered = false;
        for (const auto &other : sources) {
            if (other == node || contains(other, node->id)) {
                covered = true;
                break;
            }
        }
        if (!covered)
            sources.append(node);
    }
    if (sources.isEmpty())
        return {};

    std::function<NodePtr(const NodePtr &)> clone = [&](const NodePtr &source) {
        auto copy = std::make_shared<SiloNode>(*source);
        copy->id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        if (const QString password = secret(source->id); !password.isEmpty())
            m_secrets.insert(copy->id, password);
        copy->children.clear();
        for (const auto &child : source->children)
            copy->children.append(clone(child));
        return copy;
    };
    auto siblingNamed = [&](const QString &name) {
        for (const auto &sibling : *target) {
            if (sibling->name == name)
                return true;
        }
        return false;
    };

    QVariantList created;
    for (const auto &source : sources) {
        auto copy = clone(source);
        // "Name" -> "Name copy" -> "Name copy 2" when the destination already has that name.
        if (siblingNamed(copy->name)) {
            const QString base = copy->name + QStringLiteral(" copy");
            QString candidate = base;
            for (int n = 2; siblingNamed(candidate); ++n)
                candidate = base + QLatin1Char(' ') + QString::number(n);
            copy->name = candidate;
        }
        target->append(copy);
        created.append(copy->id);
    }
    if (destination)
        m_expandedIds.insert(destination->id);
    save();
    saveSecrets();
    rebuildModels();
    return created;
}

void AppStore::moveNodes(const QVariantList &ids, const QString &destinationId)
{
    QSet<QString> idSet;
    for (const auto &id : ids)
        idSet.insert(id.toString());
    if (idSet.isEmpty() || idSet.contains(destinationId))
        return;

    NodePtr destination;
    if (!destinationId.isEmpty()) {
        destination = findNode(destinationId);
        if (!destination || !destination->folder)
            return;
        for (const auto &id : idSet) {
            if (contains(findNode(id), destinationId))
                return;
        }
    }

    auto *workspace = currentWorkspace();
    if (!workspace)
        return;

    // Keep the caller's order, drop duplicates, and skip nodes that already live
    // in the destination so a drop on the current folder background is a no-op.
    QList<QString> toMove;
    for (const auto &value : ids) {
        const QString id = value.toString();
        if (toMove.contains(id) || !findNode(id))
            continue;
        const auto parent = findParent(id);
        const QString parentId = parent ? parent->id : QString();
        if (parentId != destinationId)
            toMove.append(id);
    }
    if (toMove.isEmpty())
        return;

    QList<NodePtr> moved;
    for (const auto &id : toMove) {
        NodePtr node;
        if (detachNode(id, workspace->roots, node))
            moved.append(node);
    }
    auto *target = destination ? &destination->children : &workspace->roots;
    target->append(moved);
    if (destination)
        m_expandedIds.insert(destination->id);
    save();
    rebuildModels();
}

SiloWorkspace *AppStore::currentWorkspace()
{
    for (auto &workspace : m_workspaces) {
        if (workspace.id == m_currentWorkspaceId)
            return &workspace;
    }
    return m_workspaces.isEmpty() ? nullptr : &m_workspaces.first();
}

const SiloWorkspace *AppStore::currentWorkspace() const
{
    for (const auto &workspace : m_workspaces) {
        if (workspace.id == m_currentWorkspaceId)
            return &workspace;
    }
    return m_workspaces.isEmpty() ? nullptr : &m_workspaces.first();
}

AppStore::NodePtr AppStore::findNode(const QString &id) const
{
    if (id.isEmpty())
        return {};
    const auto *workspace = currentWorkspace();
    return workspace ? findNode(id, workspace->roots) : NodePtr{};
}

AppStore::NodePtr AppStore::findNode(const QString &id, const QList<NodePtr> &nodes) const
{
    for (const auto &node : nodes) {
        if (node->id == id)
            return node;
        if (const auto found = findNode(id, node->children))
            return found;
    }
    return {};
}

AppStore::NodePtr AppStore::findParent(const QString &id) const
{
    const auto *workspace = currentWorkspace();
    return workspace ? findParent(id, workspace->roots, {}) : NodePtr{};
}

AppStore::NodePtr AppStore::findParent(const QString &id, const QList<NodePtr> &nodes,
                                       const NodePtr &parent) const
{
    for (const auto &node : nodes) {
        if (node->id == id)
            return parent;
        if (const auto found = findParent(id, node->children, node))
            return found;
    }
    return {};
}

QList<AppStore::NodePtr> *AppStore::currentChildren()
{
    auto *workspace = currentWorkspace();
    if (!workspace)
        return nullptr;
    if (m_currentFolderId.isEmpty())
        return &workspace->roots;
    const auto folder = findNode(m_currentFolderId);
    return folder && folder->folder ? &folder->children : &workspace->roots;
}

bool AppStore::detachNode(const QString &id, QList<NodePtr> &nodes, NodePtr &result)
{
    for (qsizetype i = 0; i < nodes.size(); ++i) {
        if (nodes.at(i)->id == id) {
            result = nodes.takeAt(i);
            return true;
        }
        if (detachNode(id, nodes[i]->children, result))
            return true;
    }
    return false;
}

bool AppStore::contains(const NodePtr &node, const QString &id) const
{
    if (!node)
        return false;
    if (node->id == id)
        return true;
    for (const auto &child : node->children) {
        if (contains(child, id))
            return true;
    }
    return false;
}

void AppStore::appendTreeRows(const QList<NodePtr> &nodes, int depth, QList<TreeModel::Row> &rows) const
{
    for (const auto &node : nodes) {
        const bool expanded = m_expandedIds.contains(node->id);
        rows.append({node, depth, expanded, !node->children.isEmpty()});
        if (node->folder && expanded)
            appendTreeRows(node->children, depth + 1, rows);
    }
}

void AppStore::rebuildModels()
{
    m_workspaceModel.setItems(&m_workspaces, m_currentWorkspaceId);
    QList<TreeModel::Row> rows;
    if (const auto *workspace = currentWorkspace())
        appendTreeRows(workspace->roots, 0, rows);
    m_treeModel.setRows(std::move(rows));
    const auto *workspace = currentWorkspace();
    if (!workspace) {
        m_directoryModel.setItems({});
    } else if (const auto folder = findNode(m_currentFolderId)) {
        const auto parent = findParent(folder->id);
        m_directoryModel.setItems(folder->children, true, parent ? parent->id : QString());
    } else {
        m_directoryModel.setItems(workspace->roots);
    }
    ++m_revision;
    emit dataChanged();
}

QString AppStore::dataDirectory()
{
    const QByteArray override = qgetenv("SILO_DATA_DIR");
    const QString directory = override.isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        : QString::fromUtf8(override);
    QDir().mkpath(directory);
    return directory;
}

QString AppStore::webStoragePath() const
{
    if (qEnvironmentVariableIsEmpty("SILO_DATA_DIR"))
        return {};
    return dataDirectory() + QStringLiteral("/web");
}

QString AppStore::storagePath() const
{
    return dataDirectory() + QStringLiteral("/library.json");
}

void AppStore::load()
{
    QFile file(storagePath());
    if (file.open(QIODevice::ReadOnly)) {
        const auto document = QJsonDocument::fromJson(file.readAll());
        const auto workspaceArray = document.object().value(QStringLiteral("workspaces")).toArray();
        for (const auto &value : workspaceArray) {
            const auto object = value.toObject();
            SiloWorkspace workspace;
            workspace.id = object.value(QStringLiteral("id")).toString();
            workspace.name = object.value(QStringLiteral("name")).toString();
            workspace.color = object.value(QStringLiteral("color")).toString(QStringLiteral("#176E61"));
            workspace.iconType = object.value(QStringLiteral("iconType")).toString(QStringLiteral("emoji"));
            workspace.iconValue = object.value(QStringLiteral("iconValue")).toString(QStringLiteral("📦"));
            for (const auto &node : object.value(QStringLiteral("roots")).toArray())
                workspace.roots.append(nodeFromJson(node.toObject()));
            m_workspaces.append(workspace);
        }
    }

    if (m_workspaces.isEmpty()) {
        SiloWorkspace workspace;
        workspace.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        workspace.name = QStringLiteral("My Silo");
        workspace.color = QStringLiteral("#176E61");
        workspace.iconType = QStringLiteral("emoji");
        workspace.iconValue = QStringLiteral("📦");

        auto work = std::make_shared<SiloNode>();
        work->id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        work->name = QStringLiteral("Work");
        work->folder = true;
        auto design = std::make_shared<SiloNode>();
        design->id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        design->name = QStringLiteral("Design system");
        design->url = QStringLiteral("https://developer.apple.com/design/");
        work->children.append(design);
        workspace.roots.append(work);
        m_workspaces.append(workspace);
    }

    const QString savedId = QSettings().value(QStringLiteral("currentWorkspaceId")).toString();
    const auto found = std::find_if(m_workspaces.cbegin(), m_workspaces.cend(),
                                    [&](const auto &workspace) { return workspace.id == savedId; });
    m_currentWorkspaceId = found == m_workspaces.cend() ? m_workspaces.first().id : savedId;
    save();
}

void AppStore::save() const
{
    QJsonArray workspaceArray;
    for (const auto &workspace : m_workspaces) {
        QJsonArray roots;
        for (const auto &node : workspace.roots)
            roots.append(nodeToJson(node));
        workspaceArray.append(QJsonObject{
            {QStringLiteral("id"), workspace.id},
            {QStringLiteral("name"), workspace.name},
            {QStringLiteral("color"), workspace.color},
            {QStringLiteral("iconType"), workspace.iconType},
            {QStringLiteral("iconValue"), workspace.iconValue},
            {QStringLiteral("roots"), roots}
        });
    }
    QFile file(storagePath());
    if (file.open(QIODevice::WriteOnly))
        file.write(QJsonDocument(QJsonObject{{QStringLiteral("workspaces"), workspaceArray}})
                       .toJson(QJsonDocument::Indented));
}

QJsonObject AppStore::nodeToJson(const NodePtr &node)
{
    QJsonArray children;
    for (const auto &child : node->children)
        children.append(nodeToJson(child));
    QJsonObject object{{QStringLiteral("id"), node->id}, {QStringLiteral("name"), node->name},
                       {QStringLiteral("url"), node->url}, {QStringLiteral("folder"), node->folder},
                       {QStringLiteral("children"), children}};
    if (!node->folder && node->type != QStringLiteral("web"))
        object.insert(QStringLiteral("type"), node->type);
    if (!node->options.isEmpty())
        object.insert(QStringLiteral("options"), QJsonObject::fromVariantMap(node->options));
    if (!node->iconType.isEmpty()) {
        object.insert(QStringLiteral("iconType"), node->iconType);
        object.insert(QStringLiteral("iconValue"), node->iconValue);
    }
    if (!node->color.isEmpty())
        object.insert(QStringLiteral("color"), node->color);
    return object;
}

AppStore::NodePtr AppStore::nodeFromJson(const QJsonObject &object)
{
    auto node = std::make_shared<SiloNode>();
    node->id = object.value(QStringLiteral("id")).toString();
    node->name = object.value(QStringLiteral("name")).toString();
    node->url = object.value(QStringLiteral("url")).toString();
    node->folder = object.value(QStringLiteral("folder")).toBool();
    const QString type = object.value(QStringLiteral("type")).toString();
    node->type = type.isEmpty() ? QStringLiteral("web") : type;
    node->options = object.value(QStringLiteral("options")).toObject().toVariantMap();
    node->iconType = object.value(QStringLiteral("iconType")).toString();
    node->iconValue = object.value(QStringLiteral("iconValue")).toString();
    node->color = object.value(QStringLiteral("color")).toString();
    for (const auto &child : object.value(QStringLiteral("children")).toArray())
        node->children.append(nodeFromJson(child.toObject()));
    return node;
}

// ------------------------------------------------------------------ secrets

QString AppStore::secret(const QString &id) const
{
    loadSecrets();
    return m_secrets.value(id);
}

void AppStore::setSecret(const QString &id, const QString &value)
{
    loadSecrets();
    if (m_secrets.value(id) == value)
        return;
    if (value.isEmpty())
        m_secrets.remove(id);
    else
        m_secrets.insert(id, value);
    saveSecrets();
}

void AppStore::forgetSecrets(const NodePtr &node)
{
    loadSecrets();
    m_secrets.remove(node->id);
    for (const auto &child : node->children)
        forgetSecrets(child);
    saveSecrets();
}

void AppStore::loadSecrets() const
{
    if (m_secretsLoaded)
        return;
    m_secretsLoaded = true;
    QFile file(dataDirectory() + QStringLiteral("/secrets.json"));
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
    for (auto it = object.constBegin(); it != object.constEnd(); ++it)
        m_secrets.insert(it.key(), it.value().toString());
}

void AppStore::saveSecrets() const
{
    QSaveFile file(dataDirectory() + QStringLiteral("/secrets.json"));
    if (!file.open(QIODevice::WriteOnly))
        return;
    QJsonObject object;
    for (auto it = m_secrets.constBegin(); it != m_secrets.constEnd(); ++it)
        object.insert(it.key(), it.value());
    file.write(QJsonDocument(object).toJson(QJsonDocument::Compact));
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    file.commit();
}

// ------------------------------------------------------------------ transfer
//
// File layout (version 1):
// {
//   "format": "silo-workspace", "version": 1, "exportedAt": "<ISO 8601>",
//   "workspace": { name, color, iconType, iconValue, roots: [ nodes... ] },
//   "secrets": { "<node id>": "<ssh password>" }          // only when requested
// }
// Image icons (workspace or items) are embedded as data: URLs so the file stands alone.

void AppStore::countNodes(const QList<NodePtr> &nodes, int &folders, int &items)
{
    for (const auto &node : nodes) {
        if (node->folder) {
            ++folders;
            countNodes(node->children, folders, items);
        } else {
            ++items;
        }
    }
}

QString AppStore::embedIcon(const QString &value)
{
    if (value.isEmpty() || value.startsWith(QStringLiteral("data:")))
        return value;
    const QString path = localPathOf(QUrl(value));
    QFile file(path);
    if (path.isEmpty() || !file.exists() || file.size() > kMaxEmbeddedIconBytes
        || !file.open(QIODevice::ReadOnly))
        return value;
    const QByteArray bytes = file.readAll();
    const QString mime = QMimeDatabase().mimeTypeForFileNameAndData(path, bytes).name();
    return QStringLiteral("data:") + mime + QStringLiteral(";base64,") + QString::fromLatin1(bytes.toBase64());
}

// Writes an embedded data: URL into <data dir>/icons/<sha1>.<ext> and returns its file URL.
QString AppStore::materializeIcon(const QString &value)
{
    if (!value.startsWith(QStringLiteral("data:")))
        return value;
    const int comma = value.indexOf(QLatin1Char(','));
    if (comma < 0)
        return {};
    const QString header = value.mid(5, comma - 5); // "image/png;base64"
    const QString mime = header.section(QLatin1Char(';'), 0, 0);
    const QByteArray bytes = QByteArray::fromBase64(value.mid(comma + 1).toLatin1());
    if (bytes.isEmpty())
        return {};
    QString suffix = QMimeDatabase().mimeTypeForName(mime).preferredSuffix();
    if (suffix.isEmpty())
        suffix = QStringLiteral("img");
    const QString directory = dataDirectory() + QStringLiteral("/icons");
    QDir().mkpath(directory);
    const QString name = QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha1).toHex());
    const QString path = directory + QLatin1Char('/') + name + QLatin1Char('.') + suffix;
    if (!QFile::exists(path)) {
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly))
            return {};
        file.write(bytes);
        file.commit();
    }
    return QUrl::fromLocalFile(path).toString();
}

QJsonObject AppStore::workspaceToJson(const SiloWorkspace &workspace)
{
    std::function<QJsonObject(const NodePtr &)> convert = [&](const NodePtr &node) {
        QJsonObject object = nodeToJson(node);
        if (node->iconType == QStringLiteral("image"))
            object.insert(QStringLiteral("iconValue"), embedIcon(node->iconValue));
        if (!node->children.isEmpty()) {
            QJsonArray children;
            for (const auto &child : node->children)
                children.append(convert(child));
            object.insert(QStringLiteral("children"), children);
        }
        return object;
    };
    QJsonArray roots;
    for (const auto &node : workspace.roots)
        roots.append(convert(node));
    return QJsonObject{
        {QStringLiteral("name"), workspace.name},
        {QStringLiteral("color"), workspace.color},
        {QStringLiteral("iconType"), workspace.iconType},
        {QStringLiteral("iconValue"), workspace.iconType == QStringLiteral("image")
                                          ? embedIcon(workspace.iconValue) : workspace.iconValue},
        {QStringLiteral("roots"), roots}
    };
}

SiloWorkspace AppStore::workspaceFromJson(const QJsonObject &object)
{
    SiloWorkspace workspace;
    workspace.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    workspace.name = object.value(QStringLiteral("name")).toString().trimmed();
    if (workspace.name.isEmpty())
        workspace.name = QStringLiteral("Imported workspace");
    workspace.color = object.value(QStringLiteral("color")).toString(QStringLiteral("#176E61"));
    workspace.iconType = object.value(QStringLiteral("iconType")).toString(QStringLiteral("emoji"));
    workspace.iconValue = object.value(QStringLiteral("iconValue")).toString(QStringLiteral("📦"));
    for (const auto &node : object.value(QStringLiteral("roots")).toArray())
        workspace.roots.append(nodeFromJson(node.toObject()));
    return workspace;
}

bool AppStore::parseWorkspaceFile(const QUrl &fileUrl, QJsonObject &document, QString &error)
{
    const QString path = localPathOf(fileUrl);
    QFile file(path);
    if (path.isEmpty() || !file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("The file could not be opened.");
        return false;
    }
    QJsonParseError parseError;
    const auto json = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !json.isObject()) {
        error = QStringLiteral("This is not a valid JSON file (%1).").arg(parseError.errorString());
        return false;
    }
    document = json.object();
    if (document.value(QStringLiteral("format")).toString() != kTransferFormat
        || !document.value(QStringLiteral("workspace")).isObject()) {
        error = QStringLiteral("This file does not contain a Silo workspace.");
        return false;
    }
    if (document.value(QStringLiteral("version")).toInt(1) > kTransferVersion) {
        error = QStringLiteral("This workspace was exported by a newer version of Silo.");
        return false;
    }
    return true;
}

QVariantMap AppStore::workspaceSummary(const QString &id) const
{
    const auto found = std::find_if(m_workspaces.cbegin(), m_workspaces.cend(),
                                    [&](const auto &workspace) { return workspace.id == id; });
    if (found == m_workspaces.cend())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Unknown workspace.")}};
    int folders = 0, items = 0, secrets = 0;
    countNodes(found->roots, folders, items);
    loadSecrets();
    std::function<void(const QList<NodePtr> &)> visit = [&](const QList<NodePtr> &nodes) {
        for (const auto &node : nodes) {
            if (!m_secrets.value(node->id).isEmpty())
                ++secrets;
            visit(node->children);
        }
    };
    visit(found->roots);
    return {{QStringLiteral("ok"), true}, {QStringLiteral("id"), found->id},
            {QStringLiteral("name"), found->name}, {QStringLiteral("color"), found->color},
            {QStringLiteral("iconType"), found->iconType}, {QStringLiteral("iconValue"), found->iconValue},
            {QStringLiteral("folders"), folders}, {QStringLiteral("items"), items},
            {QStringLiteral("secrets"), secrets}};
}

QVariantMap AppStore::exportWorkspace(const QString &id, const QUrl &fileUrl, bool includeSecrets) const
{
    const auto found = std::find_if(m_workspaces.cbegin(), m_workspaces.cend(),
                                    [&](const auto &workspace) { return workspace.id == id; });
    if (found == m_workspaces.cend())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Unknown workspace.")}};

    QJsonObject document{
        {QStringLiteral("format"), kTransferFormat},
        {QStringLiteral("version"), kTransferVersion},
        {QStringLiteral("exportedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {QStringLiteral("workspace"), workspaceToJson(*found)}
    };
    int secretCount = 0;
    if (includeSecrets) {
        loadSecrets();
        QJsonObject secrets;
        std::function<void(const QList<NodePtr> &)> visit = [&](const QList<NodePtr> &nodes) {
            for (const auto &node : nodes) {
                if (const QString password = m_secrets.value(node->id); !password.isEmpty()) {
                    secrets.insert(node->id, password);
                    ++secretCount;
                }
                visit(node->children);
            }
        };
        visit(found->roots);
        if (!secrets.isEmpty())
            document.insert(QStringLiteral("secrets"), secrets);
    }

    const QString path = localPathOf(fileUrl);
    QSaveFile file(path);
    if (path.isEmpty() || !file.open(QIODevice::WriteOnly))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("The file could not be written.")}};
    file.write(QJsonDocument(document).toJson(QJsonDocument::Indented));
    if (secretCount > 0)
        file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    if (!file.commit())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("The file could not be written.")}};

    int folders = 0, items = 0;
    countNodes(found->roots, folders, items);
    return {{QStringLiteral("ok"), true}, {QStringLiteral("path"), path}, {QStringLiteral("name"), found->name},
            {QStringLiteral("folders"), folders}, {QStringLiteral("items"), items},
            {QStringLiteral("secrets"), secretCount}};
}

QVariantMap AppStore::inspectWorkspaceFile(const QUrl &fileUrl) const
{
    QJsonObject document;
    QString error;
    if (!parseWorkspaceFile(fileUrl, document, error))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), error},
                {QStringLiteral("path"), localPathOf(fileUrl)}};
    const SiloWorkspace workspace = workspaceFromJson(document.value(QStringLiteral("workspace")).toObject());
    int folders = 0, items = 0;
    countNodes(workspace.roots, folders, items);
    bool nameTaken = false;
    for (const auto &existing : m_workspaces)
        nameTaken = nameTaken || existing.name == workspace.name;
    return {{QStringLiteral("ok"), true}, {QStringLiteral("path"), localPathOf(fileUrl)},
            {QStringLiteral("name"), workspace.name}, {QStringLiteral("color"), workspace.color},
            {QStringLiteral("iconType"), workspace.iconType},
            // Preview only: keep data: URLs as they are (Image renders them directly).
            {QStringLiteral("iconValue"), workspace.iconValue},
            {QStringLiteral("folders"), folders}, {QStringLiteral("items"), items},
            {QStringLiteral("secrets"), document.value(QStringLiteral("secrets")).toObject().size()},
            {QStringLiteral("exportedAt"), document.value(QStringLiteral("exportedAt")).toString()},
            {QStringLiteral("nameTaken"), nameTaken}};
}

QVariantMap AppStore::importWorkspace(const QUrl &fileUrl, bool includeSecrets)
{
    QJsonObject document;
    QString error;
    if (!parseWorkspaceFile(fileUrl, document, error))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), error}};

    SiloWorkspace workspace = workspaceFromJson(document.value(QStringLiteral("workspace")).toObject());
    if (workspace.iconType == QStringLiteral("image"))
        workspace.iconValue = materializeIcon(workspace.iconValue);

    // Fresh ids everywhere (the same file may be imported twice, or come from this very
    // library), remembering the mapping so the exported passwords follow their items.
    const QJsonObject secrets = includeSecrets ? document.value(QStringLiteral("secrets")).toObject() : QJsonObject();
    int imported = 0;
    loadSecrets();
    std::function<void(const NodePtr &)> refresh = [&](const NodePtr &node) {
        const QString oldId = node->id;
        node->id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        if (node->type.isEmpty())
            node->type = QStringLiteral("web");
        if (node->iconType == QStringLiteral("image"))
            node->iconValue = materializeIcon(node->iconValue);
        if (const QString password = secrets.value(oldId).toString(); !password.isEmpty()) {
            m_secrets.insert(node->id, password);
            ++imported;
        }
        for (const auto &child : node->children)
            refresh(child);
    };
    for (const auto &node : workspace.roots)
        refresh(node);

    // "Name" -> "Name (imported)" -> "Name (imported 2)" when it already exists.
    auto nameTaken = [&](const QString &name) {
        for (const auto &existing : m_workspaces) {
            if (existing.name == name)
                return true;
        }
        return false;
    };
    if (nameTaken(workspace.name)) {
        const QString base = workspace.name + QStringLiteral(" (imported");
        QString candidate = base + QLatin1Char(')');
        for (int n = 2; nameTaken(candidate); ++n)
            candidate = base + QLatin1Char(' ') + QString::number(n) + QLatin1Char(')');
        workspace.name = candidate;
    }

    int folders = 0, items = 0;
    countNodes(workspace.roots, folders, items);
    const QString id = workspace.id;
    const QString name = workspace.name;
    if (imported > 0)
        saveSecrets();
    adoptWorkspace(std::move(workspace));
    return {{QStringLiteral("ok"), true}, {QStringLiteral("id"), id}, {QStringLiteral("name"), name},
            {QStringLiteral("folders"), folders}, {QStringLiteral("items"), items},
            {QStringLiteral("secrets"), imported}};
}
