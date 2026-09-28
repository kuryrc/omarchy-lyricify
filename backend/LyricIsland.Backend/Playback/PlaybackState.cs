using System.Diagnostics;

namespace LyricIsland.Backend.Playback;

public sealed record TrackScope(string PlayerInstanceId, long TrackGeneration);
public sealed record PlayerInfo(string ApplicationId, string DisplayName, string InstanceId);
public sealed record TrackInfo(string TrackKey, string IdentityStrength, string Title, string[] Artists,
    string Album, double? DurationMs, string ContentKind, string ArtUrl);
public sealed record Transport(string Status, double Rate, bool CanPlay, bool CanPause,
    bool CanNext, bool CanPrevious, bool CanSeekAbsolute);
public sealed record PositionSample(bool Known, double PositionMsAtSend, double SourceAgeMs,
    double SamplingRoundTripMs, long DiscontinuityId, string Reason);
public sealed record PlaybackState(PlayerInfo? Player, TrackInfo? Track, Transport Playback,
    TrackScope? Scope, bool PositionKnown, double SampleMs, long SampleTimestamp,
    double RoundTripMs, long DiscontinuityId, string Reason)
{
    public static PlaybackState Empty { get; } = new(null, null,
        new("Stopped", 1, false, false, false, false, false), null, false, 0, 0, 0, 0, "reconnect");

    public PositionSample Position()
    {
        var age = SampleTimestamp == 0 ? 0 : Stopwatch.GetElapsedTime(SampleTimestamp).TotalMilliseconds;
        var known = PositionKnown && age < 10000;
        var ms = SampleMs + (known && Playback.Status == "Playing" ? age * Playback.Rate : 0);
        return new(known, Math.Clamp(ms, 0, Track?.DurationMs ?? double.MaxValue), age,
            RoundTripMs, DiscontinuityId, Reason);
    }
}
