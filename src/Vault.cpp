#include "Vault.h"

#include "AppStore.h"
#include "../third_party/monocypher/monocypher.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMessageAuthenticationCode>
#include <QProcess>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>
#include <QtEndian>

#ifdef Q_OS_WIN
#include <windows.h>
#include <wincred.h>
#endif

#include <algorithm>
#include <cstdlib>
#include <vector>

namespace {
const QByteArray kMagic = QByteArrayLiteral("SILOVLT1");
constexpr int kNonceSize = 24;
constexpr int kMacSize = 16;
constexpr int kKeySize = 32;
constexpr int kSaltSize = 16;
constexpr uint32_t kArgonBlocks = 65536; // 64 MiB
constexpr uint32_t kArgonPasses = 3;

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

bool hostMatches(const QString &itemHost, const QString &pageHost)
{
    if (itemHost.isEmpty() || pageHost.isEmpty())
        return false;
    if (itemHost == pageHost)
        return true;
    return pageHost.endsWith(QLatin1Char('.') + itemHost) || itemHost.endsWith(QLatin1Char('.') + pageHost);
}

QByteArray base32Decode(const QString &input)
{
    QByteArray out;
    int buffer = 0, bits = 0;
    for (const QChar ch : input) {
        const char c = ch.toUpper().toLatin1();
        int value;
        if (c >= 'A' && c <= 'Z')
            value = c - 'A';
        else if (c >= '2' && c <= '7')
            value = c - '2' + 26;
        else
            continue; // padding, spaces, dashes
        buffer = (buffer << 5) | value;
        bits += 5;
        if (bits >= 8) {
            out.append(char((buffer >> (bits - 8)) & 0xFF));
            bits -= 8;
        }
    }
    return out;
}

struct TotpSpec {
    QByteArray secret;
    int digits = 6;
    int period = 30;
    QCryptographicHash::Algorithm algorithm = QCryptographicHash::Sha1;
};

TotpSpec parseTotp(const QString &secretOrUri)
{
    TotpSpec spec;
    const QString text = secretOrUri.trimmed();
    if (text.startsWith(QStringLiteral("otpauth://"), Qt::CaseInsensitive)) {
        const QUrlQuery query(QUrl(text).query());
        spec.secret = base32Decode(query.queryItemValue(QStringLiteral("secret")));
        if (query.hasQueryItem(QStringLiteral("digits")))
            spec.digits = qBound(6, query.queryItemValue(QStringLiteral("digits")).toInt(), 8);
        if (query.hasQueryItem(QStringLiteral("period")))
            spec.period = qMax(1, query.queryItemValue(QStringLiteral("period")).toInt());
        const QString algorithm = query.queryItemValue(QStringLiteral("algorithm")).toUpper();
        if (algorithm == QStringLiteral("SHA256"))
            spec.algorithm = QCryptographicHash::Sha256;
        else if (algorithm == QStringLiteral("SHA512"))
            spec.algorithm = QCryptographicHash::Sha512;
    } else {
        spec.secret = base32Decode(text);
    }
    return spec;
}

QString csvColumnKey(QString name)
{
    name = name.trimmed().toLower();
    name.remove(QChar(0xFEFF));
    name.replace(QLatin1Char('-'), QLatin1Char('_'));
    name.replace(QLatin1Char(' '), QLatin1Char('_'));
    return name;
}
} // namespace

// ------------------------------------------------------------------ key store

// Where the 32-byte vault key rests when no master password is set.
struct Vault::KeyStore
{
    static QString service() { return QStringLiteral("Silo Vault"); }
    static QString account() { return QStringLiteral("vault-key"); }

    static bool runTool(const QStringList &command, const QByteArray &stdinData, QByteArray *stdoutData)
    {
        if (command.isEmpty() || QStandardPaths::findExecutable(command.first()).isEmpty())
            return false;
        QProcess process;
        process.start(command.first(), command.mid(1));
        if (!process.waitForStarted(3000))
            return false;
        if (!stdinData.isEmpty())
            process.write(stdinData);
        process.closeWriteChannel();
        if (!process.waitForFinished(8000))
            return false;
        if (stdoutData)
            *stdoutData = process.readAllStandardOutput();
        return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
    }

