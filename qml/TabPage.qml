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
