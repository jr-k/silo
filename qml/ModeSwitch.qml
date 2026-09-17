import QtQuick

// Segmented pill switching between Organize (setup) and Live (working) modes, with a sliding thumb.
Rectangle {
    id: control
    // Natural width from the labels; when the control is narrower (sidebar
    // footer) the segments share what is available instead of overflowing.
    implicitWidth: {
        var total = 0
        for (var i = 0; i < segmentRepeater.count; ++i) {
            var item = segmentRepeater.itemAt(i)
            total += item ? item.naturalWidth : 0
        }
        return total + 8
    }
    implicitHeight: 36
    radius: height / 2
    color: Theme.controlBg
    border.width: 1
    border.color: Theme.borderStrong

    readonly property var options: [
        { key: "setup", label: "Organize", icon: "fluent-wrench-20-regular" },
        { key: "working", label: "Live", icon: "fluent-window-20-regular" }
    ]
    readonly property int currentIndex: Session.working ? 1 : 0

    // Sliding thumb
    Rectangle {
        id: thumb
        // Depends on the repeater count so it re-evaluates once the segments exist.
        readonly property Item target: segmentRepeater.count > control.currentIndex
                                       ? segmentRepeater.itemAt(control.currentIndex) : null
        x: target ? segments.x + target.x : 4
        y: 4
        width: target ? target.width : 0
        height: parent.height - 8
        radius: height / 2
        color: Theme.accent
        Behavior on x { NumberAnimation { duration: Theme.animationNormal; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.animationNormal; easing.type: Easing.OutCubic } }
    }

    Row {
        id: segments
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            id: segmentRepeater
            model: control.options
            delegate: Item {
                id: segment
                required property int index
                required property var modelData
                readonly property bool active: control.currentIndex === index
                readonly property real naturalWidth: content.implicitWidth + 28
                width: (control.width - 8) / segmentRepeater.count
                height: control.height - 8

                HoverHandler { id: segmentHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Session.setMode(segment.modelData.key) }

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 7
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: segment.modelData.icon
                        size: 16
                        color: segment.active ? Theme.textOnAccent
                             : segmentHover.hovered ? Theme.text : Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: Theme.animationFast } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: segment.modelData.label
                        font.pixelSize: Theme.fontSize
                        font.weight: Font.DemiBold
                        color: segment.active ? Theme.textOnAccent
                             : segmentHover.hovered ? Theme.text : Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: Theme.animationFast } }
                    }
                }
            }
        }
    }
}
