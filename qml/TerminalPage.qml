import QtQuick
import QtWebEngine
import QtWebChannel
import Silo.Backend

// Terminal page of an "ssh" tab: xterm.js in a WebEngineView, wired through
// QWebChannel to a TerminalSession that drives `ssh` in a pseudo-terminal.
Item {
    id: page
    property string tabUrl: ""
    property string tabNodeId: ""
    property bool loaded: false

    readonly property string kind: "ssh"
    readonly property var connection: ItemTypes.parseSsh(tabUrl)
    // Auth settings of the item (re-read when the store changes)
    readonly property var options: appStore.revision >= 0 ? (appStore.nodeInfo(tabNodeId).options || ({})) : ({})
    readonly property string displayUrl: connection.host.length > 0 ? ItemTypes.subtitle("ssh", tabUrl) : "Local shell"
    readonly property bool loading: view.loading
    readonly property bool canGoBack: false
    readonly property bool canGoForward: false
    readonly property int loadProgress: view.loadProgress
    readonly property string icon: ""
    readonly property bool running: session.running

    function ensureLoaded() {
        if (loaded)
            return
        loaded = true
        view.url = "qrc:/web/terminal.html"
    }
    // The toolbar's reload button reconnects.
    function reload() { session.restart() }
    function stop() { session.stop() }
    function goBack() {}
    function goForward() {}
    function openExternally() {
        Qt.openUrlExternally("ssh://" + (connection.user.length > 0 ? connection.user + "@" : "")
                             + connection.host + (connection.port !== 22 ? ":" + connection.port : ""))
    }

    onVisibleChanged: if (visible && loaded) view.forceActiveFocus()

    TerminalSession {
        id: session
        WebChannel.id: "session"
        host: page.connection.host
        user: page.connection.user
        port: page.connection.port
        authMethod: page.options.auth || ""
        keyPath: page.options.keyPath || ""
        password: page.options.auth === "password" && appStore.revision >= 0 ? appStore.secret(page.tabNodeId) : ""
        theme: ({
            background: String(Theme.terminalBg),
            foreground: String(Theme.terminalFg),
            cursor: String(Theme.accent),
            selection: String(Theme.selectionBorder),
            fontSize: 13
        })
    }

    WebChannel {
        id: channel
        registeredObjects: [session]
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        webChannel: channel
        backgroundColor: Theme.terminalBg
        settings.localContentCanAccessRemoteUrls: false
        settings.localContentCanAccessFileUrls: false
        settings.focusOnNavigationEnabled: true
        onLoadingChanged: function(info) {
            if (info.status === WebEngineView.LoadSucceededStatus && page.visible)
                view.forceActiveFocus()
        }
    }

    // Closed session overlay
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 34
        visible: page.loaded && !session.running && !view.loading
        color: Theme.surface
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.divider }
        Row {
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Session closed"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            SiloButton {
                anchors.verticalCenter: parent.verticalCenter
                text: "Reconnect"
                iconName: "fluent-arrow-clockwise-20-regular"
                height: 26
                onClicked: { session.restart(); view.forceActiveFocus() }
            }
        }
    }
}
