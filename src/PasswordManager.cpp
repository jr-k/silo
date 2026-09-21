#include "PasswordManager.h"

#include "AppStore.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTimer>
#include <QUrl>
#include <QUuid>

#include <memory>

namespace {
const auto kEnabledKey = QStringLiteral("passwords/connectors/%1/enabled");
constexpr int kOpCacheSeconds = 10 * 60;
const auto kOnePassword = QStringLiteral("1password");
const auto kBitwarden = QStringLiteral("bitwarden");
const auto kDashlane = QStringLiteral("dashlane");

QString stripWww(QString host)
{
    host = host.toLower();
    if (host.startsWith(QStringLiteral("www.")))
        host.remove(0, 4);
    return host;
}

QString hostFromAny(const QString &text)
{
    QString t = text.trimmed();
    if (t.isEmpty())
        return {};
    if (!t.contains(QStringLiteral("://")))
        t.prepend(QStringLiteral("https://"));
    return stripWww(QUrl(t).host());
}

bool isArm()
{
    const QString arch = QSysInfo::currentCpuArchitecture();
    return arch.startsWith(QStringLiteral("arm")) || arch == QStringLiteral("aarch64");
}

// Site whose favicon can stand for the organisation behind an e-mail address:
// its domain, unless it is a public mailbox provider.
QString organisationSite(const QString &email)
{
    const QString domain = email.section(QLatin1Char('@'), 1).trimmed().toLower();
    if (domain.isEmpty() || !domain.contains(QLatin1Char('.')))
        return {};
    static const QStringList publicProviders{
        QStringLiteral("gmail.com"), QStringLiteral("googlemail.com"), QStringLiteral("outlook.com"), QStringLiteral("hotmail.com"),
        QStringLiteral("hotmail.fr"), QStringLiteral("live.com"), QStringLiteral("live.fr"), QStringLiteral("msn.com"),
        QStringLiteral("yahoo.com"), QStringLiteral("yahoo.fr"), QStringLiteral("ymail.com"), QStringLiteral("icloud.com"),
        QStringLiteral("me.com"), QStringLiteral("mac.com"), QStringLiteral("protonmail.com"), QStringLiteral("proton.me"),
        QStringLiteral("pm.me"), QStringLiteral("fastmail.com"), QStringLiteral("hey.com"), QStringLiteral("gmx.com"),
        QStringLiteral("gmx.fr"), QStringLiteral("gmx.de"), QStringLiteral("free.fr"), QStringLiteral("orange.fr"),
        QStringLiteral("wanadoo.fr"), QStringLiteral("sfr.fr"), QStringLiteral("laposte.net"), QStringLiteral("aol.com"),
        QStringLiteral("mail.com"), QStringLiteral("zoho.com"), QStringLiteral("tutanota.com"), QStringLiteral("tuta.io")};
    if (publicProviders.contains(domain))
        return {};
    return QStringLiteral("https://") + domain;
}

QString exeName(const QString &binary)
{
#ifdef Q_OS_WIN
    return binary + QStringLiteral(".exe");
#else
    return binary;
#endif
}
} // namespace

PasswordManager::PasswordManager(QObject *parent) : QObject(parent), m_network(new QNetworkAccessManager(this))
{
    m_network->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);

    Connector bitwarden;
    bitwarden.id = kBitwarden;
    bitwarden.name = QStringLiteral("Bitwarden");
    bitwarden.binary = QStringLiteral("bw");
    Connector onePassword;
    onePassword.id = kOnePassword;
    onePassword.name = QStringLiteral("1Password");
    onePassword.binary = QStringLiteral("op");
    Connector dashlane;
    dashlane.id = kDashlane;
    dashlane.name = QStringLiteral("Dashlane");
    dashlane.binary = QStringLiteral("dcli");
    m_connectors = {bitwarden, onePassword, dashlane};

    QSettings settings;
    for (Connector &connector : m_connectors)
        connector.enabled = settings.value(kEnabledKey.arg(connector.id), true).toBool();
    // Only look for the CLIs on disk here. Their status is probed on first use
    // (see needsProbe): spawning `op` at launch would trigger the macOS
    // "access data from other apps" prompt every time Silo starts.
    detect();
}

// Child CLIs still running at exit are killed rather than left orphaned.
PasswordManager::~PasswordManager()
{
    for (QProcess *process : findChildren<QProcess *>()) {
        process->disconnect(this);
        if (process->state() != QProcess::NotRunning) {
            process->kill();
            process->waitForFinished(1000);
        }
    }
}

// ------------------------------------------------------------------ state

PasswordManager::Connector *PasswordManager::find(const QString &id)
{
    for (Connector &connector : m_connectors)
        if (connector.id == id)
            return &connector;
    return nullptr;
}

const PasswordManager::Connector *PasswordManager::find(const QString &id) const
{
    for (const Connector &connector : m_connectors)
        if (connector.id == id)
            return &connector;
    return nullptr;
}

// Can answer a search without further user input
bool PasswordManager::usable(const Connector &connector) const
{
    if (!connector.enabled || connector.cliPath.isEmpty())
        return false;
    // 1Password is asked again even when locked: the desktop app may have
    // been unlocked since, and the request itself triggers its prompt.
    if (connector.id == kOnePassword && connector.auth == QStringLiteral("locked"))
        return true;
    return connector.auth == QStringLiteral("unlocked") || connector.auth == QStringLiteral("ready");
}

QVariantList PasswordManager::connectors() const
{
    QVariantList list;
    for (const Connector &connector : m_connectors)
        list.append(this->connector(connector.id));
    return list;
}

QVariantMap PasswordManager::connector(const QString &id) const
{
    const Connector *connector = find(id);
    if (!connector)
        return {};
    // 1Password: signed-in accounts, so the UI can pick which one to unlock
    QVariantList accounts;
    if (id == kOnePassword) {
        for (const OpAccount &account : m_opAccounts)
            accounts.append(QVariantMap{{QStringLiteral("id"), account.uuid}, {QStringLiteral("label"), account.label},
                                        {QStringLiteral("shortLabel"), account.shortLabel}, {QStringLiteral("locked"), account.locked},
                                        {QStringLiteral("unlocked"), !account.sessionToken.isEmpty()},
                                        {QStringLiteral("logoUrl"), account.logoUrl}});
    }
    return {{QStringLiteral("id"), connector->id},
            {QStringLiteral("name"), connector->name},
            {QStringLiteral("binary"), connector->binary},
            {QStringLiteral("installed"), !connector->cliPath.isEmpty()},
            {QStringLiteral("cliPath"), connector->cliPath},
            {QStringLiteral("managed"), !connector->cliPath.isEmpty() && connector->cliPath.startsWith(binDirectory())},
            {QStringLiteral("enabled"), connector->enabled},
            {QStringLiteral("auth"), connector->auth},
            {QStringLiteral("account"), connector->account},
            {QStringLiteral("version"), connector->version},
            {QStringLiteral("installing"), connector->installing},
            {QStringLiteral("installProgress"), connector->installProgress},
            {QStringLiteral("installError"), connector->installError},
            {QStringLiteral("usable"), usable(*connector)},
            {QStringLiteral("accounts"), accounts},
            {QStringLiteral("hint"), connector->hint}};
}

