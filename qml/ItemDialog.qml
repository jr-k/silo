import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// Create / edit a leaf item. The type ("web", "ssh", "file") is chosen before
// opening (New item menu) and fixed afterwards; it drives which fields show up.
SiloDialog {
    id: dialog
    width: 520

    property string editingId: ""
    property bool editMode: false
    property string itemType: "web"

    readonly property bool isWeb: itemType === "web"
    readonly property bool isSsh: itemType === "ssh"
    readonly property bool isFile: itemType === "file"

    heading: (editMode ? "Edit " : "New ") + ItemTypes.noun(itemType)
    subheading: editMode ? "Update its name, target or icon."
                : isSsh ? "Open a terminal on a remote host from Live mode."
                : isFile ? "View a local file from Live mode."
                : "Save a web address in this folder."

    // SSH authentication: "" (ssh defaults), "password" or "key"
    property string sshAuth: ""
    readonly property string sshKeyPath: keyCustom ? keyPathField.text.trim() : keyChoice
    property bool keyCustom: false
    property string keyChoice: ""
    readonly property var sshKeys: files.sshKeyFiles()

    readonly property bool sshAuthValid: sshAuth === "password" ? passwordField.text.length > 0
                                       : sshAuth === "key" ? sshKeyPath.length > 0
                                       : true
    readonly property bool targetValid: isSsh ? hostField.text.trim().length > 0 && userField.text.trim().length > 0 && sshAuthValid
                                      : isFile ? pathField.text.trim().length > 0
                                      : true
    readonly property bool canSubmit: nameField.text.trim().length > 0 && targetValid && iconPicker.valid
    // Stored icon type: "" for the default icon (favicon / typed glyph).
    readonly property string storedIconType: iconPicker.isDefault ? "" : iconPicker.iconType

    // The value persisted in the node's url field
    function targetValue() {
        if (isSsh)
            return ItemTypes.buildSsh(userField.text, hostField.text, portField.text)
        if (isFile)
            return files.expand(pathField.text)
        return ItemTypes.normalizeWebUrl(urlField.text)
    }

    function resetFields() {
        nameField.text = ""
        urlField.text = ""
        hostField.text = ""
        userField.text = ""
        portField.text = ""
        pathField.text = ""
        passwordField.text = ""
        keyPathField.text = ""
        sshAuth = ""
        keyCustom = false
        keyChoice = sshKeys.length > 0 ? sshKeys[0] : ""
        previewFavicon.url = ""
    }

    function shortKeyName(path) {
        return String(path).replace(files.homePath(), "~")
    }

    function itemOptions() {
        if (!isSsh || sshAuth.length === 0)
            return ({})
        var options = { auth: sshAuth }
        if (sshAuth === "key")
            options.keyPath = sshKeyPath
        return options
    }

    function openForCreate(type) {
        editMode = false
        editingId = ""
        itemType = type || "web"
        resetFields()
        iconPicker.reset("default", "", "#2467A5")
        open()
    }

    function openForEdit(id) {
        var info = appStore.nodeInfo(id)
        if (!info.id)
            return
        editMode = true
        editingId = id
        itemType = info.type || "web"
        resetFields()
        nameField.text = info.name
        if (isSsh) {
            var c = ItemTypes.parseSsh(info.url)
            hostField.text = c.host
            userField.text = c.user
            portField.text = c.port !== 22 ? String(c.port) : ""
            var options = info.options || {}
            sshAuth = options.auth === "password" || options.auth === "key" ? options.auth : ""
            if (sshAuth === "password") {
                passwordField.text = appStore.secret(id)
            } else if (sshAuth === "key") {
                var key = options.keyPath || ""
                if (sshKeys.indexOf(key) >= 0) {
                    keyChoice = key
                } else {
                    keyCustom = true
                    keyPathField.text = key
                }
            }
        } else if (isFile) {
            pathField.text = info.url
        } else {
            urlField.text = info.url
        }
        iconPicker.reset(info.iconType, info.iconValue, info.color.length > 0 ? info.color : "#2467A5")
        open()
    }

    function submit() {
        if (!canSubmit)
            return
        var color = iconPicker.isDefault ? "" : String(iconPicker.badgeColor)
        var id = editingId
        if (editMode)
            appStore.updateItem(editingId, nameField.text, targetValue(),
                                storedIconType, iconPicker.resolvedValue, color, itemType, itemOptions())
        else
            id = appStore.addItem(nameField.text, targetValue(),
                                  storedIconType, iconPicker.resolvedValue, color, itemType, itemOptions())
        // Passwords live in secrets.json, never in the library itself
        appStore.setSecret(id, isSsh && sshAuth === "password" ? passwordField.text : "")
        dialog.accept()
    }

    // Suggest a name from the target when the user has not typed one yet
    function suggestName(value) {
        if (nameField.text.trim().length > 0 && !nameField.suggested)
            return
        nameField.suggested = true
        nameField.text = value
    }

    FileDialog {
        id: keyPicker
        title: "Choose a private key"
        fileMode: FileDialog.OpenFile
        currentFolder: files.toUrl(files.homePath() + "/.ssh")
        onAccepted: keyPathField.text = files.fromUrl(selectedFile)
    }

    FileDialog {
        id: filePicker
        title: "Choose a file"
        fileMode: FileDialog.OpenFile
        currentFolder: pathField.text.trim().length > 0 ? files.toUrl(files.inspect(pathField.text).dir || files.homePath())
                                                        : files.toUrl(files.homePath())
        onAccepted: {
            pathField.text = files.fromUrl(selectedFile)
            dialog.suggestName(files.inspect(pathField.text).name)
            if (nameField.text.trim().length === 0)
                nameField.forceActiveFocus()
        }
    }

    contentItem: ColumnLayout {
        spacing: 20

        // Preview + name
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Item {
                width: 56
                height: 56
                // Default web icon: the site's favicon, refreshed shortly after the URL stops changing
                SiteIcon {
                    id: previewFavicon
                    anchors.centerIn: parent
                    visible: iconPicker.isDefault && dialog.isWeb
                    size: 54
                    imagePadding: 3
                    fallbackName: "fluent-globe-24-filled"
                    fallbackColor: Theme.link
                }
                Timer {
                    id: previewDebounce
                    interval: 500
                    onTriggered: previewFavicon.url = /^(https?:\/\/)?[^\s.]+\.[^\s]+$/.test(urlField.text.trim())
                                                      ? ItemTypes.normalizeWebUrl(urlField.text) : ""
                }
                // Default ssh / file icon: typed glyph following the target
                ItemIcon {
                    anchors.centerIn: parent
                    visible: iconPicker.isDefault && !dialog.isWeb
                    size: 54
                    variant: "24"
                    glyphPadding: 4
                    type: dialog.itemType
                    url: dialog.isFile ? pathField.text : ""
                }
                Badge {
                    anchors.fill: parent
                    visible: !iconPicker.isDefault
                    size: 56
                    color: iconPicker.badgeColor
                    iconType: iconPicker.iconType
                    iconValue: iconPicker.resolvedValue
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "ITEM NAME"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }
                SiloTextField {
                    id: nameField
                    // True while the text is an automatic suggestion (replaced by the next one)
                    property bool suggested: false
                    Layout.fillWidth: true
                    placeholderText: "Item name"
                    onTextEdited: suggested = false
                    Keys.onReturnPressed: dialog.submit()
                    Keys.onEnterPressed: dialog.submit()
                }
            }
        }

        // ---------------------------------------------------------------- web
        ColumnLayout {
            Layout.fillWidth: true
            visible: dialog.isWeb
            spacing: 6
            Text {
                text: "URL"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }
            SiloTextField {
                id: urlField
                Layout.fillWidth: true
                placeholderText: "https://"
                onTextChanged: previewDebounce.restart()
                Keys.onReturnPressed: dialog.submit()
                Keys.onEnterPressed: dialog.submit()
            }
        }

        // ---------------------------------------------------------------- ssh
        RowLayout {
            Layout.fillWidth: true
            visible: dialog.isSsh
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "HOST"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }
                SiloTextField {
                    id: hostField
                    Layout.fillWidth: true
                    placeholderText: "server.example.com"
                    onTextEdited: dialog.suggestName(text.trim())
                    Keys.onReturnPressed: dialog.submit()
                    Keys.onEnterPressed: dialog.submit()
                }
            }
            ColumnLayout {
                Layout.preferredWidth: 140
                spacing: 6
                Text {
                    text: "USER"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }
                SiloTextField {
                    id: userField
                    Layout.fillWidth: true
                    placeholderText: "root"
                    Keys.onReturnPressed: dialog.submit()
                    Keys.onEnterPressed: dialog.submit()
                }
            }
            ColumnLayout {
                Layout.preferredWidth: 72
                spacing: 6
                Text {
                    text: "PORT"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }
                SiloTextField {
                    id: portField
                    Layout.fillWidth: true
                    placeholderText: "22"
                    validator: IntValidator { bottom: 1; top: 65535 }
                    Keys.onReturnPressed: dialog.submit()
                    Keys.onEnterPressed: dialog.submit()
                }
            }
        }

        // ---------------------------------------------------------------- ssh auth
        ColumnLayout {
            Layout.fillWidth: true
            visible: dialog.isSsh
            spacing: 8
            Text {
                text: "AUTHENTICATION"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }
            Row {
                spacing: 8
                SiloButton {
                    text: "SSH agent"
                    iconName: "fluent-key-20-regular"
                    accent: dialog.sshAuth === ""
                    onClicked: dialog.sshAuth = ""
                }
                SiloButton {
                    text: "Password"
                    iconName: "fluent-password-20-regular"
                    accent: dialog.sshAuth === "password"
                    onClicked: { dialog.sshAuth = "password"; passwordField.forceActiveFocus() }
                }
                SiloButton {
                    text: "Key file"
                    iconName: "fluent-document-key-20-regular"
                    accent: dialog.sshAuth === "key"
                    onClicked: dialog.sshAuth = "key"
                }
            }
            Text {
                visible: dialog.sshAuth === ""
                text: "Uses your ssh config, agent and default keys in ~/.ssh."
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeCaption
            }

            // Password
            SiloTextField {
                id: passwordField
                Layout.fillWidth: true
                visible: dialog.sshAuth === "password"
                placeholderText: "Password"
                echoMode: passwordVisible.revealed ? TextInput.Normal : TextInput.Password
                rightPadding: 36
                Keys.onReturnPressed: dialog.submit()
                Keys.onEnterPressed: dialog.submit()
                IconButton {
                    id: passwordVisible
                    property bool revealed: false
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    iconName: revealed ? "fluent-eye-off-20-regular" : "fluent-eye-20-regular"
                    iconSize: 16
                    tooltip: revealed ? "Hide password" : "Show password"
                    onClicked: revealed = !revealed
                }
            }
            Text {
                visible: dialog.sshAuth === "password"
                text: "Stored locally in secrets.json (readable by your user only)."
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeCaption
            }

            // Key file: pick one from ~/.ssh or type a path
            RowLayout {
                Layout.fillWidth: true
                visible: dialog.sshAuth === "key"
                spacing: 8

                // Dropdown of detected private keys
                SiloButton {
                    id: keyDropdown
                    Layout.fillWidth: true
                    visible: !dialog.keyCustom
                    leftPadding: 10
                    iconName: "fluent-document-key-20-regular"
                    text: dialog.keyChoice.length > 0 ? dialog.shortKeyName(dialog.keyChoice) : "Choose a key…"
                    onClicked: keyMenu.popup(keyDropdown, 0, keyDropdown.height + 4)
                    Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "fluent-chevron-down-20-regular"
                        size: 14
                        color: Theme.textSecondary
                    }
                    SiloMenu {
                        id: keyMenu
                        width: keyDropdown.width
                        Repeater {
                            model: dialog.sshKeys
                            SiloMenuItem {
                                required property string modelData
                                text: dialog.shortKeyName(modelData)
                                iconName: "fluent-document-key-20-regular"
                                checkable: true
                                checked: dialog.keyChoice === modelData
                                onTriggered: { dialog.keyChoice = modelData; dialog.keyCustom = false }
                            }
                        }
                        MenuSeparator {
                            visible: dialog.sshKeys.length > 0
                            height: visible ? implicitHeight : 0
                            padding: 4
                            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
                        }
                        SiloMenuItem {
                            text: "Custom path…"
                            iconName: "fluent-folder-open-20-filled"
                            onTriggered: { dialog.keyCustom = true; keyPathField.forceActiveFocus() }
                        }
                    }
                }

                SiloTextField {
                    id: keyPathField
                    Layout.fillWidth: true
                    visible: dialog.keyCustom
                    placeholderText: "~/.ssh/id_ed25519"
                    Keys.onReturnPressed: dialog.submit()
                    Keys.onEnterPressed: dialog.submit()
                }
                SiloButton {
                    visible: dialog.keyCustom
                    text: "Browse…"
                    iconName: "fluent-folder-open-20-filled"
                    onClicked: keyPicker.open()
                }
                IconButton {
                    visible: dialog.keyCustom && dialog.sshKeys.length > 0
                    iconName: "fluent-dismiss-20-regular"
                    iconSize: 16
                    tooltip: "Back to detected keys"
                    onClicked: dialog.keyCustom = false
                }
            }
            Text {
                visible: dialog.sshAuth === "key" && dialog.keyCustom && keyPathField.text.trim().length > 0
                         && !files.inspect(keyPathField.text).exists
                text: "Key file not found"
                color: Theme.destructive
                font.pixelSize: Theme.fontSizeCaption
            }
        }

        // ---------------------------------------------------------------- file
        ColumnLayout {
            Layout.fillWidth: true
            visible: dialog.isFile
            spacing: 6
            Text {
                text: "FILE PATH"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SiloTextField {
                    id: pathField
                    Layout.fillWidth: true
                    placeholderText: "~/Documents/report.pdf"
                    onTextEdited: {
                        var name = files.inspect(text).name
                        if (name.length > 0)
                            dialog.suggestName(name)
                    }
                    Keys.onReturnPressed: dialog.submit()
                    Keys.onEnterPressed: dialog.submit()
                }
                SiloButton {
                    text: "Browse…"
                    iconName: "fluent-folder-open-20-filled"
                    onClicked: filePicker.open()
                }
            }
            Text {
                readonly property var info: dialog.isFile && pathField.text.trim().length > 0 ? files.inspect(pathField.text) : ({})
                visible: dialog.isFile && pathField.text.trim().length > 0
                text: !info.exists ? "File not found"
                      : info.isDir ? "This is a folder"
                      : (info.mime || info.kind) + "  ·  " + files.formatSize(info.size || 0)
                color: info.exists && !info.isDir ? Theme.textTertiary : Theme.destructive
                font.pixelSize: Theme.fontSizeCaption
            }
        }

        IconPicker {
            id: iconPicker
            Layout.fillWidth: true
            allowDefault: true
            defaultLabel: "Default"
            defaultIconName: ItemTypes.glyph(dialog.itemType, dialog.isFile ? pathField.text : "", "20")
            pickerTitle: "Choose an item icon"
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
                text: dialog.editMode ? "Save" : "Add"
                iconName: dialog.editMode ? "fluent-checkmark-20-regular" : "fluent-add-20-regular"
                iconRight: true
                accent: true
                enabled: dialog.canSubmit
                onClicked: dialog.submit()
            }
        }
    }
}
