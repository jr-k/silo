import QtQuick
import QtQuick.Controls

SiloMenu {
    id: menu
    title: "Color"
    // Filled with the folder's current color
    iconName: "fluent-folder-20-filled"
    iconColor: currentColor.length > 0 ? currentColor : Theme.folder

    property string folderId: ""
    readonly property string currentColor: {
        var revision = appStore.revision
        return folderId.length > 0 ? (appStore.nodeInfo(folderId).color || "") : ""
    }

    function apply(color) {
        appStore.setFolderColor(folderId, color)
    }

    SiloMenuItem {
        text: "Default"
        iconName: "fluent-folder-20-filled"
        iconColor: Theme.folder
        checkable: true
        checked: menu.currentColor.length === 0
        onTriggered: menu.apply("")
    }
    SiloMenuItem {
        text: "Red"
        iconName: "fluent-folder-20-filled"
        iconColor: "#FF453A"
        checkable: true
        checked: menu.currentColor === "#FF453A"
        onTriggered: menu.apply("#FF453A")
    }
    SiloMenuItem {
        text: "Orange"
        iconName: "fluent-folder-20-filled"
        iconColor: "#FF9F0A"
        checkable: true
        checked: menu.currentColor === "#FF9F0A"
        onTriggered: menu.apply("#FF9F0A")
    }
    SiloMenuItem {
        text: "Yellow"
        iconName: "fluent-folder-20-filled"
        iconColor: "#FFD60A"
        checkable: true
        checked: menu.currentColor === "#FFD60A"
        onTriggered: menu.apply("#FFD60A")
    }
    SiloMenuItem {
        text: "Green"
        iconName: "fluent-folder-20-filled"
        iconColor: "#30D158"
        checkable: true
        checked: menu.currentColor === "#30D158"
        onTriggered: menu.apply("#30D158")
    }
    SiloMenuItem {
        text: "Blue"
        iconName: "fluent-folder-20-filled"
        iconColor: "#0A84FF"
        checkable: true
        checked: menu.currentColor === "#0A84FF"
        onTriggered: menu.apply("#0A84FF")
    }
    SiloMenuItem {
        text: "Purple"
        iconName: "fluent-folder-20-filled"
        iconColor: "#BF5AF2"
        checkable: true
        checked: menu.currentColor === "#BF5AF2"
        onTriggered: menu.apply("#BF5AF2")
    }
    SiloMenuItem {
        text: "Pink"
        iconName: "fluent-folder-20-filled"
        iconColor: "#FF375F"
        checkable: true
        checked: menu.currentColor === "#FF375F"
        onTriggered: menu.apply("#FF375F")
    }
    SiloMenuItem {
        text: "Gray"
        iconName: "fluent-folder-20-filled"
        iconColor: "#8E8E93"
        checkable: true
        checked: menu.currentColor === "#8E8E93"
        onTriggered: menu.apply("#8E8E93")
    }
}
