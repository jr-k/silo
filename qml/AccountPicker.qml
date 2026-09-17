import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Vertical list of password-manager accounts (1Password signed-in accounts),
// one row per account: lock state, short name, full label and a check mark
// on the selected one. Keyboard: Up/Down move, Space/Enter select.
ColumnLayout {
    id: picker
    // [{id, label, shortLabel, locked, unlocked}]
    property var accounts: []
    property string current: ""
    signal picked(string id)

    spacing: 2

    function move(step) {
        if (accounts.length === 0)
            return
        var index = 0
        for (var i = 0; i < accounts.length; ++i)
            if (accounts[i].id === current) index = i
        index = Math.max(0, Math.min(accounts.length - 1, index + step))
        picked(accounts[index].id)
    }

    Repeater {
        model: picker.accounts
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool selected: picker.current === modelData.id
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Theme.radius
            color: selected ? (rowHover.hovered ? Theme.selectionHover : Theme.selection)
                            : (rowHover.hovered ? Theme.hover : "transparent")
            border.width: 1
            border.color: selected ? Theme.selectionBorder : "transparent"

            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: picker.picked(row.modelData.id) }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 10
                spacing: 10

                // Organisation tile: favicon of the e-mail domain in a rounded
                // square, initial letter when there is none. Lock state as a badge.
                Item {
                    id: tile
                    readonly property string initial: (row.modelData.shortLabel || "?").charAt(0).toUpperCase()
                    // Stable hue per account for the initial's background
                    readonly property real hue: {
                        var s = row.modelData.id || row.modelData.shortLabel || ""
                        var h = 0
                        for (var i = 0; i < s.length; ++i) h = (h * 31 + s.charCodeAt(i)) % 360
                        return h / 360
                    }
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: logo.ready ? Theme.surface : Qt.hsla(tile.hue, 0.45, Theme.dark ? 0.32 : 0.88, 1)
                        border.width: 1
                        border.color: logo.ready ? Theme.border : Qt.hsla(tile.hue, 0.4, Theme.dark ? 0.42 : 0.78, 1)
                        Text {
                            anchors.centerIn: parent
                            visible: !logo.ready
                            text: tile.initial
                            color: Qt.hsla(tile.hue, 0.5, Theme.dark ? 0.85 : 0.28, 1)
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        SiteIcon {
                            id: logo
                            anchors.fill: parent
                            anchors.margins: 4
                            size: 20
                            url: row.modelData.logoUrl || ""
                            fallbackName: ""
                        }
                    }
                    // Lock badge
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -4
                        anchors.bottomMargin: -4
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.menuBg
                        border.width: 1
                        border.color: Theme.border
                        Icon {
                            anchors.centerIn: parent
                            name: row.modelData.unlocked ? "fluent-lock-open-20-regular" : "fluent-lock-closed-20-regular"
                            size: 9
                            color: row.modelData.unlocked ? Theme.terminal : (row.modelData.locked ? Theme.destructive : Theme.textTertiary)
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.shortLabel
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0 && text !== row.modelData.shortLabel
                        text: row.modelData.label || ""
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeCaption
                        elide: Text.ElideRight
                    }
                }
                Icon {
                    name: "fluent-checkmark-20-filled"
                    size: 14
                    color: Theme.accent
                    opacity: row.selected ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }
            }
        }
    }
}
