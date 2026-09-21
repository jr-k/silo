import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// Icon (emoji / image, optionally "default") + background color picker,
// shared by the workspace and item dialogs.
ColumnLayout {
    id: picker
    spacing: 20

    // "default" (only when allowDefault), "emoji" or "image"
    property string iconType: "emoji"
    property string iconValue: "📦"
    property string imageSource: ""
    property color badgeColor: "#176E61"
    property bool allowDefault: false
    property string defaultLabel: "Default"
    property string defaultIconName: "fluent-globe-20-regular"
    property string pickerTitle: "Choose an icon"

    readonly property var paletteColors: ["#176E61", "#2467A5", "#7251A6", "#B33F62",
                                          "#CE6429", "#B08A20", "#56606B", "#272A2E"]
    readonly property var emojis: ["📦", "🪴", "🧭", "🎨", "🚀", "💼", "🏠", "✨"]

    // Persisted when the badge has no background (fully transparent)
    readonly property string noBackground: "#00000000"
    readonly property bool isTransparent: badgeColor.a === 0

    readonly property bool isDefault: iconType === "default"
    readonly property bool valid: isDefault
                                  || (iconType === "emoji" ? iconValue.length > 0 : imageSource.length > 0)
    // Value to persist for the current type.
    readonly property string resolvedValue: iconType === "image" ? imageSource : iconType === "emoji" ? iconValue : ""

    function reset(type, value, color) {
        iconType = type && type.length > 0 ? type : (allowDefault ? "default" : "emoji")
        if (iconType === "image") {
            imageSource = value
            iconValue = "📦"
        } else {
            iconValue = value && value.length > 0 ? value : "📦"
            imageSource = ""
        }
        badgeColor = color && color.length > 0 ? color : "#176E61"
        customEmoji.text = emojis.indexOf(iconValue) >= 0 || iconType !== "emoji" ? "" : iconValue
    }

    // Icon
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
            text: "ICON"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
        }

        Row {
            spacing: 6
            SiloButton {
                visible: picker.allowDefault
                text: picker.defaultLabel
                iconName: picker.defaultIconName
                accent: picker.iconType === "default"
                onClicked: picker.iconType = "default"
            }
            SiloButton {
                text: "Emoji"
                iconName: "fluent-emoji-20-regular"
                accent: picker.iconType === "emoji"
                onClicked: picker.iconType = "emoji"
            }
            SiloButton {
                text: "Icon"
                iconName: "fluent-image-add-20-regular"
                accent: picker.iconType === "image"
                onClicked: picker.iconType = "image"
            }
        }

        Row {
            visible: picker.iconType === "emoji"
            spacing: 6
            Repeater {
                model: picker.emojis
                delegate: Rectangle {
                    id: emojiCell
                    required property string modelData
                    readonly property bool selected: picker.iconValue === modelData
                    width: 36
                    height: 36
                    radius: Theme.radius
                    color: selected ? Theme.accentSoft : emojiHover.hovered ? Theme.controlHover : Theme.controlBg
                    border.width: 1
                    border.color: selected ? Theme.selectionBorder : Theme.border
                    Text {
                        anchors.centerIn: parent
                        text: emojiCell.modelData
                        font.pixelSize: 19
                    }
                    HoverHandler { id: emojiHover }
                    TapHandler {
                        onTapped: {
                            picker.iconValue = emojiCell.modelData
                            customEmoji.text = ""
                        }
                    }
                }
            }
            SiloTextField {
                id: customEmoji
                width: 64
                height: 36
                horizontalAlignment: TextInput.AlignHCenter
                placeholderText: "Other"
                maximumLength: 4
                onTextEdited: if (text.length > 0) picker.iconValue = text
            }
        }

        Row {
            visible: picker.iconType === "image"
            spacing: 10
            SiloButton {
                text: picker.imageSource.length > 0 ? "Change icon…" : "Upload icon…"
                iconName: "fluent-image-add-20-regular"
                onClicked: imagePicker.open()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: picker.imageSource.length > 0
                      ? decodeURIComponent(String(picker.imageSource).split("/").pop())
                      : "PNG, SVG, JPG or WebP"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideMiddle
                width: 260
            }
        }

        Text {
            visible: picker.isDefault
            text: "Uses the standard icon."
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // Background color
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: !picker.isDefault

        Text {
            text: "BACKGROUND"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
        }

        Row {
            spacing: 8
            // No background: white disc crossed by a red diagonal
            Rectangle {
                id: noneSwatch
                readonly property bool selected: picker.isTransparent
                width: 28
                height: 28
                radius: 14
                color: "#FFFFFF"
                border.width: selected ? 3 : 0
                border.color: Theme.surface

                Rectangle {
                    anchors.centerIn: parent
                    width: 18
                    height: 2
                    radius: 1
                    rotation: -45
                    color: "#E5484D"
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: width / 2
                    color: "transparent"
                    border.width: noneSwatch.selected ? 2 : 1
                    border.color: noneSwatch.selected ? Theme.accent : Theme.borderStrong
                }
                HoverHandler { id: noneHover }
                ToolTip.visible: noneHover.hovered
                ToolTip.text: "No background"
                ToolTip.delay: 500
                TapHandler { onTapped: picker.badgeColor = picker.noBackground }
            }
            Repeater {
                model: picker.paletteColors
                delegate: Rectangle {
                    id: swatch
                    required property string modelData
                    readonly property bool selected: Qt.colorEqual(picker.badgeColor, modelData)
                    width: 28
                    height: 28
                    radius: 14
                    color: modelData
                    border.width: selected ? 3 : 0
                    border.color: Theme.surface

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: width / 2
                        color: "transparent"
                        border.width: swatch.selected ? 2 : 1
                        border.color: swatch.selected ? Theme.accent : Theme.borderStrong
                    }
                    TapHandler { onTapped: picker.badgeColor = swatch.modelData }
                }
            }
            IconButton {
                width: 28
                height: 28
                iconName: "fluent-color-20-regular"
                iconSize: 18
                tooltip: "Custom color"
                onClicked: colorPicker.open()
            }
        }
    }

    FileDialog {
        id: imagePicker
        title: picker.pickerTitle
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg *.webp)"]
        onAccepted: picker.imageSource = String(selectedFile)
    }

    ColorDialog {
        id: colorPicker
        title: "Choose a color"
        selectedColor: picker.badgeColor
        onAccepted: picker.badgeColor = selectedColor
    }
}
