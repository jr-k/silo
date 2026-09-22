#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariant>

// Live-mode layout persisted next to the library (<data dir>/session.json):
// open tabs per workspace, active tab, UI mode, sidebar visibility…
// Every change is written atomically right away, so nothing is lost if the
// app is killed instead of closed.
class SessionStore final : public QObject
{
    Q_OBJECT
public:
    explicit SessionStore(QObject *parent = nullptr);

    Q_INVOKABLE QVariant value(const QString &key, const QVariant &fallback = {}) const;
    Q_INVOKABLE void setValue(const QString &key, const QVariant &value);
    Q_INVOKABLE void remove(const QString &key);

    // Tabs of one workspace: {"ids": [nodeId…], "current": index, "manualOrder": bool}
    QJsonObject tabs(const QString &workspaceId) const;
    void setTabs(const QString &workspaceId, const QStringList &ids, int current, bool manualOrder);
    void forgetTabs(const QString &workspaceId);

    static QString filePath();

private:
    void load();
    void save() const;

    QJsonObject m_root;
};
