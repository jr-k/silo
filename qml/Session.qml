pragma Singleton
import QtQuick

// UI session state shared across views. Mode and sidebar visibility are
// restored from session.json (tabs are handled by TabsModel) so the Live
// layout survives a restart.
QtObject {
    // "setup" (Organize): arrange folders and items. "working" (Live): browse items in tabs.
    property string mode: sessionStore.value("mode", "setup") === "working" ? "working" : "setup"
    readonly property bool working: mode === "working"
    onModeChanged: sessionStore.setValue("mode", mode)

    function setMode(next) {
        if (next === "setup" || next === "working")
            mode = next
    }

    function toggle() {
        mode = working ? "setup" : "working"
    }

    // Left sidebar (tree) visibility.
    property bool sidebarVisible: sessionStore.value("sidebarVisible", true) === true
    onSidebarVisibleChanged: sessionStore.setValue("sidebarVisible", sidebarVisible)

    function toggleSidebar() {
        sidebarVisible = !sidebarVisible
    }

    // Organize directory layout: "grid" (tiles) or "list" (details rows).
    property string dirViewMode: sessionStore.value("dirViewMode", "grid") === "list" ? "list" : "grid"
    readonly property bool dirListMode: dirViewMode === "list"
    onDirViewModeChanged: sessionStore.setValue("dirViewMode", dirViewMode)

    function toggleDirViewMode() {
        dirViewMode = dirListMode ? "grid" : "list"
    }

    // Opens the settings dialog (owned by the sidebar's cog button) on a section.
    signal settingsRequested(string section)
    function openSettings(section) {
        settingsRequested(section || "general")
    }

    // Folders / items go through the system clipboard as JSON (see AppStore::copyToClipboard),
    // so they paste across workspaces, across Silo instances, or from a hand-written payload.
    readonly property bool canPaste: appStore.clipboardHasNodes

    function copy(ids) {
        if (ids && ids.length > 0)
            appStore.copyToClipboard(ids)
    }

    // Deep-copies the clipboard into the folder (empty id = workspace root); returns the new
    // ids. Reads the clipboard directly: canPaste may lag behind an external change.
    function pasteInto(folderId) {
        return appStore.pasteFromClipboard(folderId)
    }
}
