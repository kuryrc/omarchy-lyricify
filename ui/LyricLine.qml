// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import "../core/Timeline.js" as Timeline
import QtQuick

Item {
    id: root

    property var line: null
    property real positionMs: 0
    property real fontSize: 25
    property bool active: true
    property var advances: []
    property real scrollX: 0
    property real lastPosition: -1
    readonly property var words: line && line.words ? line.words : []
    readonly property bool wordSynced: words.length > 0
    readonly property real filled: wordSynced ? Timeline.highlightWidth(words, advances, positionMs) : baseText.implicitWidth
    readonly property real textWidth: baseText.implicitWidth

    function renderState() {
        return {
            "textWidth": textWidth,
            "viewportWidth": width,
            "scrollPx": scrollX,
            "highlightPx": filled,
            "wordSynced": wordSynced
        };
    }

    function measure() {
        var prefix = "", widths = [];
        for (var i = 0; i < words.length; i++) {
            prefix += words[i].text;
            measureText.text = prefix;
            widths.push(measureText.advanceWidth);
        }
        advances = widths;
        scrollX = 0;
        lastPosition = -1;
        // Binding/layout updates finish after the line changes, including while paused.
        Qt.callLater(updateScroll, 1);
    }

    function updateScroll(delta) {
        if (!line)
            return ;

        var target = Timeline.scrollTarget(textWidth, width, filled, positionMs - line.startMs, line.endMs - line.startMs, wordSynced);
        // A seek changes the viewport immediately; continuous playback follows smoothly.
        if (!active || lastPosition < 0 || Math.abs(positionMs - lastPosition) > 500)
            scrollX = target;
        else
            scrollX = Timeline.approach(scrollX, target, delta, 9);
        lastPosition = positionMs;
    }

    onWordsChanged: measure()
    onFontSizeChanged: measure()
    onWidthChanged: Qt.callLater(updateScroll, 1)
    onPositionMsChanged: {
        // filled depends on positionMs too: wait for its binding to settle before
        // reading the target, particularly on a paused seek with no future frames.
        if (!active || lastPosition < 0 || Math.abs(positionMs - lastPosition) > 500)
            Qt.callLater(updateScroll, 1);

    }
    Component.onCompleted: measure()

    TextMetrics {
        id: measureText

        font: baseText.font
    }

    Item {
        anchors.fill: parent
        clip: true

        Item {
            x: root.textWidth <= root.width ? (root.width - root.textWidth) / 2 : -root.scrollX
            anchors.verticalCenter: parent.verticalCenter
            width: baseText.implicitWidth
            height: baseText.implicitHeight

            Text {
                id: baseText

                text: root.line ? root.line.text : ""
                textFormat: Text.PlainText
                font.family: "Noto Sans CJK JP"
                font.pixelSize: root.fontSize
                font.weight: Font.Medium
                color: "#66696b"
                renderType: Text.QtRendering
            }

            Item {
                width: root.filled
                height: parent.height
                clip: true

                Text {
                    text: baseText.text
                    textFormat: Text.PlainText
                    font: baseText.font
                    color: "#f7f7f5"
                    renderType: Text.QtRendering
                }

            }

        }

        Rectangle {
            visible: root.textWidth > root.width && root.scrollX > 1
            width: 18
            height: parent.height

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: "#080909"
                }

                GradientStop {
                    position: 1
                    color: "#00080909"
                }

            }

        }

        Rectangle {
            visible: root.textWidth > root.width && root.scrollX < root.textWidth - root.width - 1
            anchors.right: parent.right
            width: 18
            height: parent.height

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: "#00080909"
                }

                GradientStop {
                    position: 1
                    color: "#080909"
                }

            }

        }

    }

    FrameAnimation {
        running: root.active && root.visible && root.textWidth > root.width
        onTriggered: root.updateScroll(frameTime)
    }

}
