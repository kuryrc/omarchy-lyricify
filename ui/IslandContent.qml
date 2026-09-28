// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import "../core/I18n.js" as I18n
import "../core/Timeline.js" as Timeline
import QtQuick
import QtQuick.Controls as Controls

Item {
    id: root

    required property var playback
    property bool expanded: false
    property bool collapsed: false
    property real offsetMs: 0
    property bool motion: true
    readonly property bool dragging: drag.dragging
    readonly property real lyricPosition: playback.positionMs + offsetMs
    readonly property int activeIndex: Timeline.activeIndex(playback.lines, lyricPosition)
    readonly property int displayIndex: Timeline.displayIndex(playback.lines, lyricPosition)
    readonly property var activeLine: displayIndex >= 0 ? playback.lines[displayIndex] : null
    readonly property bool hovered: hover.hovered
    readonly property bool showControls: hovered && !expanded && !collapsed && !dragging

    signal toggleExpanded()
    signal openSettings()
    signal adjustOffset(real delta)
    signal moveStarted()
    signal moveRequested(real deltaX)
    signal moveFinished(bool canceled)

    function tr(en, zh) {
        return I18n.text(playback.language || "auto", en, zh);
    }

    function renderState() {
        return current.renderState();
    }

    HoverHandler {
        id: hover
    }

    DragSurface {
        id: drag

        anchors.fill: parent
        onActivated: root.toggleExpanded()
        onContextRequested: root.openSettings()
        onMoveStarted: root.moveStarted()
        onMoveRequested: (deltaX) => {
            return root.moveRequested(deltaX);
        }
        onMoveFinished: (canceled) => {
            return root.moveFinished(canceled);
        }
    }

    Item {
        id: musicMark

        x: root.collapsed ? 29 : 33
        y: root.collapsed ? 8 : 24
        width: 30
        height: 32

        Row {
            spacing: 3
            anchors.centerIn: parent

            Repeater {
                model: [12, 23, 32, 20, 10]

                Rectangle {
                    required property int modelData
                    required property int index

                    width: 4
                    height: modelData
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 2
                    color: "#36da85"
                    opacity: root.playback.playing ? 0.9 : 0.35

                    SequentialAnimation on scale {
                        running: root.motion && root.playback.playing && root.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: 0.55
                            to: 1
                            duration: 440 + index * 110
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            from: 1
                            to: 0.55
                            duration: 530 + index * 80
                            easing.type: Easing.InOutSine
                        }

                    }

                }

            }

        }

    }

    Text {
        visible: root.collapsed
        x: 78
        y: 10
        width: parent.width - 151
        text: root.playback.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: "Noto Sans CJK JP"
        font.pixelSize: 14
        color: "#bcbfbc"
    }

    Item {
        id: lyricArea

        property bool ready: false

        function changeLine() {
            if (!ready)
                return ;

            transition.stop();
            outgoing.line = current.line;
            outgoing.positionMs = root.lyricPosition;
            current.line = root.activeLine || {
                "text": root.playback.title,
                "translation": root.playback.statusText,
                "startMs": 0,
                "endMs": 1e+12,
                "words": []
            };
            transition.restart();
        }

        x: 79
        y: 11
        width: parent.width - 162
        height: 66
        opacity: root.collapsed || root.showControls ? 0 : 1
        visible: opacity > 0
        clip: true
        Component.onCompleted: {
            ready = true;
            changeLine();
        }

        LyricBlock {
            id: outgoing

            width: parent.width
            opacity: 0
        }

        LyricBlock {
            id: current

            objectName: "currentLyricBlock"
            width: parent.width
            positionMs: root.lyricPosition
            animate: root.motion && root.playback.playing
        }

        Connections {
            function onDisplayIndexChanged() {
                lyricArea.changeLine();
            }

            target: root
        }

        Connections {
            function onDocumentIdChanged() {
                lyricArea.changeLine();
            }

            function onLinesChanged() {
                Qt.callLater(lyricArea.changeLine);
            }

            function onStatusTextChanged() {
                if (root.activeLine === null)
                    lyricArea.changeLine();

            }

            function onTitleChanged() {
                if (root.activeLine === null)
                    lyricArea.changeLine();

            }

            target: root.playback
        }

        ParallelAnimation {
            id: transition

            NumberAnimation {
                target: current
                property: "y"
                from: 15
                to: 0
                duration: 340
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: current
                property: "opacity"
                from: 0
                to: 1
                duration: 220
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: outgoing
                property: "y"
                from: 0
                to: -15
                duration: 260
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: outgoing
                property: "opacity"
                from: 1
                to: 0
                duration: 180
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 130
            }

        }

    }

    Rectangle {
        id: coverFrame

        x: root.width - (root.collapsed ? 61 : 77)
        y: root.collapsed ? 8 : 20
        width: root.collapsed ? 29 : 44
        height: width
        radius: 10
        color: "#25312f"
        clip: true

        Image {
            anchors.fill: parent
            source: root.playback.artUrl
            sourceSize.width: 160
            sourceSize.height: 160
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }

    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 27
        spacing: 20
        visible: root.showControls

        IconButton {
            label: "‹"
            hint: root.tr("Previous", "上一曲")
            enabled: root.playback.canPrevious
            onClicked: root.playback.previous()
        }

        IconButton {
            label: root.playback.playing ? "Ⅱ" : "▷"
            hint: root.tr("Play or pause", "播放或暂停")
            primary: true
            enabled: root.playback.canToggle
            onClicked: root.playback.togglePlaying()
        }

        IconButton {
            label: "›"
            hint: root.tr("Next", "下一曲")
            enabled: root.playback.canNext
            onClicked: root.playback.next()
        }

        IconButton {
            label: "⌄"
            hint: root.tr("Expand lyrics", "展开歌词")
            onClicked: root.toggleExpanded()
        }

    }

    Item {
        x: 38
        y: 95
        width: parent.width - 76
        height: 242
        opacity: root.expanded ? 1 : 0
        visible: opacity > 0
        enabled: root.expanded

        Rectangle {
            width: parent.width
            height: 1
            color: "#282c2a"
        }

        Text {
            y: 13
            width: parent.width - 35
            text: root.playback.title + "  ·  " + root.playback.artist
            textFormat: Text.PlainText
            font.family: "Noto Sans CJK JP"
            font.pixelSize: 12
            elide: Text.ElideRight
            color: "#919b95"
        }

        IconButton {
            anchors.right: parent.right
            y: 5
            label: "⌃"
            hint: root.tr("Collapse", "收起")
            onClicked: root.toggleExpanded()
        }

        IconButton {
            anchors.right: parent.right
            anchors.rightMargin: 38
            y: 5
            label: "⚙"
            hint: root.tr("Settings", "设置")
            onClicked: root.openSettings()
        }

        Column {
            y: 42
            width: parent.width
            spacing: 6

            Repeater {
                model: 3

                Text {
                    required property int index
                    property int lyricIndex: Math.max(0, root.displayIndex) + index - 1

                    width: parent.width
                    height: Math.min(implicitHeight, 66)
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    text: lyricIndex >= 0 && lyricIndex < root.playback.lines.length ? root.playback.lines[lyricIndex].text : ""
                    textFormat: Text.PlainText
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: index === 1 ? 17 : 14
                    color: index === 1 ? "#f3f5f1" : "#747e77"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

            }

        }

        Text {
            visible: !root.playback.demo && root.playback.lines.length === 0
            y: 63
            width: parent.width
            text: root.playback.statusText
            color: "#818b84"
            horizontalAlignment: Text.AlignHCenter
            font.family: "Noto Sans CJK JP"
            font.pixelSize: 14
        }

        Controls.Slider {
            id: progress

            y: 139
            width: parent.width
            height: 22
            from: 0
            to: Math.max(1, root.playback.durationMs)
            enabled: root.playback.canSeek
            value: root.playback.positionMs
            onMoved: root.playback.seek(value)

            background: Rectangle {
                x: progress.leftPadding
                y: progress.topPadding + progress.availableHeight / 2 - 2
                width: progress.availableWidth
                height: 3
                radius: 1.5
                color: "#303934"

                Rectangle {
                    width: parent.width * progress.visualPosition
                    height: parent.height
                    radius: 1.5
                    color: "#5fdd95"
                }

            }

            handle: Rectangle {
                x: progress.leftPadding + progress.visualPosition * (progress.availableWidth - width)
                y: progress.topPadding + progress.availableHeight / 2 - height / 2
                width: 8
                height: 8
                radius: 4
                color: "#ddffe7"
            }

        }

        Text {
            y: 164
            text: Timeline.formatTime(root.playback.positionMs)
            color: "#818b84"
            font.pixelSize: 11
        }

        Text {
            y: 164
            anchors.right: parent.right
            text: Timeline.formatTime(root.playback.durationMs)
            color: "#818b84"
            font.pixelSize: 11
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 189
            spacing: 20

            IconButton {
                label: "‹"
                hint: root.tr("Previous", "上一曲")
                enabled: root.playback.canPrevious
                onClicked: root.playback.previous()
            }

            IconButton {
                label: root.playback.playing ? "Ⅱ" : "▷"
                hint: root.tr("Play or pause", "播放或暂停")
                primary: true
                enabled: root.playback.canToggle
                onClicked: root.playback.togglePlaying()
            }

            IconButton {
                label: "›"
                hint: root.tr("Next", "下一曲")
                enabled: root.playback.canNext
                onClicked: root.playback.next()
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }

        }

    }

}
