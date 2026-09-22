import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live mode: tabs for the items opened from the tree (browser pages,
// SSH terminals and file viewers).
Item {
    id: root
    // Tabs of the current workspace. Every workspace keeps its own live set of
    // pages (see the pages repeater), so switching never reloads anything.
    readonly property var tabsModel: tabsHub.current
    readonly property int tabCount: tabsModel ? tabsModel.count : 0
    readonly property int currentTabIndex: tabsModel ? tabsModel.currentIndex : -1

    // Page container of the current workspace, and the TabPage of its active tab.
    readonly property var currentPages: tabsHub.currentRow >= 0 && workspaceRepeater.count > tabsHub.currentRow
                                        ? workspaceRepeater.itemAt(tabsHub.currentRow) : null
    readonly property var currentView: currentPages && currentPages.pageCount > root.currentTabIndex
                                       ? currentPages.viewAt(root.currentTabIndex) : null

    function viewAt(index) {
        return currentPages ? currentPages.viewAt(index) : null
    }

    function closeCurrent() {
        if (tabsModel && tabsModel.currentIndex >= 0)
            tabsModel.closeTab(tabsModel.currentIndex)
    }

    // Reloads the web and file tabs of the current workspace that have been
    // loaded already.
    function reloadAll() {
        for (var i = 0; i < root.tabCount; ++i) {
            var view = root.viewAt(i)
            if (view && view.loaded && view.kind !== "ssh")
                view.reload()
        }
    }

    // Opens every web tab of the current workspace in the system browser.
    function openAllInBrowser() {
        for (var i = 0; i < root.tabCount; ++i) {
            var view = root.viewAt(i)
            if (view && view.kind === "web")
                view.openExternally()
        }
    }

    // Keep tabs consistent with the tree: renames update titles/urls, deletions close tabs.
    function syncTabs() {
        // While a workspace switch is in flight the tabs still belong to the previous one.
        if (!tabsModel || tabsModel.workspaceId !== appStore.currentWorkspaceId)
            return
        for (var i = tabsModel.count - 1; i >= 0; --i) {
            var info = appStore.nodeInfo(tabsModel.nodeIdAt(i))
            if (!info.id)
                tabsModel.closeTab(i)
            else
                tabsModel.updateTab(info.id, info.name, info.url)
        }
    }

    Connections {
        target: appStore
        function onDataChanged() { root.syncTabs() }
    }

    onCurrentTabIndexChanged: {
        if (currentTabIndex >= 0)
            tabStrip.positionViewAtIndex(currentTabIndex, ListView.Contain)
    }

    Shortcut { enabled: root.visible; sequences: [StandardKey.Close]; onActivated: root.closeCurrent() }
    Shortcut { enabled: root.visible; sequences: [StandardKey.Refresh]; onActivated: if (root.currentView) root.currentView.reload() }
    // Next / previous tab. In Qt key strings "Ctrl" is ⌘ on macOS (and ⌘Tab
    // belongs to the system), the physical Control key is "Meta" there; the
    // browser chords ⌘⌥→/← and ⌘⇧]/[ are offered as well.
    Shortcut {
        enabled: root.visible && !!root.tabsModel
        sequences: ["Ctrl+Tab", "Meta+Tab", "Ctrl+PgDown", "Ctrl+Alt+Right", "Ctrl+Shift+]"]
        onActivated: tabsModel.activateNext()
    }
    Shortcut {
        enabled: root.visible && !!root.tabsModel
        sequences: ["Ctrl+Shift+Tab", "Meta+Shift+Tab", "Ctrl+PgUp", "Ctrl+Alt+Left", "Ctrl+Shift+["]
        onActivated: tabsModel.activatePrevious()
    }
    // Jump to tab 1–8, and to the last one with 9 (browser convention)
    Repeater {
        model: 9
        Item {
            required property int index
            Shortcut {
                enabled: root.visible && !!root.tabsModel
                sequence: "Ctrl+" + (index + 1)
                onActivated: {
                    if (index === 8)
                        tabsModel.currentIndex = tabsModel.count - 1
                    else if (index < tabsModel.count)
                        tabsModel.currentIndex = index
                }
            }
        }
    }
    // Reopen the last closed tab (Cmd+Shift+T on macOS), one per press
    Shortcut { enabled: root.visible && !!root.tabsModel; sequences: ["Ctrl+Shift+T"]; onActivated: tabsModel.reopenClosed() }
    // Fill login from the password manager (Cmd+Shift+L on macOS)
    Shortcut { enabled: root.visible && root.canFillLogin; sequences: ["Ctrl+Shift+L"]; onActivated: root.openPasswordPopover() }

    readonly property bool canFillLogin: !!root.currentView && root.currentView.canFill
    function openPasswordPopover() {
        if (!canFillLogin)
            return
        passwordPopover.parent = fillButton
        passwordPopover.x = fillButton.width - passwordPopover.width
        passwordPopover.y = fillButton.height + 6
        passwordPopover.openFor(root.currentView)
    }
    PasswordPopover { id: passwordPopover }

    SiloMenu {
        id: tabMenu
        property int targetIndex: -1
        SiloMenuItem {
            text: "Reload"
            iconName: "fluent-arrow-clockwise-20-regular"
            onTriggered: { var v = root.viewAt(tabMenu.targetIndex); if (v) v.reload() }
        }
        SiloMenuItem {
            readonly property var view: root.viewAt(tabMenu.targetIndex)
            text: view && view.kind === "file" ? "Open with default app" : view && view.kind === "ssh" ? "Open in terminal app" : "Open in browser"
            iconName: "fluent-open-20-regular"
            onTriggered: { var v = root.viewAt(tabMenu.targetIndex); if (v) v.openExternally() }
        }
        SiloMenuItem {
            readonly property var view: root.viewAt(tabMenu.targetIndex)
            visible: view && view.kind === "file"
            height: visible ? implicitHeight : 0
            text: "Show in folder"
            iconName: "fluent-folder-open-20-filled"
            onTriggered: { var v = root.viewAt(tabMenu.targetIndex); if (v) v.showInFolder() }
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: "Close tab"
            iconName: "fluent-dismiss-20-regular"
            onTriggered: tabsModel.closeTab(tabMenu.targetIndex)
        }
        SiloMenuItem {
            text: "Close other tabs"
            enabled: root.tabCount > 1
            onTriggered: tabsModel.closeOthers(tabMenu.targetIndex)
        }
        SiloMenuItem {
            text: "Close all tabs"
            onTriggered: tabsModel.closeAll()
        }
        MenuSeparator {
            padding: 4
            contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
        }
        SiloMenuItem {
            text: "Reopen closed tab"
            iconName: "fluent-arrow-undo-20-regular"
            enabled: !!root.tabsModel && root.tabsModel.closedCount > 0
            onTriggered: tabsModel.reopenClosed()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: 12
        anchors.leftMargin: Session.sidebarVisible ? 4 : 12
        spacing: 0

        // ---------------------------------------------------------------- tab strip
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 40

            // Overflow hints at both ends of the tab strip
            Rectangle {
                z: 1
                anchors.left: tabStrip.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 28
                visible: tabStrip.contentX > 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.windowBg }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                z: 1
                anchors.right: tabStrip.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 28
                visible: tabStrip.contentWidth - tabStrip.contentX > tabStrip.width + 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.windowBg }
                }
            }

            SidebarToggle {
                id: sidebarToggle
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
            }

            // Tabs follow the tree order until the user drags one; this puts them
            // back in tree order (and makes them follow it again).
            IconButton {
                id: syncOrderButton
                anchors.left: sidebarToggle.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                iconName: "fluent-arrow-sort-20-regular"
                iconSize: 18
                enabled: !!root.tabsModel && root.tabsModel.manualOrder
                iconColor: Theme.accent
                tooltip: "Restore tab order from the tree"
                onClicked: tabsModel.syncOrder()
            }

            // Reload every loaded page of the workspace (web pages and files;
            // terminals are left alone, a reload would kill their shell)
            IconButton {
                id: refreshAllButton
                anchors.left: syncOrderButton.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                iconName: "fluent-arrow-clockwise-20-regular"
                iconSize: 18
                enabled: root.tabCount > 0
                tooltip: "Reload all tabs"
                onClicked: root.reloadAll()
            }

            IconButton {
                id: openAllButton
                anchors.left: refreshAllButton.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                iconName: "fluent-open-20-regular"
                iconSize: 18
                enabled: root.tabCount > 0
                tooltip: "Open all in browser"
                onClicked: root.openAllInBrowser()
            }

            ListView {
                id: tabStrip
                anchors.left: openAllButton.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                // Start past the card's rounded corners so the active tab sits on the straight edge.
                anchors.leftMargin: 6
                anchors.rightMargin: Theme.radiusLarge + 2
                orientation: ListView.Horizontal
                clip: true
                spacing: 2
                model: root.tabsModel
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 4000

                // Vertical wheel scrolls the strip horizontally.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(event) {
                        var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                        var max = Math.max(0, tabStrip.contentWidth - tabStrip.width)
                        tabStrip.contentX = Math.max(0, Math.min(max, tabStrip.contentX - delta))
                    }
                }

                // Tabs slide when the model reorders them (drag, tree sync)
                move: Transition { NumberAnimation { properties: "x"; duration: Theme.animationFast; easing.type: Easing.OutCubic } }
                moveDisplaced: Transition { NumberAnimation { properties: "x"; duration: Theme.animationFast; easing.type: Easing.OutCubic } }

                delegate: Item {
                    id: tab
                    required property int index
                    required property string tabNodeId
                    required property string tabTitle
                    required property string tabUrl
                    readonly property bool active: root.currentTabIndex === index
                    readonly property var view: root.currentPages && root.currentPages.pageCount > index
                                                ? root.currentPages.viewAt(index) : null
                    // Custom leaf icon (re-read when the store changes)
                    readonly property var nodeInfo: appStore.revision >= 0 ? appStore.nodeInfo(tabNodeId) : ({})
                    readonly property bool customIcon: !!nodeInfo.iconType && nodeInfo.iconType.length > 0
                    readonly property string nodeType: nodeInfo.type || "web"
                    readonly property bool hasFavicon: !customIcon && view && view.kind === "web" && String(view.icon).length > 0

                    // Drag reordering: the wrapper stays where the ListView puts it while
                    // `tabContent` follows the pointer; the row is moved in the model as
                    // soon as the tab's centre crosses into a neighbouring slot.
                    property bool dragging: false
                    property real pressOffset: 0
                    property real pointerStripX: 0
                    readonly property real slot: width + tabStrip.spacing

                    width: 208
                    height: tabStrip.height

                    HoverHandler { id: tabHover }

                    // Below the content so the close button keeps its clicks.
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        // The strip is a Flickable: keep the grab so a horizontal drag reorders
                        // instead of flicking the list.
                        preventStealing: true
                        property point pressPos: Qt.point(0, 0)

                        onPressed: function(mouse) {
                            pressPos = Qt.point(mouse.x, mouse.y)
                            tab.pressOffset = mouse.x
                            tabsModel.currentIndex = tab.index
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed)
                                return
                            if (!tab.dragging) {
                                var threshold = Application.styleHints.startDragDistance
                                if (Math.abs(mouse.x - pressPos.x) < threshold && Math.abs(mouse.y - pressPos.y) < threshold)
                                    return
                                tab.dragging = true
                            }
                            tab.pointerStripX = tabStrip.mapFromItem(tab, mouse.x, mouse.y).x
                            var centre = tab.pointerStripX + tabStrip.contentX - tab.pressOffset + tab.width / 2
                            var target = Math.max(0, Math.min(tabsModel.count - 1, Math.floor(centre / tab.slot)))
                            if (target !== tab.index)
                                tabsModel.moveTab(tab.index, target)
                        }
                        onReleased: tab.dragging = false
                        onCanceled: tab.dragging = false
                    }
                    TapHandler {
                        acceptedButtons: Qt.MiddleButton
                        onTapped: tabsModel.closeTab(tab.index)
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: {
                            tabMenu.targetIndex = tab.index
                            tabMenu.popup()
                        }
                    }

                    Item {
                        id: tabContent
                        width: tab.width
                        height: tab.height
                        z: tab.dragging ? 2 : 0
                        x: tab.dragging ? tab.pointerStripX + tabStrip.contentX - tab.x - tab.pressOffset : 0
                        Behavior on x {
                            enabled: !tab.dragging
                            NumberAnimation { duration: Theme.animationFast; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            id: tabBg
                            anchors.fill: parent
                            anchors.topMargin: 5
                            anchors.bottomMargin: tab.active ? -1 : 3   // active tab merges with the card
                            topLeftRadius: Theme.radiusLarge
                            topRightRadius: Theme.radiusLarge
                            bottomLeftRadius: tab.active ? 0 : Theme.radius
                            bottomRightRadius: tab.active ? 0 : Theme.radius
                            color: tab.active ? Theme.surface : tabHover.hovered || tab.dragging ? Theme.hover : "transparent"
                            border.width: tab.active ? 1 : 0
                            border.color: Theme.border
                            Behavior on color { ColorAnimation { duration: Theme.animationFast } }

                            // Hide the bottom border of the active tab
                            Rectangle {
                                visible: tab.active && !tab.dragging
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 1
                                anchors.rightMargin: 1
                                height: 2
                                color: Theme.surface
                            }
                        }

                        // Favicon (or spinner-ish dot while loading)
                        Item {
                            id: favicon
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: tabBg.verticalCenter
                            width: 16
                            height: 16
                            Badge {
                                anchors.fill: parent
                                visible: tab.customIcon
                                size: 16
                                color: tab.customIcon && tab.nodeInfo.color.length > 0 ? tab.nodeInfo.color : Theme.link
                                iconType: tab.customIcon ? tab.nodeInfo.iconType : "emoji"
                                iconValue: tab.customIcon ? tab.nodeInfo.iconValue : ""
                            }
                            Image {
                                anchors.fill: parent
                                source: tab.hasFavicon ? tab.view.icon : ""
                                visible: tab.hasFavicon && status === Image.Ready
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                sourceSize: Qt.size(32, 32)
                            }
                            ItemIcon {
                                anchors.fill: parent
                                visible: !tab.customIcon && !tab.hasFavicon
                                size: 16
                                type: tab.nodeType
                                url: tab.tabUrl
                                opacity: tab.active ? 1 : 0.75
                            }
                            Rectangle {
                                visible: tab.view ? tab.view.loading : false
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: -2
                                width: 7
                                height: 7
                                radius: 3.5
                                color: Theme.accent
                                border.width: 1
                                border.color: Theme.surface
                            }
                        }

                        Text {
                            anchors.left: favicon.right
                            anchors.leftMargin: 8
                            anchors.right: closeButton.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: tabBg.verticalCenter
                            text: tab.tabTitle
                            color: tab.active ? Theme.text : Theme.textSecondary
                            font.pixelSize: Theme.fontSize
                            font.weight: tab.active ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        IconButton {
                            id: closeButton
                            z: 1
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: tabBg.verticalCenter
                            width: 24
                            height: 24
                            iconName: "fluent-dismiss-16-regular"
                            iconSize: 12
                            iconColor: Theme.textSecondary
                            opacity: tab.active || tabHover.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animationFast } }
                            onClicked: tabsModel.closeTab(tab.index)
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------------------- browser card
        Rectangle {
            id: card
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                // Navigation toolbar
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    visible: root.tabCount > 0

                    RowLayout {
                        id: addressRow
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 2

                        readonly property string kind: root.currentView ? root.currentView.kind : "web"
                        readonly property bool isWeb: kind === "web"

                        IconButton {
                            visible: parent.isWeb
                            iconName: "fluent-arrow-left-20-regular"
                            iconSize: 18
                            tooltip: "Back"
                            enabled: root.currentView ? root.currentView.canGoBack : false
                            onClicked: root.currentView.goBack()
                        }
                        IconButton {
                            visible: parent.isWeb
                            iconName: "fluent-arrow-right-20-regular"
                            iconSize: 18
                            tooltip: "Forward"
                            enabled: root.currentView ? root.currentView.canGoForward : false
                            onClicked: root.currentView.goForward()
                        }
                        IconButton {
                            iconName: root.currentView && root.currentView.loading && parent.isWeb ? "fluent-dismiss-20-regular" : "fluent-arrow-clockwise-20-regular"
                            iconSize: 18
                            tooltip: root.currentView && root.currentView.loading && parent.isWeb ? "Stop"
                                     : parent.kind === "ssh" ? "Reconnect" : "Reload"
                            enabled: root.currentView !== null
                            onClicked: root.currentView.loading && parent.isWeb ? root.currentView.stop() : root.currentView.reload()
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            radius: 15
                            color: Theme.controlBg
                            border.width: 1
                            border.color: Theme.border
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 14
                                spacing: 8
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !addressRow.isWeb
                                    name: ItemTypes.glyph(addressRow.kind, root.currentView ? root.currentView.displayUrl : "", "20")
                                    size: 15
                                    color: ItemTypes.color(addressRow.kind)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - (addressRow.isWeb ? 0 : 23)
                                    text: root.currentView ? root.currentView.displayUrl : ""
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: addressRow.kind === "file" ? Text.ElideMiddle : Text.ElideRight
                                }
                            }
                        }

                        IconButton {
                            id: fillButton
                            visible: parent.isWeb
                            iconName: "fluent-key-20-regular"
                            iconSize: 18
                            tooltip: "Fill login (" + (Qt.platform.os === "osx" ? "⌘⇧L" : "Ctrl+Shift+L") + ")"
                            enabled: root.canFillLogin
                            onClicked: root.openPasswordPopover()
                        }
                        IconButton {
                            visible: parent.kind === "file"
                            iconName: "fluent-folder-open-20-filled"
                            iconSize: 18
                            tooltip: "Show in folder"
                            enabled: root.currentView !== null
                            onClicked: root.currentView.showInFolder()
                        }
                        IconButton {
                            iconName: "fluent-open-20-regular"
                            iconSize: 18
                            tooltip: parent.kind === "file" ? "Open with default app" : parent.kind === "ssh" ? "Open in terminal app" : "Open in browser"
                            enabled: root.currentView !== null
                            onClicked: root.currentView.openExternally()
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.divider
                    }

                    // Load progress
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 2
                        width: root.currentView && root.currentView.loading && root.currentView.kind === "web"
                               ? parent.width * root.currentView.loadProgress / 100 : 0
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }

                // Offer to save a login submitted in the current tab
                SavePasswordBanner {
                    Layout.fillWidth: true
                    view: root.currentView
                }

                // Pages: one container per workspace, one TabPage per tab.
                // All of them stay alive so switching workspace never reloads anything.
                Item {
                    id: pages
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Repeater {
                        id: workspaceRepeater
                        model: tabsHub
                        delegate: Item {
                            id: workspacePages
                            required property int index
                            required property string workspaceId
                            required property var tabs
                            readonly property int pageCount: pageRepeater.count
                            anchors.fill: parent
                            visible: tabsHub.currentWorkspaceId === workspaceId

                            // A row move changes neither `count` nor any notified property, so bindings
                            // that resolve a page through viewAt() would keep the item that sat at that
                            // index before the move (wrong favicon / loading dot on the tab). Bump a
                            // revision once the Repeater has reordered its items to re-resolve them.
                            property int orderRevision: 0
                            Connections {
                                target: workspacePages.tabs
                                function onRowsMoved() {
                                    Qt.callLater(function() { workspacePages.orderRevision++ })
                                }
                            }

                            function viewAt(tabIndex) {
                                var revision = workspacePages.orderRevision
                                return tabIndex >= 0 && pageRepeater.count > tabIndex ? pageRepeater.itemAt(tabIndex) : null
                            }

                            Repeater {
                                id: pageRepeater
                                model: workspacePages.tabs
                                delegate: TabPage {
                                    id: page
                                    required property int index
                                    required tabNodeId
                                    required tabUrl
                                    anchors.fill: parent
                                    visible: workspacePages.tabs.currentIndex === index
                                    // The item type is fixed for the tab's lifetime
                                    tabType: appStore.nodeInfo(tabNodeId).type || "web"

                                    // Web pages and files load right away, so "Open all items" and a
                                    // restored session are ready without visiting each tab. Terminals
                                    // wait for their first show: connecting to every host at startup
                                    // is not what a restored layout should do.
                                    Component.onCompleted: if (visible || tabType !== "ssh") ensureLoaded()
                                    onVisibleChanged: if (visible) ensureLoaded()
                                }
                            }
                        }
                    }

                    // Pages clip to a rectangle: give the card its bottom radius back
                    CornerMask {
                        corner: "bottomLeft"
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: -1
                        anchors.bottomMargin: -1
                        z: 10
                    }
                    CornerMask {
                        corner: "bottomRight"
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -1
                        anchors.bottomMargin: -1
                        z: 10
                    }

                    // Empty state
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        visible: root.tabCount === 0
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "fluent-window-20-regular"
                            size: 60
                            color: Theme.borderStrong
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No open tabs"
                            color: Theme.text
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: "Click an item in the tree to open it here.\n"
                                  + (Qt.platform.os === "osx" ? "⌘" : "Ctrl") + "+click a folder to open all its items."
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            lineHeight: 1.3
                        }
                    }
                }
            }
        }
    }
}
