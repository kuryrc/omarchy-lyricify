using Lyricify.Lyrics.Searchers.Helpers;
using LyricIsland.Backend.Lyrics.UpstreamMatching;
using System.Text.RegularExpressions;

namespace LyricIsland.Backend.Lyrics;

// Reuse the pinned Helper's artist-name table, without maintaining a second
// alias database or changing the player/source credits shown in the UI.
public static class ArtistNames
{
    static string Key(string name) => Regex.Replace(name.ToPortableSimplified().ToLowerInvariant(), @"\s+", " ").Trim();

    static readonly IReadOnlyDictionary<string, string> aliases = ArtistHelper.ArtistNamePairs
        .GroupBy(artist => Key(artist.Name))
        .Select(group => new { Name = group.Key, Names = group.Select(artist => Key(artist.ChineseName)).Distinct().ToArray() })
        // A shared English name is not enough to choose between different artists.
        .Where(group => group.Name.Length > 0 && group.Names.Length == 1 && group.Names[0].Length > 0)
        .ToDictionary(group => group.Name, group => group.Names[0], StringComparer.Ordinal);

    public static string Normalize(string name)
    {
        var key = Key(name);
        return aliases.GetValueOrDefault(key, key);
    }
}
