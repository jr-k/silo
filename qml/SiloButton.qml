import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool accent: false
    property bool destructive: false
    property string iconName: ""
    // Place the icon after the label (e.g. "Add +")
    property bool iconRight: false
    readonly property bool filled: accent || destructive

    implicitHeight: 32
    implicitWidth: Math.max(72, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: 14
    rightPadding: 14
    hoverEnabled: true
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily

    contentItem: Row {
        spacing: 8
        layoutDirection: control.iconRight ? Qt.RightToLeft : Qt.LeftToRight
        Icon {
            visible: control.iconName.length > 0
            name: control.iconName
            size: 16
            color: control.enabled
                   ? (control.filled ? Theme.textOnAccent : Theme.text)
                   : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            font: control.font
            color: control.enabled
                   ? (control.filled ? Theme.textOnAccent : Theme.text)
                   : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: Theme.radius
        color: {
            if (!control.enabled)
                return control.filled ? Theme.accentDisabled : Theme.controlBg
            if (control.destructive)
                return Qt.darker(Theme.destructive, control.down ? 1.25 : control.hovered ? 1.1 : 1)
            if (control.accent)
                return control.down ? Theme.accentPressed : control.hovered ? Theme.accentHover : Theme.accent
            return control.down ? Theme.controlPressed : control.hovered ? Theme.controlHover : Theme.controlBg
        }
        border.width: control.filled ? 0 : 1
        border.color: Theme.borderStrong

        Behavior on color { ColorAnimation { duration: Theme.animationFast } }
    }
}
