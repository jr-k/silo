import QtQuick
import QtQuick.Controls

Menu {
    id: menu
    property string iconName: ""
    property color iconColor: Theme.text
    padding: 4
    // Grow with the widest item (checkable items reserve room for the checkmark),
    // never narrower than the 200px background.
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentWidth + leftPadding + rightPadding)
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily

    background: Rectangle {
        implicitWidth: 200
        radius: Theme.radiusLarge
        color: Theme.menuBg
        border.width: 1
        border.color: Theme.border
    }

    delegate: SiloMenuItem {
        iconName: subMenu && subMenu.hasOwnProperty("iconName") ? subMenu.iconName : ""
        iconColor: subMenu && subMenu.hasOwnProperty("iconColor") ? subMenu.iconColor : Theme.text
    }
}
