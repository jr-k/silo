import QtQuick
import QtQuick.Layouts

// Shown under the Live toolbar after a login form was submitted in the
// current tab: save the login into the Silo vault, or never ask for this site.
Rectangle {
    id: banner
    // TabPage of the current tab
    property var view: null
    readonly property var capture: view && view.pendingCapture ? view.pendingCapture : null
    readonly property bool active: capture !== null && !vault.locked

    implicitHeight: active ? 44 : 0
    visible: implicitHeight > 0
    clip: true
    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.22 : 0.10)
    Behavior on implicitHeight { NumberAnimation { duration: Theme.animationFast } }

    function save() {
        if (!capture)
            return
        var payload = { url: capture.url, username: capture.username, password: capture.password, source: "captured" }
        if (capture.existingId)
            payload.id = capture.existingId
        else
            payload.title = capture.host
        vault.save(payload)
        view.clearCapture()
    }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 8
        spacing: 10
        Icon { name: "fluent-key-20-regular"; size: 16; color: Theme.text }
        Text {
            Layout.fillWidth: true
            text: banner.capture
                  ? (banner.capture.existingId ? "Update the password for " : "Save the login for ")
                    + "<b>" + banner.capture.host + "</b>"
                    + (banner.capture.username ? " (" + banner.capture.username + ")" : "") + " in the Silo vault?"
                  : ""
            textFormat: Text.StyledText
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }
        SiloButton {
            text: banner.capture && banner.capture.existingId ? "Update" : "Save"
            iconName: "fluent-save-20-regular"
            accent: true
            implicitHeight: 28
            onClicked: banner.save()
        }
        SiloButton {
            text: "Never for this site"
            iconName: "fluent-prohibited-20-regular"
            implicitHeight: 28
            onClicked: { vault.setNeverSave(banner.capture.url, true); banner.view.clearCapture() }
        }
        IconButton {
            iconName: "fluent-dismiss-20-regular"
            iconSize: 14
            implicitWidth: 26
            implicitHeight: 26
            tooltip: "Not now"
            onClicked: banner.view.clearCapture()
        }
    }
}
