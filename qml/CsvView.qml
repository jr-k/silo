import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Silo.Backend

// CSV / TSV editor: a sortable, filterable spreadsheet-like table where cells
// can be edited in place (rows and columns added or removed), with a toggle to
// the raw text editor. Both modes write back to the file automatically.
Item {
    id: view
    property string path: ""
    // "table" | "text"
    property string mode: "table"
    property int selectedRow: -1
    property int selectedColumn: -1
    property alias filterText: searchField.text
    // Cell being edited in place (row -1 + column: header cell)
    property int editRow: -2
    property int editColumn: -1
    property string editSeed: ""
    // The TextInput currently editing a cell (null when not editing)
    property Item activeEditor: null
    readonly property bool editing: editRow > -2
    readonly property bool readOnly: csv.truncated || !files.isWritable(path)
    // "" | "saving" | "saved" | "error"
    property string saveState: ""
    property string saveError: ""

    readonly property bool loading: false
    readonly property int rowHeight: 30

    function reload() {
        endEdit()
        csv.reload()
        if (textLoader.item)
            textLoader.item.reload()
    }
    function sortBy(column) { csv.toggleSort(column) }
    function copySelection(wholeRow) {
        if (selectedRow < 0)
            return
        files.copyToClipboard(wholeRow ? csv.rowText(selectedRow) : csv.cellText(selectedRow, selectedColumn))
    }

    // --- editing
    function beginEdit(row, column, seed) {
        if (readOnly || column < 0 || column >= csv.columns)
            return
        if (row === -1 && !csv.hasHeader)
            return
        if (row >= 0) {
            selectedRow = row
            selectedColumn = column
            table.positionViewAtCell(Qt.point(column, row), TableView.Contain)
        }
        editSeed = seed === undefined ? "" : seed
        editRow = row
        editColumn = column
    }
    // Commit whatever the live editor holds (click outside, window deactivation…)
    function commitActiveEdit() {
        if (!editing)
            return
        if (activeEditor)
            commitEdit(activeEditor.text)
        else
            endEdit()
    }
    function commitEdit(text) {
        if (!editing)
            return
        if (editRow === -1)
            csv.setHeader(editColumn, text)
        else
            csv.setCell(editRow, editColumn, text)
        endEdit()
    }
    function endEdit() {
        editRow = -2
        editColumn = -1
        editSeed = ""
        if (mode === "table")
            sheet.forceActiveFocus()
    }
    function clearCell() {
        if (selectedRow >= 0 && selectedColumn >= 0)
            csv.setCell(selectedRow, selectedColumn, "")
    }
    function insertRow(after) {
        var at = selectedRow < 0 ? csv.visibleRows : selectedRow + (after ? 1 : 0)
        var row = csv.insertRowAt(at)
        if (row >= 0) {
            selectedRow = row
            if (selectedColumn < 0)
                selectedColumn = 0
            table.positionViewAtRow(row, TableView.Contain)
        }
    }
    function deleteRow() {
        if (selectedRow < 0)
            return
        var row = selectedRow
        csv.removeRowAt(row)
        selectedRow = Math.min(row, csv.visibleRows - 1)
    }
    function insertColumn(after) {
        var at = selectedColumn < 0 ? csv.columns : selectedColumn + (after ? 1 : 0)
        var row = selectedRow
        csv.insertColumnAt(at)
        selectedRow = row
        selectedColumn = at
    }
    function deleteColumn() {
        if (selectedColumn < 0)
            return
        var row = selectedRow, column = selectedColumn
        csv.removeColumnAt(column)
        selectedRow = row
        selectedColumn = Math.min(column, csv.columns - 1)
    }
    // Write pending edits now (called before leaving table mode / on destruction)
    function flushTable() {
        if (!saveTimer.running && !csv.dirty)
            return
        saveTimer.stop()
        saveNow()
    }
    function saveNow() {
        if (!csv.dirty)
            return
        saveState = "saving"
        var error = csv.save()
        if (error) {
            saveError = error
            saveState = "error"
        } else {
            saveState = "saved"
            savedTimer.restart()
        }
    }

    onModeChanged: {
        if (mode === "text") {
            endEdit()
            flushTable()
            if (textLoader.item)
                textLoader.item.reload()
        } else if (textLoader.item) {
            // Any edit still batched in the text editor lands on disk, and the
            // table reloads from its saved() signal.
            textLoader.item.flush()
        }
    }
    Component.onDestruction: flushTable()
    onVisibleChanged: if (visible && mode === "table") sheet.forceActiveFocus()

    CsvModel {
        id: csv
        source: view.path
        filter: searchField.text
        onLayoutChanged: {
            if (!view.editing)
                view.selectedRow = -1
            table.forceLayout()
        }
        onDirtyChanged: if (dirty) saveTimer.restart()
    }
    Timer { id: saveTimer; interval: 400; onTriggered: view.saveNow() }

    // A press anywhere in the window outside the cell editor commits the edit.
    // Focus alone is not enough: most surfaces (empty table area, card
    // backgrounds, flickables) swallow clicks without taking focus. The press
    // is left unaccepted so it still reaches whatever was clicked.
    MouseArea {
        id: outsideCatcher
        parent: view.Overlay.overlay
        anchors.fill: parent
        visible: view.editing && view.visible
        z: 10000
        acceptedButtons: Qt.AllButtons
        onPressed: function(mouse) {
            mouse.accepted = false
            var editor = view.activeEditor
            if (editor) {
                var p = editor.mapFromItem(outsideCatcher, mouse.x, mouse.y)
                if (p.x >= 0 && p.y >= 0 && p.x <= editor.width && p.y <= editor.height)
                    return
            }
            view.commitActiveEdit()
        }
    }
    // Switching to another app or window also commits
    Connections {
        target: view.Window.window
        function onActiveChanged() { if (!view.Window.window.active) view.commitActiveEdit() }
    }
    Timer { id: savedTimer; interval: 1800; onTriggered: if (view.saveState === "saved") view.saveState = "" }

    Rectangle { anchors.fill: parent; color: Theme.surfaceAlt }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ------------------------------------------------------------ toolbar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                // Table / Text segmented switch
                Row {
                    spacing: 0
                    Rectangle {
                        width: segments.width + 4
                        height: 30
                        radius: Theme.radius
                        color: Theme.controlBg
                        border.width: 1
                        border.color: Theme.border
                        Row {
                            id: segments
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: [{ id: "table", label: "Table", icon: "fluent-table-20-regular" },
                                        { id: "text", label: "Text", icon: "fluent-text-align-left-20-regular" }]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool active: view.mode === modelData.id
                                    width: segmentRow.implicitWidth + 20
                                    height: 26
                                    radius: Theme.radiusSmall
                                    color: active ? Theme.accent : segmentHover.hovered ? Theme.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.animationFast } }
                                    Row {
                                        id: segmentRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: modelData.icon
                                            size: 15
                                            color: active ? Theme.textOnAccent : Theme.text
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            color: active ? Theme.textOnAccent : Theme.text
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: active ? Font.DemiBold : Font.Normal
                                        }
                                    }
                                    HoverHandler { id: segmentHover }
                                    TapHandler { onTapped: view.mode = modelData.id }
                                }
                            }
                        }
                    }
                }

                // Search
                SiloTextField {
                    id: searchField
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 30
                    visible: view.mode === "table"
                    placeholderText: "Filter rows…"
                    leftPadding: 30
                    font.pixelSize: Theme.fontSizeSmall
                    Icon {
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        name: "fluent-search-20-regular"
                        size: 15
                        color: Theme.textTertiary
                    }
                    IconButton {
                        visible: searchField.text.length > 0
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        iconName: "fluent-dismiss-16-regular"
                        iconSize: 12
                        onClicked: searchField.text = ""
                    }
                }

                // Header row toggle
                SiloButton {
                    visible: view.mode === "table"
                    implicitHeight: 30
                    text: "Header row"
                    iconName: csv.hasHeader ? "fluent-checkbox-checked-20-regular" : "fluent-checkbox-unchecked-20-regular"
                    accent: csv.hasHeader
                    onClicked: csv.hasHeader = !csv.hasHeader
                }

                // Row / column edits
                Row {
                    visible: view.mode === "table" && !view.readOnly
                    spacing: 2
                    IconButton {
                        iconName: "fluent-table-insert-row-20-regular"
                        tooltip: view.selectedRow >= 0 ? "Insert row below" : "Add row"
                        onClicked: view.insertRow(true)
                    }
                    IconButton {
                        iconName: "fluent-table-delete-row-20-regular"
                        tooltip: "Delete row"
                        enabled: view.selectedRow >= 0
                        onClicked: view.deleteRow()
                    }
                    IconButton {
                        iconName: "fluent-table-insert-column-20-regular"
                        tooltip: view.selectedColumn >= 0 ? "Insert column right" : "Add column"
                        onClicked: view.insertColumn(true)
                    }
                    IconButton {
                        iconName: "fluent-table-delete-column-20-regular"
                        tooltip: "Delete column"
                        enabled: view.selectedColumn >= 0 && csv.columns > 1
                        onClicked: view.deleteColumn()
                    }
                }

                Item { Layout.fillWidth: true }

                // Autosave status
                Row {
                    visible: view.mode === "table" && (view.saveState !== "" || view.readOnly)
                    Layout.rightMargin: 8
                    spacing: 5
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: view.saveState !== "saving"
                        name: view.saveState === "saved" ? "fluent-checkmark-20-regular"
                            : view.saveState === "error" ? "fluent-dismiss-16-regular" : "fluent-lock-closed-20-regular"
                        size: 13
                        color: view.saveState === "error" ? Theme.destructive : view.saveState === "saved" ? Theme.accent : Theme.textTertiary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: view.saveState === "saving" ? "Saving…"
                            : view.saveState === "saved" ? "Saved"
                            : view.saveState === "error" ? (view.saveError || "Could not save")
                            : csv.truncated ? "Too large to edit" : "Read only"
                        color: view.saveState === "error" ? Theme.destructive : Theme.textTertiary
                        font.pixelSize: Theme.fontSizeCaption
                    }
                }

                Text {
                    visible: view.mode === "table"
                    text: (csv.visibleRows !== csv.totalRows ? csv.visibleRows.toLocaleString() + " of " : "")
                          + csv.totalRows.toLocaleString() + (csv.totalRows === 1 ? " row" : " rows")
                          + "  ·  " + csv.columns + (csv.columns === 1 ? " column" : " columns")
                          + "  ·  " + csv.delimiterName
                          + (csv.truncated ? "  ·  truncated" : "")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                }
            }

            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
        }

        // ------------------------------------------------------------ content
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Raw text (editable)
            Loader {
                id: textLoader
                // Created on first use, then kept alive so switching back is instant
                property bool everShown: false
                anchors.fill: parent
                visible: view.mode === "text"
                onVisibleChanged: if (visible) everShown = true
                active: everShown
                sourceComponent: TextEditor {
                    path: view.path
                    language: "plaintext"
                    // Keep the table in sync with what was typed
                    onSaved: if (view.mode !== "table" || !view.editing) csv.reload()
                }
            }

            // Spreadsheet
            Item {
                id: sheet
                anchors.fill: parent
                visible: view.mode === "table"
                onVisibleChanged: if (visible && view.visible) forceActiveFocus()
                Component.onCompleted: if (visible && view.visible) forceActiveFocus()
                readonly property int rowHeaderWidth: Math.max(40, String(csv.totalRows).length * 8 + 20)

                // Corner
                Rectangle {
                    x: 0; y: 0
                    width: sheet.rowHeaderWidth
                    height: view.rowHeight
                    color: Theme.surface
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
                }

                HorizontalHeaderView {
                    id: columnHeader
                    x: sheet.rowHeaderWidth
                    y: 0
                    width: sheet.width - x
                    height: view.rowHeight
                    syncView: table
                    clip: true
                    delegate: Rectangle {
                        id: headerCell
                        required property int index
                        required property string display
                        readonly property bool sorted: csv.sortColumn === index
                        implicitWidth: table.columnWidthProvider(index)
                        implicitHeight: view.rowHeight
                        color: headerHover.hovered ? Theme.controlHover : Theme.surface
                        Text {
                            anchors.left: parent.left
                            anchors.right: sortIcon.visible ? sortIcon.left : parent.right
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: headerCell.display
                            color: headerCell.sorted ? Theme.accent : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Icon {
                            id: sortIcon
                            visible: headerCell.sorted
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            name: csv.sortDescending ? "fluent-arrow-sort-down-20-regular" : "fluent-arrow-sort-up-20-regular"
                            size: 14
                            color: Theme.accent
                        }
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
                        HoverHandler { id: headerHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: csv.toggleSort(headerCell.index)
                            onDoubleTapped: view.beginEdit(-1, headerCell.index)
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: { view.selectedColumn = headerCell.index; view.selectedRow = -1; cellMenu.popup() }
                        }
                        Loader {
                            anchors.fill: parent
                            active: view.editRow === -1 && view.editColumn === headerCell.index
                            sourceComponent: cellEditor
                            onLoaded: item.start(headerCell.display, view.editSeed)
                        }
                    }
                }

                VerticalHeaderView {
                    id: rowHeader
                    x: 0
                    y: view.rowHeight
                    width: sheet.rowHeaderWidth
                    height: sheet.height - y
                    syncView: table
                    clip: true
                    delegate: Rectangle {
                        required property int index
                        required property var display
                        implicitWidth: sheet.rowHeaderWidth
                        implicitHeight: view.rowHeight
                        color: view.selectedRow === index ? Theme.accentSoft : Theme.surface
                        Text {
                            anchors.centerIn: parent
                            text: display
                            color: view.selectedRow === index ? Theme.accent : Theme.textTertiary
                            font.pixelSize: Theme.fontSizeCaption
                        }
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
                        TapHandler { onTapped: { view.selectedRow = index; view.selectedColumn = -1 } }
                    }
                }

                TableView {
                    id: table
                    x: sheet.rowHeaderWidth
                    y: view.rowHeight
                    width: sheet.width - x
                    height: sheet.height - y
                    clip: true
                    model: csv
                    boundsBehavior: Flickable.StopAtBounds
                    columnSpacing: 0
                    rowSpacing: 0
                    columnWidthProvider: function(column) { return csv.columnWidth(column) }
                    rowHeightProvider: function() { return view.rowHeight }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: cell
                        required property int row
                        required property int column
                        required property string display
                        readonly property bool rowSelected: view.selectedRow === row
                        readonly property bool selected: rowSelected && view.selectedColumn === column
                        implicitWidth: 100
                        implicitHeight: view.rowHeight
                        color: selected ? Theme.selection
                             : rowSelected ? Theme.accentSoft
                             : row % 2 === 1 ? Theme.surfaceAlt : Theme.surface
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            text: cell.display
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.divider }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: { view.selectedRow = cell.row; view.selectedColumn = cell.column; sheet.forceActiveFocus() }
                            onDoubleTapped: {
                                if (view.readOnly) { view.copySelection(false); copyToast.show("Cell copied") }
                                else view.beginEdit(cell.row, cell.column)
                            }
                        }
                        Loader {
                            anchors.fill: parent
                            active: view.editRow === cell.row && view.editColumn === cell.column
                            sourceComponent: cellEditor
                            onLoaded: item.start(cell.display, view.editSeed)
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                view.selectedRow = cell.row
                                view.selectedColumn = cell.column
                                cellMenu.popup()
                            }
                        }
                        ToolTip.visible: cellHover.hovered && cell.display.length > 0 && cellText.truncated
                        ToolTip.delay: 600
                        ToolTip.text: cell.display
                        HoverHandler { id: cellHover }
                        // Hidden probe to know whether the text is elided
                        Text { id: cellText; visible: false; width: cell.width - 20; text: cell.display; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight }
                    }
                }

                // Keyboard: arrows move the selection, Ctrl+C copies the row (Shift: cell),
                // Enter / F2 or typing edits the cell, Delete clears it.
                focus: visible
                Keys.onPressed: function(event) {
                    if (view.editing)
                        return
                    var canEdit = !view.readOnly && view.selectedRow >= 0 && view.selectedColumn >= 0
                    if (canEdit && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_F2)) {
                        view.beginEdit(view.selectedRow, view.selectedColumn)
                        event.accepted = true
                        return
                    }
                    if (canEdit && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
                        view.clearCell()
                        event.accepted = true
                        return
                    }
                    if (canEdit && event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))
                            && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Tab && event.text.charCodeAt(0) >= 32) {
                        view.beginEdit(view.selectedRow, view.selectedColumn, event.text)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Down && view.selectedRow < csv.visibleRows - 1) { view.selectedRow++; event.accepted = true }
                    else if (event.key === Qt.Key_Up && view.selectedRow > 0) { view.selectedRow--; event.accepted = true }
                    else if (event.key === Qt.Key_Right && view.selectedColumn < csv.columns - 1) { view.selectedColumn++; event.accepted = true }
                    else if (event.key === Qt.Key_Left && view.selectedColumn > 0) { view.selectedColumn--; event.accepted = true }
                    else if (event.matches(StandardKey.Copy)) {
                        view.copySelection(!(event.modifiers & Qt.ShiftModifier) || view.selectedColumn < 0)
                        copyToast.show(view.selectedColumn < 0 || !(event.modifiers & Qt.ShiftModifier) ? "Row copied" : "Cell copied")
                        event.accepted = true
                    }
                    if (event.accepted && view.selectedRow >= 0)
                        table.positionViewAtRow(view.selectedRow, TableView.Contain)
                }

                // Empty states
                Column {
                    anchors.centerIn: parent
                    visible: csv.visibleRows === 0
                    spacing: 8
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "fluent-table-24-regular"
                        size: 48
                        color: Theme.borderStrong
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: csv.totalRows === 0 ? "No data" : "No rows match the filter"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            SiloMenu {
                id: cellMenu
                readonly property bool onHeader: view.selectedRow === -1
                SiloMenuItem {
                    text: cellMenu.onHeader ? "Rename column" : "Edit cell"
                    iconName: "fluent-edit-20-regular"
                    enabled: !view.readOnly && (!cellMenu.onHeader || csv.hasHeader)
                    onTriggered: view.beginEdit(view.selectedRow, view.selectedColumn)
                }
                SiloMenuItem {
                    text: "Copy cell"
                    iconName: "fluent-copy-20-regular"
                    visible: !cellMenu.onHeader
                    height: visible ? implicitHeight : 0
                    onTriggered: { view.copySelection(false); copyToast.show("Cell copied") }
                }
                SiloMenuItem {
                    text: "Copy row"
                    visible: !cellMenu.onHeader
                    height: visible ? implicitHeight : 0
                    onTriggered: { view.copySelection(true); copyToast.show("Row copied") }
                }
                MenuSeparator {
                    padding: 4
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
                }
                SiloMenuItem {
                    text: "Insert row above"
                    iconName: "fluent-table-insert-row-20-regular"
                    enabled: !view.readOnly
                    visible: !cellMenu.onHeader
                    height: visible ? implicitHeight : 0
                    onTriggered: view.insertRow(false)
                }
                SiloMenuItem {
                    text: "Insert row below"
                    enabled: !view.readOnly
                    visible: !cellMenu.onHeader
                    height: visible ? implicitHeight : 0
                    onTriggered: view.insertRow(true)
                }
                SiloMenuItem {
                    text: "Delete row"
                    iconName: "fluent-table-delete-row-20-regular"
                    destructive: true
                    enabled: !view.readOnly
                    visible: !cellMenu.onHeader
                    height: visible ? implicitHeight : 0
                    onTriggered: view.deleteRow()
                }
                MenuSeparator {
                    visible: !cellMenu.onHeader
                    height: visible ? implicitHeight : 0
                    padding: 4
                    contentItem: Rectangle { implicitHeight: 1; color: Theme.divider }
                }
                SiloMenuItem {
                    text: "Insert column left"
                    iconName: "fluent-table-insert-column-20-regular"
                    enabled: !view.readOnly
                    onTriggered: view.insertColumn(false)
                }
                SiloMenuItem {
                    text: "Insert column right"
                    enabled: !view.readOnly
                    onTriggered: view.insertColumn(true)
                }
                SiloMenuItem {
                    text: "Delete column"
                    iconName: "fluent-table-delete-column-20-regular"
                    destructive: true
                    enabled: !view.readOnly && csv.columns > 1
                    onTriggered: view.deleteColumn()
                }
            }

            // In-place cell editor, loaded over the cell being edited
            Component {
                id: cellEditor
                Rectangle {
                    id: editorBox
                    color: Theme.fieldBgFocused
                    border.width: 2
                    border.color: Theme.accent
                    function start(current, seed) {
                        view.activeEditor = input
                        input.text = seed.length > 0 ? seed : current
                        input.forceActiveFocus()
                        if (seed.length > 0) input.cursorPosition = input.length
                        else input.selectAll()
                    }
                    TextInput {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.textOnAccent
                        font.pixelSize: Theme.fontSizeSmall
                        clip: true
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) { view.endEdit(); event.accepted = true }
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                var row = view.editRow, column = view.editColumn
                                view.commitEdit(text)
                                // Enter moves down like a spreadsheet
                                if (row >= 0 && row < csv.visibleRows - 1) view.selectedRow = row + 1
                                event.accepted = true
                            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                var r = view.editRow, c = view.editColumn
                                var next = event.key === Qt.Key_Tab ? c + 1 : c - 1
                                view.commitEdit(text)
                                if (next >= 0 && next < csv.columns) view.beginEdit(r, next)
                                event.accepted = true
                            }
                        }
                        onActiveFocusChanged: if (!activeFocus && view.editRow > -2) view.commitEdit(text)
                        Component.onDestruction: if (view.activeEditor === input) view.activeEditor = null
                    }
                }
            }

            // Small confirmation toast
            Rectangle {
                id: copyToast
                property string message: ""
                function show(text) { message = text; opacity = 1; toastTimer.restart() }
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                width: toastText.implicitWidth + 28
                height: 30
                radius: 15
                color: Theme.text
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.animationNormal } }
                Text {
                    id: toastText
                    anchors.centerIn: parent
                    text: copyToast.message
                    color: Theme.surface
                    font.pixelSize: Theme.fontSizeSmall
                }
                Timer { id: toastTimer; interval: 1400; onTriggered: copyToast.opacity = 0 }
            }
        }
    }
}
