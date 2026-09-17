import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// Export / import of a whole workspace as a single JSON file (.silo.json):
// tree, icons and, if wanted, ssh passwords. Owns the two confirmation dialogs
// and the native file pickers.
Item {
    id: root
    width: 0
    height: 0

    // ---------------------------------------------------------------- export
    property var exportInfo: ({})
    property bool exportSecrets: false
    property string exportError: ""
    property string exportedPath: ""

    function exportWorkspace(id) {
        var info = appStore.workspaceSummary(id)
        if (!info.ok)
            return
        exportInfo = info
        exportSecrets = false
        exportError = ""
        exportedPath = ""
        exportDialog.open()
    }

    function safeFileName(name) {
        var cleaned = String(name).replace(/[\\/:*?"<>|]+/g, "-").trim()
        return (cleaned.length > 0 ? cleaned : "workspace") + ".silo.json"
    }

    function runExport(url) {
        var result = appStore.exportWorkspace(exportInfo.id, url, exportSecrets)
        if (!result.ok) {
            exportError = result.error
            return
        }
        exportedPath = result.path
    }

    // ---------------------------------------------------------------- import
    property var importInfo: ({})
    property bool importSecrets: true
    property string importError: ""

    function importWorkspace() {
        importPicker.open()
    }

    function inspectFile(url) {
        var info = appStore.inspectWorkspaceFile(url)
        importInfo = info
        importError = info.ok ? "" : info.error
        importSecrets = true
        importDialog.open()
    }

    function runImport() {
        if (!importInfo.ok)
            return
        var result = appStore.importWorkspace(files.toUrl(importInfo.path), importSecrets)
        if (!result.ok) {
            importError = result.error
            return
        }
        importDialog.accept()
    }

    function plural(count, noun) {
        return count + " " + noun + (count === 1 ? "" : "s")
    }

    // ---------------------------------------------------------------- pickers
    FileDialog {
        id: exportPicker
        title: "Export workspace"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Silo workspace (*.silo.json)", "JSON (*.json)"]
        defaultSuffix: "json"
        currentFolder: files.toUrl(files.homePath())
        onAccepted: root.runExport(selectedFile)
    }

    FileDialog {
        id: importPicker
        title: "Import workspace"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Silo workspace (*.silo.json *.json)", "All files (*)"]
        currentFolder: files.toUrl(files.homePath())
        onAccepted: root.inspectFile(selectedFile)
    }

    // ---------------------------------------------------------------- export dialog
    SiloDialog {
        id: exportDialog
        width: 460
        heading: root.exportedPath.length > 0 ? "Workspace exported" : "Export workspace"
        subheading: root.exportedPath.length > 0
                    ? "Saved to " + root.exportedPath
                    : "Everything in this workspace goes into one JSON file you can share or import elsewhere."
        initialFocusItem: exportButton

        contentItem: ColumnLayout {
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Badge {
                    size: 48
                    color: root.exportInfo.color || "#176E61"
                    iconType: root.exportInfo.iconType || "emoji"
                    iconValue: root.exportInfo.iconValue || "📦"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.exportInfo.name || ""
                        color: Theme.text
                        font.pixelSize: Theme.fontSize + 2
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.plural(root.exportInfo.folders || 0, "folder") + " · "
                              + root.plural(root.exportInfo.items || 0, "item")
                              + ((root.exportInfo.secrets || 0) > 0
                                 ? " · " + root.plural(root.exportInfo.secrets, "SSH password") : "")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // Passwords are opt-in: the file would hold them in clear text.
            ColumnLayout {
                visible: (root.exportInfo.secrets || 0) > 0 && root.exportedPath.length === 0
                Layout.fillWidth: true
                spacing: 6
                SiloButton {
                    text: "Include SSH passwords"
                    iconName: root.exportSecrets ? "fluent-checkmark-20-regular" : "fluent-password-20-regular"
                    accent: root.exportSecrets
                    onClicked: root.exportSecrets = !root.exportSecrets
                }
                Text {
                    Layout.fillWidth: true
                    text: root.exportSecrets
                          ? "Passwords are written in clear text. Keep the file private."
                          : "Passwords stay on this machine; the items are exported without them."
                    color: root.exportSecrets ? Theme.destructive : Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                visible: root.exportError.length > 0
                Layout.fillWidth: true
                text: root.exportError
                color: Theme.destructive
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                SiloButton {
                    visible: root.exportedPath.length > 0
                    text: "Show in folder"
                    iconName: "fluent-folder-open-20-regular"
                    onClicked: Qt.openUrlExternally(files.toUrl(files.inspect(root.exportedPath).dir || files.homePath()))
                }
                Item { Layout.fillWidth: true }
                SiloButton {
                    text: root.exportedPath.length > 0 ? "Done" : "Cancel"
                    iconName: root.exportedPath.length > 0 ? "fluent-checkmark-20-regular" : "fluent-dismiss-20-regular"
                    onClicked: exportDialog.reject()
                }
                SiloButton {
                    id: exportButton
                    visible: root.exportedPath.length === 0
                    text: "Export…"
                    iconName: "fluent-arrow-export-20-regular"
                    iconRight: true
                    accent: true
                    onClicked: {
                        exportPicker.currentFile = files.toUrl(files.homePath() + "/" + root.safeFileName(root.exportInfo.name))
                        exportPicker.open()
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- import dialog
    SiloDialog {
        id: importDialog
        width: 460
        heading: root.importInfo.ok ? "Import workspace" : "Cannot import"
        subheading: root.importInfo.ok
                    ? "A new workspace is created from the file; nothing existing is changed."
                    : (root.importInfo.path || "")
        initialFocusItem: importButton

        contentItem: ColumnLayout {
            spacing: 16

            RowLayout {
                visible: !!root.importInfo.ok
                Layout.fillWidth: true
                spacing: 14
                Badge {
                    size: 48
                    color: root.importInfo.color || "#176E61"
                    iconType: root.importInfo.iconType || "emoji"
                    iconValue: root.importInfo.iconValue || "📦"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.importInfo.name || ""
                        color: Theme.text
                        font.pixelSize: Theme.fontSize + 2
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.plural(root.importInfo.folders || 0, "folder") + " · "
                              + root.plural(root.importInfo.items || 0, "item")
                              + (root.importInfo.exportedAt
                                 ? " · exported " + Qt.formatDateTime(new Date(root.importInfo.exportedAt), "d MMM yyyy") : "")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            Text {
                visible: !!root.importInfo.ok && !!root.importInfo.nameTaken
                Layout.fillWidth: true
                text: "A workspace with this name already exists. The copy will be named \""
                      + (root.importInfo.name || "") + " (imported)\"."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                visible: !!root.importInfo.ok && (root.importInfo.secrets || 0) > 0
                Layout.fillWidth: true
                spacing: 6
                SiloButton {
                    text: "Import " + root.plural(root.importInfo.secrets || 0, "SSH password")
                    iconName: root.importSecrets ? "fluent-checkmark-20-regular" : "fluent-password-20-regular"
                    accent: root.importSecrets
                    onClicked: root.importSecrets = !root.importSecrets
                }
                Text {
                    Layout.fillWidth: true
                    text: root.importSecrets
                          ? "They are stored in your local secrets.json, readable by your user only."
                          : "The SSH items are imported without their passwords."
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                visible: root.importError.length > 0
                Layout.fillWidth: true
                text: root.importError
                color: Theme.destructive
                font.pixelSize: Theme.fontSize
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                SiloButton {
                    visible: !root.importInfo.ok
                    text: "Choose another file…"
                    iconName: "fluent-folder-open-20-regular"
                    onClicked: { importDialog.reject(); importPicker.open() }
                }
                Item { Layout.fillWidth: true }
                SiloButton {
                    text: root.importInfo.ok ? "Cancel" : "Close"
                    iconName: "fluent-dismiss-20-regular"
                    onClicked: importDialog.reject()
                }
                SiloButton {
                    id: importButton
                    visible: !!root.importInfo.ok
                    text: "Import"
                    iconName: "fluent-arrow-import-20-regular"
                    iconRight: true
                    accent: true
                    onClicked: root.runImport()
                }
            }
        }
    }
}