    // Returns "" when nothing is stored; ok=false when the keychain is unusable.
    static QByteArray read(bool *ok)
    {
        *ok = true;
#if defined(Q_OS_MACOS)
        QByteArray out;
        if (runTool({QStringLiteral("security"), QStringLiteral("find-generic-password"), QStringLiteral("-s"), service(),
                     QStringLiteral("-a"), account(), QStringLiteral("-w")}, {}, &out))
            return QByteArray::fromHex(out.trimmed());
        return {};
#elif defined(Q_OS_WIN)
        PCREDENTIALW credential = nullptr;
        if (!CredReadW(reinterpret_cast<LPCWSTR>(service().utf16()), CRED_TYPE_GENERIC, 0, &credential))
            return {};
        const QByteArray hex(reinterpret_cast<const char *>(credential->CredentialBlob), int(credential->CredentialBlobSize));
        CredFree(credential);
        return QByteArray::fromHex(hex);
#else
        if (QStandardPaths::findExecutable(QStringLiteral("secret-tool")).isEmpty()) {
            *ok = false;
            return {};
        }
        QByteArray out;
        if (runTool({QStringLiteral("secret-tool"), QStringLiteral("lookup"), QStringLiteral("service"), QStringLiteral("silo-vault"),
                     QStringLiteral("account"), account()}, {}, &out))
            return QByteArray::fromHex(out.trimmed());
        return {};
#endif
    }

    static bool write(const QByteArray &key)
    {
        const QByteArray hex = key.toHex();
#if defined(Q_OS_MACOS)
        return runTool({QStringLiteral("security"), QStringLiteral("add-generic-password"), QStringLiteral("-s"), service(),
                        QStringLiteral("-a"), account(), QStringLiteral("-w"), QString::fromLatin1(hex), QStringLiteral("-U"),
                        QStringLiteral("-l"), QStringLiteral("Silo Vault key")}, {}, nullptr);
#elif defined(Q_OS_WIN)
        CREDENTIALW credential{};
        credential.Type = CRED_TYPE_GENERIC;
        credential.TargetName = const_cast<LPWSTR>(reinterpret_cast<LPCWSTR>(service().utf16()));
        credential.CredentialBlobSize = DWORD(hex.size());
        credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char *>(hex.constData()));
        credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
        credential.UserName = const_cast<LPWSTR>(reinterpret_cast<LPCWSTR>(account().utf16()));
        return CredWriteW(&credential, 0);
#else
        return runTool({QStringLiteral("secret-tool"), QStringLiteral("store"), QStringLiteral("--label=Silo Vault key"),
                        QStringLiteral("service"), QStringLiteral("silo-vault"), QStringLiteral("account"), account()},
                       hex, nullptr);
#endif
    }

    static void clear()
    {
#if defined(Q_OS_MACOS)
        runTool({QStringLiteral("security"), QStringLiteral("delete-generic-password"), QStringLiteral("-s"), service(),
                 QStringLiteral("-a"), account()}, {}, nullptr);
#elif defined(Q_OS_WIN)
        CredDeleteW(reinterpret_cast<LPCWSTR>(service().utf16()), CRED_TYPE_GENERIC, 0);
#else
        runTool({QStringLiteral("secret-tool"), QStringLiteral("clear"), QStringLiteral("service"), QStringLiteral("silo-vault"),
                 QStringLiteral("account"), account()}, {}, nullptr);
#endif
    }
};

// ------------------------------------------------------------------ crypto helpers

QByteArray Vault::randomBytes(int size)
{
    QByteArray bytes(size, Qt::Uninitialized);
    QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(bytes.data()), size / 4);
    for (int i = size - size % 4; i < size; ++i)
        bytes[i] = char(QRandomGenerator::system()->bounded(256));
    return bytes;
}

// nonce(24) + mac(16) + ciphertext
QByteArray Vault::seal(const QByteArray &key, const QByteArray &plain)
{
    QByteArray out = randomBytes(kNonceSize);
    out.resize(kNonceSize + kMacSize + plain.size());
    crypto_aead_lock(reinterpret_cast<uint8_t *>(out.data() + kNonceSize + kMacSize),
                     reinterpret_cast<uint8_t *>(out.data() + kNonceSize),
                     reinterpret_cast<const uint8_t *>(key.constData()),
                     reinterpret_cast<const uint8_t *>(out.constData()),
                     nullptr, 0,
                     reinterpret_cast<const uint8_t *>(plain.constData()), size_t(plain.size()));
    return out;
}

