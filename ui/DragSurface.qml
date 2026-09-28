// SPDX-License-Identifier: CC-BY-SA-4.0
// Visual adaptation of Lyricify by WXRIW / XY Wang; changes by omarchy-lyricify contributors. See NOTICE.
import QtQuick

// Stays behind controls. Scene coordinates avoid feedback as the card moves.
MouseArea {
    id: root

    property bool dragging: false
    property real pressSceneX: 0
    property real pressSceneY: 0
    property bool moved: false
    property real threshold: 8

    signal activated()
    signal contextRequested()
    signal moveStarted()
    signal moveRequested(real deltaX)
    signal moveFinished(bool canceled)

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: true
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onPressed: (mouse) => {
        if (mouse.button !== Qt.LeftButton)
            return ;

        var p = mapToItem(null, mouse.x, mouse.y);
        pressSceneX = p.x;
        pressSceneY = p.y;
        moved = false;
    }
    onPositionChanged: (mouse) => {
        if (!pressed || !(pressedButtons & Qt.LeftButton))
            return ;

        var p = mapToItem(null, mouse.x, mouse.y);
        var dx = p.x - pressSceneX;
        moved = moved || Math.abs(dx) >= threshold || Math.abs(p.y - pressSceneY) >= threshold;
        if (!dragging && Math.abs(dx) >= threshold) {
            dragging = true;
            moveStarted();
        }
        if (dragging)
            moveRequested(dx);

    }
    onReleased: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            contextRequested();
            return ;
        }
        if (dragging) {
            dragging = false;
            moveFinished(false);
        } else if (!moved) {
            activated();
        }
    }
    onCanceled: {
        if (dragging) {
            dragging = false;
            moveFinished(true);
        }
    }
}
