import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Confirmation before deleting folders / items (⏎ confirms, Esc cancels).
SiloDialog {
    id: dialog
    width: 440

    property var ids: []
    property int folderCount: 0
    property int itemCount: 0
    property int nestedCount: 0
    property string firstName: ""

    signal confirmed(var ids)

    readonly property int total: ids.length
    heading: total === 1 ? "Delete \u201C" + firstName + "\u201D?" : "Delete " + total + " items?"
    subheading: "This can't be undone."

    function openFor(nodeIds) {
        var list = []
        var folders = 0, items = 0, nested = 0, first = ""
        for (var i = 0; i < nodeIds.length; ++i) {
            var info = appStore.nodeInfo(nodeIds[i])
            if (!info.id)
                continue
            list.push(info.id)
            if (first.length === 0)
                first = info.name
            if (info.folder) {
                folders++
                nested += appStore.collectItems(info.id, true).length
            } else {
                items++
            }
        }
        if (list.length === 0)
            return
        ids = list
        folderCount = folders
        itemCount = items
        nestedCount = nested
        firstName = first
        open()
    }

    function confirm() {
        var list = ids
        dialog.close()
        confirmed(list)
    }

    initialFocusItem: deleteButton

    contentItem: ColumnLayout {
        spacing: 16
        Keys.onReturnPressed: dialog.confirm()
        Keys.onEnterPressed: dialog.confirm()

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: Qt.rgba(Theme.destructive.r, Theme.destructive.g, Theme.destructive.b, 0.14)
                Icon {
                    anchors.centerIn: parent
                    name: "fluent-delete-20-regular"
                    size: 20
                    color: Theme.destructive
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize
                text: {
                    var parts = []
                    if (dialog.folderCount > 0)
                        parts.push(dialog.folderCount + (dialog.folderCount === 1 ? " folder" : " folders"))
                    if (dialog.itemCount > 0)
                        parts.push(dialog.itemCount + (dialog.itemCount === 1 ? " item" : " items"))
                    var s = parts.join(" and ") + " will be removed from this workspace."
                    if (dialog.nestedCount > 0)
                        s += " The " + (dialog.folderCount === 1 ? "folder contains " : "folders contain ")
                             + dialog.nestedCount + (dialog.nestedCount === 1 ? " item" : " items")
                             + " that will be deleted too."
                    return s
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Item { Layout.fillWidth: true }
            SiloButton {
                text: "Cancel"
                iconName: "fluent-dismiss-20-regular"
                onClicked: dialog.reject()
            }
            SiloButton {
                id: deleteButton
                text: "Delete"
                iconName: "fluent-delete-20-regular"
                destructive: true
                onClicked: dialog.confirm()
            }
        }
    }
}
