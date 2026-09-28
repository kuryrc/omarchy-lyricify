import QtQuick
import Quickshell.Io
import "Timeline.js" as Timeline

Item {
    id: root

    property bool demo: true
    property bool tickEnabled: true
    property bool demoPlaying: true
    property bool demoAvailable: true
    property real demoPosition: 1000
    property real demoAnchor: 1000
    property var demoTrack: null
    property string error: ""
    readonly property bool available: demoAvailable && demoTrack !== null
    readonly property bool playing: available && demoPlaying
    readonly property real positionMs: demoPosition
    readonly property real durationMs: demoTrack ? demoTrack.durationMs : 0
    readonly property string title: demoTrack ? demoTrack.title : "Loading preview"
    readonly property string artist: demoTrack ? demoTrack.artist : ""
    readonly property string artUrl: Qt.resolvedUrl("../assets/demo-cover.svg")
    readonly property var lines: demoTrack ? demoTrack.lines : []
    readonly property bool canSeek: true
    readonly property bool canToggle: true
    readonly property bool canNext: true
    readonly property bool canPrevious: true

    function seek(ms) {
        if (!Number.isFinite(ms) || !canSeek)
            return ;

        var target = Timeline.clamp(ms, 0, Math.max(0, durationMs - 1));
        demoPosition = target;
        demoAnchor = target;
        clock.reset();
    }

    function togglePlaying() {
        demoPlaying = !demoPlaying;
    }

    function next() {
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].startMs > positionMs + 100) {
                seek(lines[i].startMs);
                return ;
            }
        }
        seek(0);
    }

    function previous() {
        for (var i = lines.length - 1; i >= 0; i--) {
            if (lines[i].startMs < positionMs - 1000) {
                seek(lines[i].startMs);
                return ;
            }
        }
        seek(0);
    }

    FileView {
        path: Qt.resolvedUrl("../fixtures/demo.json")
        onLoaded: {
            try {
                var data = JSON.parse(text());
                if (!Timeline.validate(data))
                    throw new Error("Invalid fixture timeline");

                root.demoTrack = data;
            } catch (e) {
                root.error = String(e);
            }
        }
    }

    FrameAnimation {
        id: clock

        running: root.playing && root.tickEnabled
        onRunningChanged: {
            if (running) {
                root.demoAnchor = root.demoPosition;
                reset();
            }
        }
        onTriggered: {
            root.demoPosition = (root.demoAnchor + elapsedTime * 1000) % root.durationMs;
        }
    }

}
