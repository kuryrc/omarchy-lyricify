import QtQuick
import QtTest
import "../../ui" as Ui
import "../../core/Timeline.js" as Timeline

Item {
    width: 900
    height: 100
    Ui.LyricLine {
        id: lyric
        width: 300
        height: 40
        active: false
        positionMs: 1000
        line: ({startMs: 1000, endMs: 5000,
            text: "We follow little lights across the quiet city, one slow breath at a time",
            words: [
                {text: "We follow little lights ", startMs: 1000, endMs: 2000},
                {text: "across the quiet city, ", startMs: 2000, endMs: 3000},
                {text: "one slow breath at a time", startMs: 3000, endMs: 5000}
            ]})
    }
    TestCase {
        name: "PausedViewport"
        when: windowShown
        function aligned() {
            var expected = Timeline.scrollTarget(lyric.textWidth, lyric.width, lyric.filled,
                lyric.positionMs - 1000, 4000, true);
            return Math.abs(lyric.scrollX - expected) < .01;
        }
        function test_repeated_seeks_in_same_line_and_resize() {
            for (var position of [1400, 3200, 4100, 4200, 1900]) {
                lyric.positionMs = position;
                tryVerify(aligned);
            }
            lyric.positionMs = 4000;
            tryVerify(aligned);
            lyric.width = 500;
            tryVerify(aligned);
            lyric.width = 180;
            tryVerify(aligned);
        }
    }
}
