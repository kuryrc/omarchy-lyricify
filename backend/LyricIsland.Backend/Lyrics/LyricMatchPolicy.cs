using Lyricify.Lyrics.Models;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Lyrics.UpstreamMatching;
using System.Text;
using System.Text.RegularExpressions;

namespace LyricIsland.Backend.Lyrics;

// Helper owns similarity and scoring. This adapter owns automatic acceptance
// and explicit recording conflicts; it never performs network or storage I/O.
public static class LyricMatchPolicy
{
    static string Normalize(string value) => Regex.Replace(value.Normalize(NormalizationForm.FormKC).ToLowerInvariant(), @"\s+", " ").Trim();
    static readonly (string Kind, Regex Pattern)[] VersionMarkers =
    [
        ("live", new(@"\blive\b|现场|現場|演唱会|演唱會")),
        ("instrumental", new(@"\b(instrumental|karaoke)\b|伴奏")),
        ("acoustic", new(@"\b(acoustic|unplugged)\b|不插电|不插電")),
        ("remix", new(@"\bremix(?:ed)?\b|混音")),
        ("remaster", new(@"\bremaster(?:ed)?\b|重制|重製")),
        ("rerecorded", new(@"\bre[- ]record(?:ed|ing)?\b|重录|重錄")),
        ("radio-edit", new(@"\bradio edit\b")),
        ("single-edit", new(@"\bsingle edit\b")),
        ("extended", new(@"\bextended\b")),
        ("sped-up", new(@"\bsped up\b|加速版")),
        ("slowed", new(@"\bslowed\b|慢速版")),
        ("demo", new(@"\bdemo\b"))
    ];
    static string VersionSignature(string title, string album)
    {
        var text = Normalize(title + " " + album);
        var kinds = VersionMarkers.Where(marker => marker.Pattern.IsMatch(text)).Select(marker => marker.Kind).ToArray();
        // Remaster years distinguish named releases even when the title omits them.
        IEnumerable<string> years = kinds.Contains("remaster") ? Regex.Matches(text, @"\b(?:19|20)\d{2}\b").Select(m => m.Value).Distinct().Order() : [];
        return string.Join("|", kinds.Concat(years));
    }

    static TrackMultiArtistMetadata Metadata(string title, string[] artists, string album, double? duration) => new() {
        Title = Normalize(title), Artists = artists.Select(ArtistNames.Normalize).Where(a => a.Length > 0).Distinct().ToList(),
        Album = string.IsNullOrWhiteSpace(album) ? null : Normalize(album),
        DurationMs = duration is > 0 and <= 86400000 ? (int)Math.Round(duration.Value) : null
    };

    public static LyricCandidate Match(TrackInfo track, LyricCandidate candidate)
    {
        if (new[] { track.Title, candidate.Title, track.Album, candidate.Album }.Concat(track.Artists).Concat(candidate.Artists).Any(s => s.Length > 512)
            || track.Artists.Length > 32 || candidate.Artists.Length > 32)
            return candidate with { Automatic = false, Score = -1, Reasons = ["metadata_too_large"] };
        var original = Metadata(track.Title, track.Artists, track.Album, track.DurationMs);
        var result = Metadata(candidate.Title, candidate.Artists, candidate.Album, candidate.DurationMs);
        var grade = CompareHelper.CompareTrack(original, result);
        var title = CompareHelper.CompareName(original.Title, result.Title);
        var artists = CompareHelper.CompareArtist(original.Artists, result.Artists);
        var duration = CompareHelper.CompareDuration(original.DurationMs, result.DurationMs);
        var album = CompareHelper.CompareName(original.Album, result.Album);
        var sameVersion = VersionSignature(track.Title, track.Album) == VersionSignature(candidate.Title, candidate.Album);
        var primary = original.Artists.Count > 0 && result.Artists.Count > 0
            && (original.Artists[0].ToPortableSimplified() == result.Artists[0].ToPortableSimplified()
                || original.Artists.ToHashSet().SetEquals(result.Artists));
        var titleAccepted = title is CompareHelper.NameMatchType.Perfect or CompareHelper.NameMatchType.VeryHigh or CompareHelper.NameMatchType.High;
        var artistAccepted = primary && (artists is CompareHelper.ArtistMatchType.Perfect or CompareHelper.ArtistMatchType.VeryHigh or CompareHelper.ArtistMatchType.High);
        var reasons = new List<string>();
        if (!titleAccepted) reasons.Add("title_or_version_differs");
        if (!artistAccepted) reasons.Add("artists_differ");
        else if (artists != CompareHelper.ArtistMatchType.Perfect) reasons.Add("additional_artist_credits");
        if (duration is null or CompareHelper.DurationMatchType.NoMatch) reasons.Add("duration_differs_or_missing");
        if (album != CompareHelper.NameMatchType.Perfect) reasons.Add("album_differs_or_missing");
        if (!sameVersion) reasons.Add("recording_version_differs");
        return candidate with { Score = (int)grade, Reasons = reasons.ToArray(),
            Automatic = (int)grade >= (int)CompareHelper.MatchType.PrettyHigh && titleAccepted && artistAccepted
                && duration is not null and not CompareHelper.DurationMatchType.NoMatch && sameVersion };
    }
}
