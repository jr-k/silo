#pragma once

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QProcessEnvironment>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QList>

#include <functional>

class QNetworkAccessManager;
class QNetworkReply;

// Connectors to password managers' command line tools (1Password `op`,
// Bitwarden `bw`, Dashlane `dcli`) so Live mode can fill logins into the
// embedded browser. Silo downloads the CLIs itself into its data directory
// when they are missing, so nothing has to be installed by hand. Session
// tokens stay in memory.
class PasswordManager final : public QObject
{
    Q_OBJECT
    // [{id, name, installed, cliPath, managed, enabled, auth, account, version,
    //   installing, installProgress, installError, usable, hint}]
    // auth: "unknown" | "signed-out" | "locked" | "unlocked" | "syncing"
    Q_PROPERTY(QVariantList connectors READ connectors NOTIFY connectorsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Most recent error, any connector
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    // Last error per connector id, so one manager failing never hides another
    Q_PROPERTY(QVariantMap errors READ errors NOTIFY errorChanged)
    // Enabled connectors that can answer a search right now
    Q_PROPERTY(int usableCount READ usableCount NOTIFY connectorsChanged)
    // Enabled connectors waiting for a password (Bitwarden / 1Password unlock)
    Q_PROPERTY(QStringList lockedConnectors READ lockedConnectors NOTIFY connectorsChanged)

public:
    explicit PasswordManager(QObject *parent = nullptr);
    ~PasswordManager() override;

    QVariantList connectors() const;
    Q_INVOKABLE QVariantMap connector(const QString &id) const;
    bool busy() const { return m_busy > 0; }
    QString error() const { return m_error; }
    QVariantMap errors() const;
    int usableCount() const;
    QStringList lockedConnectors() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setEnabled(const QString &id, bool enabled);
    // Download the CLI into <data>/bin (no admin rights) -> installFinished
    Q_INVOKABLE void install(const QString &id);
    Q_INVOKABLE void uninstall(const QString &id);
    Q_INVOKABLE QString binDirectory() const;
    // Interactive sign-in / registration to run in a Silo terminal ([program, args…])
    Q_INVOKABLE QStringList signInCommand(const QString &id) const;
    Q_INVOKABLE bool needsInteractiveSignIn(const QString &id) const;

    // Logins matching the page host from every usable connector
    // -> resultsReady(url, source, items) per connector, then searchFinished(url)
    Q_INVOKABLE void search(const QString &url);
    // Full credentials for one result -> credentialsReady({source, id, title, username, password, totp})
    Q_INVOKABLE void fetch(const QString &source, const QString &id);
    // Bitwarden: master password; 1Password without app integration: account
    // password (account = 1Password account uuid, needed when several are signed in)
    Q_INVOKABLE void unlock(const QString &id, const QString &password, const QString &account = {});
    Q_INVOKABLE void lock(const QString &id);
    Q_INVOKABLE void signOut(const QString &id);
    // Without id: every connector
    Q_INVOKABLE void clearError(const QString &id = {});
    Q_INVOKABLE QString hostOf(const QString &url) const;

signals:
    void connectorsChanged();
    void busyChanged();
    void errorChanged();
    void resultsReady(const QString &url, const QString &source, const QVariantList &items);
    void searchFinished(const QString &url);
    void credentialsReady(const QVariantMap &credentials);
    void unlocked(const QString &id);
    void installFinished(const QString &id, bool ok, const QString &message);

private:
    struct Connector {
        QString id, name, binary, cliPath, auth = QStringLiteral("unknown"), account, version, hint;
        bool enabled = true;
        bool installing = false;
        int installProgress = 0;
        QString installError;
    };
    using Callback = std::function<void(int exitCode, const QByteArray &out, const QByteArray &err)>;

    Connector *find(const QString &id);
    const Connector *find(const QString &id) const;
    bool usable(const Connector &connector) const;
    void run(const Connector &connector, const QStringList &args, const Callback &callback,
             const QProcessEnvironment &extraEnv = {}, int timeoutMs = 90000, const QByteArray &stdinData = {});
    void setError(const QString &id, const QString &error);
    void setBusy(int delta);
    void setAuth(Connector &connector, const QString &auth, const QString &account = {});
    QString findCli(const QString &binary) const;
    void detect();
    void refreshStatus(const QString &id);
    static bool hostMatches(const QString &itemHost, const QString &pageHost);
    static QString friendlyError(const QString &id, const QByteArray &stderrText);
    void searchDone(const QString &url);

    // installer
    void download(const QString &id, const QUrl &url, const std::function<void(const QByteArray &)> &done);
    void finishInstall(const QString &id, const QString &version, const QByteArray &payload, bool zipped);
    void failInstall(const QString &id, const QString &message);

    struct OpAccount {
        // logoUrl: site whose favicon stands for the organisation (e-mail domain), or empty
        QString uuid, label, shortLabel, logoUrl, sessionVar, sessionToken;
        bool locked = false;
        QVariantList items;
        QDateTime fetched;
    };
    OpAccount *opAccount(const QString &uuid);
    void opUpdateAuth(Connector &connector);
    void opRefresh(Connector &connector);
    void opSearch(const QString &url, const QString &host);
    void opFetch(const QString &id);
    void opUnlock(const QString &password, const QString &account);
    void bwRefresh(Connector &connector);
    void bwSearch(const QString &url, const QString &host);
    void bwFetch(const QString &id);
    void bwUnlock(const QString &password);
    void dcliRefresh(Connector &connector);
    void dcliSearch(const QString &url, const QString &host);
    void dcliFetch(const QString &id);

    QList<Connector> m_connectors;
    int m_busy = 0;
    QString m_error;
    QHash<QString, QString> m_errors;
    QNetworkAccessManager *m_network = nullptr;
    QHash<QString, int> m_pendingSearches;

    // 1Password: one entry per signed-in account (every `op` call must name its
    // account, otherwise the CLI prompts for one), with item cache and session
    QList<OpAccount> m_opAccounts;

    // Bitwarden: in-memory session key and last results (they already hold the secrets)
    QString m_bwSession;
    QHash<QString, QVariantMap> m_bwItems;

    // Dashlane: last results
    QHash<QString, QVariantMap> m_dcliItems;
};
