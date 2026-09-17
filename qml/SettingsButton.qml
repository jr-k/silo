import QtQuick

// Cog button in the sidebar footer, opening the app settings dialog.
IconButton {
    id: control
    implicitWidth: 36
    implicitHeight: 36
    iconName: "fluent-settings-20-regular"
    iconSize: 18
    iconColor: Theme.textSecondary
    tooltip: "Settings"
    onClicked: settingsDialog.open()

    background: Rectangle {
        radius: height / 2
        color: control.down ? Theme.pressed : control.hovered ? Theme.hover : Theme.controlBg
        border.width: 1
        border.color: Theme.borderStrong
        Behavior on color { ColorAnimation { duration: Theme.animationFast } }
    }

    SettingsDialog { id: settingsDialog }
}
