using System.Text.Json;
using LyricIsland.Backend;
using LyricIsland.Backend.Lyrics;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Storage;

// Explicit opt-in network probe. Reports match evidence, never titles, IDs or lyric text.
static class MatchProbe
{
    public static async Task RunAsync()
    {
        var input = JsonSerializer.Deserialize<Input>(await Console.In.ReadToEndAsync(), LocalStore.Json)
            ?? throw new ArgumentException("Expected track metadata and a provider on stdin");
        ILyricProvider source = input.Provider switch
        {
            "qq" => new QqProvider(), "netease" => new NeteaseProvider(),
            _ => throw new ArgumentException("Expected qq or netease")
        };
        var provider = new ObservedProvider(source);
        var directory = Path.Combine(Path.GetTempPath(), "lyric-match-probe-" + Guid.NewGuid().ToString("N"));
        var variables = new[] { "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME" };
        var original = variables.ToDictionary(v => v, Environment.GetEnvironmentVariable);
        try
        {
            foreach (var variable in variables) Environment.SetEnvironmentVariable(variable, Path.Combine(directory, variable));
            var track = new TrackInfo("probe:track", "weak", input.Title, input.Artists, input.Album, input.DurationMs, "song", "");
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(35));
            var result = await new LyricsResolver(new LocalStore(), [provider]).ResolveAsync(track,
                new Settings().WithSource(input.Provider, true), true, timeout.Token);
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                result.Status, result.Error, candidateCount = result.Candidates.Length,
                automaticCount = result.Candidates.Count(c => c.Automatic), lineCount = result.Document?.Document.Lines.Length,
                syncLevel = result.Document?.Document.SyncLevel,
                fetchErrors = provider.Errors,
                topCandidates = result.Candidates.Take(6).Select(c => new {
                    c.Score, c.Automatic, c.Reasons, durationDeltaMs = c.DurationMs - input.DurationMs,
                    playerArtistCount = input.Artists.Length, candidateArtistCount = c.Artists.Length,
                    sharedArtistCount = c.Artists.Intersect(input.Artists, StringComparer.OrdinalIgnoreCase).Count(),
                    primaryArtistMatches = input.Artists.Length > 0 && c.Artists.Length > 0
                        && string.Equals(input.Artists[0], c.Artists[0], StringComparison.OrdinalIgnoreCase)
                })
            }, LocalStore.Json));
        }
        finally
        {
            foreach (var variable in variables) Environment.SetEnvironmentVariable(variable, original[variable]);
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }
    sealed record Input(string Provider, string Title, string[] Artists, string Album, double DurationMs);
    sealed class ObservedProvider(ILyricProvider source) : ILyricProvider
    {
        public string Id => source.Id;
        public List<object> Errors { get; } = [];
        public Task<LyricCandidate[]> SearchAsync(TrackInfo track, CancellationToken token) => source.SearchAsync(track, token);
        public async Task<LyricTrack> FetchAsync(LyricCandidate candidate, TrackInfo track, CancellationToken token)
        {
            try { return await source.FetchAsync(candidate, track, token); }
            catch (RequestError error) { Errors.Add(new { error.Code, error.Message }); throw; }
        }
    }
}
