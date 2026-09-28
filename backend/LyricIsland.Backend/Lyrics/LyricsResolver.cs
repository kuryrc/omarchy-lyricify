using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Storage;

namespace LyricIsland.Backend.Lyrics;

public sealed record Resolution(string Status, LyricDocument? Document, LyricCandidate[] Candidates, string? Error = null);
public sealed record CacheEntry(int SchemaVersion, string TrackKey, DateTimeOffset Expires, LyricDocument? Document, string Status);

public sealed class LyricsResolver(LocalStore store, ILyricProvider[] providers)
{
    readonly LyricDocuments documents = new(store);
    readonly LyricCache cache = new(store);
    public async Task<Resolution> ResolveAsync(TrackInfo track, Settings settings, bool refresh, CancellationToken token)
    {
        if (track.ContentKind is "podcast" or "advertisement" || string.IsNullOrWhiteSpace(track.Title) || track.Artists.Length == 0 || track.DurationMs is null)
            return new("unsupported", null, []);
        var enabled = providers.Where(p => settings.IsEnabled(p.Id)).ToArray();
        var sources = enabled.Select(p => p.Id).ToArray();
        if (!refresh || enabled.Length == 0)
        {
            var cached = cache.Read(track, sources);
            if (cached is not null)
                return new(cached.Status, cached.Document is null ? null : documents.WithSavedOffset(track, cached.Document), []);
        }
        if (enabled.Length == 0) return new("disabled", null, []);
        var candidates = new List<LyricCandidate>(); var errors = new List<string>();
        foreach (var provider in enabled)
        {
            token.ThrowIfCancellationRequested();
            try
            {
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(15));
                candidates.AddRange((await provider.SearchAsync(track, deadline.Token)).Select(c => Match(track, c)));
            }
            catch (OperationCanceledException) when (!token.IsCancellationRequested) { errors.Add("timeout"); }
            catch (RequestError e) { errors.Add(e.Code); }
            catch (Exception e) when (e is HttpRequestException or Newtonsoft.Json.JsonException or InvalidOperationException) { errors.Add("provider_error"); }
        }
        token.ThrowIfCancellationRequested();
        // Equivalent releases and providers are alternatives, not an ambiguous recording.
        // Stable tie-breaking also prevents upstream result order from changing the selection.
        var sorted = candidates.DistinctBy(c => c.CandidateId)
            .OrderByDescending(c => c.Automatic).ThenByDescending(c => c.Score)
            .ThenBy(c => c.Reasons?.Contains("additional_artist_credits") == true)
            .ThenBy(c => c.Reasons?.Contains("album_differs_or_missing") == true)
            .ThenBy(c => c.DurationMs is double duration && track.DurationMs is double length ? Math.Abs(duration - length) : double.PositiveInfinity)
            .ThenBy(c => Array.FindIndex(providers, p => p.Id == c.Provider)).ThenBy(c => c.CandidateId, StringComparer.Ordinal).Take(40).ToArray();
        var automatic = sorted.Where(c => c.Automatic).Take(3);
        Resolution result = new(sorted.Length > 0 ? "ambiguous" : errors.Count > 0 ? "error" : "notFound", null, sorted, errors.FirstOrDefault());
        foreach (var candidate in automatic)
        {
            token.ThrowIfCancellationRequested();
            try { result = new("ready", await SelectAsync(track, candidate, settings, token), sorted); break; }
            catch (RequestError e) when (LyricDocuments.IsContentError(e.Code))
            {
                // A broken document does not disqualify another metadata-compatible recording.
                result = new(e.Code is "no_lyrics" or "no_synced_lyrics" ? "notFound" : "error", null, sorted, e.Code);
            }
            catch (OperationCanceledException) when (!token.IsCancellationRequested) { result = new("error", null, sorted, "timeout"); break; }
            catch (RequestError e) { result = new("error", null, sorted, e.Code); break; }
            catch (HttpRequestException) { result = new("error", null, sorted, "provider_error"); break; }
        }
        token.ThrowIfCancellationRequested();
        // Exhausting a few candidates is not proof that the song has no lyrics.
        if (result.Status == "ready" || result.Status == "notFound" && sorted.Length == 0)
        {
            if (!cache.Save(track, result, sources, settings.CacheLimitMb)) result = result with { Error = "cache_write_failed" };
        }
        return result;
    }
    public async Task<LyricDocument> SelectAsync(TrackInfo track, LyricCandidate candidate, Settings settings, CancellationToken token)
    {
        var provider = providers.FirstOrDefault(p => p.Id == candidate.Provider && settings.IsEnabled(p.Id))
            ?? throw new RequestError("unsupported_capability", "Provider is disabled.");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(15));
        var parsed = await provider.FetchAsync(candidate, track, deadline.Token);
        token.ThrowIfCancellationRequested();
        return documents.WithSavedOffset(track, LyricDocuments.Create(parsed, candidate.CandidateId));
    }
    public static LyricCandidate Match(TrackInfo track, LyricCandidate candidate) => LyricMatchPolicy.Match(track, candidate);

}
