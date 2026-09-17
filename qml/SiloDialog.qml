import QtQuick
import QtQuick.Controls

Dialog {
    id: dialog
    property string heading: ""
    property string subheading: ""
    // Item focused when the dialog opens. Defaults to the first visible text input;
    // dialogs without inputs can point it at their primary button.
    property Item initialFocusItem: null
    property bool selectTextOnFocus: true

    function firstInput(item) {
        if (!item || !item.visible || !item.enabled)
            return null
        if (item instanceof TextInput || item instanceof TextEdit)
            return item.readOnly ? null : item
        for (var i = 0; i < item.children.length; ++i) {
            var found = firstInput(item.children[i])
            if (found)
                return found
        }
        return null
    }

    function focusInitial() {
        if (!opened)
            return
        var target = initialFocusItem || firstInput(contentItem)
        if (!target)
            return
        target.forceActiveFocus()
        if (selectTextOnFocus && typeof target.selectAll === "function")
            target.selectAll()
    }

    onOpened: focusInitial()
    // A closing menu can hand focus back to the page right after we opened: the
    // dialog is modal, so reclaim it. Focus inside another popup (nested dialog)
    // or a deactivated window (null) is left alone.
    onActiveFocusChanged: if (opened && !activeFocus) Qt.callLater(reclaimFocus)

    function reclaimFocus() {
        if (!opened || activeFocus)
            return
        var item = contentItem.Window.activeFocusItem
        if (!item)
            return
        for (var p = item; p; p = p.parent) {
            if (p === Overlay.overlay)
                return
        }
        focusInitial()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    padding: 24
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle {
        color: Theme.overlay
    }

    background: Rectangle {
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Theme.borderStrong
    }

    header: Item {
        implicitHeight: dialog.heading.length > 0 ? 24 + headerColumn.implicitHeight : 0
        Column {
            id: headerColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            anchors.bottomMargin: 0
            spacing: 4
            Text {
                text: dialog.heading
                color: Theme.text
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Font.DemiBold
                font.family: Theme.fontFamily
            }
            Text {
                visible: dialog.subheading.length > 0
                text: dialog.subheading
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }
    }
}
