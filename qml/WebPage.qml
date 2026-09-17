import QtQuick
import QtWebEngine

// Browser page of a "web" tab.
WebEngineView {
    id: page
    property string tabUrl: ""
    // Restored tabs load lazily, the first time they are shown.
    property bool loaded: false

    readonly property string kind: "web"
    readonly property string displayUrl: String(url)

    function ensureLoaded() {
        if (loaded)
            return
        loaded = true
        url = tabUrl
    }
    function openExternally() { Qt.openUrlExternally(url) }

    onTabUrlChanged: if (loaded) url = tabUrl

    onNewWindowRequested: function(request) {
        // Popups (OAuth, target=_blank) stay in this tab for now.
        request.openIn(this)
    }
}
