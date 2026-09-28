import "I18n.js" as I18n
import "Protocol.js" as Protocol
import QtQuick

Item {
    id: root

    property bool active: true
    property string language: "auto"
    property bool tickEnabled: true
    property alias client: backend
    property real pendingSeek: NaN
    property string seekRequest: ""
    property string resyncRequest: ""
    readonly property var state: backend.snapshot
    readonly property bool available: state !== null && state.player !== null
    readonly property bool playing: available && backend.ready && clock.valid && state.playback.status === "Playing"
    readonly property real positionMs: clock.positionMs
    readonly property real durationMs: state && state.track ? (state.track.durationMs || 0) : 0
    readonly property string title: state && state.track ? state.track.title : "Lyric Island"
    readonly property string artist: state && state.track ? state.track.artists.join(" / ") : ""
    readonly property string artUrl: state && state.track ? state.track.artUrl : ""
    readonly property var lines: backend.document && lyricStatus === "ready" ? backend.document.document.lines : []
    readonly property string documentId: backend.document ? backend.document.documentId : ""
    readonly property real offsetMs: state ? state.lyrics.offsetMs : 0
    readonly property string lyricStatus: state ? state.lyrics.status : "idle"
    readonly property string lyricError: state ? (state.lyrics.errorCode || "") : ""
    readonly property string statusText: !backend.ready ? I18n.status(language, backend.status) : lyricStatus === "ready" ? I18n.text(language, "Interlude", "间奏") : I18n.lyricStatus(language, lyricStatus, lyricError)
    readonly property string error: backend.error || lyricError
    readonly property bool canSeek: backend.ready && backend.scope !== null && available && state.playback.canSeekAbsolute
    readonly property bool canToggle: backend.ready && backend.scope !== null && available && (state.playback.status === "Playing" ? state.playback.canPause : state.playback.canPlay)
    readonly property bool canNext: backend.ready && backend.scope !== null && available && state.playback.canNext
    readonly property bool canPrevious: backend.ready && backend.scope !== null && available && state.playback.canPrevious

    function seek(ms) {
        if (canSeek && Number.isFinite(ms))
            pendingSeek = Math.max(0, Math.min(durationMs, ms));

    }

    function togglePlaying() {
        if (canToggle)
            backend.request(state.playback.status === "Playing" ? "playback.pause" : "playback.play", {
        }, true);

    }

    function next() {
        if (canNext)
            backend.request("playback.next", {
        }, true);

    }

    function previous() {
        if (canPrevious)
            backend.request("playback.previous", {
        }, true);

    }

    function adjustOffset(delta) {
        if (documentId)
            backend.request("lyrics.set-offset", {
            "documentId": documentId,
            "lyricVersionId": backend.document.lyricVersionId,
            "offsetMs": Math.max(-30000, Math.min(30000, offsetMs + delta))
        }, true);

    }

    function requestResync() {
        if (backend.ready && clock.awaitingResync && !root.resyncRequest)
            root.resyncRequest = backend.request("session.resync", {
        }, false);

    }

    Timer {
        interval: 80
        repeat: true
        running: Number.isFinite(root.pendingSeek) && !root.seekRequest
        onTriggered: {
            root.seekRequest = backend.request("playback.seek", {
                "positionMs": root.pendingSeek
            }, true);
            root.pendingSeek = NaN;
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: backend.ready && clock.awaitingResync && !root.resyncRequest
        onTriggered: root.requestResync()
    }

    BackendClient {
        id: backend

        active: root.active
        onSampled: (state, scope) => {
            return clock.accept(state, scope);
        }
        onScopeChanged: {
            root.pendingSeek = NaN;
            root.seekRequest = "";
        }
        onReadyChanged: {
            if (!ready) {
                root.pendingSeek = NaN;
                root.seekRequest = "";
                root.resyncRequest = "";
            }
        }
        onResponse: (id, operation, result, code) => {
            if (id === root.seekRequest)
                root.seekRequest = "";

            if (id === root.resyncRequest) {
                root.resyncRequest = "";
                // A seek can publish a newer state before this response is queued.
                if (!code && result && Protocol.validState(result.snapshot) && Protocol.scopeEqual(result.scope, backend.scope) && (!backend.snapshot || result.snapshot.position.discontinuityId >= backend.snapshot.position.discontinuityId))
                    clock.accept(result.snapshot, result.scope, true);
                else
                    clock.invalidate();
            }
        }
    }

    RenderClock {
        id: clock

        enabled: root.tickEnabled
        connected: backend.ready
        onResyncRequested: {
            // A new stall also invalidates a response already in flight.
            root.resyncRequest = "";
            root.requestResync();
        }
    }

}
