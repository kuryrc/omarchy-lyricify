import QtQuick
import Quickshell

Item {
    id: root

    property bool enabled: true
    property bool connected: false
    property real positionMs: 0
    property real anchor: 0
    property real received: 0
    property real sourceAge: 0
    property real duration: 0
    property real rate: 1
    property bool playing: false
    property bool valid: false
    property real correction: 0
    property string identity: ""
    property real discontinuity: -1
    property real lastPulse: 0
    property bool awaitingResync: false

    signal resyncRequested()

    function invalidate() {
        valid = false;
        awaitingResync = true;
    }

    function requestFreshSample() {
        invalidate();
        resyncRequested();
    }

    function checkContinuity() {
        var now = monotonic.elapsedMs();
        var stalled = enabled && connected && lastPulse > 0 && now - lastPulse > 500;
        lastPulse = now;
        if (stalled)
            requestFreshSample();

        return !stalled;
    }

    function accept(state, scope, fresh) {
        // Buffered events retain their old send position after a blocked UI resumes.
        // Only a response to our new resync request can re-establish the anchor.
        if (!checkContinuity() || (awaitingResync && !fresh))
            return ;

        awaitingResync = false;
        var p = state.position;
        var nextIdentity = scope ? scope.playerInstanceId + ":" + scope.trackGeneration : "";
        var now = monotonic.elapsedMs();
        var hard = !valid || identity !== nextIdentity || discontinuity !== p.discontinuityId || !state.playback || state.playback.status !== "Playing";
        correction = !hard && Math.abs(positionMs - p.positionMsAtSend) < 100 ? positionMs - p.positionMsAtSend : 0;
        identity = nextIdentity;
        discontinuity = p.discontinuityId;
        anchor = p.positionMsAtSend;
        received = now;
        sourceAge = p.sourceAgeMs;
        playing = state.playback.status === "Playing";
        rate = state.playback.rate;
        duration = state.track && state.track.durationMs !== null ? state.track.durationMs : 0;
        valid = p.known && sourceAge < 10000;
        if (p.known)
            update();

    }

    function update() {
        if (!checkContinuity() || !valid || !connected)
            return ;

        var elapsed = Math.max(0, monotonic.elapsedMs() - received);
        if (sourceAge + elapsed >= 10000) {
            requestFreshSample();
            return ;
        }
        positionMs = Math.max(0, anchor + (playing ? elapsed * rate : 0) + correction * Math.max(0, 1 - elapsed / 200));
        if (duration > 0)
            positionMs = Math.min(duration, positionMs);

    }

    onEnabledChanged: {
        lastPulse = monotonic.elapsedMs();
        if (enabled && connected)
            requestFreshSample();

    }
    onConnectedChanged: {
        lastPulse = monotonic.elapsedMs();
        awaitingResync = false;
        if (!connected)
            valid = false;

    }

    ElapsedTimer {
        id: monotonic
    }

    Timer {
        interval: 250
        repeat: true
        running: root.enabled && root.connected
        onTriggered: root.checkContinuity()
    }

    FrameAnimation {
        running: root.enabled && root.connected && root.valid && root.playing
        onTriggered: root.update()
    }

}
