import QtQuick
import QtQuick.Controls
import QtTest
import "../../ui" as Ui
import "../../core/Timeline.js" as Timeline

Item {
    id: stage
    width: 1200
    height: 500
    property real offset: 200
    property real startOffset: 0
    property bool snapped: false
    property int clicks: 0
    property int saves: 0
    property int controls: 0
    property int contexts: 0
    Item {
        id: card
        width: 520
        height: 300
        x: (stage.width - width) / 2 + stage.offset
        Ui.DragSurface {
            id: drag
            anchors.fill: parent
            onActivated: stage.clicks++
            onContextRequested: stage.contexts++
            onMoveStarted: stage.startOffset = stage.offset
            onMoveRequested: deltaX => {
                var p = Timeline.dragPlacement(stage.width, card.width, stage.startOffset + deltaX, stage.snapped);
                stage.offset = p.offset;
                stage.snapped = p.snapped;
            }
            onMoveFinished: canceled => { if (!canceled) stage.saves++; }
        }
        Ui.IconButton {
            id: button
            x: 200
            y: 100
            label: "▷"
            hint: "播放"
            onClicked: stage.controls++
        }
        Slider {
            id: progress
            x: 40
            y: 200
            width: 400
            from: 0
            to: 100
        }
    }
    TestCase {
        name: "IslandDragging"
        when: windowShown
        function init() {
            stage.offset = 200;
            stage.snapped = false;
            stage.clicks = 0;
            stage.saves = 0;
            stage.controls = 0;
            stage.contexts = 0;
            progress.value = 0;
        }
        function test_click_and_small_motion() {
            mousePress(card, 40, 30);
            mouseMove(stage, card.x + 43, 30);
            mouseRelease(stage, card.x + 43, 30);
            compare(stage.clicks, 1);
            compare(stage.saves, 0);
            compare(stage.offset, 200);
        }
        function test_snap_hysteresis_and_no_moving_origin_feedback() {
            var x = card.x + 40;
            mousePress(stage, x, 30);
            mouseMove(stage, x - 192, 30);
            compare(stage.offset, 0);
            verify(stage.snapped);
            mouseMove(stage, x - 180, 30);
            compare(stage.offset, 0);
            mouseMove(stage, x - 160, 30);
            compare(stage.offset, 40);
            verify(!stage.snapped);
            mouseMove(stage, x - 162, 30);
            compare(stage.offset, 38);
            mouseRelease(stage, x - 162, 30);
            compare(stage.saves, 1);
            compare(stage.clicks, 0);
            verify(!drag.dragging);
        }
        function test_controls_keep_their_input() {
            mouseClick(button, button.width / 2, button.height / 2);
            compare(stage.controls, 1);
            mousePress(progress, 10, progress.height / 2);
            mouseMove(progress, 280, progress.height / 2);
            mouseRelease(progress, 280, progress.height / 2);
            verify(progress.value > 50);
            compare(stage.offset, 200);
            compare(stage.clicks, 0);
            compare(stage.saves, 0);
        }
        function test_right_click_opens_settings_without_dragging() {
            mouseClick(card, 40, 30, Qt.RightButton);
            compare(stage.contexts, 1);
            compare(stage.clicks, 0);
            compare(stage.saves, 0);
            compare(stage.offset, 200);
        }
        function test_vertical_gesture_does_not_expand() {
            mousePress(card, 40, 30);
            mouseMove(card, 40, 70);
            mouseRelease(card, 40, 70);
            compare(stage.offset, 200);
            compare(stage.clicks, 0);
            compare(stage.saves, 0);
        }
    }
}
