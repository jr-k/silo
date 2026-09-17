import QtQuick
import QtQuick.Controls

TextField {
    id: control
    implicitHeight: 32
    leftPadding: 10
    rightPadding: 10
    selectByMouse: true
    color: Theme.text
    placeholderTextColor: Theme.textTertiary
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    selectionColor: Theme.accent
    selectedTextColor: Theme.textOnAccent
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: Theme.radius
        color: control.activeFocus ? Theme.fieldBgFocused : Theme.fieldBg
        border.width: 1
        border.color: control.activeFocus ? Theme.borderStrong : Theme.border

        // Windows 11 focus underline
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            height: control.activeFocus ? 2 : 1
            radius: 1
            color: control.activeFocus ? Theme.accent : Theme.fieldUnderline
        }
    }
}
