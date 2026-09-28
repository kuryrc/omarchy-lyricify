// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick

Item {
    id: root

    property var line: null
    property real positionMs: 0
    property bool animate: false

    function renderState() {
        return lyric.renderState();
    }

    height: 66

    LyricLine {
        id: lyric

        width: parent.width
        height: root.line && root.line.translation ? 37 : 60
        line: root.line
        positionMs: root.positionMs
        active: root.animate
        fontSize: 23
    }

    Text {
        visible: root.line && !!root.line.translation
        y: 37
        width: parent.width
        height: 25
        text: root.line ? (root.line.translation || "") : ""
        textFormat: Text.PlainText
        font.family: "Noto Sans CJK JP"
        font.pixelSize: 15
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: "#b9b9b6"
    }

}
