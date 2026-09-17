import QtQuick
import QtWebChannel
import QtWebEngine

// Editable text / code view (Ace in a WebEngineView). Every edit is written
// back to disk automatically: the page batches keystrokes for ~350 ms, sends
// the whole document over the web channel and the file is rewritten
// atomically. There is no save button on purpose.
Item {
    id: editor
    property string path: ""
    // highlight.js-style language id from FileInspector (mapped to an Ace mode)
    property string language: ""
    property bool readOnly: false

    readonly property bool loading: web.loading
    readonly property int loadProgress: web.loadProgress
    // "" | "editing" | "saving" | "saved" | "error" | "readonly"
    property string saveState: ""
    property string errorText: ""
    property bool documentLoaded: false
    property var document: ({})
    readonly property bool effectiveReadOnly: readOnly || !!document.truncated || !documentLoaded || !files.isWritable(path)
    readonly property string readOnlyReason: !!document.truncated ? "File too large to edit — read only"
                                           : documentLoaded && !readOnly && !files.isWritable(path) ? "File is read only" : ""

    signal saved()

    function reload() { loadDocument() }
    // Ask the page to push any pending edits now
    function flush() { if (pageReady) web.runJavaScript("flushChanges()") }

    property bool pageReady: false

    function loadDocument() {
        document = files.readDocument(path)
        documentLoaded = true
        if (document.error) {
            errorText = document.error
            saveState = "error"
        } else {
            saveState = effectiveReadOnly ? "readonly" : ""
        }
        pushContent()
    }
    function pushContent() {
        if (!pageReady || !documentLoaded)
            return
        web.runJavaScript("setContent(" + JSON.stringify(document.text || "") + ", "
                          + JSON.stringify(language || "") + ", " + (effectiveReadOnly ? "true" : "false") + ")")
    }
    function applyTheme() {
        web.runJavaScript("setTheme(" + (Theme.dark ? "true" : "false") + ", "
                          + JSON.stringify(String(Theme.surface)) + ", " + JSON.stringify(String(Theme.text)) + ", "
                          + JSON.stringify(String(Theme.textTertiary)) + ", " + JSON.stringify(String(Theme.divider)) + ")")
    }
    function write(text) {
        if (effectiveReadOnly)
            return
        saveState = "saving"
        var error = files.writeText(path, text, { latin1: !!document.latin1, bom: !!document.bom })
        if (error) {
            errorText = error
            saveState = "error"
        } else {
            document.text = text
            saveState = "saved"
            savedTimer.restart()
            editor.saved()
        }
    }

    onPathChanged: if (pageReady) loadDocument()
    onLanguageChanged: pushContent()
    onVisibleChanged: if (visible && pageReady) web.forceActiveFocus()

    QtObject {
        id: bridge
        WebChannel.id: "bridge"
        function ready() {
            editor.pageReady = true
            editor.applyTheme()
            editor.loadDocument()
            if (editor.visible)
                web.forceActiveFocus()
        }
        function notifyDirty() { if (editor.saveState !== "editing") editor.saveState = "editing" }
        function textEdited(text) { editor.write(text) }
    }

    WebChannel {
        id: channel
        registeredObjects: [bridge]
    }

    WebEngineView {
        id: web
        anchors.fill: parent
        webChannel: channel
        backgroundColor: Theme.surface
        settings.localContentCanAccessRemoteUrls: false
        settings.localContentCanAccessFileUrls: false
        settings.focusOnNavigationEnabled: true
        url: "qrc:/web/editor.html"
        onActiveFocusChanged: if (activeFocus && editor.pageReady) runJavaScript("focusEditor()")
    }

    Connections {
        target: Theme
        function onDarkChanged() { if (editor.pageReady) editor.applyTheme() }
    }

    Timer { id: savedTimer; interval: 1800; onTriggered: if (editor.saveState === "saved") editor.saveState = "" }

    // Unobtrusive status pill (bottom right)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: statusRow.implicitWidth + 20
        height: 24
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: editor.saveState === "error" ? Theme.destructive : Theme.border
        visible: editor.saveState !== ""
        opacity: visible ? 0.95 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animationNormal } }
        Row {
            id: statusRow
            anchors.centerIn: parent
            spacing: 6
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: editor.saveState === "saved" || editor.saveState === "readonly" || editor.saveState === "error"
                name: editor.saveState === "saved" ? "fluent-checkmark-20-regular"
                    : editor.saveState === "error" ? "fluent-dismiss-16-regular" : "fluent-lock-closed-20-regular"
                size: 13
                color: editor.saveState === "error" ? Theme.destructive : editor.saveState === "saved" ? Theme.accent : Theme.textSecondary
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: editor.saveState === "editing" ? "Editing…"
                    : editor.saveState === "saving" ? "Saving…"
                    : editor.saveState === "saved" ? "Saved"
                    : editor.saveState === "error" ? (editor.errorText || "Could not save")
                    : editor.readOnlyReason
                color: editor.saveState === "error" ? Theme.destructive : Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
            }
        }
    }

    Component.onDestruction: flush()
}
