#pragma once

#include <QHash>
#include <QImage>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>
#include <QSet>
#include <QUrl>

class FaviconResponse;

// Downloads and caches site favicons (main-thread QObject owning the network manager).
class FaviconFetcher final : public QObject
{
    Q_OBJECT
public:
    explicit FaviconFetcher(QObject *parent = nullptr);

    // Resolves the favicon for `pageUrl`; delivers via response->deliver().
    void fetch(const QUrl &pageUrl, FaviconResponse *response);

private:
    QString cachePathFor(const QString &host) const;
    QList<QUrl> candidateUrls(const QUrl &pageUrl) const;
    void tryNext(const QString &host, QList<QUrl> candidates, QPointer<FaviconResponse> response);
    void finish(const QString &host, const QImage &image);

    QNetworkAccessManager m_network;
    QString m_cacheDir;
    QHash<QString, QImage> m_memory;                       // host -> image
    QSet<QString> m_failed;                                // hosts with no favicon (this session)
    QHash<QString, QList<QPointer<FaviconResponse>>> m_pending; // host -> waiting responses
};

class FaviconResponse final : public QQuickImageResponse
{
    Q_OBJECT
public:
    QQuickTextureFactory *textureFactory() const override;
    QString errorString() const override { return m_error; }
    void deliver(const QImage &image, const QSize &requestedSize);

private:
    QImage m_image;
    QString m_error;
};

// image://siteicon/<percent-encoded page url> (WebEngine already owns "favicon")
class FaviconProvider final : public QQuickAsyncImageProvider
{
public:
    explicit FaviconProvider(FaviconFetcher *fetcher) : m_fetcher(fetcher) {}
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

private:
    FaviconFetcher *m_fetcher;
};