bool Vault::open(const QByteArray &key, const QByteArray &sealed, QByteArray *plain)
{
    if (key.size() != kKeySize || sealed.size() < kNonceSize + kMacSize)
        return false;
    const int textSize = sealed.size() - kNonceSize - kMacSize;
    plain->resize(textSize);
    const int result = crypto_aead_unlock(reinterpret_cast<uint8_t *>(plain->data()),
                                          reinterpret_cast<const uint8_t *>(sealed.constData() + kNonceSize),
                                          reinterpret_cast<const uint8_t *>(key.constData()),
                                          reinterpret_cast<const uint8_t *>(sealed.constData()),
                                          nullptr, 0,
                                          reinterpret_cast<const uint8_t *>(sealed.constData() + kNonceSize + kMacSize),
                                          size_t(textSize));
    if (result != 0) {
        plain->clear();
        return false;
    }
    return true;
}

QByteArray Vault::deriveKey(const QString &password, const QByteArray &salt)
{
    const QByteArray pass = password.toUtf8();
    std::vector<uint8_t> work(size_t(kArgonBlocks) * 1024);
    QByteArray key(kKeySize, Qt::Uninitialized);
    crypto_argon2_config config{CRYPTO_ARGON2_I, kArgonBlocks, kArgonPasses, 1};
    crypto_argon2_inputs inputs{reinterpret_cast<const uint8_t *>(pass.constData()),
                                reinterpret_cast<const uint8_t *>(salt.constData()),
                                uint32_t(pass.size()), uint32_t(salt.size())};
    crypto_argon2(reinterpret_cast<uint8_t *>(key.data()), kKeySize, work.data(), config, inputs, crypto_argon2_no_extras);
    crypto_wipe(work.data(), work.size());
    return key;
}

// ------------------------------------------------------------------ lifecycle

Vault::Vault(QObject *parent) : QObject(parent), m_dir(AppStore::dataDirectory())
{
    QDir().mkpath(m_dir);
    loadKey();
    if (!locked())
        loadEntries();
}

void Vault::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    emit errorChanged();
}

// Reads vault.key (master-wrapped or plain fallback) or the OS keychain,
// creating a fresh key on first run.
void Vault::loadKey()
{
    QFile keyFile(m_dir + QStringLiteral("/vault.key"));
    if (keyFile.exists() && keyFile.open(QIODevice::ReadOnly)) {
        const QJsonObject object = QJsonDocument::fromJson(keyFile.readAll()).object();
        if (object.value(QStringLiteral("wrapped")).toBool()) {
            m_hasMaster = true;
            m_keyStorage = QStringLiteral("master");
            return; // locked until unlock()
        }
        const QByteArray key = QByteArray::fromHex(object.value(QStringLiteral("key")).toString().toLatin1());
        if (key.size() == kKeySize) {
            m_key = key;
            m_keyStorage = QStringLiteral("file");
            return;
        }
    }

    bool keychainOk = true;
    QByteArray key = KeyStore::read(&keychainOk);
    if (key.size() == kKeySize) {
        m_key = key;
        m_keyStorage = QStringLiteral("keychain");
        return;
    }
    // First run (or the keychain entry is gone). A vault without a reachable
    // key cannot be opened: leave it alone rather than overwrite it.
    if (QFile::exists(m_dir + QStringLiteral("/vault.bin"))) {
        setError(QStringLiteral("The vault key was not found in the keychain; the existing vault cannot be opened."));
        m_keyStorage.clear();
        return;
    }
    key = randomBytes(kKeySize);
    if (keychainOk && KeyStore::write(key)) {
        m_keyStorage = QStringLiteral("keychain");
    } else {
        QSaveFile file(m_dir + QStringLiteral("/vault.key"));
        if (file.open(QIODevice::WriteOnly)) {
            file.write(QJsonDocument(QJsonObject{{QStringLiteral("key"), QString::fromLatin1(key.toHex())}}).toJson());
            file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
            file.commit();
        }
        m_keyStorage = QStringLiteral("file");
    }
    m_key = key;
}

