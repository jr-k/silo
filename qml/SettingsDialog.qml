import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// App settings: "General" (appearance, sidebar, storage), "Passwords"
// (Silo vault, CSV import, master password, password manager connectors)
// and "About" (version, engines, links).
SiloDialog {
    id: dialog
    // Fixed, near full-window size: sections live in a left rail, the body
    // scrolls on the right, so switching section never resizes the dialog.
    width: Math.min(820, parent.width - 48)
    height: Math.max(480, parent.height - 48)
    padding: 0
    initialFocusItem: doneButton
    // "general" | "passwords" | "about"
    property string section: "general"
    onOpened: passwords.refresh()
    onSectionChanged: body.contentY = 0

    function sectionLabel(key) {
        for (var i = 0; i < sections.length; ++i)
            if (sections[i].key === key)
                return sections[i].label
        return ""
    }

    readonly property var sections: [
        { key: "general", label: "General", icon: "fluent-settings-20-regular" },
        { key: "passwords", label: "Passwords", icon: "fluent-key-20-regular" },
        { key: "about", label: "About", icon: "fluent-info-20-regular" }
    ]
    readonly property var appearanceOptions: [
        { key: "light", label: "Light", icon: "fluent-weather-sunny-20-regular" },
        { key: "dark", label: "Dark", icon: "fluent-weather-moon-20-regular" },
        { key: "system", label: "System", icon: "fluent-desktop-20-regular" }
    ]

    // ---------------------------------------------------------------- helpers
    function keyStorageText() {
        if (vault.keyStorage === "master")
            return "Encrypted with your master password" + (vault.locked ? " · locked" : "")
        if (vault.keyStorage === "keychain")
            return "Encrypted; key stored in the " + (Qt.platform.os === "osx" ? "macOS Keychain" : Qt.platform.os === "windows" ? "Windows Credential Manager" : "system keyring")
        if (vault.keyStorage === "file")
            return "Encrypted; key stored next to the vault (set a master password for stronger protection)"
        return vault.error || "Unavailable"
    }
    function versionText() {
        return "Version " + appInfo.version + (appInfo.commit ? " (" + appInfo.commit + ")" : "")
    }
    // Plain-text summary for bug reports.
    function aboutSummary() {
        return "Silo " + appInfo.version + (appInfo.commit ? " (" + appInfo.commit + ")" : "")
             + "\nQt " + appInfo.qtVersion + " · Chromium " + appInfo.chromiumVersion
             + "\n" + appInfo.os + " · " + appInfo.arch
    }
    function connectorStatus(c) {
        if (c.installing)
            return c.installProgress > 0 ? "Downloading… " + c.installProgress + "%" : "Downloading…"
        if (c.installError)
            return c.installError
        if (!c.installed)
            return "Not installed"
        var where = c.managed ? "installed by Silo" : c.cliPath
        var version = c.version ? " " + c.version : ""
        if (!c.enabled)
            return "Disabled · `" + c.binary + "`" + version
        switch (c.auth) {
        case "signed-out": return "Signed out · `" + c.binary + "`" + version + ", " + where
        case "locked": return "Locked" + (c.account ? " · " + c.account : "")
        case "unlocked": return "Unlocked" + (c.account ? " · " + c.account : "")
        case "syncing": return "Syncing…" + (c.account ? " · " + c.account : "")
        case "ready": return "Ready" + (c.account ? " · " + c.account : "") + " · fill logins with the key button on a login page"
        default: return "Checking…"
        }
    }

    // ---------------------------------------------------------------- CSV import
    property var importInfo: ({})
    property url importFile
    property string importResult: ""

    FileDialog {
        id: csvPicker
        title: "Import logins from a CSV export"
        nameFilters: ["CSV files (*.csv *.txt)", "All files (*)"]
        onAccepted: {
            dialog.importFile = selectedFile
            dialog.importInfo = vault.inspectCsv(selectedFile)
            dialog.importResult = ""
            importDialog.open()
        }
    }
    SiloDialog {
        id: importDialog
        width: 440
        heading: "Import logins"
        initialFocusItem: importButton
        contentItem: ColumnLayout {
            spacing: 14
            Text {
                Layout.fillWidth: true
                text: dialog.importInfo.ok
                      ? "<b>" + dialog.importInfo.format + "</b> export · " + dialog.importInfo.logins
                        + (dialog.importInfo.logins === 1 ? " login" : " logins")
                        + (dialog.importInfo.hasTotp ? ", with 2FA secrets" : "")
                        + ".<br>Existing logins with the same site and username are updated, identical ones skipped."
                      : (dialog.importInfo.error || "This file could not be read.")
                textFormat: Text.StyledText
                color: dialog.importInfo.ok ? Theme.textSecondary : Theme.destructive
                font.pixelSize: Theme.fontSize
                wrapMode: Text.WordWrap
            }
            Text {
                visible: dialog.importResult.length > 0
                Layout.fillWidth: true
                text: dialog.importResult
                color: Theme.text
                font.pixelSize: Theme.fontSize
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                SiloButton {
                    text: dialog.importResult ? "Close" : "Cancel"
                    iconName: "fluent-dismiss-20-regular"
                    onClicked: importDialog.close()
                }
                SiloButton {
                    id: importButton
                    visible: !!dialog.importInfo.ok && !dialog.importResult
                    text: "Import"
                    iconName: "fluent-arrow-import-20-regular"
                    accent: true
                    onClicked: {
                        var result = vault.importCsv(dialog.importFile)
                        dialog.importResult = result.ok
                            ? "Imported: " + result.added + " added, " + result.updated + " updated, " + result.skipped + " skipped."
                            : (result.error || "Import failed.")
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- master password
    property string masterError: ""
    SiloDialog {
        id: masterDialog
        width: 420
        heading: vault.hasMasterPassword ? "Remove master password" : "Set a master password"
        subheading: vault.hasMasterPassword
                    ? "The vault key goes back to the system keychain; the vault opens without a prompt."
                    : "The vault key will be protected by this password (Argon2) instead of the system keychain. You will be asked for it when Silo starts."
        onOpened: dialog.masterError = ""
        contentItem: ColumnLayout {
            spacing: 12
            SiloTextField {
                id: masterField
                Layout.fillWidth: true
                placeholderText: "Master password"
                echoMode: TextInput.Password
                onAccepted: masterApply.clicked()
            }
            SiloTextField {
                id: masterConfirm
                visible: !vault.hasMasterPassword
                Layout.fillWidth: true
                placeholderText: "Confirm master password"
                echoMode: TextInput.Password
                onAccepted: masterApply.clicked()
            }
            Text {
                visible: dialog.masterError.length > 0
                Layout.fillWidth: true
                text: dialog.masterError
                color: Theme.destructive
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                SiloButton {
                    text: "Cancel"
                    iconName: "fluent-dismiss-20-regular"
                    onClicked: masterDialog.close()
                }
                SiloButton {
                    id: masterApply
                    text: vault.hasMasterPassword ? "Remove" : "Set password"
                    iconName: vault.hasMasterPassword ? "fluent-lock-open-20-regular" : "fluent-lock-closed-20-regular"
                    accent: true
                    enabled: masterField.text.length > 0
                    onClicked: {
                        var error
                        if (vault.hasMasterPassword) {
                            error = vault.removeMasterPassword(masterField.text)
                        } else if (masterField.text !== masterConfirm.text) {
                            error = "The two passwords differ."
                        } else {
                            error = vault.setMasterPassword(masterField.text)
                        }
                        if (error) {
                            dialog.masterError = error
                            return
                        }
                        masterField.text = ""
                        masterConfirm.text = ""
                        masterDialog.close()
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- connector unlock
    property string unlockId: ""
    property string unlockAccount: ""
    readonly property var unlockAccounts: unlockId === "1password" ? (passwords.connector("1password").accounts || []) : []
    SiloDialog {
        id: unlockDialog
        width: 400
        heading: "Unlock " + (passwords.connector(dialog.unlockId).name || "")
        subheading: dialog.unlockId === "1password" ? "With the desktop app integration on, leave the password empty and approve the prompt in the 1Password app. Otherwise the account password is only handed to the `op` CLI."
                                                    : "The master password is only handed to the `bw` CLI."
        onOpened: {
            dialog.unlockAccount = ""
            for (var i = 0; i < dialog.unlockAccounts.length; ++i)
                if (dialog.unlockAccounts[i].locked && !dialog.unlockAccount) dialog.unlockAccount = dialog.unlockAccounts[i].id
            if (!dialog.unlockAccount && dialog.unlockAccounts.length > 0) dialog.unlockAccount = dialog.unlockAccounts[0].id
        }
        contentItem: ColumnLayout {
            spacing: 12
            AccountPicker {
                id: settingsAccountPicker
                visible: dialog.unlockAccounts.length > 1
                Layout.fillWidth: true
                accounts: dialog.unlockAccounts
                current: dialog.unlockAccount
                onPicked: function(id) { dialog.unlockAccount = id; connectorPassword.forceActiveFocus() }
            }
            SiloTextField {
                id: connectorPassword
                Layout.fillWidth: true
                placeholderText: dialog.unlockId === "1password" ? "Account password" : "Master password"
                echoMode: TextInput.Password
                onAccepted: connectorUnlock.clicked()
                Keys.onUpPressed: settingsAccountPicker.move(-1)
                Keys.onDownPressed: settingsAccountPicker.move(1)
            }
            Text {
                visible: text.length > 0
                Layout.fillWidth: true
                text: passwords.errors[dialog.unlockId] || ""
                color: Theme.destructive
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Spinner { visible: passwords.busy; size: 18 }
                Item { Layout.fillWidth: true }
                SiloButton { text: "Cancel"; iconName: "fluent-dismiss-20-regular"; onClicked: unlockDialog.close() }
                SiloButton {
                    id: connectorUnlock
                    readonly property bool viaApp: dialog.unlockId === "1password" && connectorPassword.text.length === 0
                    text: viaApp ? "Ask the app" : "Unlock"
                    iconName: viaApp ? "fluent-open-20-regular" : "fluent-lock-open-20-regular"
                    accent: true
                    enabled: (connectorPassword.text.length > 0 || viaApp) && !passwords.busy
                    onClicked: { passwords.unlock(dialog.unlockId, connectorPassword.text, dialog.unlockAccount); connectorPassword.text = "" }
                }
            }
        }
        Connections {
            target: passwords
            function onUnlocked(id) { if (unlockDialog.opened && id === dialog.unlockId) unlockDialog.close() }
        }
    }

    ConnectorSignInDialog { id: signInDialog }
    VaultDialog { id: vaultDialog }

    SiloMenu {
        id: connectorMenu
        property var target: ({})
        SiloMenuItem {
            text: "Sign out"
            iconName: "fluent-sign-out-20-regular"
            enabled: !!connectorMenu.target.installed && connectorMenu.target.auth !== "signed-out"
            onTriggered: passwords.signOut(connectorMenu.target.id)
        }
        SiloMenuItem {
            text: "Check again"
            iconName: "fluent-arrow-sync-20-regular"
            onTriggered: passwords.refresh()
        }
        SiloMenuItem {
            text: "Show CLI in folder"
            iconName: "fluent-folder-open-20-regular"
            enabled: !!connectorMenu.target.installed
            onTriggered: Qt.openUrlExternally(files.toUrl(String(connectorMenu.target.cliPath).replace(/[\\/][^\\/]+$/, "")))
        }
        SiloMenuItem {
            text: "Remove CLI"
            iconName: "fluent-delete-20-regular"
            destructive: true
            enabled: !!connectorMenu.target.managed
            onTriggered: passwords.uninstall(connectorMenu.target.id)
        }
    }

    // ---------------------------------------------------------------- building blocks
    component SectionLabel: Text {
        Layout.fillWidth: true
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSizeCaption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
    }

    // Label + description on the left, control on the right
    component SettingRow: RowLayout {
        id: row
        property string title: ""
        property string description: ""
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: row.title
                color: Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: row.description.length > 0
                text: row.description
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }
        Item {
            id: slot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }

    component Divider: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

    contentItem: RowLayout {
        spacing: 0

        // ============================================================ NAV RAIL
        Rectangle {
            id: rail
            Layout.fillHeight: true
            Layout.preferredWidth: 188
            radius: 10
            color: Theme.surfaceAlt
            // Square the right corners (the dialog background rounds the left ones).
            Rectangle { anchors.fill: parent; anchors.leftMargin: parent.radius; color: parent.color }
            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: Theme.divider }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 22
                spacing: 2

                Text {
                    Layout.leftMargin: 10
                    Layout.bottomMargin: 14
                    text: "Settings"
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeTitle
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: dialog.sections
                    delegate: Rectangle {
                        id: navRow
                        required property var modelData
                        readonly property bool active: dialog.section === modelData.key
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: Theme.radiusSmall
                        color: active ? Theme.selection : navHover.hovered ? Theme.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animationFast } }
                        Rectangle {
                            visible: navRow.active
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 16
                            radius: 1.5
                            color: Theme.accent
                        }
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: navRow.modelData.icon; size: 16; color: navRow.active ? Theme.accent : Theme.textSecondary }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: navRow.modelData.label
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                                font.weight: navRow.active ? Font.DemiBold : Font.Normal
                            }
                        }
                        HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: dialog.section = navRow.modelData.key }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ============================================================ BODY
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Flickable {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: bodyColumn.implicitHeight + 48
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: bodyColumn
                    x: 24
                    y: 24
                    width: body.width - 48
                    spacing: 14

                    Text {
                        Layout.bottomMargin: 4
                        text: dialog.sectionLabel(dialog.section)
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeTitle
                        font.weight: Font.DemiBold
                    }

                    // ============================================================ GENERAL
                    ColumnLayout {
                        visible: dialog.section === "general"
                        Layout.fillWidth: true
                        spacing: 14

                        SettingRow {
                            title: "Appearance"
                            description: "Light or dark, or follow the system setting."
                            Rectangle {
                                width: appearanceSegments.implicitWidth + 4
                                height: 32
                                radius: Theme.radius
                                color: Theme.controlBg
                                border.width: 1
                                border.color: Theme.border
                                Row {
                                    id: appearanceSegments
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Repeater {
                                        model: dialog.appearanceOptions
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: themeController.mode === modelData.key
                                            width: segmentContent.implicitWidth + 20
                                            height: 28
                                            radius: Theme.radiusSmall
                                            color: active ? Theme.accent : segmentHover.hovered ? Theme.hover : "transparent"
                                            Behavior on color { ColorAnimation { duration: Theme.animationFast } }
                                            Row {
                                                id: segmentContent
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 15; color: active ? Theme.textOnAccent : Theme.text }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.label
                                                    color: active ? Theme.textOnAccent : Theme.text
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: active ? Font.DemiBold : Font.Normal
                                                }
                                            }
                                            HoverHandler { id: segmentHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: themeController.mode = modelData.key }
                                        }
                                    }
                                }
                            }
                        }

                        Divider {}

                        SettingRow {
                            title: "Sidebar"
                            description: "Show the workspace tree. Toggle anytime with " + (Qt.platform.os === "osx" ? "⌘B" : "Ctrl+B") + "."
                            SiloButton {
                                text: Session.sidebarVisible ? "Visible" : "Hidden"
                                iconName: Session.sidebarVisible ? "fluent-eye-20-regular" : "fluent-eye-off-20-regular"
                                onClicked: Session.toggleSidebar()
                            }
                        }

                        Divider {}

                        SettingRow {
                            title: "Storage"
                            description: appStore.dataPath()
                            SiloButton {
                                text: "Show in folder"
                                iconName: "fluent-folder-open-20-regular"
                                onClicked: Qt.openUrlExternally(files.toUrl(appStore.dataPath()))
                            }
                        }
                    }

                    // ============================================================ PASSWORDS
                    ColumnLayout {
                        visible: dialog.section === "passwords"
                        Layout.fillWidth: true
                        spacing: 14

                        Text {
                            Layout.fillWidth: true
                            text: "Web tabs cannot run browser extensions, so Silo fills logins itself: from its own vault, and from the password managers connected below. Press "
                                  + (Qt.platform.os === "osx" ? "⌘⇧L" : "Ctrl+Shift+L") + " or the key button on a login page."
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }

                        SectionLabel { text: "SILO VAULT" }

                        // Vault card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: vaultColumn.implicitHeight + 24
                            radius: Theme.radius
                            color: Theme.controlBg
                            border.width: 1
                            border.color: Theme.border
                            ColumnLayout {
                                id: vaultColumn
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Icon { name: "fluent-vault-20-regular"; size: 20; color: Theme.accent }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            Layout.fillWidth: true
                                            text: vault.locked ? "Silo vault · locked" : (vault.count === 1 ? "1 login" : vault.count + " logins")
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: dialog.keyStorageText()
                                            color: vault.error ? Theme.destructive : Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                    SiloButton {
                                        visible: vault.hasMasterPassword && !vault.locked
                                        text: "Lock"
                                        iconName: "fluent-lock-closed-20-regular"
                                        onClicked: vault.lock()
                                    }
                                }
                                // Unlock inline when a master password is set
                                RowLayout {
                                    visible: vault.locked && vault.hasMasterPassword
                                    Layout.fillWidth: true
                                    spacing: 6
                                    SiloTextField {
                                        id: vaultUnlockField
                                        Layout.fillWidth: true
                                        placeholderText: "Master password"
                                        echoMode: TextInput.Password
                                        onAccepted: vaultUnlockButton.clicked()
                                    }
                                    SiloButton {
                                        id: vaultUnlockButton
                                        text: "Unlock"
                                        iconName: "fluent-lock-open-20-regular"
                                        accent: true
                                        enabled: vaultUnlockField.text.length > 0
                                        onClicked: {
                                            if (!vault.unlock(vaultUnlockField.text))
                                                dialog.masterError = "Wrong master password."
                                            else
                                                dialog.masterError = ""
                                            vaultUnlockField.text = ""
                                        }
                                    }
                                }
                                Text {
                                    visible: vault.locked && dialog.masterError.length > 0
                                    text: dialog.masterError
                                    color: Theme.destructive
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    SiloButton {
                                        enabled: !vault.locked
                                        text: "Import CSV…"
                                        iconName: "fluent-arrow-import-20-regular"
                                        onClicked: csvPicker.open()
                                    }
                                    SiloButton {
                                        enabled: !vault.locked
                                        text: "Manage logins"
                                        iconName: "fluent-key-20-regular"
                                        onClicked: vaultDialog.open()
                                    }
                                    SiloButton {
                                        enabled: !vault.locked
                                        text: vault.hasMasterPassword ? "Remove master password…" : "Set master password…"
                                        iconName: "fluent-shield-keyhole-20-regular"
                                        onClicked: masterDialog.open()
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Import the CSV export of any password manager (1Password, Bitwarden, Dashlane, LastPass, KeePass, Chrome, Firefox, Proton Pass…). Logins you submit in Live tabs can be saved here too."
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeCaption
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        SectionLabel { text: "PASSWORD MANAGERS" }

                        Text {
                            Layout.fillWidth: true
                            text: "Live connections through the managers' own command line tools. Silo downloads them into its data folder; nothing is installed system-wide and no password is stored by Silo."
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: passwords.connectors
                            delegate: Rectangle {
                                id: connectorRow
                                required property var modelData
                                readonly property var c: modelData
                                Layout.fillWidth: true
                                implicitHeight: connectorLayout.implicitHeight + 20
                                radius: Theme.radius
                                color: Theme.controlBg
                                border.width: 1
                                border.color: Theme.border
                                RowLayout {
                                    id: connectorLayout
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10
                                    Icon {
                                        name: connectorRow.c.installed ? (connectorRow.c.enabled ? "fluent-plug-connected-20-regular" : "fluent-plug-disconnected-20-regular") : "fluent-cloud-arrow-down-20-regular"
                                        size: 18
                                        color: connectorRow.c.usable ? Theme.accent : Theme.textSecondary
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: connectorRow.c.name
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: dialog.connectorStatus(connectorRow.c)
                                            color: connectorRow.c.installError ? Theme.destructive : Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideMiddle
                                        }
                                        // Install progress
                                        Rectangle {
                                            visible: connectorRow.c.installing
                                            Layout.fillWidth: true
                                            Layout.topMargin: 4
                                            height: 3
                                            radius: 1.5
                                            color: Theme.border
                                            Rectangle {
                                                width: parent.width * connectorRow.c.installProgress / 100
                                                height: parent.height
                                                radius: 1.5
                                                color: Theme.accent
                                                Behavior on width { NumberAnimation { duration: 150 } }
                                            }
                                        }
                                    }
                                    // Primary action
                                    SiloButton {
                                        visible: !connectorRow.c.installed
                                        enabled: !connectorRow.c.installing
                                        text: connectorRow.c.installing ? "Installing…" : connectorRow.c.installError ? "Retry" : "Install"
                                        iconName: "fluent-arrow-download-20-regular"
                                        onClicked: passwords.install(connectorRow.c.id)
                                    }
                                    SiloButton {
                                        visible: connectorRow.c.installed && connectorRow.c.enabled && passwords.needsInteractiveSignIn(connectorRow.c.id)
                                        text: connectorRow.c.auth === "locked" ? "Unlock…" : "Sign in…"
                                        iconName: "fluent-person-20-regular"
                                        accent: true
                                        onClicked: signInDialog.start(connectorRow.c.id)
                                    }
                                    SiloButton {
                                        visible: connectorRow.c.installed && connectorRow.c.enabled && connectorRow.c.auth === "locked" && connectorRow.c.id !== "dashlane"
                                        text: "Unlock…"
                                        iconName: "fluent-lock-open-20-regular"
                                        accent: true
                                        onClicked: { dialog.unlockId = connectorRow.c.id; passwords.clearError(connectorRow.c.id); unlockDialog.open() }
                                    }
                                    SiloButton {
                                        visible: connectorRow.c.installed && connectorRow.c.enabled && (connectorRow.c.auth === "unlocked" || connectorRow.c.auth === "syncing")
                                        text: "Lock"
                                        iconName: "fluent-lock-closed-20-regular"
                                        onClicked: passwords.lock(connectorRow.c.id)
                                    }
                                    // Enabled toggle
                                    SiloButton {
                                        visible: connectorRow.c.installed
                                        text: connectorRow.c.enabled ? "On" : "Off"
                                        iconName: connectorRow.c.enabled ? "fluent-checkbox-checked-20-regular" : "fluent-checkbox-unchecked-20-regular"
                                        implicitWidth: 72
                                        onClicked: passwords.setEnabled(connectorRow.c.id, !connectorRow.c.enabled)
                                    }
                                    IconButton {
                                        visible: connectorRow.c.installed
                                        iconName: "fluent-more-horizontal-20-regular"
                                        iconSize: 16
                                        tooltip: "More"
                                        onClicked: { connectorMenu.target = connectorRow.c; connectorMenu.popup(this, 0, height + 2) }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: passwords.error.length > 0 && !unlockDialog.opened
                            Layout.fillWidth: true
                            text: passwords.error
                            color: Theme.destructive
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ============================================================ ABOUT
                    ColumnLayout {
                        visible: dialog.section === "about"
                        Layout.fillWidth: true
                        spacing: 14

                        // Identity card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: aboutRow.implicitHeight + 32
                            radius: Theme.radius
                            color: Theme.controlBg
                            border.width: 1
                            border.color: Theme.border
                            RowLayout {
                                id: aboutRow
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 16
                                Image {
                                    source: "qrc:/app/logo-512.png"
                                    sourceSize: Qt.size(56, 56)
                                    Layout.preferredWidth: 56
                                    Layout.preferredHeight: 56
                                    smooth: true
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: "Silo"
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeTitle
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: dialog.versionText()
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSize
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Everything a project needs, one window."
                                        color: Theme.textTertiary
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }
                                }
                                SiloButton {
                                    Layout.alignment: Qt.AlignTop
                                    text: "Copy"
                                    iconName: "fluent-copy-20-regular"
                                    onClicked: files.copyToClipboard(dialog.aboutSummary())
                                }
                            }
                        }

                        SectionLabel { text: "BUILD" }

                        SettingRow {
                            title: "Engines"
                            description: "Qt " + appInfo.qtVersion + " · Chromium " + appInfo.chromiumVersion + " (Qt WebEngine)"
                        }

                        Divider {}

                        SettingRow {
                            title: "System"
                            description: appInfo.os + " · " + appInfo.arch
                        }

                        SectionLabel { text: "LINKS" }

                        SettingRow {
                            title: "Source code"
                            description: appInfo.repository.replace(/^https?:\/\//, "")
                            SiloButton {
                                text: "GitHub"
                                iconName: "fluent-code-20-regular"
                                onClicked: Qt.openUrlExternally(appInfo.repository)
                            }
                        }

                        Divider {}

                        SettingRow {
                            title: "Releases"
                            description: "Download the latest version or read the changelog."
                            SiloButton {
                                text: "Open"
                                iconName: "fluent-open-20-regular"
                                onClicked: Qt.openUrlExternally(appInfo.repository + "/releases")
                            }
                        }

                        Divider {}

                        SettingRow {
                            title: "Report an issue"
                            description: "Include the build details above (use Copy)."
                            SiloButton {
                                text: "New issue"
                                iconName: "fluent-arrow-export-20-regular"
                                onClicked: Qt.openUrlExternally(appInfo.repository + "/issues/new")
                            }
                        }
                    }

                } // bodyColumn
            } // body

            // Footer, pinned under the scrolling body
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Spinner {
                    visible: dialog.section === "passwords" && passwords.busy
                    size: 18
                }
                Item { Layout.fillWidth: true }
                SiloButton {
                    id: doneButton
                    text: "Done"
                    iconName: "fluent-checkmark-20-regular"
                    accent: true
                    onClicked: dialog.close()
                }
            }
        }
    }
}
