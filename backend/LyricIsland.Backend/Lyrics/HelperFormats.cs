using Lyricify.Lyrics.Helpers;
using Lyricify.Lyrics.Models;
using LyricIsland.Backend.Playback;

namespace LyricIsland.Backend.Lyrics;

// Never expose Helper's mutable, lazily cached models to the session or UI.
public static class HelperFormats
{
    public static LyricTrack ParseWithLineFallback(string wordLyrics, string wordFormat, string lineLyrics,
        TrackInfo track, string source, string wordTranslation = "", string lineTranslation = "")
    {
        if (!string.IsNullOrWhiteSpace(wordLyrics))
        {
            try { return Parse(wordLyrics, wordFormat, track, source, wordTranslation); }
            catch (RequestError error) when (LyricDocuments.IsContentError(error.Code) && !string.IsNullOrWhiteSpace(lineLyrics))
            { /* Use this same provider recording's existing line timestamps, never synthesize word times. */ }
        }
        if (string.IsNullOrWhiteSpace(lineLyrics)) throw new RequestError("no_lyrics", "No lyrics available.");
        return Parse(lineLyrics, "lrc", track, source, lineTranslation);
    }

    public static LyricTrack Parse(string text, string format, TrackInfo track, string source, string translation = "")
    {
        if (text.Length > 500000) throw new RequestError("document_too_large", "Lyrics exceed size limit.");
        if (track.DurationMs is not double duration) throw new RequestError("invalid_lyrics", "Track duration is required.");
        LyricTrack result;
        if (format == "lrc") result = LrcParser.Parse(text, track.TrackKey, track.Title, string.Join(" / ", track.Artists), duration) with { Source = source };
        else
        {
            var type = format switch { "qrc" => LyricsRawTypes.Qrc, "yrc" => LyricsRawTypes.Yrc, _ => throw new RequestError("invalid_lyrics", "Supported formats: LRC, QRC, YRC, timeline JSON.") };
            // YRC's JSON credit records have no end time and are not sung lines.
            // Exclude those records rather than inventing timing for the credits.
            if (format == "yrc") text = string.Join('\n', text.Split('\n').Where(line => !line.TrimStart().StartsWith('{')));
            // Version 0.2.0's auto-detect overload returns null; always pass the explicit format.
            var parsed = ParseHelper.ParseLyrics(text, type)?.Lines;
            if (parsed is null || parsed.Count == 0) throw new RequestError("no_lyrics", "No timed lyrics.");
            var lines = new List<LyricLine>();
            foreach (var line in parsed)
            {
                if (line is SyllableLineInfo { Syllables.Count: 0 }) continue;
                if (line.SubLine is not null) throw new RequestError("invalid_lyrics", "Overlapping vocal parts are not supported yet.");
                if (string.IsNullOrWhiteSpace(line.Text)) continue;
                if (line.StartTime is not int start || line.EndTime is not int end) throw new RequestError("invalid_lyrics", "Missing timing.");
                var words = line is SyllableLineInfo syllables ? syllables.Syllables.Select(w => new LyricWord(w.Text, w.StartTime, w.EndTime)).ToArray() : [];
                lines.Add(new(start, end, line.Text, "", words));
            }
            result = new(1, track.TrackKey, track.Title, string.Join(" / ", track.Artists), duration, source,
                lines.Any(l => l.Words.Length > 0) ? "word" : "line", lines.OrderBy(l => l.StartMs).ToArray());
        }
        if (!string.IsNullOrWhiteSpace(translation))
        {
            try
            {
                var translations = LrcParser.Parse(translation, track.TrackKey, "", "", duration).Lines;
                result = result with { Lines = result.Lines.Select(line => line with {
                    Translation = translations.SingleOrDefault(t => t.StartMs == line.StartMs)?.Text ?? ""
                }).ToArray() };
            }
            catch (RequestError) { /* Invalid translation must not invalidate usable original lyrics. */ }
        }
        LyricDocuments.Validate(result); return result;
    }
}
