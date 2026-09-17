#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantMap>

// Local file helpers for the "file" item type (Live mode viewers).
class FileInspector final : public QObject
{
    Q_OBJECT
public:
    explicit FileInspector(QObject *parent = nullptr);

    // {exists, isDir, name, dir, suffix, size, mime, kind, language}
    // kind: "pdf" | "csv" | "image" | "video" | "audio" | "text" | "other"
    // language: highlight.js language id for text files ("" = let it guess).
    Q_INVOKABLE QVariantMap inspect(const QString &path) const;
    Q_INVOKABLE QString readText(const QString &path, int maxBytes = 4 * 1024 * 1024) const;
    // Text plus what is needed to write it back byte-for-byte compatible:
    // {text, truncated, latin1, bom, error}. Truncated documents must not be
    // written back (the tail would be lost).
    Q_INVOKABLE QVariantMap readDocument(const QString &path, int maxBytes = 4 * 1024 * 1024) const;
    // Atomic write (QSaveFile). options: {latin1, bom}. Returns "" or an error message.
    Q_INVOKABLE QString writeText(const QString &path, const QString &text, const QVariantMap &options = {}) const;
    Q_INVOKABLE bool isWritable(const QString &path) const;
    Q_INVOKABLE QUrl toUrl(const QString &path) const { return QUrl::fromLocalFile(expand(path)); }
    Q_INVOKABLE QString fromUrl(const QUrl &url) const { return url.toLocalFile(); }
    Q_INVOKABLE QString expand(const QString &path) const;
    Q_INVOKABLE QString formatSize(qint64 bytes) const;
    Q_INVOKABLE QString homePath() const;
    Q_INVOKABLE void copyToClipboard(const QString &text) const;
    // Private key files found in ~/.ssh (absolute paths).
    Q_INVOKABLE QStringList sshKeyFiles() const;

private:
    static QString kindFor(const QString &suffix, const QString &mime);
    static QString languageFor(const QString &suffix, const QString &baseName);
};