void Vault::loadEntries()
{
    m_entries.clear();
    m_never.clear();
    QFile file(m_dir + QStringLiteral("/vault.bin"));
    if (!file.exists()) {
        emit changed();
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        setError(file.errorString());
        return;
    }
    QByteArray sealed = file.readAll();
    if (!sealed.startsWith(kMagic)) {
        setError(QStringLiteral("vault.bin is not a Silo vault."));
        return;
    }
    sealed.remove(0, kMagic.size());
    QByteArray plain;
    if (!open(m_key, sealed, &plain)) {
        setError(QStringLiteral("The vault could not be decrypted with the stored key."));
        return;
    }
    const QJsonObject root = QJsonDocument::fromJson(plain).object();
    crypto_wipe(plain.data(), size_t(plain.size()));
    for (const QJsonValue &value : root.value(QStringLiteral("entries")).toArray()) {
        const QJsonObject object = value.toObject();
        Entry entry;
        entry.id = object.value(QStringLiteral("id")).toString();
        entry.title = object.value(QStringLiteral("title")).toString();
        entry.url = object.value(QStringLiteral("url")).toString();
        entry.host = hostFromAny(entry.url);
        entry.username = object.value(QStringLiteral("username")).toString();
        entry.password = object.value(QStringLiteral("password")).toString();
        entry.totp = object.value(QStringLiteral("totp")).toString();
        entry.notes = object.value(QStringLiteral("notes")).toString();
        entry.source = object.value(QStringLiteral("source")).toString();
        entry.createdAt = qint64(object.value(QStringLiteral("createdAt")).toDouble());
        entry.updatedAt = qint64(object.value(QStringLiteral("updatedAt")).toDouble());
        if (!entry.id.isEmpty())
            m_entries.append(entry);
    }
    for (const QJsonValue &value : root.value(QStringLiteral("never")).toArray())
        m_never.insert(value.toString());
    emit changed();
}

bool Vault::persist()
{
    if (locked()) {
        setError(QStringLiteral("The vault is locked."));
        return false;
    }
    QJsonArray entries;
    for (const Entry &entry : m_entries) {
        entries.append(QJsonObject{{QStringLiteral("id"), entry.id}, {QStringLiteral("title"), entry.title},
                                   {QStringLiteral("url"), entry.url}, {QStringLiteral("username"), entry.username},
                                   {QStringLiteral("password"), entry.password}, {QStringLiteral("totp"), entry.totp},
                                   {QStringLiteral("notes"), entry.notes}, {QStringLiteral("source"), entry.source},
                                   {QStringLiteral("createdAt"), double(entry.createdAt)},
                                   {QStringLiteral("updatedAt"), double(entry.updatedAt)}});
    }
    QJsonArray never;
    for (const QString &host : m_never)
        never.append(host);
    QByteArray plain = QJsonDocument(QJsonObject{{QStringLiteral("entries"), entries}, {QStringLiteral("never"), never}})
                           .toJson(QJsonDocument::Compact);
    const QByteArray sealed = seal(m_key, plain);
    crypto_wipe(plain.data(), size_t(plain.size()));

    QSaveFile file(m_dir + QStringLiteral("/vault.bin"));
    if (!file.open(QIODevice::WriteOnly)) {
        setError(file.errorString());
        return false;
    }
    file.write(kMagic);
    file.write(sealed);
    file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
    if (!file.commit()) {
        setError(file.errorString());
        return false;
    }
    setError({});
    emit changed();
    return true;
}

// ------------------------------------------------------------------ queries

QString Vault::hostOf(const QString &url) const
{
    return hostFromAny(url);
}

QVariantMap Vault::toSummary(const Entry &entry) const
{
    return {{QStringLiteral("id"), entry.id},
            {QStringLiteral("title"), entry.title.isEmpty() ? entry.host : entry.title},
            {QStringLiteral("username"), entry.username},
            {QStringLiteral("url"), entry.url},
            {QStringLiteral("host"), entry.host},
            {QStringLiteral("hasTotp"), !entry.totp.isEmpty()},
            {QStringLiteral("source"), QStringLiteral("vault")},
            {QStringLiteral("origin"), entry.source},
            {QStringLiteral("updatedAt"), entry.updatedAt}};
}

QVariantList Vault::search(const QString &url) const
{
    QVariantList results;
    const QString host = hostFromAny(url);
    if (host.isEmpty())
        return results;
    for (const Entry &entry : m_entries)
        if (hostMatches(entry.host, host))
            results.append(toSummary(entry));
    return results;
}

QVariantMap Vault::get(const QString &id) const
{
    for (const Entry &entry : m_entries) {
        if (entry.id != id)
            continue;
        QVariantMap map = toSummary(entry);
        map.insert(QStringLiteral("password"), entry.password);
        map.insert(QStringLiteral("notes"), entry.notes);
        map.insert(QStringLiteral("totpSecret"), entry.totp);
        map.insert(QStringLiteral("totp"), entry.totp.isEmpty() ? QString() : totpCode(entry.totp));
        return map;
    }
    return {};
}

