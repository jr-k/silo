import QtQuick
import QtQuick.Controls

// Explorer command bar button: icon + label, flat, rounded hover.
Button {
    id: control
    property string iconName: ""
    property color iconColor: Theme.text
    property bool accent: false

    implicitHeight: 36
    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    leftPadding: 12
    rightPadding: 14
    hoverEnabled: true
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily

    contentItem: Row {
        spacing: 8
        Icon {
            name: control.iconName
            size: 18
            color: control.enabled ? control.iconColor : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            font: control.font
            color: control.enabled ? Theme.text : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: Theme.radius
        color: control.down ? Theme.pressed : control.hovered ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animationFast } }
    }
}
