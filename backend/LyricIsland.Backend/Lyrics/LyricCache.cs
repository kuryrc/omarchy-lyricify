using System.Security.Cryptography;
using System.Text;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Storage;

namespace LyricIsland.Backend.Lyrics;

// Rebuildable storage never decides whether an already obtained document can play.
public sealed class LyricCache(LocalStore store)
{
    string PathFor(string key) => Path.Combine(store.Cache, Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(key))) + ".json");
    static string SearchKey(TrackInfo track, IEnumerable<string> sources) => "search:" + track.TrackKey + ":" +
        System.Text.Json.JsonSerializer.Serialize(new { track.Title, track.Artists, track.Album, track.DurationMs, sources = sources.Order() });

    public CacheEntry? Read(TrackInfo track, IEnumerable<string> sources)
    {
        // Old positive caches included network switches in their key. Read them
        // once through this compatibility path without changing saved selections.
        var keys = new[] { "track:" + track.TrackKey }
            .Concat(new[] { "True:True", "True:False", "False:True", "False:False" }.Select(flags => track.TrackKey + ":" + flags));
        foreach (var key in keys)
        {
            var cached = ReadEntry(PathFor(key), track);
            if (cached?.Document is not null && cached.Status == "ready") return cached;
        }
        return ReadEntry(PathFor(SearchKey(track, sources)), track);
    }

    CacheEntry? ReadEntry(string path, TrackInfo track)
    {
        try
        {
            var entry = store.Read<CacheEntry>(path);
            if (entry is not { SchemaVersion: 1 } || entry.TrackKey != track.TrackKey || entry.Expires <= DateTimeOffset.UtcNow) return null;
            if (entry.Document is not null) LyricDocuments.Validate(entry.Document.Document);
            return entry;
        }
        catch (Exception e) when (e is RequestError or IOException or UnauthorizedAccessException) { return null; }
    }

    public bool Save(TrackInfo track, Resolution result, IEnumerable<string> sources, int limitMb)
    {
        try
        {
            var key = result.Document is null ? SearchKey(track, sources) : "track:" + track.TrackKey;
            store.Write(PathFor(key), new CacheEntry(1, track.TrackKey,
                DateTimeOffset.UtcNow.Add(result.Document is null ? TimeSpan.FromMinutes(15) : TimeSpan.FromDays(7)), result.Document, result.Status));
            var files = new DirectoryInfo(store.Cache).EnumerateFiles("*.json").OrderBy(f => f.LastWriteTimeUtc).ToArray();
            long total = files.Sum(f => f.Length), limit = limitMb * 1024L * 1024;
            foreach (var file in files) { if (total <= limit) break; total -= file.Length; file.Delete(); }
            return true;
        }
        catch (Exception e) when (e is RequestError or IOException or UnauthorizedAccessException) { return false; }
    }
}
