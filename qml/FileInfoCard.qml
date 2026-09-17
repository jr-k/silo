import QtQuick

// Placeholder shown for files we cannot render inline (or that are missing).
Item {
    id: card
    property var info: ({})
    property string heading: ""
    property string message: ""
    property bool showOpen: true
    signal openRequested()
    signal revealRequested()

    Rectangle { anchors.fill: parent; color: Theme.surfaceAlt }

    Column {
        anchors.centerIn: parent
        spacing: 14
        width: Math.min(420, card.width - 40)

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: !!card.info.exists ? ItemTypes.glyph("file", card.info.path, "24") : "fluent-document-24-regular"
            size: 72
            color: !!card.info.exists ? Theme.file : Theme.borderStrong
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: card.heading
            color: Theme.text
            font.pixelSize: 16
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: card.message
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideMiddle
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !!card.info.exists && !card.info.isDir
            text: (card.info.mime || "unknown type") + "  ·  " + files.formatSize(card.info.size || 0)
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeCaption
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            SiloButton {
                visible: card.showOpen && !!card.info.exists
                text: "Open with default app"
                iconName: "fluent-open-20-regular"
                accent: true
                onClicked: card.openRequested()
            }
            SiloButton {
                visible: !!card.info.exists
                text: "Show in folder"
                iconName: "fluent-folder-open-20-filled"
                onClicked: card.revealRequested()
            }
        }
    }
}
