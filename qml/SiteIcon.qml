import QtQuick
import QtQuick.Window

// Favicon of a site (fetched and cached by the C++ favicon provider),
// falling back to a themed glyph while loading or when none exists.
Item {
    id: root
    property string url: ""
    property real size: 16
    property string fallbackName: "fluent-globe-20-regular"
    property color fallbackColor: Theme.link
    // Inset applied to the favicon only (the fallback glyph keeps the full size)
    property real imagePadding: 0

    width: size
    height: size

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property bool ready: image.status === Image.Ready && image.implicitWidth > 0

    Image {
        id: image
        anchors.fill: parent
        anchors.margins: root.imagePadding
        source: root.url.trim().length > 0 ? "image://siteicon/" + encodeURIComponent(root.url.trim()) : ""
        sourceSize: Qt.size(Math.round(root.size * root.dpr), Math.round(root.size * root.dpr))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        cache: true
        visible: root.ready
    }

    Icon {
        anchors.fill: parent
        visible: !root.ready
        name: root.fallbackName
        size: root.size
        color: root.fallbackColor
    }
}
