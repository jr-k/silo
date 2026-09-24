#include "SessionStore.h"

#include "AppStore.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>

SessionStore::SessionStore(QObject *parent) : QObject(parent)
{
    load();
}

QString SessionStore::filePath()
{
    return AppStore::dataDirectory() + QStringLiteral("/session.json");
}

void SessionStore::load()
{
    QFile file(filePath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const auto document = QJsonDocument::fromJson(file.readAll());
    if (document.isObject())
        m_root = document.object();
}

void SessionStore::save() const
{
    QSaveFile file(filePath());
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(m_root).toJson(QJsonDocument::Indented));
    file.commit();
}

QVariant SessionStore::value(const QString &key, const QVariant &fallback) const
{
    const auto it = m_root.constFind(key);
    return it == m_root.constEnd() ? fallback : it->toVariant();
}

void SessionStore::setValue(const QString &key, const QVariant &value)
{
    const QJsonValue json = QJsonValue::fromVariant(value);
    if (m_root.value(key) == json)
        return;
    m_root.insert(key, json);
    save();
}

void SessionStore::remove(const QString &key)
{
    if (!m_root.contains(key))
        return;
    m_root.remove(key);
    save();
}

QJsonObject SessionStore::tabs(const QString &workspaceId) const
{
    return m_root.value(QStringLiteral("tabs")).toObject().value(workspaceId).toObject();
}

void SessionStore::setTabs(const QString &workspaceId, const QStringList &ids, int current, bool manualOrder)
{
    QJsonObject all = m_root.value(QStringLiteral("tabs")).toObject();
    const QJsonObject entry{{QStringLiteral("ids"), QJsonArray::fromStringList(ids)},
                            {QStringLiteral("current"), current},
                            {QStringLiteral("manualOrder"), manualOrder}};
    if (all.value(workspaceId) == entry)
        return;
    all.insert(workspaceId, entry);
    m_root.insert(QStringLiteral("tabs"), all);
    save();
}

void SessionStore::forgetTabs(const QString &workspaceId)
{
    QJsonObject all = m_root.value(QStringLiteral("tabs")).toObject();
    if (!all.contains(workspaceId))
        return;
    all.remove(workspaceId);
    m_root.insert(QStringLiteral("tabs"), all);
    save();
}

QStringList SessionStore::expandedFolders(const QString &workspaceId) const
{
    QStringList ids;
    const QJsonArray array = m_root.value(QStringLiteral("expandedFolders")).toObject()
                                 .value(workspaceId).toArray();
    ids.reserve(array.size());
    for (const auto &value : array)
        ids.append(value.toString());
    return ids;
}

void SessionStore::setExpandedFolders(const QString &workspaceId, const QStringList &ids)
{
    QJsonObject all = m_root.value(QStringLiteral("expandedFolders")).toObject();
    const QJsonArray entry = QJsonArray::fromStringList(ids);
    if (all.value(workspaceId) == entry)
        return;
    all.insert(workspaceId, entry);
    m_root.insert(QStringLiteral("expandedFolders"), all);
    save();
}

void SessionStore::forgetExpandedFolders(const QString &workspaceId)
{
    QJsonObject all = m_root.value(QStringLiteral("expandedFolders")).toObject();
    if (!all.contains(workspaceId))
        return;
    all.remove(workspaceId);
    m_root.insert(QStringLiteral("expandedFolders"), all);
    save();
}
