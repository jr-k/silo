pragma Singleton
import QtQml
import QtWebEngine

// Shared, persistent browser profile for web tabs. The QML default profile is
// off-the-record, which would forget every login on restart.
//
// A new WebEngineProfile is off-the-record too, and `storageName` alone does
// not change that (cookies then silently stay in memory, the policy reads
// NoPersistentCookies): it has to be switched off explicitly, first.
WebEngineProfile {
    // Set only under SILO_DATA_DIR; empty keeps QtWebEngine's default location
    readonly property string overridePath: appStore.webStoragePath()

    offTheRecord: false
    storageName: "Silo"
    persistentStoragePath: overridePath !== "" ? overridePath + "/storage" : ""
    cachePath: overridePath !== "" ? overridePath + "/cache" : ""
    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    httpCacheType: WebEngineProfile.DiskHttpCache
    httpCacheMaximumSize: 256 * 1024 * 1024

    // Some sign-in flows (Google, Microsoft) refuse "unknown" browsers: present
    // the plain Chromium user agent, without the QtWebEngine token.
    Component.onCompleted: httpUserAgent = httpUserAgent.replace(/ QtWebEngine\/[\d.]+/, "")
}
