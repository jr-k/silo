import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: sidebar
    property string renamingId: ""
    // Keyboard cursor in the tree (independent from the "current folder" highlight).
    property string focusedId: ""
    // Multi-selection over the visible rows: Ctrl/Cmd+click cherry-picks, Shift+click
    // ranges from `anchorId` (the last row picked without Shift).
    property var selectedIds: []
    property string anchorId: ""
    property alias switcher: workspaceSwitcher
    // Tabs of the current workspace (each workspace keeps its own live set).
    readonly property var tabsModel: tabsHub.current

    ItemDialog { id: sidebarItemDialog }
    OpenAllDialog { id: openAllDialog }
    BulkIconDialog {
        id: bulkIconDialog
        onClosed: treeFocus.forceActiveFocus()
    }
    DeleteDialog {
        id: deleteDialog
        onConfirmed: function(ids) {
            // Move the cursor to the neighbour of the first row before they disappear.
            var index = tree.count
            for (var i = 0; i < ids.length; ++i) {
                var at = appStore.treeIndexOf(ids[i])
                if (at >= 0)
                    index = Math.min(index, at)
            }
            appStore.deleteNodes(ids)
            sidebar.clearSelection()
            var count = tree.count
            sidebar.focusedId = count > 0 ? appStore.treeNodeIdAt(Math.min(index, count - 1)) : ""
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

    // An in-place rename does not survive the switch to Live mode.
    Connections {
        target: Session
        function onModeChanged() {
            if (Session.working)
                sidebar.renamingId = ""
        }
    }

    // Selection ids belong to a workspace: drop them when it changes.
    Connections {
        target: appStore
        function onCurrentWorkspaceChanged() {
            sidebar.clearSelection()
            sidebar.focusedId = ""
            sidebar.renamingId = ""
        }
    }

    // A press anywhere but on a tree row drops the selection (the rows handle their
    // own clicks). Presses in the tree's context menus are left alone: their items
    // act on the selection when triggered.
    Connections {
        target: windowEvents
        function onPressed(x, y) {
            if (sidebar.selectedIds.length === 0)
                return
            if (folderMenu.visible || itemMenu.visible || liveFolderMenu.visible || liveItemMenu.visible)
                return
            var p = tree.mapFromItem(null, x, y)
            if (p.x >= 0 && p.y >= 0 && p.x < tree.width && p.y < tree.height
                    && tree.itemAt(p.x + tree.contentX, p.y + tree.contentY))
                return
            sidebar.clearSelection()
        }
    }

    // ---- selection ------------------------------------------------------------
    function isSelected(id) {
        return selectedIds.indexOf(id) >= 0
    }

    function selectOnly(id) {
        selectedIds = [id]
        anchorId = id
        focusNode(id)
    }

    function toggleSelection(id) {
        var next = selectedIds.slice()
        var at = next.indexOf(id)
        if (at >= 0)
            next.splice(at, 1)
        else
            next.push(id)
        selectedIds = next
        anchorId = id
        focusNode(id)
    }

    // Range over the visible rows, from the anchor to `toId` (folders and their
    // unfolded children included, like a flat list).
    function selectRange(toId) {
        var to = appStore.treeIndexOf(toId)
        if (to < 0)
            return
        var from = anchorId.length > 0 ? appStore.treeIndexOf(anchorId) : -1
        if (from < 0) {
            anchorId = toId
            from = to
        }
        var lo = Math.min(from, to)
        var hi = Math.max(from, to)
        var next = []
        for (var i = lo; i <= hi; ++i)
            next.push(appStore.treeNodeIdAt(i))
        selectedIds = next
        focusNode(toId)
    }

    function selectAll() {
        var next = []
        for (var i = 0; i < tree.count; ++i)
            next.push(appStore.treeNodeIdAt(i))
        selectedIds = next
    }

    function clearSelection() {
        selectedIds = []
        anchorId = ""
    }

    // The selection, or the cursor row when nothing is selected (keyboard shortcuts).
    function targetIds() {
        if (selectedIds.length > 0)
            return selectedIds
        return focusedId.length > 0 ? [focusedId] : []
    }

    // Selected rows whose ancestors are not selected themselves: a folder brings its
    // subtree along when moved, copied or deleted, so nested picks would double up.
    function topLevelTargets() {
        var ids = targetIds()
        return ids.filter(function(id) {
            for (var parent = appStore.parentIdOf(id); parent.length > 0; parent = appStore.parentIdOf(parent)) {
                if (ids.indexOf(parent) >= 0)
                    return false
            }
            return true
        })
    }

    // Leaf items in the selection (folders have no tab to open, no icon to bulk-edit).
    readonly property var selectedItems: {
        var revision = appStore.revision
        var items = []
        for (var i = 0; i < selectedIds.length; ++i) {
            var info = appStore.nodeInfo(selectedIds[i])
            if (info.id && !info.folder)
                items.push(info)
        }
        return items
    }
    readonly property int selectedItemCount: selectedItems.length
    readonly property bool canBulkEditIcon: selectedIds.length > 1 && selectedItemCount > 0
    readonly property string bulkIconLabel: "Edit icon of " + selectedItemCount + (selectedItemCount > 1 ? " items…" : " item…")

    function editSelectionIcon() {
        if (canBulkEditIcon)
            bulkIconDialog.openFor(selectedIds)
    }

    // Delete / Backspace, context menus: confirm first. Nothing is edited from Live mode.
    function requestDelete() {
        if (Session.working)
            return
        var ids = topLevelTargets()
        if (ids.length > 0)
            deleteDialog.openFor(ids)
    }

    // Ctrl+C on the selection; Ctrl+V pastes into the focused folder (or next to a focused item).
    function copySelection() {
        if (Session.working)
            return
        var ids = topLevelTargets()
        if (ids.length > 0)
            Session.copy(ids)
    }

    function pasteAtFocused() {
        if (Session.working)
            return
        var info = focusedInfo()
        var target = info.id ? (info.folder ? info.id : appStore.parentIdOf(info.id)) : ""
        pasteInto(target)
    }

    function pasteInto(folderId) {
        var created = Session.pasteInto(folderId)
        if (created.length > 0) {
            selectedIds = created
            anchorId = created[0]
            focusNode(created[0])
        }
    }

    // ---- keyboard navigation -------------------------------------------------
    function focusNode(id) {
        focusedId = id
        treeFocus.forceActiveFocus()
        var index = appStore.treeIndexOf(id)
        if (index >= 0)
            tree.positionViewAtIndex(index, ListView.Contain)
    }

    // ↑/↓ select the neighbour row; with Shift the selection extends from the anchor.
    function moveFocus(step, extend) {
        var count = tree.count
        if (count === 0)
            return
        var index = appStore.treeIndexOf(focusedId)
        var next = index < 0 ? (step > 0 ? 0 : count - 1)
                             : Math.max(0, Math.min(count - 1, index + step))
        var id = appStore.treeNodeIdAt(next)
        if (extend)
            selectRange(id)
        else
            selectOnly(id)
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

    // Return: Live opens the selected items in tabs; Organize goes to the focused
    // folder (directory view) or opens the focused item's edit dialog.
    function activateFocused() {
        if (Session.working) {
            openSelection(focusedId)
            return
        }
        var info = focusedInfo()
        if (!info.id)
            return
        if (info.folder)
            appStore.openFolder(info.id)
        else
            sidebarItemDialog.openForEdit(info.id)
    }

    // Space: rename in place (Organize only).
    function renameFocused() {
        if (!Session.working && focusedId.length > 0)
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
            selectOnly(parentId)
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
            selectOnly(childId)
    }

    // Live only: opens every selected leaf in a tab; `preferredId` is the row that was
    // activated and becomes the current tab. `groupIds` overrides the selection (a
    // double-click on a group the first click just collapsed). With nothing to open,
    // a folder under the cursor folds / unfolds instead.
    function openSelection(preferredId, groupIds) {
        if (!Session.working)
            return
        var ids = groupIds && groupIds.length > 0 ? groupIds : targetIds()
        if (ids.length === 0 && preferredId)
            ids = [preferredId]
        var items = []
        for (var i = 0; i < ids.length; ++i) {
            var info = appStore.nodeInfo(ids[i])
            if (info.id && !info.folder)
                items.push(info)
        }
        if (items.length === 0) {
            var folder = appStore.nodeInfo(preferredId || focusedId)
            if (folder.folder)
                appStore.toggleExpanded(folder.id)
            return
        }
        var activeId = items[0].id
        for (var j = 0; j < items.length; ++j) {
            if (items[j].id === preferredId)
                activeId = preferredId
        }
        for (var k = 0; k < items.length; ++k)
            tabsModel.openTab(items[k].id, items[k].name, items[k].url, items[k].id === activeId)
    }

    // Live mode is a launcher: the tree is read-only there, so its menus only open things.
    SiloMenu {
        id: liveFolderMenu
        property string targetId: ""
        property string targetName: ""
        SiloMenuItem {
            text: "Open all items…"
            iconName: "fluent-tab-desktop-multiple-20-regular"
            onTriggered: openAllDialog.openFor(liveFolderMenu.targetId, liveFolderMenu.targetName)
        }
    }

    SiloMenu {
        id: liveItemMenu
        property string targetId: ""
        SiloMenuItem {
            text: sidebar.selectedItemCount > 1 ? "Open " + sidebar.selectedItemCount + " items in tabs" : "Open in tab"
            iconName: "fluent-window-20-regular"
            onTriggered: sidebar.openSelection(liveItemMenu.targetId)
        }
    }

    // Organize mode menus (edit, rename, copy / paste, delete…)
    SiloMenu {
        id: folderMenu
        property string targetId: ""
        property string targetName: ""
        onAboutToShow: appStore.refreshClipboardState()
        SiloMenuItem {
            text: "Open"
            iconName: "fluent-folder-open-20-regular"
            onTriggered: appStore.openFolder(folderMenu.targetId)
        }
        SiloMenuItem {
            text: "Rename"
            iconName: "fluent-rename-20-regular"
            onTriggered: sidebar.renamingId = folderMenu.targetId
        }
        FolderColorMenu {
            folderId: folderMenu.targetId
        }
        SiloMenuItem {
            visible: sidebar.canBulkEditIcon
            height: visible ? implicitHeight : 0
            text: sidebar.bulkIconLabel
            iconName: "fluent-emoji-20-regular"
            onTriggered: sidebar.editSelectionIcon()
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: sidebar.selectedIds.length > 1 ? "Copy " + sidebar.selectedIds.length + " items" : "Copy"
            iconName: "fluent-copy-20-regular"
            onTriggered: sidebar.copySelection()
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
            text: sidebar.selectedIds.length > 1 ? "Delete " + sidebar.selectedIds.length + " items" : "Delete"
            iconName: "fluent-delete-20-regular"
            destructive: true
            onTriggered: sidebar.requestDelete()
        }
    }

    SiloMenu {
        id: itemMenu
        property string targetId: ""
        SiloMenuItem {
            text: "Edit…"
            iconName: "fluent-edit-20-regular"
            onTriggered: sidebarItemDialog.openForEdit(itemMenu.targetId)
        }
        SiloMenuItem {
            visible: sidebar.canBulkEditIcon
            height: visible ? implicitHeight : 0
            text: sidebar.bulkIconLabel
            iconName: "fluent-emoji-20-regular"
            onTriggered: sidebar.editSelectionIcon()
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
            text: sidebar.selectedIds.length > 1 ? "Copy " + sidebar.selectedIds.length + " items" : "Copy"
            iconName: "fluent-copy-20-regular"
            onTriggered: sidebar.copySelection()
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: sidebar.selectedIds.length > 1 ? "Delete " + sidebar.selectedIds.length + " items" : "Delete"
            iconName: "fluent-delete-20-regular"
            destructive: true
            onTriggered: sidebar.requestDelete()
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

            // Keyboard: ↑/↓ select (Shift extends), Tab toggles a folder, ⏎ activates,
            // Space renames, ←/→ fold/unfold, Delete removes, Ctrl+A/C/V.
            Keys.onUpPressed: function(event) { sidebar.moveFocus(-1, (event.modifiers & Qt.ShiftModifier) !== 0) }
            Keys.onDownPressed: function(event) { sidebar.moveFocus(1, (event.modifiers & Qt.ShiftModifier) !== 0) }
            Keys.onTabPressed: sidebar.toggleFocused()
            Keys.onBacktabPressed: sidebar.toggleFocused()
            Keys.onReturnPressed: sidebar.activateFocused()
            Keys.onEnterPressed: sidebar.activateFocused()
            Keys.onSpacePressed: sidebar.renameFocused()
            Keys.onDeletePressed: sidebar.requestDelete()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Backspace) {
                    sidebar.requestDelete()
                    event.accepted = true
                } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                    sidebar.selectAll()
                    event.accepted = true
                } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                    sidebar.copySelection()
                    event.accepted = true
                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                    sidebar.pasteAtFocused()
                    event.accepted = true
                }
            }
            Keys.onLeftPressed: sidebar.collapseOrParent()
            Keys.onRightPressed: sidebar.expandOrChild()
            Keys.onEscapePressed: {
                sidebar.clearSelection()
                sidebar.focusedId = ""
            }

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
                readonly property bool selected: sidebar.isSelected(nodeId)
                readonly property bool focused: sidebar.focusedId === nodeId && treeFocus.activeFocus
                // Live mode: the tree order drives the tab order, so no drag reordering from here.
                readonly property bool canDrag: !editing && !Session.working

                // Drop zone under the pointer: "before" / "after" reorder among the siblings,
                // "into" (middle of a folder) moves into it. Dropping right after an
                // expanded folder puts the nodes at the top of its children.
                readonly property string dropZone: rowDrop.containsDrag ? zoneAt(rowDrop.drag.y) : ""
                readonly property bool dropAsFirstChild: dropZone === "after" && isFolder && isExpanded && hasChildren
                function zoneAt(y) {
                    var pos = y / height
                    if (isFolder)
                        return pos < 0.25 ? "before" : pos > 0.75 ? "after" : "into"
                    return pos < 0.5 ? "before" : "after"
                }
                function dropAt(y) {
                    var zone = zoneAt(y)
                    if (zone === "into")
                        appStore.moveNodes(DragState.ids, nodeId)
                    else if (zone === "after" && isFolder && isExpanded && hasChildren)
                        appStore.insertNodes(DragState.ids, nodeId, appStore.treeNodeIdAt(index + 1))
                    else
                        appStore.moveNodesRelative(DragState.ids, nodeId, zone === "after")
                }

                // Multi-selection this row belonged to when it was last plain-clicked. The
                // click collapses the group right away; a double-click (whose first tap is
                // that click) can still open the whole group in Live mode.
                property var groupBeforeClick: []

                // Plain click: select just this row (folders also navigate in Organize mode).
                function click() {
                    groupBeforeClick = selected && sidebar.selectedIds.length > 1 ? sidebar.selectedIds : []
                    sidebar.selectOnly(nodeId)
                    if (!Session.working && isFolder)
                        appStore.openFolder(nodeId)
                }

                // Double-click: Live opens the selected items in tabs, Organize opens the item's
                // edit dialog; folders fold / unfold.
                function open() {
                    var group = groupBeforeClick
                    groupBeforeClick = []
                    if (Session.working)
                        sidebar.openSelection(nodeId, group)
                    else if (isFolder) {
                        if (hasChildren)
                            appStore.toggleExpanded(nodeId)
                    } else {
                        sidebarItemDialog.openForEdit(nodeId)
                    }
                }

                width: tree.width
                height: 32

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    color: row.dropZone === "into" ? Theme.dropTarget
                         : row.selected ? (rowHover.hovered ? Theme.selectionHover : Theme.selection)
                         : row.isCurrent ? Theme.selection
                         : rowHover.hovered || row.focused ? Theme.hover : "transparent"
                    border.width: row.selected || row.focused ? 1 : 0
                    border.color: row.focused ? Theme.accent : Theme.selectionBorder
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
                    onSingleTapped: row.click()
                    onDoubleTapped: row.open()
                }

                // Ctrl (Cmd on macOS) + click: cherry-pick the row in / out of the selection.
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.ControlModifier
                    enabled: !row.editing
                    onSingleTapped: sidebar.toggleSelection(row.nodeId)
                }

                // Shift + click: select the range from the anchor row.
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.ShiftModifier
                    enabled: !row.editing
                    onSingleTapped: sidebar.selectRange(row.nodeId)
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        if (row.selected)
                            sidebar.focusNode(row.nodeId)
                        else
                            sidebar.selectOnly(row.nodeId)
                        var menu = row.isFolder ? (Session.working ? liveFolderMenu : folderMenu)
                                                : (Session.working ? liveItemMenu : itemMenu)
                        menu.targetId = row.nodeId
                        if (row.isFolder)
                            menu.targetName = row.nodeName
                        menu.popup()
                    }
                }

                // Dragging a selected row carries the whole selection along.
                DragHandler {
                    id: rowDrag
                    target: null
                    enabled: row.canDrag
                    onActiveChanged: {
                        if (active) {
                            if (!row.selected)
                                sidebar.selectOnly(row.nodeId)
                            DragState.begin(sidebar.topLevelTargets(), row.nodeName, row.nodeKind, centroid.scenePosition)
                        } else {
                            DragState.finish()
                        }
                    }
                    onCentroidChanged: if (active) DragState.update(centroid.scenePosition)
                }

                // Insertion mark for a reorder drop: a line between the rows, indented to
                // the level the nodes will land at.
                Item {
                    visible: row.dropZone === "before" || row.dropZone === "after"
                    z: 3
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8 + (row.depth + (row.dropAsFirstChild ? 1 : 0)) * 16 + 4
                    anchors.rightMargin: 8
                    height: 2
                    y: row.dropZone === "before" ? -1 : row.height - 1
                    Rectangle {
                        anchors.fill: parent
                        radius: 1
                        color: Theme.accent
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: -3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: Theme.accent
                    }
                }

                // Every row accepts drops (Organize only): edges reorder among the siblings,
                // the middle of a folder moves into it.
                DropArea {
                    id: rowDrop
                    anchors.fill: parent
                    enabled: DragState.active && !Session.working && !DragState.contains(row.nodeId)
                    onDropped: function(drop) { row.dropAt(drop.y) }
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
