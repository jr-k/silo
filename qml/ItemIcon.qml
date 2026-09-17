import QtQuick

// Default (non-custom) icon of a leaf item: the site's favicon for web pages,
// a typed glyph (terminal, document, image…) for SSH and file items.
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

    SiteIcon {
        anchors.fill: parent
        visible: root.isWeb
        size: root.size
        imagePadding: root.imagePadding
        url: root.isWeb ? root.url : ""
        fallbackName: ItemTypes.glyph("web", root.url, root.variant)
        fallbackColor: Theme.link
    }

    Icon {
        anchors.centerIn: parent
        visible: !root.isWeb
        size: root.size - root.glyphPadding * 2
        name: ItemTypes.glyph(root.type, root.url, root.variant)
        color: ItemTypes.color(root.type, root.url)
    }
}
