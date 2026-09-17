import QtQuick
import QtQuick.Controls

Menu {
    id: menu
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

    delegate: SiloMenuItem {}
}
