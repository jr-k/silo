import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// App settings. One "General" section for now: appearance and storage.
SiloDialog {
    id: dialog
    width: 480
    heading: "Settings"
    initialFocusItem: doneButton

    readonly property var appearanceOptions: [
        { key: "light", label: "Light", icon: "fluent-weather-sunny-20-regular" },
        { key: "dark", label: "Dark", icon: "fluent-weather-moon-20-regular" },
        { key: "system", label: "System", icon: "fluent-desktop-20-regular" }
    ]

    // Section title
    component SectionLabel: Text {
        Layout.fillWidth: true
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSizeCaption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
    }

    // Label + description on the left, control on the right
    component SettingRow: RowLayout {
        id: row
        property string title: ""
        property string description: ""
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: row.title
                color: Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: row.description.length > 0
                text: row.description
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }
        Item {
            id: slot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }

    contentItem: ColumnLayout {
        spacing: 14

        SectionLabel { text: "GENERAL" }

        // Appearance: segmented Light / Dark / System
        SettingRow {
            title: "Appearance"
            description: "Light or dark, or follow the system setting."
            Rectangle {
                width: appearanceSegments.implicitWidth + 4
                height: 32
                radius: Theme.radius
                color: Theme.controlBg
                border.width: 1
                border.color: Theme.border
                Row {
                    id: appearanceSegments
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: dialog.appearanceOptions
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: themeController.mode === modelData.key
                            width: segmentContent.implicitWidth + 20
                            height: 28
                            radius: Theme.radiusSmall
                            color: active ? Theme.accent : segmentHover.hovered ? Theme.hover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animationFast } }
                            Row {
                                id: segmentContent
                                anchors.centerIn: parent
                                spacing: 6
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.icon
                                    size: 15
                                    color: active ? Theme.textOnAccent : Theme.text
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: active ? Theme.textOnAccent : Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: active ? Font.DemiBold : Font.Normal
                                }
                            }
                            HoverHandler { id: segmentHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: themeController.mode = modelData.key }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

        // Sidebar visibility (also Ctrl/Cmd+B)
        SettingRow {
            title: "Sidebar"
            description: "Show the workspace tree. Toggle anytime with " + (Qt.platform.os === "osx" ? "⌘B" : "Ctrl+B") + "."
            SiloButton {
                text: Session.sidebarVisible ? "Visible" : "Hidden"
                iconName: Session.sidebarVisible ? "fluent-eye-20-regular" : "fluent-eye-off-20-regular"
                onClicked: Session.toggleSidebar()
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

        // Storage location
        SettingRow {
            title: "Storage"
            description: appStore.dataPath()
            SiloButton {
                text: "Show in folder"
                iconName: "fluent-folder-open-20-regular"
                onClicked: Qt.openUrlExternally(files.toUrl(appStore.dataPath()))
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Item { Layout.fillWidth: true }
            SiloButton {
                id: doneButton
                text: "Done"
                iconName: "fluent-checkmark-20-regular"
                accent: true
                onClicked: dialog.close()
            }
        }
    }
}
