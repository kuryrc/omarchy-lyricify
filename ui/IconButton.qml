// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick

Rectangle {
    id: root

    property string label: ""
    property string hint: ""
    property bool primary: false

    signal clicked()

    width: 36
    height: 32
    radius: 10
    color: pointer.containsMouse ? "#333737" : (primary ? "#222827" : "transparent")
    opacity: enabled ? 1 : 0.35
    Accessible.role: Accessible.Button
    Accessible.name: hint
    Accessible.onPressAction: clicked()

    Text {
        anchors.centerIn: parent
        text: root.label
        textFormat: Text.PlainText
        color: "#f0f2f0"
        font.pixelSize: 18
        font.family: "Noto Sans CJK JP"
    }

    MouseArea {
        id: pointer

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

}
