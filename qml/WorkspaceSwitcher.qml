import QtQuick
import QtQuick.Controls

Item {
    id: root
    implicitHeight: 44

    property var results: []
    property int highlightedIndex: -1   // -1 => "Add Workspace" row
    readonly property int rowHeight: 36
    readonly property int maxVisibleRows: 6

    function openPopup() {
        popup.open()
    }

    function openAddWorkspace() {
        workspaceDialog.openForCreate()
    }

    function openEditWorkspace(id) {
        popup.close()
        workspaceDialog.openForEdit(id)
    }

    function exportWorkspace(id) {
        popup.close()
        transfer.exportWorkspace(id || appStore.currentWorkspaceId)
    }

    function importWorkspace() {
        popup.close()
        transfer.importWorkspace()
    }

    function refresh() {
        results = appStore.searchWorkspaces(searchField.text)
        if (highlightedIndex >= results.length)
            highlightedIndex = results.length - 1
    }

    function moveHighlight(step) {
        var next = highlightedIndex + step
        if (next < -1)
            next = -1
        if (next > results.length - 1)
            next = results.length - 1
        highlightedIndex = next
        if (next >= 0)
            resultList.positionViewAtIndex(next, ListView.Contain)
    }

    function choose(index) {
        popup.close()
        if (index < 0) {
            workspaceDialog.openForCreate()
        } else if (index < results.length) {
            appStore.selectWorkspace(results[index].id)
        }
    }

    Connections {
        target: appStore
        function onDataChanged() { root.refresh() }
    }

    // Trigger
    Rectangle {
        id: trigger
        anchors.fill: parent
        radius: Theme.radius
        color: popup.opened ? Theme.pressed : triggerHover.hovered ? Theme.hover : "transparent"
        border.width: popup.opened ? 1 : 0
        border.color: Theme.border
        Behavior on color { ColorAnimation { duration: Theme.animationFast } }

        HoverHandler { id: triggerHover }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: popup.opened ? popup.close() : popup.open()
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: triggerMenu.popup()
        }

        SiloMenu {
            id: triggerMenu
            SiloMenuItem {
                text: "Edit workspace…"
                iconName: "fluent-edit-20-regular"
                onTriggered: root.openEditWorkspace(appStore.currentWorkspaceId)
            }
            SiloMenuItem {
                text: "Add workspace…"
                iconName: "fluent-add-20-regular"
                onTriggered: root.openAddWorkspace()
            }
            MenuSeparator {
                padding: 4
                contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
            }
            SiloMenuItem {
                text: "Export workspace…"
                iconName: "fluent-arrow-export-20-regular"
                onTriggered: root.exportWorkspace(appStore.currentWorkspaceId)
            }
            SiloMenuItem {
                text: "Import workspace…"
                iconName: "fluent-arrow-import-20-regular"
                onTriggered: root.importWorkspace()
            }
        }

        Badge {
            id: triggerBadge
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            size: 28
            color: appStore.currentWorkspaceColor
            iconType: appStore.currentWorkspaceIconType
            iconValue: appStore.currentWorkspaceIconValue
        }

        Text {
            anchors.left: triggerBadge.right
            anchors.leftMargin: 10
            anchors.right: triggerChevron.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: appStore.currentWorkspaceName
            color: Theme.text
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        Icon {
            id: triggerChevron
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            name: "fluent-chevron-down-20-regular"
            size: 16
            color: Theme.textSecondary
        }
    }

    Popup {
        id: popup
        x: 0
        y: root.height + 4
        width: root.width
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onOpened: {
            searchField.text = ""
            root.refresh()
            var current = -1
            for (var i = 0; i < root.results.length; ++i) {
                if (root.results[i].isCurrent) {
                    current = i
                    break
                }
            }
            root.highlightedIndex = current
            searchField.forceActiveFocus()
        }

        background: Rectangle {
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.borderStrong
        }

        contentItem: Column {
            spacing: 6

            // Search
            Item {
                width: parent.width
                height: 32

                SiloTextField {
                    id: searchField
                    anchors.fill: parent
                    leftPadding: 32
                    placeholderText: "Search workspaces"
                    onTextChanged: {
                        root.refresh()
                        root.highlightedIndex = root.results.length > 0 ? 0 : -1
                    }
                    Keys.onEscapePressed: popup.close()
                    Keys.onDownPressed: root.moveHighlight(1)
                    Keys.onUpPressed: root.moveHighlight(-1)
                    Keys.onReturnPressed: root.choose(root.highlightedIndex)
                    Keys.onEnterPressed: root.choose(root.highlightedIndex)
                }

                Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "fluent-search-20-regular"
                    size: 16
                    color: Theme.textSecondary
                }
            }

            // "Add Workspace" row
            Rectangle {
                id: addRow
                width: parent.width
                height: root.rowHeight
                radius: Theme.radiusSmall
                color: root.highlightedIndex === -1 ? Theme.accentSoft : addHover.hovered ? Theme.hover : "transparent"

                HoverHandler {
                    id: addHover
                    onHoveredChanged: if (hovered) root.highlightedIndex = -1
                }
                TapHandler { onTapped: root.choose(-1) }

                Rectangle {
                    id: addBadge
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: 6
                    color: Theme.accentSoft
                    border.width: 1
                    border.color: Theme.accentSoftBorder
                    Icon {
                        anchors.centerIn: parent
                        name: "fluent-add-20-regular"
                        size: 14
                        color: Theme.accent
                    }
                }

                Text {
                    anchors.left: addBadge.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add Workspace"
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // "Import workspace" row
            Rectangle {
                id: importRow
                width: parent.width
                height: root.rowHeight
                radius: Theme.radiusSmall
                color: importHover.hovered ? Theme.hover : "transparent"

                HoverHandler { id: importHover }
                TapHandler { onTapped: root.importWorkspace() }

                Rectangle {
                    id: importBadge
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: 6
                    color: Theme.controlBg
                    border.width: 1
                    border.color: Theme.border
                    Icon {
                        anchors.centerIn: parent
                        name: "fluent-arrow-import-20-regular"
                        size: 14
                        color: Theme.textSecondary
                    }
                }

                Text {
                    anchors.left: importBadge.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Import from file…"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.divider
            }

            ListView {
                id: resultList
                width: parent.width
                height: Math.max(root.rowHeight, Math.min(count, root.maxVisibleRows) * root.rowHeight)
                clip: true
                model: root.results
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property var modelData
                    width: resultList.width
                    height: root.rowHeight
                    radius: Theme.radiusSmall
                    color: root.highlightedIndex === index ? Theme.hover : "transparent"

                    HoverHandler {
                        onHoveredChanged: if (hovered) root.highlightedIndex = row.index
                    }
                    TapHandler { onTapped: root.choose(row.index) }

                    Badge {
                        id: rowBadge
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        size: 24
                        color: row.modelData.color
                        iconType: row.modelData.iconType
                        iconValue: row.modelData.iconValue
                    }

                    Text {
                        anchors.left: rowBadge.right
                        anchors.leftMargin: 10
                        anchors.right: editButton.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name
                        color: Theme.text
                        font.pixelSize: Theme.fontSize
                        font.weight: row.modelData.isCurrent ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Edit (shown on hover / keyboard highlight)
                    IconButton {
                        id: editButton
                        anchors.right: check.left
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        iconName: "fluent-edit-20-regular"
                        iconSize: 15
                        tooltip: "Edit workspace"
                        opacity: root.highlightedIndex === row.index ? 1 : 0
                        enabled: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animationFast } }
                        onClicked: root.openEditWorkspace(row.modelData.id)
                    }

                    Icon {
                        id: check
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "fluent-checkmark-20-filled"
                        size: 16
                        color: Theme.accent
                        opacity: row.modelData.isCurrent ? 1 : 0
                        width: 16
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: resultList.count === 0
                    text: "No workspace found"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    WorkspaceDialog {
        id: workspaceDialog
        onExportRequested: function(id) { transfer.exportWorkspace(id) }
    }

    WorkspaceTransfer {
        id: transfer
    }

    Component.onCompleted: refresh()
}