int PasswordManager::usableCount() const
{
    int count = 0;
    for (const Connector &connector : m_connectors)
        if (usable(connector))
            ++count;
    return count;
}

// Enabled and installed, but its CLI has never been asked its status
bool PasswordManager::needsProbe(const Connector &connector) const
{
    return connector.enabled && !connector.cliPath.isEmpty() && !m_probed.contains(connector.id);
}

int PasswordManager::unprobedCount() const
{
    int count = 0;
    for (const Connector &connector : m_connectors)
        if (needsProbe(connector))
            ++count;
    return count;
}

QStringList PasswordManager::lockedConnectors() const
{
    QStringList list;
    for (const Connector &connector : m_connectors) {
        if (!connector.enabled || connector.cliPath.isEmpty() || connector.id == kDashlane)
            continue;
        bool locked = connector.auth == QStringLiteral("locked");
        // 1Password: offer the unlock form as long as one of the accounts refused us
        if (connector.id == kOnePassword)
            for (const OpAccount &account : m_opAccounts)
                locked = locked || account.locked;
        if (locked)
            list.append(connector.id);
    }
    return list;
}

void PasswordManager::setEnabled(const QString &id, bool enabled)
{
    Connector *connector = find(id);
    if (!connector || connector->enabled == enabled)
        return;
    connector->enabled = enabled;
    QSettings().setValue(kEnabledKey.arg(id), enabled);
    emit connectorsChanged();
    if (enabled)
        refreshStatus(id);
}

QVariantMap PasswordManager::errors() const
{
    QVariantMap map;
    for (auto it = m_errors.cbegin(); it != m_errors.cend(); ++it)
        map.insert(it.key(), it.value());
    return map;
}

// Always notifies on a new failure (even the same message twice) so the UI
// can react to a retry that failed again.
void PasswordManager::setError(const QString &id, const QString &error)
{
    if (error.isEmpty()) {
        if (!m_errors.contains(id))
            return;
        m_errors.remove(id);
        m_error = m_errors.isEmpty() ? QString() : m_errors.cbegin().value();
    } else {
        m_errors.insert(id, error);
        m_error = error;
    }
    emit errorChanged();
}

void PasswordManager::clearError(const QString &id)
{
    if (!id.isEmpty()) {
        setError(id, {});
        return;
    }
    if (m_errors.isEmpty() && m_error.isEmpty())
        return;
    m_errors.clear();
    m_error.clear();
    emit errorChanged();
}

void PasswordManager::setBusy(int delta)
{
    const bool was = busy();
    m_busy = qMax(0, m_busy + delta);
    if (was != busy())
        emit busyChanged();
}

void PasswordManager::setAuth(Connector &connector, const QString &auth, const QString &account)
{
    if (connector.auth == auth && connector.account == account)
        return;
    connector.auth = auth;
    connector.account = account;
    emit connectorsChanged();
}

QString PasswordManager::hostOf(const QString &url) const
{
    return hostFromAny(url);
}

// Same registrable site: exact host, or one is a sub-domain of the other.
bool PasswordManager::hostMatches(const QString &itemHost, const QString &pageHost)
{
    if (itemHost.isEmpty() || pageHost.isEmpty())
        return false;
    if (itemHost == pageHost)
        return true;
    return pageHost.endsWith(QLatin1Char('.') + itemHost) || itemHost.endsWith(QLatin1Char('.') + pageHost);
}

// ------------------------------------------------------------------ detection

QString PasswordManager::binDirectory() const
{
    return AppStore::dataDirectory() + QStringLiteral("/bin");
}

// Silo's own bin first, then PATH, then the usual install locations GUI apps
// do not see on macOS.
QString PasswordManager::findCli(const QString &binary) const
{
    const QString managed = binDirectory() + QLatin1Char('/') + exeName(binary);
    if (QFile::exists(managed))
        return managed;
    const QStringList extra{QStringLiteral("/opt/homebrew/bin"), QStringLiteral("/usr/local/bin"),
                            QDir::homePath() + QStringLiteral("/.local/bin"), QStringLiteral("/snap/bin"),
                            QDir::homePath() + QStringLiteral("/.npm-global/bin"),
                            QDir::homePath() + QStringLiteral("/AppData/Roaming/npm")};
    QString path = QStandardPaths::findExecutable(binary);
    if (path.isEmpty())
        path = QStandardPaths::findExecutable(binary, extra);
    return path;
}

void PasswordManager::detect()
{
    for (Connector &connector : m_connectors) {
        connector.cliPath = findCli(connector.binary);
        if (connector.cliPath.isEmpty()) {
            connector.auth = QStringLiteral("unknown");
            connector.account.clear();
            connector.version.clear();
        }
    }
    emit connectorsChanged();
}

void PasswordManager::refresh()
{
    detect();
    for (const Connector &connector : m_connectors)
        if (!connector.cliPath.isEmpty() && connector.enabled)
            refreshStatus(connector.id);
}

void PasswordManager::refreshStatus(const QString &id)
{
    Connector *connector = find(id);
    if (!connector || connector->cliPath.isEmpty() || m_probing.contains(id))
        return;
    m_probing.insert(id);
    if (id == kBitwarden)
        bwRefresh(*connector);
    else if (id == kOnePassword)
        opRefresh(*connector);
    else if (id == kDashlane)
        dcliRefresh(*connector);
}

// Called once per status probe, whatever its outcome. Runs the search that
// was waiting for the first probes as soon as the last one has answered.
void PasswordManager::probeDone(const QString &id)
{
    m_probing.remove(id);
    m_probed.insert(id);
    emit connectorsChanged();
    if (m_probing.isEmpty() && !m_deferredSearch.isEmpty()) {
        const QString url = m_deferredSearch;
        m_deferredSearch.clear();
        search(url);
    }
}

// ------------------------------------------------------------------ process plumbing

QString PasswordManager::friendlyError(const QString &id, const QByteArray &stderrText)
{
    // Drop Node.js deprecation chatter the CLIs print before their own message
    QStringList lines;
    for (const QString &line : QString::fromUtf8(stderrText).split(QLatin1Char('\n'))) {
        const QString trimmed = line.trimmed();
        if (trimmed.isEmpty() || trimmed.startsWith(QStringLiteral("(node:")) || trimmed.startsWith(QStringLiteral("(Use `node")))
            continue;
        lines.append(trimmed);
    }
    const QString text = lines.join(QLatin1Char('\n'));
    const QString lower = text.toLower();
    if (id == kOnePassword) {
        if (lower.contains(QStringLiteral("connect to the 1password desktop app")) || lower.contains(QStringLiteral("connecting to desktop app")))
            return QStringLiteral("1Password CLI could not reach the 1Password app. Make sure the app is running and unlocked, "
                                  "with Settings › Developer › “Integrate with 1Password CLI” turned on, then search again.");
        if (lower.contains(QStringLiteral("context deadline exceeded")))
            return QStringLiteral("1Password did not answer in time. Unlock the app and approve the request it shows, then search again.");
        if (lower.contains(QStringLiteral("not currently signed in")) || lower.contains(QStringLiteral("no account found"))
            || lower.contains(QStringLiteral("no accounts configured")) || lower.contains(QStringLiteral("sign in"))
            || lower.contains(QStringLiteral("authorization prompt dismissed")) || lower.contains(QStringLiteral("authorization timeout"))
            || lower.contains(QStringLiteral("session expired")))
            return QStringLiteral("1Password needs to be unlocked.");
    } else if (id == kBitwarden) {
        if (lower.contains(QStringLiteral("not logged in")))
            return QStringLiteral("Bitwarden is not signed in.");
        if (lower.contains(QStringLiteral("invalid master password")))
            return QStringLiteral("Invalid master password.");
        if (lower.contains(QStringLiteral("vault is locked")))
            return QStringLiteral("The Bitwarden vault is locked.");
    } else if (id == kDashlane) {
        if (lower.contains(QStringLiteral("master password")) || lower.contains(QStringLiteral("locked")))
            return QStringLiteral("Dashlane is locked: sign in again from Settings.");
        if (lower.contains(QStringLiteral("login")) || lower.contains(QStringLiteral("device")))
            return QStringLiteral("Dashlane is not signed in.");
    }
    if (text.isEmpty())
        return QStringLiteral("The password manager CLI failed.");
    // First line only: the CLIs print usage blurbs after the actual message
    return text.section(QLatin1Char('\n'), 0, 0).left(300);
}