QVariantList Vault::entries() const
{
    QVariantList list;
    for (const Entry &entry : m_entries)
        list.append(toSummary(entry));
    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("title")).toString().compare(
                   b.toMap().value(QStringLiteral("title")).toString(), Qt::CaseInsensitive) < 0;
    });
    return list;
}

QVariantMap Vault::findLogin(const QString &url, const QString &username) const
{
    const QString host = hostFromAny(url);
    for (const Entry &entry : m_entries)
        if (entry.host == host && entry.username.compare(username, Qt::CaseInsensitive) == 0)
            return toSummary(entry);
    return {};
}

QString Vault::save(const QVariantMap &input)
{
    if (locked())
        return {};
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    QString id = input.value(QStringLiteral("id")).toString();
    const QString url = input.value(QStringLiteral("url")).toString().trimmed();
    const QString host = hostFromAny(url);
    const QString username = input.value(QStringLiteral("username")).toString();

    Entry *target = nullptr;
    for (Entry &entry : m_entries) {
        if (!id.isEmpty() ? entry.id == id
                          : (entry.host == host && entry.username.compare(username, Qt::CaseInsensitive) == 0)) {
            target = &entry;
            break;
        }
    }
    if (!target) {
        Entry entry;
        entry.id = id.isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : id;
        entry.createdAt = now;
        entry.source = input.value(QStringLiteral("source"), QStringLiteral("manual")).toString();
        m_entries.append(entry);
        target = &m_entries.last();
    }
    target->title = input.value(QStringLiteral("title"), target->title).toString();
    if (target->title.isEmpty())
        target->title = host;
    if (!url.isEmpty()) {
        target->url = url;
        target->host = host;
    }
    target->username = username;
    if (input.contains(QStringLiteral("password")))
        target->password = input.value(QStringLiteral("password")).toString();
    if (input.contains(QStringLiteral("totp")))
        target->totp = input.value(QStringLiteral("totp")).toString().trimmed();
    if (input.contains(QStringLiteral("notes")))
        target->notes = input.value(QStringLiteral("notes")).toString();
    target->updatedAt = now;
    id = target->id;
    return persist() ? id : QString();
}

bool Vault::remove(const QString &id)
{
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries.at(i).id == id) {
            m_entries.removeAt(i);
            return persist();
        }
    }
    return false;
}

void Vault::setNeverSave(const QString &url, bool never)
{
    const QString host = hostFromAny(url);
    if (host.isEmpty())
        return;
    if (never)
        m_never.insert(host);
    else
        m_never.remove(host);
    persist();
}

bool Vault::neverSave(const QString &url) const
{
    return m_never.contains(hostFromAny(url));
}

// ------------------------------------------------------------------ master password

QString Vault::setMasterPassword(const QString &password)
{
    if (locked())
        return QStringLiteral("Unlock the vault first.");
    if (password.size() < 4)
        return QStringLiteral("Choose a longer master password.");
    const QByteArray salt = randomBytes(kSaltSize);
    QByteArray wrapKey = deriveKey(password, salt);
    const QByteArray sealedKey = seal(wrapKey, m_key);
    crypto_wipe(wrapKey.data(), size_t(wrapKey.size()));

    QSaveFile file(m_dir + QStringLiteral("/vault.key"));
    if (!file.open(QIODevice::WriteOnly))
        return file.errorString();
    file.write(QJsonDocument(QJsonObject{{QStringLiteral("wrapped"), true},
                                         {QStringLiteral("salt"), QString::fromLatin1(salt.toHex())},
                                         {QStringLiteral("key"), QString::fromLatin1(sealedKey.toHex())}})
                   .toJson());
    file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
    if (!file.commit())
        return file.errorString();
    KeyStore::clear();
    m_hasMaster = true;
    m_keyStorage = QStringLiteral("master");
    emit lockedChanged();
    return {};
}

QString Vault::removeMasterPassword(const QString &password)
{
    if (!m_hasMaster)
        return {};
    if (locked() && !unlock(password))
        return QStringLiteral("Wrong master password.");
    bool keychainOk = true;
    KeyStore::read(&keychainOk);
    const QString keyPath = m_dir + QStringLiteral("/vault.key");
    if (keychainOk && KeyStore::write(m_key)) {
        QFile::remove(keyPath);
        m_keyStorage = QStringLiteral("keychain");
    } else {
        QSaveFile file(keyPath);
        if (!file.open(QIODevice::WriteOnly))
            return file.errorString();
        file.write(QJsonDocument(QJsonObject{{QStringLiteral("key"), QString::fromLatin1(m_key.toHex())}}).toJson());
        file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
        file.commit();
        m_keyStorage = QStringLiteral("file");
    }
    m_hasMaster = false;
    emit lockedChanged();
    return {};
}

