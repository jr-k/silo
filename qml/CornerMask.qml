import QtQuick
import QtQuick.Shapes

// Paints, over a corner of a rounded card, the area outside the arc (in the
// surrounding background color) plus the card border along the arc. Lets a
// card keep its radius where content with a square clip (a WebEngineView)
// would otherwise poke through. Place it at the corner, `radius` wide.
Item {
    id: mask
    property real radius: Theme.radiusLarge
    property color color: Theme.windowBg
    property color borderColor: Theme.border
    property real borderWidth: 1
    // "topLeft" | "topRight" | "bottomRight" | "bottomLeft"
    property string corner: "bottomLeft"

    width: radius
    height: radius
    rotation: corner === "topRight" ? 90 : corner === "bottomRight" ? 180 : corner === "bottomLeft" ? 270 : 0

    // Drawn for the top-left corner, then rotated about the centre
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            fillColor: mask.color
            strokeColor: "transparent"
            startX: 0; startY: mask.radius
            PathArc { x: mask.radius; y: 0; radiusX: mask.radius; radiusY: mask.radius }
            PathLine { x: 0; y: 0 }
            PathLine { x: 0; y: mask.radius }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: mask.borderColor
            strokeWidth: mask.borderWidth
            capStyle: ShapePath.FlatCap
            startX: mask.borderWidth / 2; startY: mask.radius
            PathArc {
                x: mask.radius; y: mask.borderWidth / 2
                radiusX: mask.radius - mask.borderWidth / 2
                radiusY: mask.radius - mask.borderWidth / 2
            }
        }
    }
}
