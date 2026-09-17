import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1200
    height: 760
    minimumWidth: 940
    minimumHeight: 600
    visible: true
    title: "Silo"
    color: Theme.windowBg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    // Keep stock Qt Quick Controls (scrollbars, tooltips, separators…) on-theme.
    palette {
        window: Theme.windowBg
        windowText: Theme.text
        base: Theme.surface
        alternateBase: Theme.surfaceAlt
        text: Theme.text
        button: Theme.controlBg
        buttonText: Theme.text
        highlight: Theme.accent
        highlightedText: Theme.textOnAccent
        accent: Theme.accent
        light: Theme.surfaceAlt
        midlight: Theme.border
        mid: Theme.borderStrong
        dark: Theme.textTertiary
        shadow: Theme.overlay
        placeholderText: Theme.textTertiary
        toolTipBase: Theme.surface
        toolTipText: Theme.text
        disabled {
            text: Theme.textDisabled
            buttonText: Theme.textDisabled
            windowText: Theme.textDisabled
        }
    }

    // Sidebar slides in/out (Ctrl/⌘+B or the panel button in the views).
    readonly property real sidebarWidth: Session.sidebarVisible ? 264 : 0
    property real animatedSidebarWidth: sidebarWidth
    Behavior on animatedSidebarWidth {
        NumberAnimation { duration: Theme.animationNormal; easing.type: Easing.OutCubic }
    }

    Shortcut {
        sequences: ["Ctrl+B"]
        onActivated: Session.toggleSidebar()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // The slot shrinks while the sidebar keeps its natural width and slides out to the left.
        Item {
            visible: window.animatedSidebarWidth > 0
            clip: true
            Layout.preferredWidth: window.animatedSidebarWidth
            Layout.minimumWidth: window.animatedSidebarWidth
            Layout.maximumWidth: window.animatedSidebarWidth
            Layout.fillHeight: true

            Sidebar {
                id: sidebar
                width: window.sidebarWidth > 0 ? window.sidebarWidth : 264
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }
        }

        DirectoryView {
            id: directory
            visible: !Session.working
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        WorkingView {
            id: working
            visible: Session.working
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    // Global drag proxy: follows the pointer and delivers drop events to DropAreas.
    Item {
        id: dragProxy
        x: DragState.x
        y: DragState.y
        width: 1
        height: 1
        z: 1000
        visible: DragState.active
        Drag.active: DragState.active
        Drag.hotSpot.x: 0
        Drag.hotSpot.y: 0
        Drag.source: dragProxy

        function drop() {
            return Drag.drop()
        }

        Component.onCompleted: DragState.proxy = dragProxy

        Rectangle {
            x: 16
            y: 12
            width: ghostRow.implicitWidth + 24
            height: 34
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.borderStrong
            opacity: 0.96

            Row {
                id: ghostRow
                anchors.centerIn: parent
                spacing: 8
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 18
                    name: DragState.kind === "folder" ? "fluent-folder-20-filled" : "fluent-globe-20-regular"
                    color: DragState.kind === "folder" ? Theme.folder : Theme.link
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: DragState.count > 1 ? DragState.count + " items" : DragState.label
                    color: Theme.text
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.Medium
                }
            }
        }
    }
}
