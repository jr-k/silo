#include "FileInspector.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <QSaveFile>
#include <QSet>
#include <QStringDecoder>
#include <QClipboard>
#include <QGuiApplication>

FileInspector::FileInspector(QObject *parent) : QObject(parent) {}

QString FileInspector::expand(const QString &path) const
{
    QString p = path.trimmed();
    if (p.startsWith(QStringLiteral("file://")))
        p = QUrl(p).toLocalFile();
    if (p == QStringLiteral("~"))
        return QDir::homePath();
    if (p.startsWith(QStringLiteral("~/")))
        return QDir::homePath() + p.mid(1);
    return p;
}

void FileInspector::copyToClipboard(const QString &text) const
{
    QGuiApplication::clipboard()->setText(text);
}

QString FileInspector::homePath() const
{
    return QDir::homePath();
}

QStringList FileInspector::sshKeyFiles() const
{
    QStringList keys;
    const QDir sshDir(QDir::homePath() + QStringLiteral("/.ssh"));
    static const QSet<QString> skip = {"config", "known_hosts", "known_hosts.old", "authorized_keys",
                                       "environment", "rc", "agent.sock"};
    for (const QFileInfo &info : sshDir.entryInfoList(QDir::Files | QDir::Hidden, QDir::Name)) {
        if (skip.contains(info.fileName()) || info.suffix() == QStringLiteral("pub"))
            continue;
        QFile file(info.absoluteFilePath());
        if (!file.open(QIODevice::ReadOnly))
            continue;
        if (file.read(128).contains("PRIVATE KEY"))
            keys.append(info.absoluteFilePath());
    }
    return keys;
}

