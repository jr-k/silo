import QtQuick

// Colored rounded square showing a workspace emoji or image.
Rectangle {
    id: badge
    property string iconType: "emoji"
    property string iconValue: "📦"
    property real size: 28

    width: size
    height: size
    radius: Math.round(size * 0.25)
    color: "#176E61"

    Image {
        anchors.fill: parent
        anchors.margins: Math.round(badge.size * 0.18)
        visible: badge.iconType === "image"
        source: badge.iconType === "image" ? badge.iconValue : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        sourceSize: Qt.size(96, 96)
    }

    Text {
        anchors.centerIn: parent
        visible: badge.iconType !== "image"
        text: badge.iconValue
        font.pixelSize: Math.round(badge.size * 0.55)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
