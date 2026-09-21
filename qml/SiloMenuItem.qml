import QtQuick
import QtQuick.Controls

MenuItem {
    id: control
    property string iconName: ""
    property bool destructive: false
    property color iconColor: destructive ? Theme.destructive : Theme.text

    implicitHeight: 32
    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    leftPadding: 10
    rightPadding: checkable || subMenu ? 38 : 12
    hoverEnabled: true

    contentItem: Row {
        spacing: 10
        Icon {
            name: control.iconName
            size: 16
            visible: control.iconName.length > 0
            color: control.enabled ? control.iconColor : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            font: control.font
            color: control.enabled ? (control.destructive ? Theme.destructive : Theme.text) : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    indicator: Icon {
        visible: control.checkable && control.checked
        x: control.width - width - 12
        y: (control.height - height) / 2
        name: "fluent-checkmark-20-regular"
        size: 16
        color: Theme.accent
    }

    arrow: Icon {
        visible: !!control.subMenu
        x: control.width - width - 12
        y: (control.height - height) / 2
        name: "fluent-chevron-right-16-regular"
        size: 14
        color: Theme.textTertiary
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.highlighted || control.hovered ? Theme.hover : "transparent"
    }
}
