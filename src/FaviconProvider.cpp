#include "FaviconProvider.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QImageReader>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QUrlQuery>

namespace {
constexpr int kMaxStoredSize = 128;
}

// ---------------------------------------------------------------- FaviconFetcher

FaviconFetcher::FaviconFetcher(QObject *parent) : QObject(parent)
{
    m_network.setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
    m_cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/favicons");
    QDir().mkpath(m_cacheDir);
}

QString FaviconFetcher::cachePathFor(const QString &host) const
{
    const QByteArray key = QCryptographicHash::hash(host.toUtf8(), QCryptographicHash::Sha1).toHex();
    return m_cacheDir + QLatin1Char('/') + QString::fromLatin1(key) + QStringLiteral(".png");
}

QList<QUrl> FaviconFetcher::candidateUrls(const QUrl &pageUrl) const
{
    const QString host = pageUrl.host();
    QList<QUrl> urls;
    // Both services answer 404 when they have nothing, so we can fall back cleanly.
    urls.append(QUrl(QStringLiteral("https://icons.duckduckgo.com/ip3/") + host + QStringLiteral(".ico")));
    QUrl google(QStringLiteral("https://www.google.com/s2/favicons"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("sz"), QStringLiteral("64"));
    query.addQueryItem(QStringLiteral("domain_url"), pageUrl.scheme() + QStringLiteral("://") + host);
    google.setQuery(query);
    urls.append(google);
    // Last resort: the conventional location on the site itself.
    QUrl direct = pageUrl;
    direct.setPath(QStringLiteral("/favicon.ico"));
    direct.setQuery(QString());
    direct.setFragment(QString());
    urls.append(direct);
    return urls;
}

void FaviconFetcher::fetch(const QUrl &pageUrl, FaviconResponse *response)
{
    const QString host = pageUrl.host().toLower();
    if (host.isEmpty()) {
        response->deliver({}, {});
        return;
    }
    if (m_memory.contains(host)) {
        response->deliver(m_memory.value(host), {});
        return;
    }
    if (m_failed.contains(host)) {
        response->deliver({}, {});
        return;
    }

    QImage cached(cachePathFor(host));
    if (!cached.isNull()) {
        m_memory.insert(host, cached);
        response->deliver(cached, {});
        return;
    }

    auto &waiting = m_pending[host];
    waiting.append(response);
    if (waiting.size() > 1)
        return; // a download for this host is already in flight
    tryNext(host, candidateUrls(pageUrl), response);
}

void FaviconFetcher::tryNext(const QString &host, QList<QUrl> candidates, QPointer<FaviconResponse> response)
{
    if (candidates.isEmpty()) {
        m_failed.insert(host);
        finish(host, {});
        return;
    }
    const QUrl url = candidates.takeFirst();
    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Silo/1.0"));
    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, host, candidates, response]() mutable {
        reply->deleteLater();
        QImage image;
        // Dev aid: SILO_DEBUG_FAVICON=1 logs every lookup.
        if (qEnvironmentVariableIsSet("SILO_DEBUG_FAVICON"))
            qDebug() << "favicon" << reply->url() << reply->error()
                     << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute);
        if (reply->error() == QNetworkReply::NoError) {
            QByteArray bytes = reply->readAll();
            QBuffer buffer(&bytes);
            buffer.open(QIODevice::ReadOnly);
            // ICO files may carry several sizes: keep the largest one.
            QImageReader reader(&buffer);
            do {
                const QImage candidate = reader.read();
                if (!candidate.isNull() && candidate.width() > image.width())
                    image = candidate;
            } while (reader.jumpToNextImage());
        }
        if (image.isNull() || image.width() < 8) {
            tryNext(host, candidates, response);
            return;
        }
        if (image.width() > kMaxStoredSize)
            image = image.scaled(kMaxStoredSize, kMaxStoredSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        image.save(cachePathFor(host), "PNG");
        m_memory.insert(host, image);
        finish(host, image);
    });
}

void FaviconFetcher::finish(const QString &host, const QImage &image)
{
    const auto waiting = m_pending.take(host);
    for (const auto &response : waiting) {
        if (response)
            response->deliver(image, {});
    }
}

// ---------------------------------------------------------------- FaviconResponse

QQuickTextureFactory *FaviconResponse::textureFactory() const
{
    return m_image.isNull() ? nullptr : QQuickTextureFactory::textureFactoryForImage(m_image);
}

void FaviconResponse::deliver(const QImage &image, const QSize &requestedSize)
{
    Q_UNUSED(requestedSize)
    // A missing favicon is not an error (QQuickImage would log it): deliver an
    // empty image and let the QML side fall back on implicitWidth == 0.
    m_image = image;
    emit finished();
}

// ---------------------------------------------------------------- FaviconProvider

QQuickImageResponse *FaviconProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    Q_UNUSED(requestedSize)
    auto *response = new FaviconResponse;
    QUrl pageUrl(QUrl::fromPercentEncoding(id.toUtf8()));
    if (pageUrl.scheme().isEmpty())
        pageUrl = QUrl(QStringLiteral("https://") + pageUrl.toString());
    // Network work must run on the fetcher's (main) thread.
    QMetaObject::invokeMethod(m_fetcher, [fetcher = m_fetcher, pageUrl, response] {
        fetcher->fetch(pageUrl, response);
    }, Qt::QueuedConnection);
    return response;
}