bool Vault::unlock(const QString &password)
{
    if (!locked())
        return true;
    QFile keyFile(m_dir + QStringLiteral("/vault.key"));
    if (!keyFile.open(QIODevice::ReadOnly))
        return false;
    const QJsonObject object = QJsonDocument::fromJson(keyFile.readAll()).object();
    const QByteArray salt = QByteArray::fromHex(object.value(QStringLiteral("salt")).toString().toLatin1());
    const QByteArray sealedKey = QByteArray::fromHex(object.value(QStringLiteral("key")).toString().toLatin1());
    QByteArray wrapKey = deriveKey(password, salt);
    QByteArray key;
    const bool ok = open(wrapKey, sealedKey, &key);
    crypto_wipe(wrapKey.data(), size_t(wrapKey.size()));
    if (!ok || key.size() != kKeySize)
        return false;
    m_key = key;
    setError({});
    emit lockedChanged();
    loadEntries();
    return true;
}

void Vault::lock()
{
    if (!m_hasMaster || locked())
        return;
    crypto_wipe(m_key.data(), size_t(m_key.size()));
    m_key.clear();
    m_entries.clear();
    emit lockedChanged();
    emit changed();
}

// ------------------------------------------------------------------ TOTP

QString Vault::totpCode(const QString &secretOrUri) const
{
    const TotpSpec spec = parseTotp(secretOrUri);
    if (spec.secret.isEmpty())
        return {};
    const quint64 counter = quint64(QDateTime::currentSecsSinceEpoch() / spec.period);
    QByteArray message(8, 0);
    qToBigEndian(counter, message.data());
    const QByteArray hmac = QMessageAuthenticationCode::hash(message, spec.secret, spec.algorithm);
    const int offset = hmac.at(hmac.size() - 1) & 0x0F;
    const quint32 binary = ((quint32(quint8(hmac.at(offset))) & 0x7F) << 24)
                           | (quint32(quint8(hmac.at(offset + 1))) << 16)
                           | (quint32(quint8(hmac.at(offset + 2))) << 8)
                           | quint32(quint8(hmac.at(offset + 3)));
    quint32 modulo = 1;
    for (int i = 0; i < spec.digits; ++i)
        modulo *= 10;
    return QStringLiteral("%1").arg(binary % modulo, spec.digits, 10, QLatin1Char('0'));
}

int Vault::totpRemaining(const QString &secretOrUri) const
{
    const TotpSpec spec = parseTotp(secretOrUri);
    return spec.period - int(QDateTime::currentSecsSinceEpoch() % spec.period);
}

// ------------------------------------------------------------------ CSV import

// RFC 4180-ish: quoted fields may hold delimiters, doubled quotes and newlines.
Vault::CsvTable Vault::parseCsv(const QString &text)
{
    CsvTable table;
    // Delimiter: the most frequent of , ; \t on the header line
    const QString firstLine = text.section(QLatin1Char('\n'), 0, 0);
    QChar delimiter = QLatin1Char(',');
    int best = firstLine.count(QLatin1Char(','));
    for (const QChar candidate : {QLatin1Char(';'), QLatin1Char('\t')}) {
        const int count = int(firstLine.count(candidate));
        if (count > best) {
            best = count;
            delimiter = candidate;
        }
    }
    QStringList row;
    QString field;
    bool quoted = false;
    const qsizetype size = text.size();
    auto flushRow = [&] {
        row.append(field);
        field.clear();
        if (!(row.size() == 1 && row.first().trimmed().isEmpty())) {
            if (table.header.isEmpty())
                table.header = row;
            else
                table.rows.append(row);
        }
        row.clear();
    };
    for (qsizetype i = 0; i < size; ++i) {
        const QChar c = text.at(i);
        if (quoted) {
            if (c == QLatin1Char('"')) {
                if (i + 1 < size && text.at(i + 1) == QLatin1Char('"')) {
                    field.append(QLatin1Char('"'));
                    ++i;
                } else {
                    quoted = false;
                }
            } else {
                field.append(c);
            }
        } else if (c == QLatin1Char('"') && field.isEmpty()) {
            quoted = true;
        } else if (c == delimiter) {
            row.append(field);
            field.clear();
        } else if (c == QLatin1Char('\n') || c == QLatin1Char('\r')) {
            if (c == QLatin1Char('\r') && i + 1 < size && text.at(i + 1) == QLatin1Char('\n'))
                ++i;
            flushRow();
        } else {
            field.append(c);
        }
    }
    if (!field.isEmpty() || !row.isEmpty())
        flushRow();
    return table;
}

