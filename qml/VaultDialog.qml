import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Logins stored in the Silo vault: search, add, edit, copy, delete.
SiloDialog {
    id: dialog
    width: 620
    heading: "Silo vault"
    subheading: vault.count === 1 ? "1 login" : vault.count + " logins"

    property string filter: ""
    // Login being edited ({} = new login); null = list mode
    property var editing: null
    property string editError: ""

    property int revision: 0
    Connections { target: vault; function onChanged() { dialog.revision++ } }

    readonly property var entries: {
        var all = dialog.revision >= 0 ? vault.entries() : []
        var needle = filter.trim().toLowerCase()
        if (!needle)
            return all
        return all.filter(function(e) {
            return (e.title + " " + e.username + " " + e.host).toLowerCase().indexOf(needle) >= 0
        })
    }

    function startEdit(entry) {
        editError = ""
        if (entry) {
            var full = vault.get(entry.id)
            editing = { id: full.id, title: full.title, url: full.url, username: full.username,
                        password: full.password, totp: full.totpSecret || "", notes: full.notes || "" }
        } else {
            editing = { id: "", title: "", url: "", username: "", password: "", totp: "", notes: "" }
        }
        Qt.callLater(function() { titleField.forceActiveFocus() })
    }
    function saveEdit() {
        if (!editing)
            return
        if (!urlField.text.trim() && !titleField.text.trim()) {
            editError = "Give the login a title or a URL."
            return
        }
        var payload = { title: titleField.text.trim(), url: urlField.text.trim(), username: userField.text.trim(),
                        password: passwordField.text, totp: totpField.text.trim(), notes: notesField.text, source: "manual" }
        if (editing.id)
            payload.id = editing.id
        if (!vault.save(payload)) {
            editError = vault.error || "Could not save."
            return
        }
        editing = null
    }

    onOpened: { filter = ""; editing = null }
    onClosed: editing = null

    contentItem: ColumnLayout {
        spacing: 12

        // ------------------------------------------------------------ list mode
        ColumnLayout {
            visible: dialog.editing === null
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SiloTextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search logins"
                    text: dialog.filter
                    onTextChanged: dialog.filter = text
                }
                SiloButton {
                    text: "Add login"
                    iconName: "fluent-add-20-regular"
                    onClicked: dialog.startEdit(null)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 360
                radius: Theme.radius
                color: Theme.controlBg
                border.width: 1
                border.color: Theme.border
                clip: true

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 4
                    model: dialog.entries
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 48
                        radius: Theme.radius
                        color: rowHover.hovered ? Theme.hover : "transparent"
                        HoverHandler { id: rowHover }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 10
                            SiteIcon { url: row.modelData.url; size: 20 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.title
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (row.modelData.username || "—") + (row.modelData.host ? "  ·  " + row.modelData.host : "")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeCaption
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                visible: !!row.modelData.origin && row.modelData.origin.indexOf("import:") === 0
                                text: row.modelData.origin.substring(7)
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                            }
                            Icon {
                                visible: !!row.modelData.hasTotp
                                name: "fluent-password-20-regular"
                                size: 14
                                color: Theme.textTertiary
                            }
                            IconButton {
                                iconName: "fluent-person-20-regular"
                                iconSize: 15
                                implicitWidth: 28
                                implicitHeight: 28
                                tooltip: "Copy username"
                                enabled: !!row.modelData.username
                                onClicked: files.copyToClipboard(row.modelData.username)
                            }
                            IconButton {
                                iconName: "fluent-copy-20-regular"
                                iconSize: 15
                                implicitWidth: 28
                                implicitHeight: 28
                                tooltip: "Copy password"
                                onClicked: files.copyToClipboard(vault.get(row.modelData.id).password)
                            }
                            IconButton {
                                iconName: "fluent-edit-20-regular"
                                iconSize: 15
                                implicitWidth: 28
                                implicitHeight: 28
                                tooltip: "Edit"
                                onClicked: dialog.startEdit(row.modelData)
                            }
                            IconButton {
                                iconName: "fluent-delete-20-regular"
                                iconSize: 15
                                implicitWidth: 28
                                implicitHeight: 28
                                iconColor: Theme.destructive
                                tooltip: "Delete"
                                onClicked: vault.remove(row.modelData.id)
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: vault.count === 0 ? "No logins yet. Import a CSV export from your password manager, or sign in to a site in Live mode and save it."
                                            : "No login matches “" + dialog.filter + "”."
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    width: parent.width - 60
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ------------------------------------------------------------ edit mode
        GridLayout {
            visible: dialog.editing !== null
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 10

            component FieldLabel: Text {
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignVCenter
            }

            FieldLabel { text: "Title" }
            SiloTextField { id: titleField; Layout.fillWidth: true; text: dialog.editing ? dialog.editing.title : ""; placeholderText: "GitHub" }
            FieldLabel { text: "URL" }
            SiloTextField { id: urlField; Layout.fillWidth: true; text: dialog.editing ? dialog.editing.url : ""; placeholderText: "https://github.com/login" }
            FieldLabel { text: "Username" }
            SiloTextField { id: userField; Layout.fillWidth: true; text: dialog.editing ? dialog.editing.username : "" }
            FieldLabel { text: "Password" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                SiloTextField {
                    id: passwordField
                    Layout.fillWidth: true
                    text: dialog.editing ? dialog.editing.password : ""
                    echoMode: revealButton.checked ? TextInput.Normal : TextInput.Password
                }
                IconButton {
                    id: revealButton
                    checkable: true
                    iconName: checked ? "fluent-eye-off-20-regular" : "fluent-eye-20-regular"
                    iconSize: 16
                    tooltip: checked ? "Hide" : "Show"
                }
            }
            FieldLabel { text: "2FA secret" }
            SiloTextField { id: totpField; Layout.fillWidth: true; text: dialog.editing ? dialog.editing.totp : ""; placeholderText: "Base32 secret or otpauth:// URI (optional)" }
            FieldLabel { text: "Notes" }
            SiloTextField { id: notesField; Layout.fillWidth: true; text: dialog.editing ? dialog.editing.notes : "" }
        }

        Text {
            visible: dialog.editError.length > 0 || vault.error.length > 0
            Layout.fillWidth: true
            text: dialog.editError || vault.error
            color: Theme.destructive
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Item { Layout.fillWidth: true }
            SiloButton {
                visible: dialog.editing !== null
                text: "Cancel"
                iconName: "fluent-dismiss-20-regular"
                onClicked: dialog.editing = null
            }
            SiloButton {
                visible: dialog.editing !== null
                text: "Save"
                iconName: "fluent-save-20-regular"
                accent: true
                onClicked: dialog.saveEdit()
            }
            SiloButton {
                visible: dialog.editing === null
                text: "Done"
                iconName: "fluent-checkmark-20-regular"
                accent: true
                onClicked: dialog.close()
            }
        }
    }
}
