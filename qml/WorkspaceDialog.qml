import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

SiloDialog {
    id: dialog
    width: 520

    property bool editMode: false
    property string editingId: ""
    property bool confirmingDelete: false

    heading: editMode ? "Edit workspace" : "New workspace"
    subheading: editMode ? "Change its name, icon or color."
                         : "A separate home for your folders and saved items."

    signal exportRequested(string id)

    readonly property bool canSubmit: nameField.text.trim().length > 0 && iconPicker.valid
    readonly property bool canDelete: editMode && appStore.workspaceCount() > 1

    function openForCreate() {
        editMode = false
        editingId = ""
        nameField.text = ""
        iconPicker.reset("emoji", "📦", "#176E61")
        open()
    }

    function openForEdit(id) {
        var info = appStore.workspaceInfo(id)
        if (!info.id)
            return
        editMode = true
        editingId = id
        nameField.text = info.name
        iconPicker.reset(info.iconType, info.iconValue, info.color)
        open()
    }

    function submit() {
        if (!canSubmit)
            return
        if (editMode)
            appStore.updateWorkspace(editingId, nameField.text, String(iconPicker.badgeColor),
                                     iconPicker.iconType, iconPicker.resolvedValue)
        else
            appStore.addWorkspace(nameField.text, String(iconPicker.badgeColor),
                                  iconPicker.iconType, iconPicker.resolvedValue)
        dialog.accept()
    }

    function deleteWorkspace() {
        appStore.deleteWorkspace(editingId)
        dialog.accept()
    }

    onAboutToShow: confirmingDelete = false

    contentItem: ColumnLayout {
        spacing: 20

        // Preview + name
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Badge {
                size: 56
                color: iconPicker.badgeColor
                iconType: iconPicker.iconType
                iconValue: iconPicker.resolvedValue
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "NAME"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }
                SiloTextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: "Workspace name"
                    Keys.onReturnPressed: dialog.submit()
                    Keys.onEnterPressed: dialog.submit()
                }
            }
        }

        IconPicker {
            id: iconPicker
            Layout.fillWidth: true
            pickerTitle: "Choose a workspace icon"
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            SiloButton {
                visible: dialog.editMode && !dialog.confirmingDelete
                text: "Export…"
                iconName: "fluent-arrow-export-20-regular"
                onClicked: {
                    var id = dialog.editingId
                    dialog.reject()
                    dialog.exportRequested(id)
                }
            }
            // Delete (edit mode): two-step confirmation inline
            SiloButton {
                visible: dialog.canDelete && !dialog.confirmingDelete
                text: "Delete workspace"
                iconName: "fluent-delete-20-regular"
                onClicked: dialog.confirmingDelete = true
            }
            Text {
                visible: dialog.confirmingDelete
                text: "Delete this workspace and all its items?"
                color: Theme.destructive
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
            }
            SiloButton {
                visible: dialog.confirmingDelete
                text: "Delete"
                iconName: "fluent-delete-20-regular"
                destructive: true
                onClicked: dialog.deleteWorkspace()
            }

            Item { Layout.fillWidth: true }
            SiloButton {
                text: "Cancel"
                iconName: "fluent-dismiss-20-regular"
                onClicked: dialog.confirmingDelete ? dialog.confirmingDelete = false : dialog.reject()
            }
            SiloButton {
                visible: !dialog.confirmingDelete
                text: dialog.editMode ? "Save" : "Add Workspace"
                iconName: dialog.editMode ? "fluent-checkmark-20-regular" : "fluent-add-20-regular"
                iconRight: true
                accent: true
                enabled: dialog.canSubmit
                onClicked: dialog.submit()
            }
        }
    }
}
