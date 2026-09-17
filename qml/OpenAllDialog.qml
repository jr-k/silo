import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Asks whether "Open all" should include nested folders, then opens the tabs.
SiloDialog {
    id: dialog
    width: 440

    property string folderId: ""
    property string folderName: ""
    property var directItems: []
    property var nestedItems: []

    heading: "Open all items"
    subheading: "From \"" + folderName + "\""

    function openFor(id, name) {
        folderId = id
        folderName = name
        directItems = appStore.collectItems(id, false)
        nestedItems = appStore.collectItems(id, true)
        if (nestedItems.length === directItems.length) {
            // No nested items: nothing to ask, open straight away.
            dialog.openItems(directItems)
            return
        }
        open()
    }

    function openItems(items) {
        if (items.length === 0)
            return
        Session.setMode("working")
        for (var i = 0; i < items.length; ++i)
            tabsModel.openTab(items[i].id, items[i].name, items[i].url, i === 0)
        dialog.close()
    }

    contentItem: ColumnLayout {
        spacing: 10

        Text {
            Layout.fillWidth: true
            text: "This folder contains sub-folders. Which items do you want to open?"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: directChoice
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            radius: Theme.radius
            color: directHover.hovered ? Theme.controlHover : Theme.controlBg
            border.width: 1
            border.color: Theme.border
            enabled: dialog.directItems.length > 0
            opacity: enabled ? 1 : 0.5
            HoverHandler { id: directHover }
            TapHandler { onTapped: dialog.openItems(dialog.directItems) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12
                Icon { name: "fluent-folder-open-20-regular"; size: 20; color: Theme.folder }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: "This folder only"
                        elide: Text.ElideRight
                        color: Theme.text
                        font.pixelSize: Theme.fontSize
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: dialog.directItems.length + (dialog.directItems.length === 1 ? " item" : " items")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                Icon { name: "fluent-chevron-right-16-regular"; size: 14; color: Theme.textTertiary }
            }
        }

        Rectangle {
            id: nestedChoice
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            radius: Theme.radius
            color: nestedHover.hovered ? Theme.controlHover : Theme.controlBg
            border.width: 1
            border.color: Theme.border
            HoverHandler { id: nestedHover }
            TapHandler { onTapped: dialog.openItems(dialog.nestedItems) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12
                Icon { name: "fluent-tab-desktop-multiple-20-regular"; size: 20; color: Theme.accent }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: "Include sub-folders"
                        elide: Text.ElideRight
                        color: Theme.text
                        font.pixelSize: Theme.fontSize
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: dialog.nestedItems.length + (dialog.nestedItems.length === 1 ? " item" : " items")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                Icon { name: "fluent-chevron-right-16-regular"; size: 14; color: Theme.textTertiary }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Item { Layout.fillWidth: true }
            SiloButton {
                text: "Cancel"
                iconName: "fluent-dismiss-20-regular"
                onClicked: dialog.reject()
            }
        }
    }
}