void PasswordManager::run(const Connector &connector, const QStringList &args, const Callback &callback,
                          const QProcessEnvironment &extraEnv, int timeoutMs, const QByteArray &stdinData)
{
    auto *process = new QProcess(this);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    for (const QString &key : extraEnv.keys())
        env.insert(key, extraEnv.value(key));
    // Let the CLI find its helpers (biometric agent, node) even from a GUI PATH
    env.insert(QStringLiteral("PATH"), env.value(QStringLiteral("PATH")) + QStringLiteral(":/opt/homebrew/bin:/usr/local/bin"));
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    process->setProcessEnvironment(env);
    process->setProgram(connector.cliPath);
    process->setArguments(args);

    auto *timeout = new QTimer(process);
    timeout->setSingleShot(true);
    timeout->setInterval(timeoutMs);
    connect(timeout, &QTimer::timeout, process, [process] { process->kill(); });

    setBusy(+1);
    connect(process, &QProcess::finished, this, [this, process, callback](int exitCode, QProcess::ExitStatus status) {
        setBusy(-1);
        const QByteArray out = process->readAllStandardOutput();
        QByteArray err = process->readAllStandardError();
        if (status == QProcess::CrashExit && err.isEmpty())
            err = "The command timed out or crashed.";
        process->deleteLater();
        callback(status == QProcess::NormalExit ? exitCode : -1, out, err);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, callback](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        setBusy(-1);
        process->deleteLater();
        callback(-1, {}, QByteArrayLiteral("Could not start the password manager CLI."));
    });
    timeout->start();
    process->start();
    if (!stdinData.isEmpty())
        process->write(stdinData);
    process->closeWriteChannel();
}

// ------------------------------------------------------------------ public API

void PasswordManager::search(const QString &url)
{
    const QString host = hostFromAny(url);
    // First search of the session: ask the CLIs their status first, the search
    // resumes from probeDone() once they have all answered.
    QStringList toProbe;
    for (const Connector &connector : m_connectors)
        if (needsProbe(connector))
            toProbe.append(connector.id);
    if (!host.isEmpty() && !toProbe.isEmpty()) {
        m_deferredSearch = url;
        for (const QString &id : toProbe)
            refreshStatus(id);
        return;
    }
    QStringList sources;
    for (const Connector &connector : m_connectors)
        if (usable(connector)) {
            sources.append(connector.id);
            clearError(connector.id);
        }
    if (host.isEmpty() || sources.isEmpty()) {
        emit searchFinished(url);
        return;
    }
    m_pendingSearches[url] = int(sources.size());
    for (const QString &source : sources) {
        if (source == kOnePassword)
            opSearch(url, host);
        else if (source == kBitwarden)
            bwSearch(url, host);
        else if (source == kDashlane)
            dcliSearch(url, host);
    }
}

void PasswordManager::searchDone(const QString &url)
{
    if (!m_pendingSearches.contains(url))
        return;
    if (--m_pendingSearches[url] <= 0) {
        m_pendingSearches.remove(url);
        emit searchFinished(url);
    }
}

void PasswordManager::fetch(const QString &source, const QString &id)
{
    clearError(source);
    if (source == kOnePassword)
        opFetch(id);
    else if (source == kBitwarden)
        bwFetch(id);
    else if (source == kDashlane)
        dcliFetch(id);
}

void PasswordManager::unlock(const QString &id, const QString &password, const QString &account)
{
    // 1Password accepts an empty password: the desktop app does the unlocking
    if (password.isEmpty() && id != kOnePassword)
        return;
    clearError(id);
    if (id == kBitwarden)
        bwUnlock(password);
    else if (id == kOnePassword)
        opUnlock(password, account);
}

void PasswordManager::lock(const QString &id)
{
    Connector *connector = find(id);
    if (!connector)
        return;
    if (id == kBitwarden) {
        m_bwSession.clear();
        m_bwItems.clear();
        if (!connector->cliPath.isEmpty())
            run(*connector, {QStringLiteral("lock")}, [](int, const QByteArray &, const QByteArray &) {}, {}, 20000);
        if (connector->auth == QStringLiteral("unlocked"))
            setAuth(*connector, QStringLiteral("locked"), connector->account);
    } else if (id == kOnePassword) {
        for (OpAccount &account : m_opAccounts) {
            account.items.clear();
            account.sessionToken.clear();
            account.sessionVar.clear();
            account.locked = false;
        }
        if (!connector->cliPath.isEmpty())
            run(*connector, {QStringLiteral("signout"), QStringLiteral("--all")}, [](int, const QByteArray &, const QByteArray &) {}, {}, 20000);
        opUpdateAuth(*connector);
    } else if (id == kDashlane) {
        m_dcliItems.clear();
        if (!connector->cliPath.isEmpty())
            run(*connector, {QStringLiteral("lock")}, [this, id](int, const QByteArray &, const QByteArray &) { refreshStatus(id); }, {}, 20000);
    }
}

void PasswordManager::signOut(const QString &id)
{
    Connector *connector = find(id);
    if (!connector || connector->cliPath.isEmpty())
        return;
    QStringList args;
    QProcessEnvironment env;
    if (id == kBitwarden) {
        args = {QStringLiteral("logout")};
        m_bwSession.clear();
        m_bwItems.clear();
    } else if (id == kOnePassword) {
        args = {QStringLiteral("signout"), QStringLiteral("--forget"), QStringLiteral("--all")};
        m_opAccounts.clear();
    } else if (id == kDashlane) {
        args = {QStringLiteral("logout"), QStringLiteral("--ignore-revocation")};
        m_dcliItems.clear();
    }
    run(*connector, args, [this, id](int, const QByteArray &, const QByteArray &) { refreshStatus(id); }, env, 30000);
}

