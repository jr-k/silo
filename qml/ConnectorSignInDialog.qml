import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebChannel
import QtWebEngine
import Silo.Backend

// Runs a password manager's interactive sign-in (`bw login`, `op account add`,
// `dcli sync`) in an embedded terminal: those flows ask for 2FA codes and
// device registrations that have no non-interactive equivalent.
SiloDialog {
    id: dialog
    property string connectorId: ""
    readonly property var connector: passwords.connector(connectorId)
    property var command: []
    property bool finished: false
    property int exitCode: -1

    width: 640
    heading: "Sign in to " + (connector.name || "")
    subheading: connectorId === "bitwarden" ? "Enter your Bitwarden e-mail, master password and, if enabled, the two-step code. The session stays in the `bw` CLI; Silo asks for the master password to unlock it."
              : connectorId === "1password" ? "Enter your sign-in address, e-mail, Secret Key and account password. If the 1Password desktop app is installed, turn on Settings › Developer › “Integrate with 1Password CLI” instead and this step is not needed."
              : connectorId === "dashlane" ? "Enter your Dashlane e-mail, the verification code you receive, then your master password. Dashlane keeps it in the system keychain so later lookups need no prompt."
              : ""
    initialFocusItem: view
    closePolicy: finished ? Popup.CloseOnEscape : Popup.NoAutoClose

    function start(id) {
        connectorId = id
        command = passwords.signInCommand(id)
        finished = false
        exitCode = -1
        open()
        view.url = "qrc:/web/terminal.html"
    }

    onClosed: {
        session.stop()
        view.url = "about:blank"
        passwords.refresh()
    }

    TerminalSession {
        id: session
        WebChannel.id: "session"
        command: dialog.command
        theme: ({
            background: String(Theme.terminalBg),
            foreground: String(Theme.terminalFg),
            cursor: String(Theme.accent),
            selection: String(Theme.selectionBorder),
            fontSize: 13
        })
        onFinished: function(code) {
            dialog.finished = true
            dialog.exitCode = code
            passwords.refresh()
        }
    }
    WebChannel {
        id: channel
        registeredObjects: [session]
    }

    contentItem: ColumnLayout {
        spacing: 12
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 320
            radius: Theme.radius
            color: Theme.terminalBg
            border.width: 1
            border.color: Theme.border
            clip: true
            WebEngineView {
                id: view
                anchors.fill: parent
                anchors.margins: 1
                webChannel: channel
                backgroundColor: Theme.terminalBg
                settings.localContentCanAccessRemoteUrls: false
                settings.localContentCanAccessFileUrls: false
                settings.focusOnNavigationEnabled: true
                onLoadingChanged: function(info) {
                    if (info.status === WebEngineView.LoadSucceededStatus && dialog.opened)
                        view.forceActiveFocus()
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Icon {
                visible: dialog.finished
                name: dialog.exitCode === 0 ? "fluent-checkmark-20-regular" : "fluent-dismiss-16-regular"
                size: 16
                color: dialog.exitCode === 0 ? Theme.accent : Theme.destructive
            }
            Text {
                Layout.fillWidth: true
                text: !dialog.finished ? "Follow the prompts in the terminal."
                    : dialog.exitCode === 0 ? "Signed in. " + (dialog.connector.name || "") + " is ready."
                    : "The command ended without signing in. You can retry."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
            SiloButton {
                visible: dialog.finished && dialog.exitCode !== 0
                text: "Retry"
                iconName: "fluent-arrow-clockwise-20-regular"
                onClicked: { dialog.finished = false; session.restart(); view.forceActiveFocus() }
            }
            SiloButton {
                text: dialog.finished ? "Done" : "Cancel"
                iconName: dialog.finished ? "fluent-checkmark-20-regular" : "fluent-dismiss-20-regular"
                accent: dialog.finished
                onClicked: dialog.close()
            }
        }
    }
}
