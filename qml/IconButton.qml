import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string iconName: ""
    property real iconSize: 16
    property color iconColor: Theme.text
    property string tooltip: ""

    implicitWidth: 32
    implicitHeight: 32
    padding: 0
    hoverEnabled: true

    ToolTip.visible: tooltip.length > 0 && hovered
    ToolTip.text: tooltip
    ToolTip.delay: 600

    contentItem: Item {
        Icon {
            anchors.centerIn: parent
            name: control.iconName
            size: control.iconSize
            color: control.enabled ? control.iconColor : Theme.textDisabled
        }
    }

    background: Rectangle {
        radius: Theme.radius
        color: control.down ? Theme.pressed : control.hovered ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animationFast } }
    }
}