// Interactive flows (2FA, device registration) run in a Silo terminal.
QStringList PasswordManager::signInCommand(const QString &id) const
{
    const Connector *connector = find(id);
    if (!connector || connector->cliPath.isEmpty())
        return {};
    if (id == kBitwarden)
        return {connector->cliPath, QStringLiteral("login")};
    if (id == kOnePassword)
        return {connector->cliPath, QStringLiteral("account"), QStringLiteral("add"), QStringLiteral("--signin")};
    if (id == kDashlane)
        return {connector->cliPath, QStringLiteral("sync")};
    return {};
}

bool PasswordManager::needsInteractiveSignIn(const QString &id) const
{
    const Connector *connector = find(id);
    if (!connector || connector->cliPath.isEmpty())
        return false;
    if (connector->auth == QStringLiteral("signed-out"))
        return true;
    // Dashlane unlocks through its own prompt only
    return id == kDashlane && connector->auth == QStringLiteral("locked");
}

// ------------------------------------------------------------------ installer

void PasswordManager::failInstall(const QString &id, const QString &message)
{
    Connector *connector = find(id);
    if (connector) {
        connector->installing = false;
        connector->installProgress = 0;
        connector->installError = message;
        emit connectorsChanged();
    }
    emit installFinished(id, false, message);
}

void PasswordManager::download(const QString &id, const QUrl &url, const std::function<void(const QByteArray &)> &done)
{
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Silo/1.0 (+https://github.com)"));
    request.setRawHeader("Accept", "application/octet-stream, application/vnd.github+json, application/json, */*");
    QNetworkReply *reply = m_network->get(request);
    connect(reply, &QNetworkReply::downloadProgress, this, [this, id](qint64 received, qint64 total) {
        Connector *connector = find(id);
        if (!connector || total <= 0)
            return;
        connector->installProgress = int(received * 100 / total);
        emit connectorsChanged();
    });
    connect(reply, &QNetworkReply::finished, this, [this, id, reply, done] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            failInstall(id, QStringLiteral("Download failed: %1").arg(reply->errorString()));
            return;
        }
        done(reply->readAll());
    });
}

