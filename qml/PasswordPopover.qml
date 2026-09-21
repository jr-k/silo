import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// "Fill login" popover of the Live toolbar: logins matching the current page
// from the Silo vault and from every connected password manager, merged.
Popup {
    id: popover
    // TabPage of the current tab (must be a loaded web tab)
    property var view: null
    property string pageUrl: view ? view.displayUrl : ""
    readonly property string host: vault.hostOf(pageUrl)

    // Merged results: [{source, id, title, username, url, hasTotp}]
    property var results: []
    property var bySource: ({})
    property bool searching: false
    // Result whose password is being fetched from its connector ("" = none)
    property string fetchingId: ""
    property string fetchingSource: ""
    property string notice: ""
    // Connector whose unlock form is shown ("" = none, "vault" = master password)
    property string unlockTarget: ""
    // 1Password: account being unlocked (several can be signed in)
    property string unlockAccount: ""
    readonly property var unlockAccounts: unlockTarget === "1password" ? (passwords.connector("1password").accounts || []) : []

    readonly property var lockedIds: passwords.lockedConnectors
    // Connectors with an error to show as a row (the one being unlocked shows its own inline)
    readonly property var errorSources: {
        var list = []
        var errors = passwords.errors
        for (var id in errors)
            if (errors[id] && id !== unlockTarget)
                list.push(id)
        return list
    }
    readonly property bool nothingConfigured: vault.count === 0 && !vault.locked && passwords.usableCount === 0
                                              && passwords.unprobedCount === 0 && lockedIds.length === 0

    width: 360
    padding: 8
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function sourceName(source) {
        if (source === "vault")
            return "Silo vault"
        var c = passwords.connector(source)
        return c.name || source
    }

    // Connectors still being queried, for the loading rows
    function searchingSources() {
        var names = []
        var connectors = passwords.connectors
        for (var i = 0; i < connectors.length; ++i)
            if (connectors[i].usable && !(connectors[i].id in bySource) && !passwords.errors[connectors[i].id])
                names.push(connectors[i].name)
        return names.length > 0 ? names.join(", ") : "password managers"
    }

    function openFor(tabView) {
        view = tabView
        notice = ""
        unlockTarget = vault.locked ? "vault" : ""
        passwords.clearError()
        open()
        refresh()
    }

    function refresh() {
        bySource = {}
        fetchingId = ""
        results = vault.locked ? [] : vault.search(pageUrl)
        // Connectors not probed yet are asked their status by the search itself
        searching = passwords.usableCount > 0 || passwords.unprobedCount > 0
        if (searching)
            passwords.search(pageUrl)
    }

    function merge() {
        var list = vault.locked ? [] : vault.search(pageUrl)
        for (var source in bySource)
            list = list.concat(bySource[source])
        results = list
    }

    function fill(item) {
        if (fetchingId !== "")
            return
        notice = ""
        if (item.source === "vault") {
            var full = vault.get(item.id)
            if (full.id)
                applyCredentials(full)
            return
        }
        fetchingId = item.id
        fetchingSource = item.source
        passwords.fetch(item.source, item.id)
    }

    function applyCredentials(credentials) {
        // The web page is refreshing its 2FA code by itself (see WebPage.pendingTotp)
        if (popover.view && popover.view.totpRefreshing)
            return
        fetchingId = ""
        if (!popover.opened || !popover.view)
            return
        popover.view.fillCredentials(credentials.username, credentials.password, function(result) {
            var filled = []
            if (result.user) filled.push("username")
            if (result.password) filled.push("password")
            var hasTotp = !!(credentials.totp || credentials.totpSecret)
            if (hasTotp) {
                // Typed into the code field when it shows up; clipboard as a fallback
                popover.view.armTotp(credentials)
                if (credentials.totp)
                    files.copyToClipboard(credentials.totp)
            }
            if (filled.length === 0 && !hasTotp) {
                popover.notice = "No login field found on this page. Click a field first, then try again."
                return
            }
            if (filled.length === 0) {
                popover.notice = "2FA code ready: it is typed in as soon as the code field appears (also copied)."
                popover.view.focusContent()
                closeTimer.restart()
                return
            }
            if (hasTotp) filled.push("2FA code follows")
            popover.notice = "Filled " + filled.join(", ") + "."
            popover.view.focusContent()
            closeTimer.restart()
        })
    }

    Connections {
        target: passwords
        function onResultsReady(url, source, items) {
            if (!popover.opened || url !== popover.pageUrl)
                return
            var map = popover.bySource
            map[source] = items
            popover.bySource = map
            popover.merge()
        }
        function onSearchFinished(url) {
            if (url === popover.pageUrl)
                popover.searching = false
        }
        function onCredentialsReady(credentials) { popover.applyCredentials(credentials) }
        function onErrorChanged() {
            // A failed fetch is reported on the result's own connector
            if (popover.fetchingId !== "" && passwords.errors[popover.fetchingSource])
                popover.fetchingId = ""
        }
        function onUnlocked(id) {
            if (!popover.opened)
                return
            popover.unlockTarget = ""
            popover.refresh()
        }
    }
    Connections {
        target: vault
        function onLockedChanged() {
            if (!popover.opened)
                return
            if (!vault.locked && popover.unlockTarget === "vault")
                popover.unlockTarget = ""
            popover.refresh()
        }
    }
    Timer { id: closeTimer; interval: 900; onTriggered: popover.close() }
    onClosed: fetchingId = ""

    function focusList() {
        if (opened && unlockTarget === "" && results.length > 0)
            list.forceActiveFocus()
    }
    onOpened: unlockTarget !== "" ? unlockField.forceActiveFocus() : focusList()
    onUnlockTargetChanged: {
        if (!opened)
            return
        if (unlockTarget !== "") {
            unlockField.text = ""
            // Default to the first locked account
            // (read the connector directly: the unlockAccounts binding may not have refreshed yet)
            var accounts = unlockTarget === "1password" ? (passwords.connector("1password").accounts || []) : []
            unlockAccount = ""
            for (var i = 0; i < accounts.length; ++i)
                if (accounts[i].locked && !unlockAccount) unlockAccount = accounts[i].id
            if (!unlockAccount && accounts.length > 0) unlockAccount = accounts[0].id
            unlockField.forceActiveFocus()
        } else {
            focusList()
        }
    }
    onResultsChanged: focusList()

    background: Rectangle {
        radius: Theme.radiusLarge
        color: Theme.menuBg
        border.width: 1
        border.color: Theme.border
    }

    contentItem: ColumnLayout {
        spacing: 6

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 4
            Layout.topMargin: 2
            spacing: 8
            Icon { name: "fluent-key-20-regular"; size: 16; color: Theme.accent }
            Text {
                Layout.fillWidth: true
                text: popover.host || "Fill login"
                color: Theme.text
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Spinner {
                visible: passwords.busy || popover.searching || popover.fetchingId !== ""
                size: 14
            }
            IconButton {
                iconName: "fluent-arrow-clockwise-20-regular"
                iconSize: 14
                implicitWidth: 24
                implicitHeight: 24
                tooltip: "Search again"
                onClicked: popover.refresh()
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

        // Unlock form (Silo vault master password, Bitwarden / 1Password password)
        ColumnLayout {
            visible: popover.unlockTarget !== ""
            Layout.fillWidth: true
            Layout.margins: 6
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: popover.unlockTarget === "vault" ? "Enter the master password of your Silo vault."
                    : popover.unlockTarget === "bitwarden" ? "Unlock Bitwarden. The master password is only handed to the `bw` CLI."
                    : popover.unlockTarget === "1password" ? "Unlock 1Password. With the desktop app integration on, leave the password empty and approve the prompt in the 1Password app. Otherwise the account password is only handed to the `op` CLI."
                    : ""
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
            // Account choice (1Password with several accounts)
            AccountPicker {
                id: accountPicker
                visible: popover.unlockAccounts.length > 1
                Layout.fillWidth: true
                accounts: popover.unlockAccounts
                current: popover.unlockAccount
                onPicked: function(id) { popover.unlockAccount = id; unlockField.forceActiveFocus() }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                SiloTextField {
                    id: unlockField
                    Layout.fillWidth: true
                    placeholderText: popover.unlockTarget === "1password" ? "Account password" : "Master password"
                    echoMode: TextInput.Password
                    onAccepted: unlockButton.clicked()
                    Keys.onUpPressed: accountPicker.move(-1)
                    Keys.onDownPressed: accountPicker.move(1)
                }
                SiloButton {
                    id: unlockButton
                    readonly property bool viaApp: popover.unlockTarget === "1password" && unlockField.text.length === 0
                    text: viaApp ? "Ask the app" : "Unlock"
                    iconName: viaApp ? "fluent-open-20-regular" : "fluent-lock-open-20-regular"
                    accent: true
                    enabled: (unlockField.text.length > 0 || viaApp) && !passwords.busy
                    onClicked: {
                        if (popover.unlockTarget === "vault") {
                            if (!vault.unlock(unlockField.text))
                                popover.notice = "Wrong master password."
                        } else {
                            passwords.unlock(popover.unlockTarget, unlockField.text, popover.unlockAccount)
                        }
                        unlockField.text = ""
                    }
                }
                IconButton {
                    visible: popover.unlockTarget !== "vault" || !vault.locked
                    iconName: "fluent-dismiss-20-regular"
                    iconSize: 14
                    implicitWidth: 26
                    implicitHeight: 26
                    tooltip: "Cancel"
                    onClicked: popover.unlockTarget = ""
                }
            }
            // Failure of this very unlock (other connectors' errors are listed below)
            Text {
                visible: text.length > 0
                Layout.fillWidth: true
                text: popover.unlockTarget !== "" && popover.unlockTarget !== "vault" ? (passwords.errors[popover.unlockTarget] || "") : ""
                color: Theme.destructive
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }

        // Searching, nothing to show yet
        RowLayout {
            visible: popover.unlockTarget === "" && popover.searching && popover.results.length === 0
            Layout.fillWidth: true
            Layout.margins: 6
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 10
            Spinner { size: 18 }
            Text {
                Layout.fillWidth: true
                text: "Searching " + popover.searchingSources() + "…"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        // Results
        ListView {
            id: list
            visible: popover.results.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 5 * 44)
            clip: true
            model: popover.results
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            currentIndex: 0
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            // Still waiting for other connectors: hint that more may come
            footer: Item {
                width: list.width
                height: popover.searching ? 28 : 0
                visible: popover.searching
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    spacing: 8
                    Spinner { size: 12; lineWidth: 1.5; color: Theme.textTertiary }
                    Text {
                        Layout.fillWidth: true
                        text: "Searching " + popover.searchingSources() + "…"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeCaption
                        elide: Text.ElideRight
                    }
                }
            }
            delegate: Rectangle {
                id: entry
                required property var modelData
                required property int index
                readonly property bool fetching: popover.fetchingId === modelData.id
                width: list.width
                height: 44
                radius: Theme.radius
                color: fetching || entryHover.hovered || list.currentIndex === index ? Theme.hover : "transparent"
                opacity: popover.fetchingId === "" || fetching ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: 120 } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10
                    SiteIcon {
                        url: entry.modelData.url || popover.pageUrl
                        size: 20
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.title
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.username || "—"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeCaption
                            elide: Text.ElideRight
                        }
                    }
                    // Source pill
                    Rectangle {
                        width: sourceLabel.implicitWidth + 12
                        height: 18
                        radius: 9
                        color: Theme.controlBg
                        border.width: 1
                        border.color: Theme.border
                        Text {
                            id: sourceLabel
                            anchors.centerIn: parent
                            text: popover.sourceName(entry.modelData.source) + (entry.modelData.account ? " · " + entry.modelData.account : "")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeCaption
                        }
                    }
                    Icon {
                        visible: !!entry.modelData.hasTotp
                        name: "fluent-password-20-regular"
                        size: 14
                        color: Theme.textTertiary
                        ToolTip.visible: totpHover.hovered
                        ToolTip.text: "Has a 2FA code (copied on fill)"
                        HoverHandler { id: totpHover }
                    }
                    Item {
                        implicitWidth: 16
                        implicitHeight: 16
                        Icon {
                            anchors.centerIn: parent
                            visible: !entry.fetching
                            name: "fluent-chevron-right-20-regular"
                            size: 14
                            color: Theme.textTertiary
                        }
                        Spinner {
                            anchors.centerIn: parent
                            visible: entry.fetching
                            size: 16
                        }
                    }
                }
                HoverHandler { id: entryHover; cursorShape: popover.fetchingId === "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: popover.fill(entry.modelData) }
            }
            Keys.onReturnPressed: if (currentIndex >= 0) popover.fill(popover.results[currentIndex])
            Keys.onEnterPressed: if (currentIndex >= 0) popover.fill(popover.results[currentIndex])
        }

        // Locked connectors: one row each, tap to unlock
        Repeater {
            model: popover.unlockTarget === "" ? popover.lockedIds : []
            delegate: Rectangle {
                id: lockedRow
                required property string modelData
                Layout.fillWidth: true
                height: 36
                radius: Theme.radius
                color: lockedHover.hovered ? Theme.hover : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10
                    Icon { name: "fluent-lock-closed-20-regular"; size: 16; color: Theme.textSecondary }
                    Text {
                        Layout.fillWidth: true
                        text: popover.sourceName(lockedRow.modelData) + " is locked"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "Unlock"
                        color: Theme.accent
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: lockedHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: popover.unlockTarget = lockedRow.modelData }
            }
        }

        // Connector errors, one compact row each. They sit under whatever is
        // shown (results, unlock form) instead of replacing it.
        Repeater {
            model: popover.errorSources
            delegate: RowLayout {
                id: errorRow
                required property string modelData
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 8
                Icon { name: "fluent-error-circle-20-regular"; size: 14; color: Theme.destructive; Layout.alignment: Qt.AlignTop; Layout.topMargin: 1 }
                Text {
                    Layout.fillWidth: true
                    text: "<b>" + popover.sourceName(errorRow.modelData) + "</b> · " + (passwords.errors[errorRow.modelData] || "")
                    textFormat: Text.StyledText
                    color: Theme.destructive
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
                IconButton {
                    iconName: "fluent-dismiss-20-regular"
                    iconSize: 12
                    implicitWidth: 20
                    implicitHeight: 20
                    Layout.alignment: Qt.AlignTop
                    tooltip: "Dismiss"
                    onClicked: passwords.clearError(errorRow.modelData)
                }
            }
        }

        // Empty / notice
        Text {
            visible: text.length > 0
            Layout.fillWidth: true
            Layout.margins: 6
            text: popover.notice ? popover.notice
                : popover.nothingConfigured ? "No logins yet. Import a CSV export or connect a password manager in Settings; logins you submit in tabs can be saved too."
                : (popover.unlockTarget === "" && !popover.searching && popover.results.length === 0 && popover.errorSources.length === 0)
                    ? "No login for " + popover.host + "."
                : ""
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 2
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: "Fills the focused form"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeCaption
            }
            SiloButton {
                text: "Settings"
                iconName: "fluent-settings-20-regular"
                implicitHeight: 26
                onClicked: { popover.close(); Session.openSettings("passwords") }
            }
        }
    }
}
