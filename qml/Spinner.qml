import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Small indeterminate progress ring (Fluent style): faint track, accent arc
// spinning. Usable inline at 12–24 px, unlike the Basic BusyIndicator.
Item {
    id: spinner
    property real size: 16
    property real lineWidth: 2
    property color color: Theme.accent
    property bool running: visible

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    Layout.preferredWidth: size
    Layout.preferredHeight: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            strokeColor: Qt.rgba(spinner.color.r, spinner.color.g, spinner.color.b, 0.18)
            strokeWidth: spinner.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: spinner.size / 2
                centerY: spinner.size / 2
                radiusX: spinner.size / 2 - spinner.lineWidth
                radiusY: spinner.size / 2 - spinner.lineWidth
                startAngle: 0
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: spinner.color
            strokeWidth: spinner.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                id: arc
                centerX: spinner.size / 2
                centerY: spinner.size / 2
                radiusX: spinner.size / 2 - spinner.lineWidth
                radiusY: spinner.size / 2 - spinner.lineWidth
                startAngle: -90
                sweepAngle: 100
            }
        }

        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: spinner.running && spinner.visible
        }
        // The arc breathes between short and long while it spins
        SequentialAnimation {
            running: spinner.running && spinner.visible
            loops: Animation.Infinite
            NumberAnimation { target: arc; property: "sweepAngle"; from: 60; to: 220; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { target: arc; property: "sweepAngle"; from: 220; to: 60; duration: 700; easing.type: Easing.InOutQuad }
        }
    }
}