// Maps the export's columns to ours and names the manager it came from.
QString Vault::detectFormat(const QStringList &header, QHash<QString, int> *columns)
{
    QHash<QString, int> byName;
    for (int i = 0; i < header.size(); ++i)
        byName.insert(csvColumnKey(header.at(i)), i);
    auto pick = [&](const QString &target, const QStringList &candidates) {
        for (const QString &candidate : candidates) {
            if (byName.contains(candidate)) {
                columns->insert(target, byName.value(candidate));
                return;
            }
        }
    };
    pick(QStringLiteral("title"), {"title", "name", "account", "site", "item", "nom", "titre"});
    pick(QStringLiteral("url"), {"url", "login_uri", "uri", "website", "web_site", "login_url", "site_url", "hostname", "urls", "address", "adresse"});
    pick(QStringLiteral("username"), {"username", "login_username", "login", "user", "user_name", "email", "e_mail", "identifiant", "utilisateur"});
    pick(QStringLiteral("password"), {"password", "login_password", "pass", "pwd", "mot_de_passe", "passwd"});
    pick(QStringLiteral("totp"), {"totp", "login_totp", "otpauth", "otp", "otpsecret", "otp_secret", "otp_url", "totp_secret", "2fa"});
    pick(QStringLiteral("notes"), {"notes", "note", "extra", "comments", "comment", "remarques"});
    pick(QStringLiteral("type"), {"type"});
    pick(QStringLiteral("email"), {"email", "e_mail"});
    pick(QStringLiteral("username2"), {"username2", "secondary_login", "login2"});

    if (byName.contains(QStringLiteral("login_uri")) && byName.contains(QStringLiteral("login_username")))
        return QStringLiteral("Bitwarden");
    if (byName.contains(QStringLiteral("otpauth")) && byName.contains(QStringLiteral("title")))
        return QStringLiteral("1Password");
    if (byName.contains(QStringLiteral("grouping")) && byName.contains(QStringLiteral("extra")))
        return QStringLiteral("LastPass");
    if (byName.contains(QStringLiteral("username2")) || byName.contains(QStringLiteral("otpsecret")))
        return QStringLiteral("Dashlane");
    if (byName.contains(QStringLiteral("httprealm")))
        return QStringLiteral("Firefox");
    if (byName.contains(QStringLiteral("group")) && byName.contains(QStringLiteral("title")))
        return QStringLiteral("KeePass");
    if (byName.contains(QStringLiteral("type")) && byName.contains(QStringLiteral("email")) && byName.contains(QStringLiteral("totp")))
        return QStringLiteral("Proton Pass");
    if (byName.contains(QStringLiteral("cardholdername")))
        return QStringLiteral("NordPass");
    if (byName.contains(QStringLiteral("name")) && byName.contains(QStringLiteral("url")) && byName.contains(QStringLiteral("username")))
        return QStringLiteral("Chrome / Edge");
    return columns->contains(QStringLiteral("password")) ? QStringLiteral("Generic CSV") : QString();
}

QVariantMap Vault::inspectCsv(const QUrl &fileUrl) const
{
    QVariantMap result{{QStringLiteral("ok"), false}};
    QFile file(fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString());
    if (!file.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("error")] = file.errorString();
        return result;
    }
    QByteArray bytes = file.readAll();
    if (bytes.startsWith("\xEF\xBB\xBF"))
        bytes.remove(0, 3);
    QStringDecoder decoder(QStringDecoder::Utf8);
    QString text = decoder.decode(bytes);
    if (decoder.hasError())
        text = QString::fromLatin1(bytes);
    const CsvTable table = parseCsv(text);
    QHash<QString, int> columns;
    const QString format = detectFormat(table.header, &columns);
    if (format.isEmpty() || !columns.contains(QStringLiteral("password"))) {
        result[QStringLiteral("error")] = QStringLiteral("No password column found. Export your logins as CSV from your password manager.");
        return result;
    }
    int logins = 0;
    const int typeColumn = columns.value(QStringLiteral("type"), -1);
    for (const QStringList &row : table.rows) {
        if (typeColumn >= 0 && typeColumn < row.size()) {
            const QString type = row.at(typeColumn).trimmed().toLower();
            if (!type.isEmpty() && type != QStringLiteral("login") && type != QStringLiteral("1") && type != QStringLiteral("password"))
                continue;
        }
        const int passwordColumn = columns.value(QStringLiteral("password"));
        if (passwordColumn < row.size() && !row.at(passwordColumn).isEmpty())
            ++logins;
    }
    result[QStringLiteral("ok")] = true;
    result[QStringLiteral("format")] = format;
    result[QStringLiteral("logins")] = logins;
    result[QStringLiteral("rows")] = int(table.rows.size());
    result[QStringLiteral("hasTotp")] = columns.contains(QStringLiteral("totp"));
    return result;
}

