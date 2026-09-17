pragma Singleton
import QtQml
import QtWebEngine

// Shared, persistent browser profile for web tabs. The QML default profile is
// off-the-record, which would forget every login on restart.
WebEngineProfile {
    storageName: "Silo"
    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    httpCacheType: WebEngineProfile.DiskHttpCache
    httpCacheMaximumSize: 256 * 1024 * 1024

    // Some sign-in flows (Google, Microsoft) refuse "unknown" browsers: present
    // the plain Chromium user agent, without the QtWebEngine token.
    Component.onCompleted: httpUserAgent = httpUserAgent.replace(/ QtWebEngine\/[\d.]+/, "")
}
