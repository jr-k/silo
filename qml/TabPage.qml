import QtQuick

// Content of one Live tab. Instantiates the right page for the item type and
// exposes a uniform surface (loading, url, reload…) to the toolbar and tab strip.
Item {
    id: page
    property string tabNodeId: ""
    property string tabUrl: ""
    // Fixed at creation: "web", "ssh" or "file"
    property string tabType: "web"
    property bool loaded: false

    readonly property var impl: loader.item
    readonly property string kind: tabType
    readonly property bool loading: impl ? !!impl.loading : false
    readonly property bool canGoBack: impl ? !!impl.canGoBack : false
    readonly property bool canGoForward: impl ? !!impl.canGoForward : false
    readonly property int loadProgress: impl ? impl.loadProgress : 0
    readonly property string displayUrl: impl ? impl.displayUrl : tabUrl
    // Favicon reported by the browser page (web only)
    readonly property string icon: impl && kind === "web" ? String(impl.icon) : ""

    function ensureLoaded() {
        if (loaded)
            return
        loaded = true
        if (impl)
            impl.ensureLoaded()
    }
    function reload() { if (impl) impl.reload() }
    function stop() { if (impl) impl.stop() }
    function goBack() { if (impl) impl.goBack() }
    function goForward() { if (impl) impl.goForward() }
    function openExternally() { if (impl) impl.openExternally() }
    function showInFolder() { if (impl && impl.showInFolder) impl.showInFolder() }
    // Web tabs only: fill the page's login form (see WebPage.fillCredentials)
    readonly property bool canFill: kind === "web" && loaded
    function fillCredentials(username, password, callback) {
        if (impl && impl.fillCredentials)
            impl.fillCredentials(username, password, callback)
        else if (callback)
            callback({})
    }
    // Web tabs only: keep the 2FA code of a filled login ready for the code step
    readonly property bool totpRefreshing: impl && impl.totpRefreshing ? true : false
    function armTotp(credentials) { if (impl && impl.armTotp) impl.armTotp(credentials) }
    function focusContent() { if (impl) impl.forceActiveFocus() }
    // Login captured in the page, waiting for the user to save or dismiss it
    readonly property var pendingCapture: impl && impl.pendingCapture ? impl.pendingCapture : null
    function clearCapture() { if (impl && impl.clearCapture) impl.clearCapture() }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: page.tabType === "ssh" ? terminalPage
                       : page.tabType === "file" ? filePage
                       : webPage
        onLoaded: {
            item.tabUrl = Qt.binding(function() { return page.tabUrl })
            if (item.hasOwnProperty("tabNodeId"))
                item.tabNodeId = Qt.binding(function() { return page.tabNodeId })
            if (page.loaded)
                item.ensureLoaded()
        }
    }

    Component { id: webPage; WebPage {} }
    Component { id: terminalPage; TerminalPage {} }
    Component { id: filePage; FilePage {} }
}
