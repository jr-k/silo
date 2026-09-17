import QtQuick

// Hide / show the left sidebar (Ctrl/⌘+B).
IconButton {
    iconName: Session.sidebarVisible ? "fluent-panel-left-contract-20-regular"
                                     : "fluent-panel-left-expand-20-regular"
    iconSize: 18
    tooltip: (Session.sidebarVisible ? "Hide sidebar" : "Show sidebar")
             + " (" + (Qt.platform.os === "osx" ? "⌘" : "Ctrl+") + "B)"
    onClicked: Session.toggleSidebar()
}
