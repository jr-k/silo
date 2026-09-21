import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Applies one icon (emoji, image or default) and background to several leaf
// items at once. Folders in the selection are ignored.
SiloDialog {
    id: dialog
    width: 520

    // Leaf items only (folders are filtered out on open)
    property var targetIds: []
    // Up to five nodes shown in the preview strip
    property var previewItems: []

    readonly property int count: targetIds.length
    readonly property bool canSubmit: count > 0 && iconPicker.valid

    initialFocusItem: applyButton

    heading: "Edit icon of " + count + " item" + (count > 1 ? "s" : "")
    subheading: "The same icon and background will be applied to every selected item."

    function openFor(ids) {
        var items = []
        var previews = []
        for (var i = 0; i < ids.length; ++i) {
            var info = appStore.nodeInfo(ids[i])
            if (!info.id || info.folder)
                continue
            items.push(info.id)
            if (previews.length < 5)
                previews.push(info)
        }
        if (items.length === 0)
            return
        targetIds = items
        previewItems = previews
        // Start from the first item's icon so a shared icon can be tweaked instead of rebuilt
        var first = previews[0]
        iconPicker.reset(first.iconType, first.iconValue, first.color.length > 0 ? first.color : "#2467A5")
        open()
    }

    function submit() {
        if (!canSubmit)
            return
        var type = iconPicker.isDefault ? "" : iconPicker.iconType
        var color = iconPicker.isDefault ? "" : String(iconPicker.badgeColor)
        appStore.setItemsIcon(targetIds, type, iconPicker.resolvedValue, color)
        dialog.accept()
    }

    contentItem: ColumnLayout {
        spacing: 20

        // Preview strip: how the first items will look
        Row {
            spacing: 10
            Repeater {
                model: dialog.previewItems
                delegate: Item {
                    id: preview
                    required property var modelData
                    width: 56
                    height: 56
                    ItemIcon {
                        anchors.centerIn: parent
                        visible: iconPicker.isDefault
                        size: 54
                        variant: "24"
                        imagePadding: 3
                        glyphPadding: 4
                        type: preview.modelData.type
                        url: preview.modelData.url
                    }
                    Badge {
                        anchors.fill: parent
                        visible: !iconPicker.isDefault
                        size: 56
                        color: iconPicker.badgeColor
                        iconType: iconPicker.iconType
                        iconValue: iconPicker.resolvedValue
                    }
                }
            }
            Text {
                visible: dialog.count > dialog.previewItems.length
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (dialog.count - dialog.previewItems.length)
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
            }
        }

        IconPicker {
            id: iconPicker
            Layout.fillWidth: true
            allowDefault: true
            defaultLabel: "Default"
            pickerTitle: "Choose an icon"
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            Item { Layout.fillWidth: true }
            SiloButton {
                text: "Cancel"
                iconName: "fluent-dismiss-20-regular"
                onClicked: dialog.reject()
            }
            SiloButton {
                id: applyButton
                text: "Apply to " + dialog.count + " item" + (dialog.count > 1 ? "s" : "")
                iconName: "fluent-checkmark-20-regular"
                iconRight: true
                accent: true
                enabled: dialog.canSubmit
                onClicked: dialog.submit()
            }
        }
    }
}
