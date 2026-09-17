pragma Singleton
import QtQuick

// Application wide drag session. The visual proxy lives in Main.qml and the
// DropAreas read `ids` to know what is being moved.
QtObject {
    property bool active: false
    property var ids: []
    property string label: ""
    property string kind: "folder"
    property int count: 0
    property real x: 0
    property real y: 0
    property Item proxy: null

    function begin(idList, text, nodeKind, scenePos) {
        ids = idList.slice()
        count = idList.length
        label = text
        kind = nodeKind
        x = scenePos.x
        y = scenePos.y
        active = true
    }

    function update(scenePos) {
        x = scenePos.x
        y = scenePos.y
    }

    function finish() {
        if (!active)
            return
        if (proxy)
            proxy.drop()
        active = false
        ids = []
        count = 0
    }

    function cancel() {
        active = false
        ids = []
        count = 0
    }

    function contains(id) {
        return ids.indexOf(id) >= 0
    }
}
