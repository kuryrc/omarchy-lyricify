// Pure receive validation. No platform clock or player-specific branches.
function scopeEqual(a, b) {
    return a === b || (!!a && !!b && a.playerInstanceId === b.playerInstanceId && a.trackGeneration === b.trackGeneration);
}
function validScope(scope) {
    return scope === null || (typeof scope === "object" && typeof scope.playerInstanceId === "string" &&
        Number.isSafeInteger(scope.trackGeneration) && scope.trackGeneration > 0);
}
function validState(s) {
    if (!s || !s.playback || !s.position || !s.lyrics) return false;
    if (["Playing", "Paused", "Stopped"].indexOf(s.playback.status) < 0 ||
            !Number.isFinite(s.playback.rate) || s.playback.rate <= 0 || s.playback.rate > 16) return false;
    var capabilities = ["canPlay", "canPause", "canNext", "canPrevious", "canSeekAbsolute"];
    for (var i = 0; i < capabilities.length; i++) if (typeof s.playback[capabilities[i]] !== "boolean") return false;
    var p = s.position;
    if (typeof p.known !== "boolean" || !Number.isFinite(p.positionMsAtSend) || p.positionMsAtSend < 0 ||
            !Number.isFinite(p.sourceAgeMs) || p.sourceAgeMs < 0 || !Number.isFinite(p.samplingRoundTripMs) ||
            p.samplingRoundTripMs < 0 || !Number.isSafeInteger(p.discontinuityId)) return false;
    if (s.player !== null && (!s.player || typeof s.player.applicationId !== "string")) return false;
    if (s.track !== null && (!s.track || typeof s.track.title !== "string" || !Array.isArray(s.track.artists) ||
            s.track.artists.some(function(a) { return typeof a !== "string"; }) ||
            !(s.track.durationMs === null || Number.isFinite(s.track.durationMs) && s.track.durationMs > 0))) return false;
    return typeof s.lyrics.status === "string" && typeof s.lyrics.resolutionId === "string" && Number.isFinite(s.lyrics.offsetMs);
}
if (typeof module !== "undefined") module.exports = {scopeEqual: scopeEqual, validScope: validScope, validState: validState};
