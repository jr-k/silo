import QtQuick
import QtQuick.Layouts
import QtWebEngine
import QtMultimedia

// Viewer page of a "file" tab. Picks a viewer from the file kind:
// PDF (Chromium's viewer), image, video/audio (QtMultimedia), text/code
// (editable, Ace), or a plain card for anything else.
Item {
    id: page
    property string tabUrl: ""
    property bool loaded: false

    readonly property string kind: "file"
    // Re-inspected whenever the path changes or the tab is reloaded
    property var info: ({})
    readonly property string displayUrl: info.path || tabUrl
    readonly property bool loading: viewer.item ? !!viewer.item.loading : false
    readonly property bool canGoBack: false
    readonly property bool canGoForward: false
    readonly property int loadProgress: viewer.item && viewer.item.loadProgress !== undefined ? viewer.item.loadProgress : 100
    readonly property string icon: ""
    // The active viewer (CsvView, image view…), for callers that need to drive it
    readonly property Item viewerItem: viewer.item

    function inspect() { info = files.inspect(tabUrl) }
    function ensureLoaded() {
        if (loaded)
            return
        loaded = true
        inspect()
    }
    function reload() {
        inspect()
        if (viewer.item && viewer.item.reload)
            viewer.item.reload()
    }
    function stop() {}
    function goBack() {}
    function goForward() {}
    function openExternally() { Qt.openUrlExternally(files.toUrl(tabUrl)) }
    function showInFolder() { Qt.openUrlExternally(files.toUrl(info.dir || "")) }

    onTabUrlChanged: if (loaded) inspect()

    Loader {
        id: viewer
        anchors.fill: parent
        sourceComponent: {
            if (!page.loaded)
                return null
            if (!page.info.exists || page.info.isDir)
                return missingView
            switch (page.info.kind) {
            case "pdf": return pdfView
            case "csv": return csvView
            case "image": return imageView
            case "video":
            case "audio": return mediaView
            case "text": return codeView
            default: return otherView
            }
        }
    }

    // ------------------------------------------------------------------ PDF
    Component {
        id: pdfView
        WebEngineView {
            settings.pluginsEnabled: true
            settings.pdfViewerEnabled: true
            backgroundColor: Theme.surface
            url: page.info.url
        }
    }

    // ------------------------------------------------------------------ csv
    Component {
        id: csvView
        CsvView {
            path: page.info.path
        }
    }

    // ------------------------------------------------------------------ text / code
    // Editable, with autosave (see TextEditor)
    Component {
        id: codeView
        TextEditor {
            path: page.info.path
            language: page.info.language || ""
        }
    }

    // ------------------------------------------------------------------ image
    Component {
        id: imageView
        Item {
            id: imageArea
            property real zoom: 1   // 1 = fit to view
            readonly property bool loading: image.status === Image.Loading

            function reload() { image.source = ""; image.source = page.info.url }

            Rectangle { anchors.fill: parent; color: Theme.surfaceAlt }

            Flickable {
                id: flick
                anchors.fill: parent
                contentWidth: Math.max(width, imageHolder.width)
                contentHeight: Math.max(height, imageHolder.height)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Item {
                    id: imageHolder
                    readonly property real fitScale: image.implicitWidth > 0
                        ? Math.min(1, Math.min(flick.width / image.implicitWidth, flick.height / image.implicitHeight)) : 1
                    width: image.implicitWidth * fitScale * imageArea.zoom
                    height: image.implicitHeight * fitScale * imageArea.zoom
                    x: Math.max(0, (flick.width - width) / 2)
                    y: Math.max(0, (flick.height - height) / 2)

                    Image {
                        id: image
                        anchors.fill: parent
                        source: page.info.url
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        sourceSize.width: implicitWidth > 4096 ? 4096 : 0
                    }
                }

                WheelHandler {
                    acceptedModifiers: Qt.ControlModifier
                    onWheel: function(event) {
                        var factor = event.angleDelta.y > 0 ? 1.1 : 1 / 1.1
                        imageArea.zoom = Math.max(0.1, Math.min(16, imageArea.zoom * factor))
                    }
                }
                TapHandler {
                    onDoubleTapped: imageArea.zoom = imageArea.zoom === 1 ? 1 / imageHolder.fitScale : 1
                }
            }

            // Footer: dimensions + zoom
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                width: footerText.implicitWidth + 20
                height: 24
                radius: 12
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                opacity: 0.92
                Text {
                    id: footerText
                    anchors.centerIn: parent
                    text: image.implicitWidth > 0
                          ? image.implicitWidth + " × " + image.implicitHeight + "  ·  "
                            + Math.round(imageHolder.fitScale * imageArea.zoom * 100) + "%"
                          : "Loading…"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                }
            }
        }
    }

    // ------------------------------------------------------------------ video / audio
    Component {
        id: mediaView
        Item {
            id: mediaArea
            readonly property bool isVideo: page.info.kind === "video"
            readonly property bool loading: player.mediaStatus === MediaPlayer.LoadingMedia
            readonly property bool playing: player.playbackState === MediaPlayer.PlayingState

            // Smooth playhead: MediaPlayer.position only ticks every ~100 ms, so the
            // bar extrapolates between ticks from the last known position and the
            // wall clock, and snaps back whenever a real position arrives.
            property real smoothPosition: 0
            property real anchorPosition: 0
            property real anchorTime: 0
            readonly property real progress: player.duration > 0 ? Math.min(1, smoothPosition / player.duration) : 0

            function togglePlay() { playing ? player.pause() : player.play() }
            function reload() { player.stop(); player.source = ""; player.source = page.info.url }
            function syncPosition() {
                anchorPosition = player.position
                anchorTime = Date.now()
                smoothPosition = player.position
            }

            focus: true
            Keys.onSpacePressed: function(event) { togglePlay(); event.accepted = true }
            Keys.onLeftPressed: function(event) { if (player.seekable) player.position = Math.max(0, player.position - 5000); event.accepted = true }
            Keys.onRightPressed: function(event) { if (player.seekable) player.position = Math.min(player.duration, player.position + 5000); event.accepted = true }
            onVisibleChanged: if (visible) forceActiveFocus()
            Component.onCompleted: if (visible) forceActiveFocus()

            FrameAnimation {
                running: mediaArea.playing && page.visible
                onTriggered: {
                    var estimate = mediaArea.anchorPosition + (Date.now() - mediaArea.anchorTime) * player.playbackRate
                    mediaArea.smoothPosition = player.duration > 0 ? Math.min(estimate, player.duration) : estimate
                }
            }
            function formatTime(ms) {
                var total = Math.max(0, Math.floor(ms / 1000))
                var h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60
                var mm = (h > 0 && m < 10 ? "0" : "") + m, ss = (s < 10 ? "0" : "") + s
                return (h > 0 ? h + ":" : "") + mm + ":" + ss
            }

            Rectangle { anchors.fill: parent; color: mediaArea.isVideo ? "#000000" : Theme.surfaceAlt }

            MediaPlayer {
                id: player
                source: page.info.url
                audioOutput: AudioOutput { id: audio; volume: 0.8 }
                videoOutput: mediaArea.isVideo ? videoOut : null
                onErrorOccurred: function(error, message) { errorText.text = message }
                onPositionChanged: mediaArea.syncPosition()
                onPlaybackStateChanged: mediaArea.syncPosition()
                onSourceChanged: mediaArea.syncPosition()
            }

            VideoOutput {
                id: videoOut
                anchors.fill: parent
                anchors.bottomMargin: controls.height
                visible: mediaArea.isVideo
                fillMode: VideoOutput.PreserveAspectFit
            }

            // Audio artwork
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -controls.height / 2
                visible: !mediaArea.isVideo
                spacing: 16
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 160
                    height: 160
                    radius: 24
                    color: Theme.accentSoft
                    border.width: 1
                    border.color: Theme.accentSoftBorder
                    Icon {
                        anchors.centerIn: parent
                        name: "fluent-music-note-2-24-regular"
                        size: 84
                        color: Theme.accent
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.info.name || ""
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                Text {
                    id: errorText
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text.length > 0
                    color: Theme.destructive
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            TapHandler {
                onTapped: { mediaArea.forceActiveFocus(); if (mediaArea.isVideo) mediaArea.togglePlay() }
            }

            // Transport controls
            Rectangle {
                id: controls
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 52
                color: Theme.surface
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.divider }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 12
                    spacing: 8

                    IconButton {
                        iconName: mediaArea.playing ? "fluent-pause-20-filled" : "fluent-play-20-filled"
                        iconSize: 18
                        tooltip: mediaArea.playing ? "Pause (Space)" : "Play (Space)"
                        onClicked: { mediaArea.togglePlay(); mediaArea.forceActiveFocus() }
                    }
                    Text {
                        text: mediaArea.formatTime(mediaArea.smoothPosition)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeCaption
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignRight
                    }
                    // Seek bar
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.borderStrong
                            Rectangle {
                                width: parent.width * mediaArea.progress
                                height: parent.height
                                radius: 2
                                color: Theme.accent
                            }
                        }
                        Rectangle {
                            x: parent.width * mediaArea.progress - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: Theme.accent
                            border.width: 2
                            border.color: Theme.surface
                        }
                        MouseArea {
                            anchors.fill: parent
                            function seekTo(x) {
                                if (!player.seekable || player.duration <= 0)
                                    return
                                var target = Math.max(0, Math.min(1, x / width)) * player.duration
                                // Move the playhead right away; the player catches up asynchronously.
                                mediaArea.smoothPosition = target
                                mediaArea.anchorPosition = target
                                mediaArea.anchorTime = Date.now()
                                player.position = target
                            }
                            onPressed: function(mouse) { mediaArea.forceActiveFocus(); seekTo(mouse.x) }
                            onPositionChanged: function(mouse) { if (pressed) seekTo(mouse.x) }
                        }
                    }
                    Text {
                        text: mediaArea.formatTime(player.duration)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeCaption
                        Layout.preferredWidth: 44
                    }
                    Icon {
                        name: "fluent-speaker-2-20-regular"
                        size: 16
                        color: Theme.textSecondary
                    }
                    Item {
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 20
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.borderStrong
                            Rectangle {
                                width: parent.width * audio.volume
                                height: parent.height
                                radius: 2
                                color: Theme.textSecondary
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            function setVolume(x) { audio.volume = Math.max(0, Math.min(1, x / width)) }
                            onPressed: function(mouse) { setVolume(mouse.x) }
                            onPositionChanged: function(mouse) { if (pressed) setVolume(mouse.x) }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ other / missing
    Component {
        id: otherView
        FileInfoCard {
            info: page.info
            heading: page.info.name || ""
            message: "No viewer for this kind of file."
            onOpenRequested: page.openExternally()
            onRevealRequested: page.showInFolder()
        }
    }
    Component {
        id: missingView
        FileInfoCard {
            info: page.info
            heading: !!page.info.isDir ? "This is a folder" : "File not found"
            message: page.info.path || page.tabUrl
            showOpen: !!page.info.isDir
            onOpenRequested: page.openExternally()
            onRevealRequested: page.showInFolder()
        }
    }
}
