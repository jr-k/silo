import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    focus: true

    property var selectedIds: []
    property string renamingId: ""
    property int anchorIndex: -1

    property bool marqueeActive: false
    property point marqueeStart: Qt.point(0, 0)
    property rect marqueeRect: Qt.rect(0, 0, 0, 0)
    property var marqueeBase: []

    readonly property int columns: Math.max(1, Math.floor(grid.width / grid.cellWidth))
    // Inside a sub-folder the model prepends a virtual ".." tile; item indices skip it.
    readonly property int gridOffset: appStore.currentFolderId !== "" ? 1 : 0
    readonly property int itemCount: Math.max(0, grid.count - gridOffset)

    function isSelected(id) {
        return selectedIds.indexOf(id) >= 0
    }

    function selectOnly(id, index) {
        selectedIds = [id]
        anchorIndex = index
    }

    function toggleSelection(id, index) {
        var next = selectedIds.slice()
        var at = next.indexOf(id)
        if (at >= 0)
            next.splice(at, 1)
        else
            next.push(id)
        selectedIds = next
        anchorIndex = index
    }

    function selectRange(toIndex) {
        var ids = appStore.currentChildIds()
        var from = anchorIndex < 0 ? toIndex : anchorIndex
        var lo = Math.min(from, toIndex)
        var hi = Math.max(from, toIndex)
        var next = []
        for (var i = lo; i <= hi && i < ids.length; ++i)
            next.push(ids[i])
        selectedIds = next
    }

    function selectAll() {
        selectedIds = appStore.currentChildIds()
    }

    // Clipboard: copy the selection, paste into the current folder (folders are copied with their subtree).
    function copySelection() {
        Session.copy(selectedIds)
    }

    function pasteHere() {
        var created = Session.pasteInto(appStore.currentFolderId)
        if (created.length > 0) {
            selectedIds = created
            anchorIndex = appStore.currentChildIds().indexOf(created[0])
        }
    }

    function clearSelection() {
        selectedIds = []
        anchorIndex = -1
    }

    function openNewItem(type) {
        itemDialog.openForCreate(type || "web")
    }

    function openNewItemMenu() {
        newItemMenu.popup(newItemButton, 0, newItemButton.height + 4)
    }

    function beginRename(id) {
        selectedIds = [id]
        renamingId = id
    }

    function endRename() {
        renamingId = ""
        root.forceActiveFocus()
    }

    // Asks for confirmation first (Delete / Backspace, command bar, context menus).
    function deleteSelection() {
        if (selectedIds.length === 0)
            return
        deleteDialog.openFor(selectedIds)
    }

    DeleteDialog {
        id: deleteDialog
        onConfirmed: function(ids) {
            appStore.deleteNodes(ids)
            root.clearSelection()
        }
        onClosed: root.forceActiveFocus()
    }

    function moveFocusBy(step) {
        var ids = appStore.currentChildIds()
        if (ids.length === 0)
            return
        var current = anchorIndex
        if (selectedIds.length === 1)
            current = ids.indexOf(selectedIds[0])
        var next = current < 0 ? 0 : Math.max(0, Math.min(ids.length - 1, current + step))
        selectOnly(ids[next], next)
        grid.positionViewAtIndex(next + gridOffset, GridView.Contain)
    }

    Keys.onPressed: function(event) {
        if (renamingId.length > 0)
            return
        if (event.key === Qt.Key_Space) {
            if (selectedIds.length === 1)
                renamingId = selectedIds[0]
            event.accepted = true
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            deleteSelection()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            clearSelection()
            event.accepted = true
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            selectAll()
            event.accepted = true
        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            copySelection()
            event.accepted = true
        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
            pasteHere()
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            moveFocusBy(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            moveFocusBy(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            moveFocusBy(-columns)
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            moveFocusBy(columns)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (selectedIds.length === 1) {
                var item = grid.itemAtIndex(appStore.currentChildIds().indexOf(selectedIds[0]) + gridOffset)
                if (item && item.isFolder)
                    appStore.openFolder(item.nodeId)
            }
            event.accepted = true
        }
    }

    Connections {
        target: appStore
        function onCurrentFolderChanged() {
            root.clearSelection()
            root.renamingId = ""
        }
        function onCurrentWorkspaceChanged() {
            root.clearSelection()
            root.renamingId = ""
        }
    }

    ItemDialog { id: itemDialog }

    // Context menus (single instances, retargeted per tile)
    SiloMenu {
        id: folderTileMenu
        property string targetId: ""
        SiloMenuItem {
            text: "Open"
            iconName: "fluent-folder-open-20-regular"
            onTriggered: appStore.openFolder(folderTileMenu.targetId)
        }
        SiloMenuItem {
            text: "Rename"
            iconName: "fluent-rename-20-regular"
            onTriggered: root.beginRename(folderTileMenu.targetId)
        }
        FolderColorMenu {
            folderId: folderTileMenu.targetId
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: root.selectedIds.length > 1 ? "Copy " + root.selectedIds.length + " items" : "Copy"
            iconName: "fluent-copy-20-regular"
            onTriggered: root.copySelection()
        }
        SiloMenuItem {
            text: "Paste into folder"
            iconName: "fluent-clipboard-paste-20-regular"
            enabled: Session.canPaste
            onTriggered: Session.pasteInto(folderTileMenu.targetId)
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: root.selectedIds.length > 1 ? "Delete " + root.selectedIds.length + " items" : "Delete"
            iconName: "fluent-delete-20-regular"
            destructive: true
            onTriggered: root.deleteSelection()
        }
    }

    SiloMenu {
        id: itemTileMenu
        property string targetId: ""
        property string targetName: ""
        property string targetUrl: ""
        SiloMenuItem {
            text: "Edit…"
            iconName: "fluent-edit-20-regular"
            onTriggered: itemDialog.openForEdit(itemTileMenu.targetId)
        }
        SiloMenuItem {
            text: "Rename"
            iconName: "fluent-rename-20-regular"
            onTriggered: root.beginRename(itemTileMenu.targetId)
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: root.selectedIds.length > 1 ? "Copy " + root.selectedIds.length + " items" : "Copy"
            iconName: "fluent-copy-20-regular"
            onTriggered: root.copySelection()
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: root.selectedIds.length > 1 ? "Delete " + root.selectedIds.length + " items" : "Delete"
            iconName: "fluent-delete-20-regular"
            destructive: true
            onTriggered: root.deleteSelection()
        }
    }

    SiloMenu {
        id: parentTileMenu
        SiloMenuItem {
            text: "Go to parent folder"
            iconName: "fluent-arrow-up-20-regular"
            onTriggered: appStore.openParentFolder()
        }
        SiloMenuItem {
            text: root.selectedIds.length > 1 ? "Move " + root.selectedIds.length + " items here" : "Move selection here"
            iconName: "fluent-folder-arrow-up-24-filled"
            enabled: root.selectedIds.length > 0
            onTriggered: {
                appStore.moveNodes(root.selectedIds, appStore.parentIdOf(appStore.currentFolderId))
                root.clearSelection()
            }
        }
    }

    // Item type chooser shown by the "New item" command
    SiloMenu {
        id: newItemMenu
        Repeater {
            model: ItemTypes.all
            SiloMenuItem {
                required property string modelData
                text: ItemTypes.label(modelData)
                iconName: ItemTypes.glyph(modelData, "", "20")
                iconColor: ItemTypes.color(modelData)
                onTriggered: root.openNewItem(modelData)
            }
        }
    }

    SiloMenu {
        id: backgroundMenu
        Repeater {
            model: ItemTypes.all
            SiloMenuItem {
                required property string modelData
                text: "New " + ItemTypes.noun(modelData)
                iconName: ItemTypes.glyph(modelData, "", "20")
                iconColor: ItemTypes.color(modelData)
                onTriggered: root.openNewItem(modelData)
            }
        }
        SiloMenuItem {
            text: "New folder"
            iconName: "fluent-folder-add-20-regular"
            onTriggered: root.beginRename(appStore.addFolder("New folder"))
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: "Paste"
            iconName: "fluent-clipboard-paste-20-regular"
            enabled: Session.canPaste
            onTriggered: root.pasteHere()
        }
        SiloMenuItem {
            text: "Select all"
            iconName: "fluent-select-all-on-20-regular"
            enabled: root.itemCount > 0
            onTriggered: root.selectAll()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: 12
        anchors.leftMargin: Session.sidebarVisible ? 4 : 12
        spacing: 8

        // Address bar
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 4

            SidebarToggle {}

            IconButton {
                iconName: "fluent-arrow-up-20-regular"
                iconSize: 18
                tooltip: "Up"
                enabled: appStore.currentFolderId !== ""
                onClicked: appStore.openParentFolder()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Theme.radius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                clip: true

                Row {
                    id: crumbRow
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Rectangle {
                        height: 28
                        width: crumbHomeRow.implicitWidth + 16
                        radius: Theme.radiusSmall
                        color: crumbHomeHover.hovered ? Theme.hover : "transparent"
                        anchors.verticalCenter: parent.verticalCenter
                        HoverHandler { id: crumbHomeHover }
                        TapHandler { onTapped: appStore.openFolder("") }
                        Row {
                            id: crumbHomeRow
                            anchors.centerIn: parent
                            spacing: 8
                            Badge {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 18
                                color: appStore.currentWorkspaceColor
                                iconType: appStore.currentWorkspaceIconType
                                iconValue: appStore.currentWorkspaceIconValue
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: appStore.currentWorkspaceName
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                            }
                        }
                    }

                    Repeater {
                        model: appStore.breadcrumbs
                        delegate: Row {
                            id: crumb
                            required property var modelData
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "fluent-chevron-right-16-regular"
                                size: 14
                                color: Theme.textTertiary
                            }
                            Rectangle {
                                height: 28
                                width: crumbContent.implicitWidth + 16
                                radius: Theme.radiusSmall
                                color: crumbHover.hovered ? Theme.hover : "transparent"
                                anchors.verticalCenter: parent.verticalCenter
                                HoverHandler { id: crumbHover }
                                TapHandler { onTapped: appStore.openFolder(crumb.modelData.id) }
                                Row {
                                    id: crumbContent
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "fluent-folder-20-filled"
                                        size: 18
                                        color: crumb.modelData.color || Theme.folder
                                    }
                                    Text {
                                        id: crumbLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: crumb.modelData.name
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSize
                                        font.weight: crumb.modelData.id === appStore.currentFolderId ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Command bar
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 2

            CommandButton {
                id: newItemButton
                text: "New item"
                iconName: "fluent-add-20-regular"
                iconColor: Theme.accent
                onClicked: root.openNewItemMenu()
            }
            CommandButton {
                text: "New folder"
                iconName: "fluent-folder-add-20-regular"
                onClicked: root.beginRename(appStore.addFolder("New folder"))
            }
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 20
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                color: Theme.borderStrong
            }
            CommandButton {
                text: "Rename"
                iconName: "fluent-rename-20-regular"
                enabled: root.selectedIds.length === 1
                onClicked: root.renamingId = root.selectedIds[0]
            }
            CommandButton {
                text: "Delete"
                iconName: "fluent-delete-20-regular"
                enabled: root.selectedIds.length > 0
                onClicked: root.deleteSelection()
            }
            Item { Layout.fillWidth: true }
        }

        // Content card
        Rectangle {
            id: card
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            clip: true

            Item {
                id: gridArea
                anchors.fill: parent
                anchors.margins: 1
                anchors.bottomMargin: statusBar.height + 1

                // Background drop: move dragged nodes into the current folder
                DropArea {
                    anchors.fill: parent
                    enabled: DragState.active
                    onDropped: appStore.moveNodes(DragState.ids, appStore.currentFolderId)
                }

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    cellWidth: 118
                    cellHeight: 132
                    model: appStore.directoryModel
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        id: tile
                        required property int index
                        required property string nodeId
                        required property string nodeName
                        required property string nodeKind
                        required property string nodeUrl
                        required property string nodeType
                        required property int childCount
                        required property string nodeIconType
                        required property string nodeIconValue
                        required property string nodeColor

                        readonly property bool isParent: nodeKind === "parent"
                        readonly property bool isFolder: nodeKind === "folder"
                        readonly property bool hasCustomIcon: !isFolder && !isParent && nodeIconType.length > 0
                        readonly property bool isDropTarget: isFolder || isParent
                        // Index among real items (the virtual ".." tile is excluded).
                        readonly property int itemIndex: index - root.gridOffset
                        readonly property bool selected: !isParent && root.isSelected(nodeId)
                        readonly property bool renaming: !isParent && root.renamingId === nodeId
                        readonly property bool dragging: !isParent && DragState.active && DragState.contains(nodeId)

                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            id: tileCard
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: Theme.radius
                            color: tileDrop.containsDrag ? Theme.dropTarget
                                 : tile.selected ? (tileHover.hovered ? Theme.selectionHover : Theme.selection)
                                 : tileHover.hovered ? Theme.hover : "transparent"
                            border.width: tile.selected || tile.isParent ? 1 : 0
                            border.color: tile.selected ? Theme.selectionBorder : Theme.border
                            opacity: tile.dragging ? 0.45 : 1
                            Behavior on color { ColorAnimation { duration: 60 } }
                        }

                        Column {
                            anchors.top: tileCard.top
                            anchors.topMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: tileCard.width - 12
                            spacing: 6

                            Item {
                                width: 56
                                height: 56
                                anchors.horizontalCenter: parent.horizontalCenter
                                Icon {
                                    anchors.centerIn: parent
                                    visible: tile.isFolder || tile.isParent
                                    size: 54
                                    name: tile.isParent ? "fluent-folder-arrow-up-24-filled" : "fluent-folder-24-filled"
                                    color: tile.isParent ? Theme.textTertiary
                                                         : tile.nodeColor.length > 0 ? tile.nodeColor : Theme.folder
                                }
                                // Default item icon: favicon for sites, typed glyph for terminals/files
                                ItemIcon {
                                    anchors.centerIn: parent
                                    visible: !tile.isFolder && !tile.isParent && !tile.hasCustomIcon
                                    size: 54
                                    variant: "24"
                                    imagePadding: 3
                                    glyphPadding: 4
                                    type: tile.nodeType
                                    url: tile.nodeUrl
                                }
                                Badge {
                                    anchors.centerIn: parent
                                    visible: tile.hasCustomIcon
                                    size: 50
                                    color: tile.nodeColor.length > 0 ? tile.nodeColor : Theme.link
                                    iconType: tile.nodeIconType
                                    iconValue: tile.nodeIconValue
                                }
                            }

                            Text {
                                visible: !tile.renaming
                                width: parent.width
                                text: tile.nodeName
                                color: tile.isParent ? Theme.textSecondary : Theme.text
                                font.pixelSize: tile.isParent ? 16 : Theme.fontSizeSmall
                                font.weight: tile.isParent ? Font.Bold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            SiloTextField {
                                id: tileRename
                                visible: tile.renaming
                                width: parent.width
                                height: 26
                                leftPadding: 6
                                rightPadding: 6
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: TextInput.AlignHCenter

                                // renameNode resets the model (this delegate is destroyed),
                                // so capture state and leave rename mode before calling it.
                                function commit() {
                                    if (!tile.renaming)
                                        return
                                    var id = tile.nodeId
                                    var value = text
                                    root.endRename()
                                    appStore.renameNode(id, value)
                                }

                                function startEditing() {
                                    text = tile.nodeName
                                    forceActiveFocus()
                                    select(text.length, 0)
                                }

                                // Handle Return here (auto-accepted) so it never bubbles up to the
                                // view's "open selected folder" shortcut once editing has ended.
                                Keys.onReturnPressed: commit()
                                Keys.onEnterPressed: commit()
                                Keys.onEscapePressed: root.endRename()
                                // Focus moved elsewhere in the window: commit. Window deactivation keeps editing.
                                onActiveFocusChanged: if (!activeFocus && Window.active) commit()
                                onVisibleChanged: if (visible) startEditing()
                                Component.onCompleted: if (visible) startEditing()
                            }

                            Text {
                                visible: !tile.renaming
                                width: parent.width
                                text: tile.isParent ? "Parent folder"
                                      : tile.isFolder
                                      ? tile.childCount + (tile.childCount === 1 ? " item" : " items")
                                      : ItemTypes.subtitle(tile.nodeType, tile.nodeUrl)
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        HoverHandler { id: tileHover }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            property bool dragging: false
                            property bool didDrag: false
                            property point pressPos: Qt.point(0, 0)

                            onPressed: function(mouse) {
                                root.forceActiveFocus()
                                didDrag = false
                                dragging = false
                                pressPos = Qt.point(mouse.x, mouse.y)
                                if (tile.isParent)
                                    return
                                if (mouse.button === Qt.RightButton) {
                                    if (!tile.selected)
                                        root.selectOnly(tile.nodeId, tile.itemIndex)
                                } else if (mouse.modifiers & Qt.ShiftModifier) {
                                    root.selectRange(tile.itemIndex)
                                } else if (mouse.modifiers & Qt.ControlModifier) {
                                    root.toggleSelection(tile.nodeId, tile.itemIndex)
                                } else if (!tile.selected) {
                                    root.selectOnly(tile.nodeId, tile.itemIndex)
                                }
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed || !(mouse.buttons & Qt.LeftButton) || tile.renaming || tile.isParent)
                                    return
                                var scene = tileMouse.mapToItem(null, mouse.x, mouse.y)
                                if (!dragging) {
                                    var threshold = Application.styleHints.startDragDistance
                                    if (Math.abs(mouse.x - pressPos.x) < threshold && Math.abs(mouse.y - pressPos.y) < threshold)
                                        return
                                    dragging = true
                                    didDrag = true
                                    if (!tile.selected)
                                        root.selectOnly(tile.nodeId, tile.itemIndex)
                                    DragState.begin(root.selectedIds, tile.nodeName, tile.nodeKind, scene)
                                } else {
                                    DragState.update(scene)
                                }
                            }
                            onReleased: {
                                if (dragging) {
                                    dragging = false
                                    DragState.finish()
                                }
                            }
                            onCanceled: {
                                if (dragging) {
                                    dragging = false
                                    DragState.cancel()
                                }
                            }
                            onClicked: function(mouse) {
                                if (didDrag)
                                    return
                                if (tile.isParent) {
                                    if (mouse.button === Qt.RightButton)
                                        parentTileMenu.popup()
                                    return
                                }
                                if (mouse.button === Qt.RightButton) {
                                    if (tile.isFolder) {
                                        folderTileMenu.targetId = tile.nodeId
                                        folderTileMenu.popup()
                                    } else {
                                        itemTileMenu.targetId = tile.nodeId
                                        itemTileMenu.targetName = tile.nodeName
                                        itemTileMenu.targetUrl = tile.nodeUrl
                                        itemTileMenu.popup()
                                    }
                                } else if (!(mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier))) {
                                    root.selectOnly(tile.nodeId, tile.itemIndex)
                                }
                            }
                            onDoubleClicked: function(mouse) {
                                if (mouse.button !== Qt.LeftButton)
                                    return
                                if (tile.isParent)
                                    appStore.openParentFolder()
                                else if (tile.isFolder)
                                    appStore.openFolder(tile.nodeId)
                                else
                                    itemDialog.openForEdit(tile.nodeId)
                            }
                        }

                        // Folders and the ".." tile accept drops; ".." moves into the parent folder.
                        DropArea {
                            id: tileDrop
                            anchors.fill: parent
                            enabled: tile.isDropTarget && DragState.active && !DragState.contains(tile.nodeId)
                            onDropped: appStore.moveNodes(DragState.ids, tile.nodeId)
                        }
                    }
                }

                // Marquee selection on the empty background
                MouseArea {
                    id: marqueeArea
                    anchors.fill: grid
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    z: 5

                    function tileAt(x, y) {
                        var cx = x + grid.contentX
                        var cy = y + grid.contentY
                        var item = grid.itemAt(cx, cy)
                        if (!item)
                            return null
                        var m = 3
                        if (cx < item.x + m || cx > item.x + item.width - m || cy < item.y + m || cy > item.y + item.height - m)
                            return null
                        return item
                    }

                    onPressed: function(mouse) {
                        if (tileAt(mouse.x, mouse.y)) {
                            mouse.accepted = false
                            return
                        }
                        root.forceActiveFocus()
                        if (mouse.button === Qt.RightButton) {
                            backgroundMenu.popup()
                            return
                        }
                        root.marqueeBase = (mouse.modifiers & Qt.ControlModifier) ? root.selectedIds.slice() : []
                        if (!(mouse.modifiers & Qt.ControlModifier))
                            root.clearSelection()
                        root.marqueeStart = Qt.point(mouse.x, mouse.y)
                        root.marqueeRect = Qt.rect(mouse.x, mouse.y, 0, 0)
                        root.marqueeActive = true
                    }

                    onPositionChanged: function(mouse) {
                        if (!root.marqueeActive)
                            return
                        var left = Math.min(root.marqueeStart.x, mouse.x)
                        var top = Math.min(root.marqueeStart.y, mouse.y)
                        var right = Math.max(root.marqueeStart.x, mouse.x)
                        var bottom = Math.max(root.marqueeStart.y, mouse.y)
                        root.marqueeRect = Qt.rect(left, top, right - left, bottom - top)

                        var hits = root.marqueeBase.slice()
                        for (var i = 0; i < grid.count; ++i) {
                            var item = grid.itemAtIndex(i)
                            if (!item)
                                continue
                            var x = item.x - grid.contentX + 3
                            var y = item.y - grid.contentY + 3
                            var w = item.width - 6
                            var h = item.height - 6
                            if (item.isParent)
                                continue
                            if (x < right && x + w > left && y < bottom && y + h > top && hits.indexOf(item.nodeId) < 0)
                                hits.push(item.nodeId)
                        }
                        root.selectedIds = hits
                    }

                    onReleased: root.marqueeActive = false
                    onCanceled: root.marqueeActive = false
                }

                Rectangle {
                    visible: root.marqueeActive && (root.marqueeRect.width > 2 || root.marqueeRect.height > 2)
                    x: grid.x + root.marqueeRect.x
                    y: grid.y + root.marqueeRect.y
                    width: root.marqueeRect.width
                    height: root.marqueeRect.height
                    color: Theme.marqueeFill
                    border.width: 1
                    border.color: Theme.marqueeBorder
                    z: 6
                }

                // Empty state
                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.gridOffset > 0 ? grid.cellHeight / 2 : 0
                    spacing: 10
                    visible: root.itemCount === 0
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "fluent-folder-48-regular"
                        size: 60
                        color: Theme.borderStrong
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "This folder is empty"
                        color: Theme.text
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Use New item or New folder, or drop something here."
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // Status bar
            Rectangle {
                id: statusBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                height: 28
                color: Theme.surfaceAlt
                radius: Theme.radiusLarge

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 1
                    color: Theme.divider
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    Text {
                        text: root.itemCount + (root.itemCount === 1 ? " item" : " items")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Text {
                        visible: root.selectedIds.length > 0
                        text: root.selectedIds.length + " selected"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }
    }
}
