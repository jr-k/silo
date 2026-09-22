import QtQuick
import QtQuick.Window

// Default (non-custom) icon of a leaf item: the site's favicon for web pages,
// a thumbnail for image files, a typed glyph (terminal, document…) otherwise.
Item {
    id: root
    property string type: "web"
    property string url: ""
    property real size: 16
    // "20" for lists, "24" for tiles
    property string variant: "20"
    property real imagePadding: 0
    // Glyph inset (tile glyphs look better slightly smaller than the favicon box)
    property real glyphPadding: 0

    width: size
    height: size

    readonly property bool isWeb: type !== "ssh" && type !== "file"
    readonly property bool isImageFile: type === "file" && ItemTypes.fileKind(url) === "image"
    // Falls back to the glyph while decoding or if the format is unsupported / file missing.
    readonly property bool thumbReady: isImageFile && thumb.status === Image.Ready && thumb.implicitWidth > 0

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1

    SiteIcon {
        anchors.fill: parent
        visible: root.isWeb
        size: root.size
        imagePadding: root.imagePadding
        url: root.isWeb ? root.url : ""
        fallbackName: ItemTypes.glyph("web", root.url, root.variant)
        fallbackColor: Theme.link
    }

    // Image files: scaled-down preview of the file itself
    Image {
        id: thumb
        anchors.fill: parent
        anchors.margins: root.imagePadding
        visible: root.thumbReady
        source: root.isImageFile && root.url.trim().length > 0 ? files.toUrl(files.expand(root.url)) : ""
        sourceSize: Qt.size(Math.round(root.size * root.dpr), Math.round(root.size * root.dpr))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        cache: true
    }

    Icon {
        anchors.centerIn: parent
        visible: !root.isWeb && !root.thumbReady
        size: root.size - root.glyphPadding * 2
        name: ItemTypes.glyph(root.type, root.url, root.variant)
        color: ItemTypes.color(root.type, root.url)
    }
}