// Unpacks (if needed), drops the binary in <data>/bin and re-detects.
void PasswordManager::finishInstall(const QString &id, const QString &version, const QByteArray &payload, bool zipped)
{
    Connector *connector = find(id);
    if (!connector)
        return;
    const QString binDir = binDirectory();
    QDir().mkpath(binDir);
    const QString target = binDir + QLatin1Char('/') + exeName(connector->binary);

    if (zipped) {
        const QString tempDir = binDir + QStringLiteral("/.install-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
        QDir().mkpath(tempDir);
        const QString zipPath = tempDir + QStringLiteral("/package.zip");
        {
            QFile zip(zipPath);
            if (!zip.open(QIODevice::WriteOnly) || zip.write(payload) != payload.size()) {
                QDir(tempDir).removeRecursively();
                failInstall(id, QStringLiteral("Could not write the download to %1").arg(tempDir));
                return;
            }
        }
        QString program;
        QStringList args;
#ifdef Q_OS_WIN
        program = QStandardPaths::findExecutable(QStringLiteral("tar"));
        args = {QStringLiteral("-xf"), zipPath, QStringLiteral("-C"), tempDir};
#else
        program = QStandardPaths::findExecutable(QStringLiteral("unzip"));
        if (!program.isEmpty()) {
            args = {QStringLiteral("-o"), QStringLiteral("-q"), zipPath, QStringLiteral("-d"), tempDir};
        } else {
            program = QStandardPaths::findExecutable(QStringLiteral("bsdtar"));
            if (program.isEmpty())
                program = QStandardPaths::findExecutable(QStringLiteral("tar"));
            args = {QStringLiteral("-xf"), zipPath, QStringLiteral("-C"), tempDir};
        }
#endif
        if (program.isEmpty()) {
            QDir(tempDir).removeRecursively();
            failInstall(id, QStringLiteral("No unzip or tar tool found to unpack the download."));
            return;
        }
        QProcess unpack;
        unpack.start(program, args);
        if (!unpack.waitForFinished(120000) || unpack.exitCode() != 0) {
            QDir(tempDir).removeRecursively();
            failInstall(id, QStringLiteral("Could not unpack the download: %1")
                                .arg(QString::fromUtf8(unpack.readAllStandardError()).trimmed()));
            return;
        }
        // Locate the executable inside the archive (flat or nested)
        QString found;
        QDirIterator it(tempDir, {exeName(connector->binary)}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            found = it.next();
            break;
        }
        if (found.isEmpty()) {
            QDir(tempDir).removeRecursively();
            failInstall(id, QStringLiteral("The archive does not contain %1.").arg(exeName(connector->binary)));
            return;
        }
        QFile::remove(target);
        if (!QFile::rename(found, target) && !QFile::copy(found, target)) {
            QDir(tempDir).removeRecursively();
            failInstall(id, QStringLiteral("Could not move %1 into %2").arg(exeName(connector->binary), binDir));
            return;
        }
        QDir(tempDir).removeRecursively();
    } else {
        QSaveFile file(target);
        if (!file.open(QIODevice::WriteOnly)) {
            failInstall(id, file.errorString());
            return;
        }
        file.write(payload);
        if (!file.commit()) {
            failInstall(id, file.errorString());
            return;
        }
    }
    QFile::setPermissions(target, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner | QFile::ReadGroup | QFile::ExeGroup
                                      | QFile::ReadOther | QFile::ExeOther);
#ifdef Q_OS_MACOS
    // Downloads made by the app are not quarantined, but be explicit, and give
    // unsigned binaries (Dashlane) an ad-hoc signature so arm64 will run them.
    QProcess xattr;
    xattr.setStandardErrorFile(QProcess::nullDevice());
    xattr.start(QStringLiteral("xattr"), {QStringLiteral("-d"), QStringLiteral("com.apple.quarantine"), target});
    xattr.waitForFinished(5000);
    if (id == kDashlane && !QStandardPaths::findExecutable(QStringLiteral("codesign")).isEmpty()) {
        QProcess verify;
        verify.start(QStringLiteral("codesign"), {QStringLiteral("-v"), target});
        verify.waitForFinished(15000);
        if (verify.exitCode() != 0)
            QProcess::execute(QStringLiteral("codesign"), {QStringLiteral("-s"), QStringLiteral("-"), QStringLiteral("--force"), target});
    }
#endif

    connector->installing = false;
    connector->installProgress = 100;
    connector->installError.clear();
    connector->version = version;
    connector->enabled = true;
    QSettings().setValue(kEnabledKey.arg(id), true);
    detect();
    refreshStatus(id);
    emit installFinished(id, true, QStringLiteral("%1 CLI %2 installed").arg(connector->name, version));
}

void PasswordManager::install(const QString &id)
{
    Connector *connector = find(id);
    if (!connector || connector->installing)
        return;
    connector->installing = true;
    connector->installProgress = 0;
    connector->installError.clear();
    emit connectorsChanged();

    if (id == kBitwarden) {
        // Releases are tagged cli-vYYYY.M.P on the shared clients repository
        download(id, QUrl(QStringLiteral("https://api.github.com/repos/bitwarden/clients/releases?per_page=30")),
                 [this, id](const QByteArray &body) {
                     QString version;
                     QUrl assetUrl;
                     for (const QJsonValue &value : QJsonDocument::fromJson(body).array()) {
                         const QJsonObject release = value.toObject();
                         const QString tag = release.value(QStringLiteral("tag_name")).toString();
                         if (!tag.startsWith(QStringLiteral("cli-v")) || release.value(QStringLiteral("prerelease")).toBool())
                             continue;
                         version = tag.mid(5);
                         QStringList wanted;
#if defined(Q_OS_MACOS)
                         if (isArm())
                             wanted << QStringLiteral("bw-macos-arm64-%1.zip").arg(version);
                         wanted << QStringLiteral("bw-macos-%1.zip").arg(version);
#elif defined(Q_OS_WIN)
                         wanted << QStringLiteral("bw-windows-%1.zip").arg(version);
#else
                         wanted << (isArm() ? QStringLiteral("bw-linux-arm64-%1.zip") : QStringLiteral("bw-linux-%1.zip")).arg(version);
#endif
                         const QJsonArray assets = release.value(QStringLiteral("assets")).toArray();
                         for (const QString &name : wanted) {
                             for (const QJsonValue &asset : assets) {
                                 if (asset.toObject().value(QStringLiteral("name")).toString() == name) {
                                     assetUrl = QUrl(asset.toObject().value(QStringLiteral("browser_download_url")).toString());
                                     break;
                                 }
                             }
                             if (assetUrl.isValid())
                                 break;
                         }
                         break;
                     }
                     if (!assetUrl.isValid()) {
                         failInstall(id, QStringLiteral("No Bitwarden CLI build found for this platform."));
                         return;
                     }
                     download(id, assetUrl, [this, id, version](const QByteArray &zip) { finishInstall(id, version, zip, true); });
                 });
    } else if (id == kOnePassword) {
        download(id, QUrl(QStringLiteral("https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N")),
                 [this, id](const QByteArray &body) {
                     const QString version = QJsonDocument::fromJson(body).object().value(QStringLiteral("version")).toString();
                     if (version.isEmpty()) {
                         failInstall(id, QStringLiteral("Could not determine the latest 1Password CLI version."));
                         return;
                     }
#if defined(Q_OS_MACOS)
                     const QString platform = QStringLiteral("darwin_%1").arg(isArm() ? QStringLiteral("arm64") : QStringLiteral("amd64"));
#elif defined(Q_OS_WIN)
                     const QString platform = QStringLiteral("windows_%1").arg(isArm() ? QStringLiteral("arm64") : QStringLiteral("amd64"));
#else
                     const QString platform = QStringLiteral("linux_%1").arg(isArm() ? QStringLiteral("arm64") : QStringLiteral("amd64"));
#endif
                     const QUrl url(QStringLiteral("https://cache.agilebits.com/dist/1P/op2/pkg/v%1/op_%2_v%1.zip").arg(version, platform));
                     download(id, url, [this, id, version](const QByteArray &zip) { finishInstall(id, version, zip, true); });
                 });
    } else if (id == kDashlane) {
        download(id, QUrl(QStringLiteral("https://api.github.com/repos/Dashlane/dashlane-cli/releases/latest")),
                 [this, id](const QByteArray &body) {
                     const QJsonObject release = QJsonDocument::fromJson(body).object();
                     QString version = release.value(QStringLiteral("tag_name")).toString();
                     if (version.startsWith(QLatin1Char('v')))
                         version.remove(0, 1);
#if defined(Q_OS_MACOS)
                     const QString wanted = isArm() ? QStringLiteral("dcli-macos-arm64") : QStringLiteral("dcli-macos-x64");
#elif defined(Q_OS_WIN)
                     const QString wanted = QStringLiteral("dcli-win-x64.exe");
#else
                     const QString wanted = isArm() ? QStringLiteral("dcli-linux-arm64") : QStringLiteral("dcli-linux-x64");
#endif
                     QUrl assetUrl;
                     for (const QJsonValue &asset : release.value(QStringLiteral("assets")).toArray())
                         if (asset.toObject().value(QStringLiteral("name")).toString() == wanted)
                             assetUrl = QUrl(asset.toObject().value(QStringLiteral("browser_download_url")).toString());
                     if (!assetUrl.isValid()) {
                         failInstall(id, QStringLiteral("No Dashlane CLI build found for this platform."));
                         return;
                     }
                     download(id, assetUrl, [this, id, version](const QByteArray &binary) { finishInstall(id, version, binary, false); });
                 });
    } else {
        failInstall(id, QStringLiteral("Unknown connector."));
    }
}

void PasswordManager::uninstall(const QString &id)
{
    Connector *connector = find(id);
    if (!connector)
        return;
    const QString managed = binDirectory() + QLatin1Char('/') + exeName(connector->binary);
    if (QFile::exists(managed))
        QFile::remove(managed);
    connector->version.clear();
    if (id == kBitwarden) {
        m_bwSession.clear();
        m_bwItems.clear();
    } else if (id == kOnePassword) {
        m_opAccounts.clear();
    } else {
        m_dcliItems.clear();
    }
    refresh();
}

// ------------------------------------------------------------------ 1Password (`op`)

PasswordManager::OpAccount *PasswordManager::opAccount(const QString &uuid)
{
    for (OpAccount &account : m_opAccounts)
        if (account.uuid == uuid)
            return &account;
    return nullptr;
}

// signed-out: no account; unlocked: a session is held; locked: every account
// refused us; ready: unlocks on demand (desktop app integration or stored session)
void PasswordManager::opUpdateAuth(Connector &connector)
{
    if (m_opAccounts.isEmpty()) {
        setAuth(connector, QStringLiteral("signed-out"));
        return;
    }
    const QString label = m_opAccounts.size() == 1 ? m_opAccounts.first().label
                                                   : QStringLiteral("%1 accounts").arg(m_opAccounts.size());
    bool anySession = false, allLocked = true;
    for (const OpAccount &account : m_opAccounts) {
        anySession = anySession || !account.sessionToken.isEmpty();
        allLocked = allLocked && account.locked;
    }
    if (anySession)
        setAuth(connector, QStringLiteral("unlocked"), label);
    else if (allLocked)
        setAuth(connector, QStringLiteral("locked"), label);
    else
        setAuth(connector, QStringLiteral("ready"), label);
    emit connectorsChanged();
}

void PasswordManager::opRefresh(Connector &connector)
{
    const QString id = connector.id;
    // Generous timeout: the first call makes macOS ask the user whether Silo may
    // access the 1Password app's data, and killing `op` while that prompt is up
    // would leave the answer unrecorded (so it would be asked again).
    run(connector, {QStringLiteral("account"), QStringLiteral("list"), QStringLiteral("--format"), QStringLiteral("json")},
        [this, id](int code, const QByteArray &out, const QByteArray &) {
            Connector *connector = find(id);
            if (!connector) {
                probeDone(id);
                return;
            }
            QList<OpAccount> accounts;
            if (code == 0) {
                for (const QJsonValue &value : QJsonDocument::fromJson(out).array()) {
                    const QJsonObject object = value.toObject();
                    OpAccount account;
                    account.uuid = object.value(QStringLiteral("account_uuid")).toString();
                    if (account.uuid.isEmpty())
                        continue;
                    const QString email = object.value(QStringLiteral("email")).toString();
                    const QString url = object.value(QStringLiteral("url")).toString();
                    account.shortLabel = url.section(QLatin1Char('.'), 0, 0);
                    if (account.shortLabel.isEmpty() || account.shortLabel == QStringLiteral("my"))
                        account.shortLabel = email.isEmpty() ? url : email;
                    account.label = email.isEmpty() ? url : (url.isEmpty() ? email : email + QStringLiteral(" · ") + url);
                    account.logoUrl = organisationSite(email);
                    if (OpAccount *known = opAccount(account.uuid)) {
                        account.sessionVar = known->sessionVar;
                        account.sessionToken = known->sessionToken;
                        account.locked = known->locked;
                        account.items = known->items;
                        account.fetched = known->fetched;
                    }
                    accounts.append(account);
                }
            }
            m_opAccounts = accounts;
            opUpdateAuth(*connector);
            probeDone(id);
        }, {}, 90000);
    run(connector, {QStringLiteral("--version")}, [this, id](int code, const QByteArray &out, const QByteArray &) {
        Connector *connector = find(id);
        if (connector && code == 0) {
            connector->version = QString::fromUtf8(out).trimmed();
            emit connectorsChanged();
        }
    }, {}, 10000);
}

// Lists every account's logins (cached 10 min each) and keeps the ones for the host.
// Accounts that refused us last time are asked again: with the desktop-app
// integration, unlocking happens in the 1Password app and this very call is
// what makes the app prompt for it, so "locked" is never sticky.
void PasswordManager::opSearch(const QString &url, const QString &host)
{
    Connector *connector = find(kOnePassword);
    if (!connector)
        return;
    QStringList uuids;
    for (const OpAccount &account : m_opAccounts)
        uuids.append(account.uuid);
    if (uuids.isEmpty()) {
        opUpdateAuth(*connector);
        searchDone(url);
        return;
    }

    auto pending = std::make_shared<int>(int(uuids.size()));
    auto finish = [this, url, host, pending] {
        if (--*pending > 0)
            return;
        QVariantList results;
        for (const OpAccount &account : m_opAccounts) {
            for (const QVariant &value : account.items) {
                const QVariantMap item = value.toMap();
                QString matched;
                for (const QVariant &u : item.value(QStringLiteral("urls")).toList()) {
                    const QString href = u.toMap().value(QStringLiteral("href")).toString();
                    if (hostMatches(hostFromAny(href), host)) {
                        matched = href;
                        break;
                    }
                }
                if (matched.isEmpty())
                    continue;
                results.append(QVariantMap{{QStringLiteral("id"), account.uuid + QLatin1Char('|') + item.value(QStringLiteral("id")).toString()},
                                           {QStringLiteral("title"), item.value(QStringLiteral("title"))},
                                           {QStringLiteral("username"), item.value(QStringLiteral("additional_information"))},
                                           {QStringLiteral("url"), matched},
                                           {QStringLiteral("hasTotp"), false},
                                           {QStringLiteral("source"), kOnePassword},
                                           {QStringLiteral("account"), m_opAccounts.size() > 1 ? account.shortLabel : QString()}});
            }
        }
        emit resultsReady(url, kOnePassword, results);
        if (Connector *connector = find(kOnePassword))
            opUpdateAuth(*connector);
        searchDone(url);
    };

    for (const QString &uuid : uuids) {
        OpAccount *account = opAccount(uuid);
        if (!account->items.isEmpty() && account->fetched.isValid()
            && account->fetched.secsTo(QDateTime::currentDateTime()) < kOpCacheSeconds) {
            finish();
            continue;
        }
        QProcessEnvironment env;
        if (!account->sessionVar.isEmpty())
            env.insert(account->sessionVar, account->sessionToken);
        run(*connector,
            {QStringLiteral("item"), QStringLiteral("list"), QStringLiteral("--account"), uuid, QStringLiteral("--categories"),
             QStringLiteral("Login"), QStringLiteral("--format"), QStringLiteral("json")},
            [this, uuid, finish](int code, const QByteArray &out, const QByteArray &err) {
                if (OpAccount *account = opAccount(uuid)) {
                    if (code != 0) {
                        const QString message = friendlyError(kOnePassword, err);
                        if (message.contains(QStringLiteral("unlocked"))) {
                            // Not an error to show: the popover offers the unlock form instead
                            account->locked = true;
                            account->sessionToken.clear();
                            account->sessionVar.clear();
                        } else {
                            setError(kOnePassword, message);
                        }
                        account->items.clear();
                    } else {
                        account->items = QJsonDocument::fromJson(out).array().toVariantList();
                        account->fetched = QDateTime::currentDateTime();
                        account->locked = false;
                    }
                }
                finish();
            }, env);
    }
}

// id is "<account uuid>|<item id>" (see opSearch)
void PasswordManager::opFetch(const QString &id)
{
    Connector *connector = find(kOnePassword);
    const QString uuid = id.section(QLatin1Char('|'), 0, 0);
    const QString itemId = id.section(QLatin1Char('|'), 1);
    OpAccount *account = opAccount(uuid);
    if (!connector || !account || itemId.isEmpty()) {
        setError(kOnePassword, QStringLiteral("This login is no longer in the results, search again."));
        return;
    }
    QProcessEnvironment env;
    if (!account->sessionVar.isEmpty())
        env.insert(account->sessionVar, account->sessionToken);
    run(*connector,
        {QStringLiteral("item"), QStringLiteral("get"), itemId, QStringLiteral("--account"), uuid, QStringLiteral("--format"),
         QStringLiteral("json"), QStringLiteral("--reveal")},
        [this, id](int code, const QByteArray &out, const QByteArray &err) {
            if (code != 0) {
                setError(kOnePassword, friendlyError(kOnePassword, err));
                return;
            }
            const QJsonObject item = QJsonDocument::fromJson(out).object();
            QVariantMap credentials{{QStringLiteral("source"), kOnePassword},
                                    {QStringLiteral("id"), id},
                                    {QStringLiteral("title"), item.value(QStringLiteral("title")).toString()},
                                    {QStringLiteral("username"), QString()},
                                    {QStringLiteral("password"), QString()},
                                    {QStringLiteral("totp"), QString()}};
            for (const QJsonValue &value : item.value(QStringLiteral("urls")).toArray()) {
                if (value.toObject().value(QStringLiteral("primary")).toBool() || !credentials.contains(QStringLiteral("url")))
                    credentials[QStringLiteral("url")] = value.toObject().value(QStringLiteral("href")).toString();
            }
            for (const QJsonValue &value : item.value(QStringLiteral("fields")).toArray()) {
                const QJsonObject field = value.toObject();
                const QString purpose = field.value(QStringLiteral("purpose")).toString();
                const QString fieldId = field.value(QStringLiteral("id")).toString();
                const QString type = field.value(QStringLiteral("type")).toString();
                if (purpose == QStringLiteral("USERNAME") || fieldId == QStringLiteral("username"))
                    credentials[QStringLiteral("username")] = field.value(QStringLiteral("value")).toString();
                else if (purpose == QStringLiteral("PASSWORD") || fieldId == QStringLiteral("password"))
                    credentials[QStringLiteral("password")] = field.value(QStringLiteral("value")).toString();
                else if (type == QStringLiteral("OTP"))
                    credentials[QStringLiteral("totp")] = field.value(QStringLiteral("totp")).toString();
            }
            emit credentialsReady(credentials);
        }, env);
}

// Without the desktop-app integration `op signin --account X` reads the account
// password from stdin and prints `export OP_SESSION_xxx="token"`. With the
// integration on, the password is ignored: the 1Password app shows a prompt
// and `op` exits 0 with nothing on stdout once it is approved.
void PasswordManager::opUnlock(const QString &password, const QString &accountId)
{
    Connector *connector = find(kOnePassword);
    if (!connector || connector->cliPath.isEmpty() || m_opAccounts.isEmpty())
        return;
    clearError(kOnePassword);
    QString uuid = accountId;
    if (uuid.isEmpty()) {
        // The only locked account, else the first one
        for (const OpAccount &account : m_opAccounts)
            if (account.locked && uuid.isEmpty())
                uuid = account.uuid;
        if (uuid.isEmpty())
            uuid = m_opAccounts.first().uuid;
    }
    run(*connector, {QStringLiteral("signin"), QStringLiteral("--account"), uuid},
        [this, uuid](int code, const QByteArray &out, const QByteArray &err) {
            Connector *connector = find(kOnePassword);
            OpAccount *account = opAccount(uuid);
            if (!connector || !account)
                return;
            if (code != 0) {
                setError(kOnePassword, friendlyError(kOnePassword, err));
                return;
            }
            const QRegularExpression pattern(QStringLiteral("(OP_SESSION_[A-Za-z0-9_]+)=\"?([^\"\\s]+)"));
            const QRegularExpressionMatch match = pattern.match(QString::fromUtf8(out));
            if (match.hasMatch()) {
                account->sessionVar = match.captured(1);
                account->sessionToken = match.captured(2);
            } else {
                // Desktop-app integration: approved in the app, no token to keep
                account->sessionVar.clear();
                account->sessionToken.clear();
            }
            account->locked = false;
            account->items.clear();
            opUpdateAuth(*connector);
            emit unlocked(kOnePassword);
        }, {}, 120000, password.isEmpty() ? QByteArray() : password.toUtf8() + '\n');
}

// ------------------------------------------------------------------ Bitwarden (`bw`)

void PasswordManager::bwRefresh(Connector &connector)
{
    const QString id = connector.id;
    QProcessEnvironment env;
    if (!m_bwSession.isEmpty())
        env.insert(QStringLiteral("BW_SESSION"), m_bwSession);
    run(connector, {QStringLiteral("status")},
        [this, id](int code, const QByteArray &out, const QByteArray &) {
            Connector *connector = find(id);
            if (!connector || code != 0) {
                probeDone(id);
                return;
            }
            const QJsonObject status = QJsonDocument::fromJson(out).object();
            const QString state = status.value(QStringLiteral("status")).toString();
            const QString account = status.value(QStringLiteral("userEmail")).toString();
            if (state == QStringLiteral("unauthenticated"))
                setAuth(*connector, QStringLiteral("signed-out"));
            else if (state == QStringLiteral("unlocked") && !m_bwSession.isEmpty())
                setAuth(*connector, QStringLiteral("unlocked"), account);
            else
                setAuth(*connector, QStringLiteral("locked"), account);
            probeDone(id);
        }, env, 30000);
    run(connector, {QStringLiteral("--version")}, [this, id](int code, const QByteArray &out, const QByteArray &) {
        Connector *connector = find(id);
        if (connector && code == 0) {
            connector->version = QString::fromUtf8(out).trimmed();
            emit connectorsChanged();
        }
    }, {}, 15000);
}

void PasswordManager::bwUnlock(const QString &password)
{
    Connector *connector = find(kBitwarden);
    if (!connector || connector->cliPath.isEmpty())
        return;
    QProcessEnvironment env;
    env.insert(QStringLiteral("BW_PASSWORD"), password);
    run(*connector,
        {QStringLiteral("unlock"), QStringLiteral("--raw"), QStringLiteral("--passwordenv"), QStringLiteral("BW_PASSWORD")},
        [this](int code, const QByteArray &out, const QByteArray &err) {
            Connector *connector = find(kBitwarden);
            if (!connector)
                return;
            if (code != 0) {
                setError(kBitwarden, friendlyError(kBitwarden, err));
                return;
            }
            m_bwSession = QString::fromUtf8(out).trimmed();
            // Pull the latest vault changes first: two `bw` processes writing
            // data.json at once (sync + list) end in random failures.
            setAuth(*connector, QStringLiteral("syncing"), connector->account);
            QProcessEnvironment env;
            env.insert(QStringLiteral("BW_SESSION"), m_bwSession);
            run(*connector, {QStringLiteral("sync")}, [this](int, const QByteArray &, const QByteArray &) {
                Connector *connector = find(kBitwarden);
                if (!connector || m_bwSession.isEmpty())
                    return;
                setAuth(*connector, QStringLiteral("unlocked"), connector->account);
                emit unlocked(kBitwarden);
            }, env, 60000);
        }, env, 60000);
}

void PasswordManager::bwSearch(const QString &url, const QString &host)
{
    Connector *connector = find(kBitwarden);
    if (!connector)
        return;
    if (m_bwSession.isEmpty()) {
        setAuth(*connector, QStringLiteral("locked"), connector->account);
        searchDone(url);
        return;
    }
    QProcessEnvironment env;
    env.insert(QStringLiteral("BW_SESSION"), m_bwSession);
    run(*connector, {QStringLiteral("list"), QStringLiteral("items"), QStringLiteral("--url"), url},
        [this, url, host](int code, const QByteArray &out, const QByteArray &err) {
            if (code != 0) {
                const QString message = friendlyError(kBitwarden, err);
                if (Connector *connector = find(kBitwarden); connector && message.contains(QStringLiteral("locked"), Qt::CaseInsensitive)) {
                    m_bwSession.clear();
                    setAuth(*connector, QStringLiteral("locked"), connector->account);
                } else {
                    setError(kBitwarden, message);
                }
                searchDone(url);
                return;
            }
            QVariantList results;
            m_bwItems.clear();
            for (const QJsonValue &value : QJsonDocument::fromJson(out).array()) {
                const QJsonObject item = value.toObject();
                if (item.value(QStringLiteral("type")).toInt() != 1) // 1 = login
                    continue;
                const QJsonObject login = item.value(QStringLiteral("login")).toObject();
                QString matched;
                for (const QJsonValue &u : login.value(QStringLiteral("uris")).toArray()) {
                    const QString uri = u.toObject().value(QStringLiteral("uri")).toString();
                    if (hostMatches(hostFromAny(uri), host) || matched.isEmpty())
                        matched = uri;
                }
                const QString id = item.value(QStringLiteral("id")).toString();
                m_bwItems.insert(id, item.toVariantMap());
                results.append(QVariantMap{{QStringLiteral("id"), id},
                                           {QStringLiteral("title"), item.value(QStringLiteral("name")).toString()},
                                           {QStringLiteral("username"), login.value(QStringLiteral("username")).toString()},
                                           {QStringLiteral("url"), matched},
                                           {QStringLiteral("hasTotp"), !login.value(QStringLiteral("totp")).toString().isEmpty()},
                                           {QStringLiteral("source"), kBitwarden}});
            }
            emit resultsReady(url, kBitwarden, results);
            searchDone(url);
        }, env);
}

void PasswordManager::bwFetch(const QString &id)
{
    Connector *connector = find(kBitwarden);
    const QVariantMap item = m_bwItems.value(id);
    if (!connector || item.isEmpty()) {
        setError(kBitwarden, QStringLiteral("This login is no longer in the results, search again."));
        return;
    }
    const QVariantMap login = item.value(QStringLiteral("login")).toMap();
    QString url;
    for (const QVariant &u : login.value(QStringLiteral("uris")).toList()) {
        url = u.toMap().value(QStringLiteral("uri")).toString();
        if (!url.isEmpty())
            break;
    }
    QVariantMap credentials{{QStringLiteral("source"), kBitwarden},
                            {QStringLiteral("id"), id},
                            {QStringLiteral("title"), item.value(QStringLiteral("name"))},
                            {QStringLiteral("username"), login.value(QStringLiteral("username"))},
                            {QStringLiteral("password"), login.value(QStringLiteral("password"))},
                            {QStringLiteral("url"), url},
                            {QStringLiteral("totp"), QString()}};
    if (login.value(QStringLiteral("totp")).toString().isEmpty()) {
        emit credentialsReady(credentials);
        return;
    }
    QProcessEnvironment env;
    env.insert(QStringLiteral("BW_SESSION"), m_bwSession);
    run(*connector, {QStringLiteral("get"), QStringLiteral("totp"), id},
        [this, credentials](int code, const QByteArray &out, const QByteArray &) mutable {
            if (code == 0)
                credentials[QStringLiteral("totp")] = QString::fromUtf8(out).trimmed();
            emit credentialsReady(credentials);
        }, env, 30000);
}

// ------------------------------------------------------------------ Dashlane (`dcli`)

// `dcli status` prints "Logged in: yes|no", "Login: …", "Locked: yes|no".
void PasswordManager::dcliRefresh(Connector &connector)
{
    const QString id = connector.id;
    run(connector, {QStringLiteral("status")},
        [this, id](int code, const QByteArray &out, const QByteArray &) {
            Connector *connector = find(id);
            if (!connector) {
                probeDone(id);
                return;
            }
            const QString text = QString::fromUtf8(out);
            if (code != 0 || !text.contains(QStringLiteral("Logged in: yes"))) {
                setAuth(*connector, QStringLiteral("signed-out"));
                probeDone(id);
                return;
            }
            const QRegularExpressionMatch login = QRegularExpression(QStringLiteral("Login:\\s*(\\S+)")).match(text);
            const QString account = login.hasMatch() ? login.captured(1) : QString();
            setAuth(*connector, text.contains(QStringLiteral("Locked: yes")) ? QStringLiteral("locked") : QStringLiteral("unlocked"), account);
            probeDone(id);
        }, {}, 20000);
    run(connector, {QStringLiteral("--version")}, [this, id](int code, const QByteArray &out, const QByteArray &) {
        Connector *connector = find(id);
        if (connector && code == 0) {
            connector->version = QString::fromUtf8(out).trimmed();
            emit connectorsChanged();
        }
    }, {}, 15000);
}

void PasswordManager::dcliSearch(const QString &url, const QString &host)
{
    Connector *connector = find(kDashlane);
    if (!connector)
        return;
    run(*connector, {QStringLiteral("password"), QStringLiteral("url=") + host, QStringLiteral("-o"), QStringLiteral("json")},
        [this, url, host](int code, const QByteArray &out, const QByteArray &err) {
            if (code != 0) {
                const QString message = friendlyError(kDashlane, err);
                // "No credential found" is a plain empty result
                if (!message.contains(QStringLiteral("No credential"), Qt::CaseInsensitive)) {
                    if (Connector *connector = find(kDashlane); connector && message.contains(QStringLiteral("locked"), Qt::CaseInsensitive))
                        setAuth(*connector, QStringLiteral("locked"), connector->account);
                    setError(kDashlane, message);
                }
                emit resultsReady(url, kDashlane, {});
                searchDone(url);
                return;
            }
            QVariantList results;
            m_dcliItems.clear();
            for (const QJsonValue &value : QJsonDocument::fromJson(out).array()) {
                const QJsonObject item = value.toObject();
                const QString itemUrl = item.value(QStringLiteral("url")).toString();
                if (!hostMatches(hostFromAny(itemUrl), host))
                    continue;
                const QString id = item.value(QStringLiteral("id")).toString();
                QString username = item.value(QStringLiteral("email")).toString();
                if (username.isEmpty())
                    username = item.value(QStringLiteral("login")).toString();
                if (username.isEmpty())
                    username = item.value(QStringLiteral("secondaryLogin")).toString();
                m_dcliItems.insert(id, item.toVariantMap());
                results.append(QVariantMap{{QStringLiteral("id"), id},
                                           {QStringLiteral("title"), item.value(QStringLiteral("title")).toString().isEmpty()
                                                                         ? hostFromAny(itemUrl)
                                                                         : item.value(QStringLiteral("title")).toString()},
                                           {QStringLiteral("username"), username},
                                           {QStringLiteral("url"), itemUrl},
                                           {QStringLiteral("hasTotp"), !item.value(QStringLiteral("otpSecret")).toString().isEmpty()
                                                                           || !item.value(QStringLiteral("otpUrl")).toString().isEmpty()},
                                           {QStringLiteral("source"), kDashlane}});
            }
            emit resultsReady(url, kDashlane, results);
            searchDone(url);
        }, {}, 60000);
}

void PasswordManager::dcliFetch(const QString &id)
{
    Connector *connector = find(kDashlane);
    const QVariantMap item = m_dcliItems.value(id);
    if (!connector || item.isEmpty()) {
        setError(kDashlane, QStringLiteral("This login is no longer in the results, search again."));
        return;
    }
    QString username = item.value(QStringLiteral("email")).toString();
    if (username.isEmpty())
        username = item.value(QStringLiteral("login")).toString();
    QVariantMap credentials{{QStringLiteral("source"), kDashlane},
                            {QStringLiteral("id"), id},
                            {QStringLiteral("title"), item.value(QStringLiteral("title"))},
                            {QStringLiteral("username"), username},
                            {QStringLiteral("password"), item.value(QStringLiteral("password"))},
                            {QStringLiteral("url"), item.value(QStringLiteral("url"))},
                            {QStringLiteral("totp"), QString()}};
    const bool hasOtp = !item.value(QStringLiteral("otpSecret")).toString().isEmpty()
                        || !item.value(QStringLiteral("otpUrl")).toString().isEmpty();
    if (!hasOtp) {
        emit credentialsReady(credentials);
        return;
    }
    run(*connector, {QStringLiteral("password"), QStringLiteral("id=") + id, QStringLiteral("-f"), QStringLiteral("otp"),
                     QStringLiteral("-o"), QStringLiteral("console")},
        [this, credentials](int code, const QByteArray &out, const QByteArray &) mutable {
            if (code == 0)
                credentials[QStringLiteral("totp")] = QString::fromUtf8(out).trimmed().section(QLatin1Char(' '), 0, 0);
            emit credentialsReady(credentials);
        }, {}, 30000);
}
