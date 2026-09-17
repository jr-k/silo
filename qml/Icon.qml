import QtQuick
import QtQuick.Layouts
import QtQuick.Window

// Renders a bundled Iconify SVG (see scripts/fetch-icons.sh) tinted with `color`.
Image {
    id: icon
    property string name: ""
    property color color: Theme.textSecondary
    property real size: 16

    width: size
    height: size
    // Inside Layouts the implicit (device-pixel) size would be used otherwise.
    Layout.preferredWidth: size
    Layout.preferredHeight: size
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: false

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    sourceSize: Qt.size(Math.round(size * dpr), Math.round(size * dpr))
    source: name.length > 0
            ? "image://icon/" + name + "/" + String(color).replace("#", "")
            : ""
}
