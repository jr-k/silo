#pragma once

#include <QByteArray>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

// Silo's own login store, so autofill works with any password manager (import
// their CSV export) and without one (logins captured when submitted in a tab).
//
// vault.bin holds the JSON entries encrypted with XChaCha20-Poly1305
// (Monocypher). The 32-byte key lives in the OS keychain (macOS Keychain,
// Windows Credential Manager, libsecret) or, when the user sets a master
// password, wrapped with an Argon2i-derived key in vault.key.
class Vault final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)
    Q_PROPERTY(bool hasMasterPassword READ hasMasterPassword NOTIFY lockedChanged)
    // "keychain" | "file" | "master" | ""
    Q_PROPERTY(QString keyStorage READ keyStorage NOTIFY lockedChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit Vault(QObject *parent = nullptr);

    int count() const { return int(m_entries.size()); }
    bool locked() const { return m_key.isEmpty(); }
    bool hasMasterPassword() const { return m_hasMaster; }
    QString keyStorage() const { return m_keyStorage; }
    QString error() const { return m_error; }

    // Logins matching the page host: [{id, title, username, url, hasTotp, source: "vault"}]
    Q_INVOKABLE QVariantList search(const QString &url) const;
    // One login with its password and, when it has a TOTP secret, the current code
    Q_INVOKABLE QVariantMap get(const QString &id) const;
    // All logins without passwords, for the management list
    Q_INVOKABLE QVariantList entries() const;
    // Upsert. Without id, matches an existing login on host + username. Returns the id.
    Q_INVOKABLE QString save(const QVariantMap &entry);
    Q_INVOKABLE bool remove(const QString &id);
    // Existing login for this host + username (empty map when none): tells a
    // capture whether it is a new login or a password change.
    Q_INVOKABLE QVariantMap findLogin(const QString &url, const QString &username) const;
    Q_INVOKABLE void setNeverSave(const QString &url, bool never);
    Q_INVOKABLE bool neverSave(const QString &url) const;

    // CSV import from any password manager export
    Q_INVOKABLE QVariantMap inspectCsv(const QUrl &fileUrl) const;
    Q_INVOKABLE QVariantMap importCsv(const QUrl &fileUrl);

    // Master password (optional): wraps the key instead of the OS keychain
    Q_INVOKABLE QString setMasterPassword(const QString &password);
    Q_INVOKABLE QString removeMasterPassword(const QString &password);
    Q_INVOKABLE bool unlock(const QString &password);
    Q_INVOKABLE void lock();

    Q_INVOKABLE QString totpCode(const QString &secretOrUri) const;
    Q_INVOKABLE int totpRemaining(const QString &secretOrUri) const;
    Q_INVOKABLE QString hostOf(const QString &url) const;

    // CSV helpers shared with the importer (public for the format probe)
    struct CsvTable {
        QStringList header;
        QList<QStringList> rows;
    };
    static CsvTable parseCsv(const QString &text);

signals:
    void changed();
    void lockedChanged();
    void errorChanged();

private:
    struct Entry {
        QString id, title, url, host, username, password, totp, notes, source;
        qint64 createdAt = 0, updatedAt = 0;
    };
    struct KeyStore;

    void loadKey();
    void loadEntries();
    bool persist();
    void setError(const QString &error);
    QVariantMap toSummary(const Entry &entry) const;
    static QByteArray randomBytes(int size);
    static QByteArray seal(const QByteArray &key, const QByteArray &plain);
    static bool open(const QByteArray &key, const QByteArray &sealed, QByteArray *plain);
    static QByteArray deriveKey(const QString &password, const QByteArray &salt);
    static QString detectFormat(const QStringList &header, QHash<QString, int> *columns);

    QString m_dir;
    QByteArray m_key;
    QString m_keyStorage;
    bool m_hasMaster = false;
    QString m_error;
    QList<Entry> m_entries;
    QSet<QString> m_never;
};