QString FileInspector::formatSize(qint64 bytes) const
{
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

QString FileInspector::kindFor(const QString &suffix, const QString &mime)
{
    static const QSet<QString> images = {"png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "tif", "tiff", "heic", "avif"};
    static const QSet<QString> videos = {"mp4", "m4v", "mov", "webm", "mkv", "avi", "mpg", "mpeg"};
    static const QSet<QString> audios = {"mp3", "m4a", "aac", "flac", "wav", "ogg", "oga", "opus", "aiff", "aif"};
    if (suffix == QStringLiteral("pdf") || mime == QStringLiteral("application/pdf"))
        return QStringLiteral("pdf");
    if (suffix == QStringLiteral("csv") || suffix == QStringLiteral("tsv") || mime == QStringLiteral("text/csv")
        || mime == QStringLiteral("text/tab-separated-values"))
        return QStringLiteral("csv");
    if (images.contains(suffix) || mime.startsWith(QStringLiteral("image/")))
        return QStringLiteral("image");
    if (videos.contains(suffix) || mime.startsWith(QStringLiteral("video/")))
        return QStringLiteral("video");
    if (audios.contains(suffix) || mime.startsWith(QStringLiteral("audio/")))
        return QStringLiteral("audio");
    if (mime.startsWith(QStringLiteral("text/")) || mime.endsWith(QStringLiteral("json"))
        || mime.endsWith(QStringLiteral("xml")) || mime.endsWith(QStringLiteral("javascript"))
        || mime.endsWith(QStringLiteral("yaml")) || mime.contains(QStringLiteral("x-sh"))
        || mime.contains(QStringLiteral("shellscript")) || mime.contains(QStringLiteral("x-php"))
        || mime.contains(QStringLiteral("x-python")) || mime.contains(QStringLiteral("x-ruby"))
        || mime.contains(QStringLiteral("x-perl")) || mime.contains(QStringLiteral("toml")))
        return QStringLiteral("text");
    return QStringLiteral("other");
}

QString FileInspector::languageFor(const QString &suffix, const QString &baseName)
{
    static const QHash<QString, QString> bySuffix = {
        {"json", "json"},       {"jsonc", "json"},     {"yaml", "yaml"},        {"yml", "yaml"},
        {"js", "javascript"},   {"mjs", "javascript"}, {"cjs", "javascript"},   {"jsx", "javascript"},
        {"ts", "typescript"},   {"tsx", "typescript"}, {"php", "php"},          {"py", "python"},
        {"rb", "ruby"},         {"go", "go"},          {"rs", "rust"},          {"java", "java"},
        {"kt", "kotlin"},       {"kts", "kotlin"},     {"swift", "swift"},      {"c", "c"},
        {"h", "c"},             {"cpp", "cpp"},        {"cc", "cpp"},           {"cxx", "cpp"},
        {"hpp", "cpp"},         {"hh", "cpp"},         {"mm", "objectivec"},    {"m", "objectivec"},
        {"cs", "csharp"},       {"sh", "bash"},        {"bash", "bash"},        {"zsh", "bash"},
        {"fish", "bash"},       {"ps1", "powershell"}, {"sql", "sql"},          {"html", "xml"},
        {"htm", "xml"},         {"xml", "xml"},        {"svg", "xml"},          {"plist", "xml"},
        {"css", "css"},         {"scss", "scss"},      {"less", "less"},        {"md", "markdown"},
        {"markdown", "markdown"}, {"ini", "ini"},      {"toml", "ini"},         {"cfg", "ini"},
        {"conf", "ini"},        {"env", "bash"},       {"dockerfile", "dockerfile"}, {"mk", "makefile"},
        {"cmake", "cmake"},     {"gradle", "gradle"},  {"lua", "lua"},          {"pl", "perl"},
        {"r", "r"},             {"dart", "dart"},      {"scala", "scala"},      {"vue", "xml"},
        {"qml", "javascript"},  {"graphql", "graphql"}, {"proto", "protobuf"},  {"diff", "diff"},
        {"patch", "diff"},      {"txt", "plaintext"},  {"log", "plaintext"},    {"csv", "plaintext"},
    };
    const QString lowerName = baseName.toLower();
    if (lowerName == QStringLiteral("dockerfile"))
        return QStringLiteral("dockerfile");
    if (lowerName == QStringLiteral("makefile") || lowerName == QStringLiteral("cmakelists.txt"))
        return lowerName.startsWith(QStringLiteral("cmake")) ? QStringLiteral("cmake") : QStringLiteral("makefile");
    return bySuffix.value(suffix);
}

QVariantMap FileInspector::inspect(const QString &path) const
{
    const QString full = expand(path);
    const QFileInfo info(full);
    QVariantMap result{{QStringLiteral("path"), full},
                       {QStringLiteral("exists"), info.exists()},
                       {QStringLiteral("isDir"), info.isDir()},
                       {QStringLiteral("name"), info.fileName()},
                       {QStringLiteral("dir"), info.absolutePath()},
                       {QStringLiteral("suffix"), info.suffix().toLower()},
                       {QStringLiteral("size"), info.size()}};
    QString mime;
    if (info.exists() && info.isFile()) {
        QMimeDatabase db;
        mime = db.mimeTypeForFile(info).name();
    }
    const QString suffix = info.suffix().toLower();
    const QString language = languageFor(suffix, info.fileName());
    QString kind = info.isDir() ? QStringLiteral("other") : kindFor(suffix, mime);
    if (kind == QStringLiteral("other") && !language.isEmpty())
        kind = QStringLiteral("text");
    result.insert(QStringLiteral("mime"), mime);
    result.insert(QStringLiteral("kind"), kind);
    result.insert(QStringLiteral("language"), language);
    result.insert(QStringLiteral("url"), QUrl::fromLocalFile(full));
    return result;
}

QString FileInspector::readText(const QString &path, int maxBytes) const
{
    QFile file(expand(path));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QByteArray bytes = file.read(maxBytes);
    const bool truncated = file.bytesAvailable() > 0;
    // Decode as UTF-8, falling back to Latin-1 for legacy files.
    QStringDecoder decoder(QStringDecoder::Utf8);
    QString text = decoder.decode(bytes);
    if (decoder.hasError())
        text = QString::fromLatin1(bytes);
    if (truncated)
        text += QStringLiteral("\n\n… (file truncated at ") + formatSize(maxBytes) + QLatin1Char(')');
    return text;
}

QVariantMap FileInspector::readDocument(const QString &path, int maxBytes) const
{
    QVariantMap result{{QStringLiteral("text"), QString()},
                       {QStringLiteral("truncated"), false},
                       {QStringLiteral("latin1"), false},
                       {QStringLiteral("bom"), false},
                       {QStringLiteral("error"), QString()}};
    QFile file(expand(path));
    if (!file.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("error")] = file.errorString();
        return result;
    }
    QByteArray bytes = file.read(maxBytes);
    result[QStringLiteral("truncated")] = file.bytesAvailable() > 0;
    if (bytes.startsWith("\xEF\xBB\xBF")) {
        bytes.remove(0, 3);
        result[QStringLiteral("bom")] = true;
    }
    QStringDecoder decoder(QStringDecoder::Utf8);
    QString text = decoder.decode(bytes);
    if (decoder.hasError()) {
        text = QString::fromLatin1(bytes);
        result[QStringLiteral("latin1")] = true;
    }
    result[QStringLiteral("text")] = text;
    return result;
}

QString FileInspector::writeText(const QString &path, const QString &text, const QVariantMap &options) const
{
    QSaveFile file(expand(path));
    if (!file.open(QIODevice::WriteOnly))
        return file.errorString();
    QByteArray bytes;
    if (options.value(QStringLiteral("bom")).toBool())
        bytes.append("\xEF\xBB\xBF", 3);
    bytes.append(options.value(QStringLiteral("latin1")).toBool() ? text.toLatin1() : text.toUtf8());
    if (file.write(bytes) != bytes.size() || !file.commit())
        return file.errorString().isEmpty() ? QStringLiteral("Write failed") : file.errorString();
    return {};
}

bool FileInspector::isWritable(const QString &path) const
{
    const QFileInfo info(expand(path));
    return info.exists() ? info.isWritable() : QFileInfo(info.absolutePath()).isWritable();
}
