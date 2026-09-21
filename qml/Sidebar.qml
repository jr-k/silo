import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: sidebar
    property string renamingId: ""
    // Keyboard focus in the tree (independent from the "current folder" highlight).
    property string focusedId: ""
    property alias switcher: workspaceSwitcher
    // Tabs of the current workspace (each workspace keeps its own live set).
    readonly property var tabsModel: tabsHub.current

    ItemDialog { id: sidebarItemDialog }
    OpenAllDialog { id: openAllDialog }
    DeleteDialog {
        id: deleteDialog
        onConfirmed: function(ids) {
            // Move keyboard focus to the neighbour before the row disappears.
            var index = appStore.treeIndexOf(ids[0])
            appStore.deleteNodes(ids)
            var count = tree.count
            var nextId = count > 0 ? appStore.treeNodeIdAt(Math.min(index, count - 1)) : ""
            sidebar.focusedId = nextId
        }
        // Refocus once the popup is fully closed, otherwise its exit transition steals focus back.
        onClosed: treeFocus.forceActiveFocus()
    }
    function openAllDialogFor(id, name) {
        openAllDialog.openFor(id, name)
    }

    // Workspace transfer (menus, and callable from anywhere holding the sidebar)
    function exportWorkspace(id) { workspaceSwitcher.exportWorkspace(id) }
    function importWorkspace() { workspaceSwitcher.importWorkspace() }

    // Delete / Backspace, context menus: confirm first.
    function requestDelete(id) {
        if (id && id.length > 0)
            deleteDialog.openFor([id])
    }

    // Ctrl+C on the focused row; Ctrl+V pastes into the focused folder (or next to a focused item).
    function copyFocused() {
        if (focusedId.length > 0)
            Session.copy([focusedId])
    }

    function pasteAtFocused() {
        var info = focusedInfo()
        var target = info.id ? (info.folder ? info.id : appStore.parentIdOf(info.id)) : ""
        pasteInto(target)
    }

    function pasteInto(folderId) {
        var created = Session.pasteInto(folderId)
        if (created.length > 0)
            focusNode(created[0])
    }

    // ---- keyboard navigation -------------------------------------------------
    function focusNode(id) {
        focusedId = id
        treeFocus.forceActiveFocus()
        var index = appStore.treeIndexOf(id)
        if (index >= 0)
            tree.positionViewAtIndex(index, ListView.Contain)
    }

    function moveFocus(step) {
        var count = tree.count
        if (count === 0)
            return
        var index = appStore.treeIndexOf(focusedId)
        var next = index < 0 ? (step > 0 ? 0 : count - 1)
                             : Math.max(0, Math.min(count - 1, index + step))
        focusNode(appStore.treeNodeIdAt(next))
    }

    function focusedInfo() {
        return focusedId.length > 0 ? appStore.nodeInfo(focusedId) : ({})
    }

    // Tab: fold / unfold the focused folder.
    function toggleFocused() {
        var info = focusedInfo()
        if (info.folder)
            appStore.toggleExpanded(info.id)
    }

    // Return: folders go to the directory view (Organize) or toggle (Live);
    // items open the edit dialog (Organize) or a tab (Live).
    function activateFocused() {
        var info = focusedInfo()
        if (!info.id)
            return
        if (info.folder) {
            if (Session.working)
                appStore.toggleExpanded(info.id)
            else
                appStore.openFolder(info.id)
        } else if (Session.working) {
            tabsModel.openTab(info.id, info.name, info.url, true)
        } else {
            sidebarItemDialog.openForEdit(info.id)
        }
    }

    // Space: rename in place.
    function renameFocused() {
        if (focusedId.length > 0)
            renamingId = focusedId
    }

    // Left: collapse, or jump to the parent when already collapsed / on an item.
    function collapseOrParent() {
        var info = focusedInfo()
        if (!info.id)
            return
        if (info.folder && appStore.isExpanded(info.id)) {
            appStore.toggleExpanded(info.id)
            return
        }
        var parentId = appStore.parentIdOf(info.id)
        if (parentId.length > 0)
            focusNode(parentId)
    }

    // Right: expand, or step into the first child when already expanded.
    function expandOrChild() {
        var info = focusedInfo()
        if (!info.folder)
            return
        if (!appStore.isExpanded(info.id)) {
            appStore.toggleExpanded(info.id)
            return
        }
        var index = appStore.treeIndexOf(info.id)
        var childId = appStore.treeNodeIdAt(index + 1)
        if (childId.length > 0 && appStore.parentIdOf(childId) === info.id)
            focusNode(childId)
    }

    // Open a leaf in a tab (switching to Live mode).
    function openItemInTab(id, name, url, activate) {
        Session.setMode("working")
        tabsModel.openTab(id, name, url, activate === undefined ? true : activate)
    }

    // Ctrl/Cmd+click on a folder: open its direct items, no questions asked.
    function openFolderDirect(id) {
        var items = appStore.collectItems(id, false)
        if (items.length === 0)
            return
        Session.setMode("working")
        for (var i = 0; i < items.length; ++i)
            tabsModel.openTab(items[i].id, items[i].name, items[i].url, i === 0)
    }

    SiloMenu {
        id: folderMenu
        property string targetId: ""
        property string targetName: ""
        SiloMenuItem {
            text: "Open"
            iconName: "fluent-folder-open-20-regular"
            visible: !Session.working
            height: visible ? implicitHeight : 0
            onTriggered: appStore.openFolder(folderMenu.targetId)
        }
        SiloMenuItem {
            text: "Open all items…"
            iconName: "fluent-tab-desktop-multiple-20-regular"
            onTriggered: openAllDialog.openFor(folderMenu.targetId, folderMenu.targetName)
        }
        SiloMenuItem {
            text: "Rename"
            iconName: "fluent-rename-20-regular"
            onTriggered: sidebar.renamingId = folderMenu.targetId
        }
        FolderColorMenu {
            folderId: folderMenu.targetId
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: "Copy"
            iconName: "fluent-copy-20-regular"
            onTriggered: Session.copy([folderMenu.targetId])
        }
        SiloMenuItem {
            text: "Paste into folder"
            iconName: "fluent-clipboard-paste-20-regular"
            enabled: Session.canPaste
            onTriggered: sidebar.pasteInto(folderMenu.targetId)
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: "Delete"
            iconName: "fluent-delete-20-regular"
            destructive: true
            onTriggered: sidebar.requestDelete(folderMenu.targetId)
        }
    }

    SiloMenu {
        id: itemMenu
        property string targetId: ""
        property string targetName: ""
        property string targetUrl: ""
        SiloMenuItem {
            text: "Open in tab"
            iconName: "fluent-window-20-regular"
            onTriggered: sidebar.openItemInTab(itemMenu.targetId, itemMenu.targetName, itemMenu.targetUrl)
        }
        SiloMenuItem {
            text: "Edit…"
            iconName: "fluent-edit-20-regular"
            onTriggered: sidebarItemDialog.openForEdit(itemMenu.targetId)
        }
        SiloMenuItem {
            text: "Rename"
            iconName: "fluent-rename-20-regular"
            onTriggered: sidebar.renamingId = itemMenu.targetId
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: "Copy"
            iconName: "fluent-copy-20-regular"
            onTriggered: Session.copy([itemMenu.targetId])
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: "Delete"
            iconName: "fluent-delete-20-regular"
            destructive: true
            onTriggered: sidebar.requestDelete(itemMenu.targetId)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        WorkspaceSwitcher {
            id: workspaceSwitcher
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 12
            Layout.bottomMargin: 10
        }

        // "All items" (workspace root) — Organize mode only
        Rectangle {
            id: homeRow
            visible: !Session.working
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.preferredHeight: 34
            radius: Theme.radiusSmall
            readonly property bool isCurrent: appStore.currentFolderId === ""
            color: homeDrop.containsDrag ? Theme.dropTarget
                 : isCurrent ? Theme.selection
                 : homeHover.hovered ? Theme.hover : "transparent"

            Rectangle {
                visible: homeRow.isCurrent
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 16
                radius: 1.5
                color: Theme.accent
            }

            HoverHandler { id: homeHover }
            TapHandler { onTapped: appStore.openFolder("") }

            Icon {
                id: homeIcon
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "fluent-home-20-regular"
                size: 18
                color: Theme.text
            }
            Text {
                anchors.left: homeIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "All items"
                color: Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: homeRow.isCurrent ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            DropArea {
                id: homeDrop
                anchors.fill: parent
                enabled: DragState.active
                onDropped: appStore.moveNodes(DragState.ids, "")
            }
        }

        Text {
            Layout.leftMargin: 20
            Layout.topMargin: Session.working ? 6 : 16
            Layout.bottomMargin: 6
            text: Session.working ? "ITEMS" : "FOLDERS"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
        }

        // Plain Item holding keyboard focus: a ListView would hand focus to its
        // currentItem and lose it whenever the tree model is rebuilt.
        Item {
            id: treeFocus
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 8
            activeFocusOnTab: false

            // Keyboard: ↑/↓ move, Tab toggles a folder, ⏎ activates, Space renames, ←/→ fold/unfold.
            Keys.onUpPressed: sidebar.moveFocus(-1)
            Keys.onDownPressed: sidebar.moveFocus(1)
            Keys.onTabPressed: sidebar.toggleFocused()
            Keys.onBacktabPressed: sidebar.toggleFocused()
            Keys.onReturnPressed: sidebar.activateFocused()
            Keys.onEnterPressed: sidebar.activateFocused()
            Keys.onSpacePressed: sidebar.renameFocused()
            Keys.onDeletePressed: sidebar.requestDelete(sidebar.focusedId)
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Backspace) {
                    sidebar.requestDelete(sidebar.focusedId)
                    event.accepted = true
                } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                    sidebar.copyFocused()
                    event.accepted = true
                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                    sidebar.pasteAtFocused()
                    event.accepted = true
                }
            }
            Keys.onLeftPressed: sidebar.collapseOrParent()
            Keys.onRightPressed: sidebar.expandOrChild()
            Keys.onEscapePressed: sidebar.focusedId = ""

        ListView {
            id: tree
            anchors.fill: parent
            clip: true
            model: appStore.treeModel
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            activeFocusOnTab: false
            keyNavigationEnabled: false
            currentIndex: -1

            delegate: Item {
                id: row
                required property int index
                required property string nodeId
                required property string nodeName
                required property string nodeKind
                required property string nodeUrl
                required property string nodeType
                required property int depth
                required property bool isExpanded
                required property bool hasChildren
                required property string nodeIconType
                required property string nodeIconValue
                required property string nodeColor

                readonly property bool isFolder: nodeKind === "folder"
                readonly property bool hasCustomIcon: !isFolder && nodeIconType.length > 0
                readonly property bool isCurrent: Session.working
                                                  ? (!isFolder && !!tabsModel && tabsModel.currentNodeId === nodeId)
                                                  : appStore.currentFolderId === nodeId
                // Depends on tabsModel.count so it re-evaluates when tabs open/close.
                readonly property bool isOpenTab: Session.working && !isFolder && !!tabsModel
                                                  && tabsModel.count > 0 && tabsModel.indexOfNode(nodeId) >= 0
                readonly property bool editing: sidebar.renamingId === nodeId
                readonly property bool focused: sidebar.focusedId === nodeId && treeFocus.activeFocus

                // Click: focus the row; folders also navigate (Organize) or toggle (Live),
                // items open a tab in Live mode.
                function activate() {
                    sidebar.focusNode(nodeId)
                    if (Session.working) {
                        if (isFolder)
                            appStore.toggleExpanded(nodeId)
                        else
                            tabsModel.openTab(nodeId, nodeName, nodeUrl, true)
                    } else if (isFolder) {
                        appStore.openFolder(nodeId)
                    }
                }

                width: tree.width
                height: 32

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    color: rowDrop.containsDrag ? Theme.dropTarget
                         : row.isCurrent ? Theme.selection
                         : rowHover.hovered || row.focused ? Theme.hover : "transparent"
                    border.width: row.focused ? 1 : 0
                    border.color: Theme.accent
                    opacity: DragState.active && DragState.contains(row.nodeId) ? 0.5 : 1
                }

                Rectangle {
                    visible: row.isCurrent
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 16
                    radius: 1.5
                    color: Theme.accent
                }

                HoverHandler { id: rowHover }

                Item {
                    id: rowContent
                    anchors.fill: parent
                    anchors.leftMargin: 8 + row.depth * 16
                    anchors.rightMargin: 8

                    IconButton {
                        id: chevron
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        iconName: row.isExpanded ? "fluent-chevron-down-12-regular" : "fluent-chevron-right-12-regular"
                        iconSize: 12
                        iconColor: Theme.textSecondary
                        opacity: row.isFolder && row.hasChildren ? 1 : 0
                        enabled: row.isFolder && row.hasChildren
                        onClicked: appStore.toggleExpanded(row.nodeId)
                    }

                    Item {
                        id: rowIcon
                        anchors.left: chevron.right
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        Icon {
                            anchors.fill: parent
                            visible: row.isFolder
                            size: 18
                            name: row.isExpanded ? "fluent-folder-open-20-filled" : "fluent-folder-20-filled"
                            color: row.nodeColor.length > 0 ? row.nodeColor : Theme.folder
                        }
                        ItemIcon {
                            anchors.fill: parent
                            visible: !row.isFolder && !row.hasCustomIcon
                            size: 18
                            type: row.nodeType
                            url: row.nodeUrl
                        }
                        Badge {
                            anchors.fill: parent
                            visible: row.hasCustomIcon
                            size: 18
                            color: row.nodeColor.length > 0 ? row.nodeColor : Theme.link
                            iconType: row.nodeIconType
                            iconValue: row.nodeIconValue
                        }
                    }

                    Text {
                        visible: !row.editing
                        anchors.left: rowIcon.right
                        anchors.leftMargin: 8
                        anchors.right: openDot.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.nodeName
                        color: Theme.text
                        font.pixelSize: Theme.fontSize
                        font.weight: row.isCurrent ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }

                    // Live mode: marks items that are open in a tab
                    Rectangle {
                        id: openDot
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: row.isOpenTab ? 6 : 0
                        height: 6
                        radius: 3
                        visible: row.isOpenTab
                        color: row.isCurrent ? Theme.accent : Theme.textTertiary
                    }

                    SiloTextField {
                        id: renameField
                        visible: row.editing
                        anchors.left: rowIcon.right
                        anchors.leftMargin: 6
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        leftPadding: 6
                        rightPadding: 6
                        font.pixelSize: Theme.fontSize

                        // renameNode resets the tree model (this row is destroyed),
                        // so capture state and leave edit mode before calling it.
                        function commit() {
                            if (!row.editing)
                                return
                            var id = row.nodeId
                            var value = text
                            sidebar.renamingId = ""
                            appStore.renameNode(id, value)
                            sidebar.focusNode(id)
                        }

                        function cancel() {
                            var id = row.nodeId
                            sidebar.renamingId = ""
                            sidebar.focusNode(id)
                        }

                        function startEditing() {
                            text = row.nodeName
                            forceActiveFocus()
                            select(text.length, 0)
                        }

                        Keys.onReturnPressed: commit()
                        Keys.onEnterPressed: commit()
                        Keys.onEscapePressed: cancel()
                        // Focus moved elsewhere in the window: commit. Window deactivation keeps editing.
                        onActiveFocusChanged: if (!activeFocus && Window.active) commit()
                        onVisibleChanged: if (visible) startEditing()
                        Component.onCompleted: if (visible) startEditing()
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.NoModifier
                    enabled: !row.editing
                    onTapped: row.activate()
                    onDoubleTapped: if (!Session.working && row.isFolder && row.hasChildren) appStore.toggleExpanded(row.nodeId)
                }

                // Ctrl (Cmd on macOS) + click: open every item of the folder / open item in a background tab.
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.ControlModifier
                    enabled: !row.editing
                    onTapped: {
                        if (row.isFolder)
                            sidebar.openFolderDirect(row.nodeId)
                        else
                            sidebar.openItemInTab(row.nodeId, row.nodeName, row.nodeUrl, false)
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        sidebar.focusNode(row.nodeId)
                        if (row.isFolder) {
                            folderMenu.targetId = row.nodeId
                            folderMenu.targetName = row.nodeName
                            folderMenu.popup()
                        } else {
                            itemMenu.targetId = row.nodeId
                            itemMenu.targetName = row.nodeName
                            itemMenu.targetUrl = row.nodeUrl
                            itemMenu.popup()
                        }
                    }
                }

                DragHandler {
                    id: rowDrag
                    target: null
                    enabled: !row.editing
                    onActiveChanged: {
                        if (active)
                            DragState.begin([row.nodeId], row.nodeName, row.nodeKind, centroid.scenePosition)
                        else
                            DragState.finish()
                    }
                    onCentroidChanged: if (active) DragState.update(centroid.scenePosition)
                }

                DropArea {
                    id: rowDrop
                    anchors.fill: parent
                    enabled: row.isFolder && DragState.active && !DragState.contains(row.nodeId)
                    onDropped: appStore.moveNodes(DragState.ids, row.nodeId)
                }
            }
        }
        }

        // ---------------------------------------------------------------- footer
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            implicitHeight: 1
            color: Theme.divider
        }

        // Organize / Live switch + settings
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            spacing: 6
            SettingsButton { Layout.alignment: Qt.AlignVCenter }
            ModeSwitch { Layout.fillWidth: true }
        }
    }
}