QVariantMap Vault::importCsv(const QUrl &fileUrl)
{
    QVariantMap result = inspectCsv(fileUrl);
    if (!result.value(QStringLiteral("ok")).toBool())
        return result;
    if (locked()) {
        result[QStringLiteral("ok")] = false;
        result[QStringLiteral("error")] = QStringLiteral("The vault is locked.");
        return result;
    }
    QFile file(fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString());
    if (!file.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("ok")] = false;
        result[QStringLiteral("error")] = file.errorString();
        return result;
    }
    QByteArray bytes = file.readAll();
    if (bytes.startsWith("\xEF\xBB\xBF"))
        bytes.remove(0, 3);
    QStringDecoder decoder(QStringDecoder::Utf8);
    QString text = decoder.decode(bytes);
    if (decoder.hasError())
        text = QString::fromLatin1(bytes);
    const CsvTable table = parseCsv(text);
    QHash<QString, int> columns;
    const QString format = detectFormat(table.header, &columns);
    auto cell = [&](const QStringList &row, const QString &name) -> QString {
        const int column = columns.value(name, -1);
        return column >= 0 && column < row.size() ? row.at(column).trimmed() : QString();
    };

    int added = 0, updated = 0, skipped = 0;
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const QString source = QStringLiteral("import:") + format;
    for (const QStringList &row : table.rows) {
        const QString type = cell(row, QStringLiteral("type")).toLower();
        if (!type.isEmpty() && type != QStringLiteral("login") && type != QStringLiteral("1") && type != QStringLiteral("password")) {
            ++skipped;
            continue;
        }
        const QString password = cell(row, QStringLiteral("password"));
        QString username = cell(row, QStringLiteral("username"));
        if (username.isEmpty())
            username = cell(row, QStringLiteral("email"));
        if (username.isEmpty())
            username = cell(row, QStringLiteral("username2"));
        // Multi-URL cells (1Password joins with newlines, LastPass with commas)
        QString url = cell(row, QStringLiteral("url"));
        url = url.split(QRegularExpression(QStringLiteral("[\\n,;]")), Qt::SkipEmptyParts).value(0).trimmed();
        if (password.isEmpty() && username.isEmpty()) {
            ++skipped;
            continue;
        }
        const QString host = hostFromAny(url);
        QString title = cell(row, QStringLiteral("title"));
        if (title.isEmpty())
            title = host.isEmpty() ? username : host;

        Entry *target = nullptr;
        for (Entry &entry : m_entries) {
            if (entry.host == host && entry.username.compare(username, Qt::CaseInsensitive) == 0) {
                target = &entry;
                break;
            }
        }
        if (target) {
            const QString totp = cell(row, QStringLiteral("totp"));
            if (target->password == password && (totp.isEmpty() || target->totp == totp)) {
                ++skipped;
                continue;
            }
            target->password = password;
            if (!totp.isEmpty())
                target->totp = totp;
            target->updatedAt = now;
            ++updated;
            continue;
        }
        Entry entry;
        entry.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        entry.title = title;
        entry.url = url;
        entry.host = host;
        entry.username = username;
        entry.password = password;
        entry.totp = cell(row, QStringLiteral("totp"));
        entry.notes = cell(row, QStringLiteral("notes"));
        entry.source = source;
        entry.createdAt = now;
        entry.updatedAt = now;
        m_entries.append(entry);
        ++added;
    }
    if ((added || updated) && !persist()) {
        result[QStringLiteral("ok")] = false;
        result[QStringLiteral("error")] = m_error;
        return result;
    }
    result[QStringLiteral("added")] = added;
    result[QStringLiteral("updated")] = updated;
    result[QStringLiteral("skipped")] = skipped;
    return result;
}
