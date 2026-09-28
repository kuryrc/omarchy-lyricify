namespace LyricIsland.Backend;

public sealed record LyricWord(string Text, double StartMs, double EndMs);
public sealed record LyricLine(double StartMs, double EndMs, string Text, string Translation, LyricWord[] Words);
public sealed record LyricTrack(int SchemaVersion, string TrackId, string Title, string Artist,
    double DurationMs, string Source, string SyncLevel, LyricLine[] Lines);

public sealed class RequestError(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
