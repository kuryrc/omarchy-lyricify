import QtQuick
import Quickshell
import "../../core" as Core
import "../../core/Release.js" as Release
import "../../ui" as Ui

ShellRoot {
    id: test
    function compare(actual, expected) {
        if (actual !== expected) throw new Error("Expected " + expected + " got " + actual);
    }
    function verify(value) { if (!value) throw new Error("Assertion failed"); }
    Core.BackendClient { id: client; active: false }
    Core.RenderClock { id: clock; connected: true }
    QtObject { id: prefs; property string language: "en"; function saveLanguage(value) { language = value; } }
    QtObject {
        id: view
        property string language: "en"
        property bool demo: true
        property bool playing: false
        property real positionMs: 1000
        property real durationMs: 10000
        property string title: "Fixture"
        property string artist: "Original"
        property string artUrl: ""
        property string statusText: "Interlude"
        property string documentId: client.document ? client.document.documentId : ""
        property var lines: client.document ? client.document.document.lines : []
        property bool canSeek: true
        property bool canToggle: true
        property bool canNext: true
        property bool canPrevious: true
        function seek(ms) {}
        function togglePlaying() {}
        function next() {}
        function previous() {}
    }
    Ui.IslandContent { id: content; width: 520; height: 86; playback: view; motion: false }
    function findNamed(item, name) {
        if (item.objectName === name) return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) { var found = findNamed(children[i], name); if (found) return found; }
        return null;
    }


    function state(title, doc) {
        return {player: {applicationId: "fixture"}, track: {title: title, artists: [], durationMs: 10000},
            playback: {status: "Paused", rate: 1, canPlay: true, canPause: true, canNext: false, canPrevious: false, canSeekAbsolute: true},
            position: {known: true, positionMsAtSend: 1000, sourceAgeMs: 0, samplingRoundTripMs: 1, discontinuityId: 1, reason: "track-change"},
            lyrics: {status: doc ? "ready" : "disabled", resolutionId: "work", documentId: doc, offsetMs: 0}};
    }
    function event(sequence, payload, generation) {
        return {version: 2, type: "event", event: "session.state", backendSessionId: "epoch", seq: sequence,
            scope: {playerInstanceId: "player", trackGeneration: generation || 1}, payload: payload};
    }
    function document(sequence, id, text) {
        var m = event(sequence, {resolutionId: "work", documentId: id, lyricVersionId: id,
            document: {schemaVersion: 1, durationMs: 10000, lines: [{startMs: 0, endMs: 10000, text: text, translation: "", words: []}]}}, 1);
        m.event = "lyrics.document"; return m;
    }
    function init() {
        client.pending = ({}); client.scope = null; client.snapshot = null; client.document = null;
        client.pendingDocument = null; client.sequence = 0; client.epoch = "epoch"; client.status = "ready";
    }
    function test_stale_epoch_sequence_and_scope() {
        client.receive(JSON.stringify(event(2, state("Current", null), 2)));
        client.receive(JSON.stringify(event(1, state("Old sequence", null), 2)));
        client.receive(JSON.stringify(event(3, state("Old scope", null), 1)));
        var old = event(4, state("Old process", null), 3); old.backendSessionId = "previous";
        client.receive(JSON.stringify(old));
        compare(client.snapshot.track.title, "Current");
    }
    function test_document_replacement_at_same_line() {
        client.receive(JSON.stringify(document(1, "one", "First")));
        client.receive(JSON.stringify(event(2, state("Song", "one"))));
        compare(client.document.document.lines[0].text, "First");
        client.receive(JSON.stringify(document(3, "two", "Replacement")));
        client.receive(JSON.stringify(event(4, state("Song", "two"))));
        compare(client.document.document.lines[0].text, "Replacement");
        client.receive(JSON.stringify(event(5, state("Next song", null), 2)));
        compare(client.document, null);
    }
    function test_split_chunks_and_invalid_payload() {
        var text = JSON.stringify(event(1, state("Fixture", null))) + "\n";
        client.chunk(text.slice(0, 20)); compare(client.snapshot, null);
        client.chunk(text.slice(20)); compare(client.snapshot.track.title, "Fixture");
        var bad = state("Malformed", null); bad.position.positionMsAtSend = null;
        client.receive(JSON.stringify(event(2, bad))); compare(client.status, "recovering");
        compare(client.snapshot.track.title, "Fixture");
    }
    function test_new_backend_resets_scope() {
        client.scope = {playerInstanceId: "old", trackGeneration: 30};
        client.pending = {hello: {op: "hello"}};
        client.receive(JSON.stringify({version: 2, type: "response", id: "hello", ok: true, backendSessionId: "epoch",
            result: {protocol: 2, backendVersion: Release.version, capabilities: ["playback"]}}));
        client.receive(JSON.stringify(event(1, state("Restarted", null))));
        compare(client.snapshot.track.title, "Restarted");
    }
    function test_incompatible_handshake_stops_recovery() {
        client.pending = {hello: {op: "hello"}};
        client.receive(JSON.stringify({version: 2, type: "response", id: "hello", ok: true, backendSessionId: "epoch",
            result: {protocol: 2, backendVersion: "old-build", capabilities: ["playback"]}}));
        compare(client.status, "incompatible"); compare(client.ready, false);
        client.pending = {hello: {op: "hello"}};
        client.receive(JSON.stringify({version: 2, type: "response", id: "hello", ok: true, backendSessionId: "epoch",
            result: {protocol: 2, backendVersion: Release.version, capabilities: []}}));
        compare(client.status, "incompatible");
    }
    function test_clock_pause_seek_rate_and_expiration() {
        var s = state("Fixture", null); var scope = {playerInstanceId: "fixture", trackGeneration: 1};
        clock.accept(s, scope); compare(clock.positionMs, 1000);
        clock.update(); compare(clock.positionMs, 1000);
        s.playback.status = "Playing"; s.playback.rate = 2; s.position.discontinuityId++;
        clock.accept(s, scope); clock.received -= 50; clock.update();
        verify(clock.positionMs >= 1090 && clock.positionMs < 1200);
        s.position.positionMsAtSend = 8000; s.position.discontinuityId++;
        clock.accept(s, scope); verify(clock.positionMs >= 8000);
        s.position.known = false; clock.accept(s, scope); var frozen = clock.positionMs;
        clock.update(); compare(clock.positionMs, frozen);
        s.position.known = true; s.position.sourceAgeMs = 10001; clock.accept(s, scope);
        compare(clock.valid, false);
    }
    Timer {
        interval: 10; running: true
        onTriggered: {
            try {
                test.init(); test.test_stale_epoch_sequence_and_scope();
                test.init(); test.test_document_replacement_at_same_line();
                test.init(); test.test_split_chunks_and_invalid_payload();
                test.init(); test.test_new_backend_resets_scope();
                test.init(); test.test_incompatible_handshake_stops_recovery();
                test.init(); test.test_clock_pause_seek_rate_and_expiration();
                test.init();
                client.receive(JSON.stringify(test.document(1, "first", "First")));
                client.receive(JSON.stringify(test.event(2, test.state("Song", "first"))));
                client.receive(JSON.stringify(test.document(3, "replacement", "New line at the same index")));
                client.receive(JSON.stringify(test.event(4, test.state("Song", "replacement"))));
                Qt.callLater(function() {
                    try {
                        test.compare(content.displayIndex, 0);
                        test.compare(test.findNamed(content, "currentLyricBlock").line.text, "New line at the same index");
                        var s = test.state("Clock", null); s.playback.status = "Playing"; s.playback.rate = 2;
                        clock.accept(s, {playerInstanceId: "real-time", trackGeneration: 1});
                        realTime.start();
                    } catch (error) { console.error("PROTOCOL_TESTS_FAIL " + error); Qt.quit(); }
                });
            } catch (error) { console.error("PROTOCOL_TESTS_FAIL " + error); Qt.quit(); }
        }
    }
    Timer {
        id: realTime
        interval: 60
        onTriggered: {
            try { clock.update(); test.verify(clock.positionMs >= 1090 && clock.positionMs < 1350); console.log("PROTOCOL_TESTS_PASS 8"); }
            catch (error) { console.error("PROTOCOL_TESTS_FAIL " + error); }
            Qt.quit();
        }
    }
}
