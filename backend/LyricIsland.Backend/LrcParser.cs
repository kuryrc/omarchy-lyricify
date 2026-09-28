using System.Globalization;
using System.Text.RegularExpressions;

namespace LyricIsland.Backend;

public static partial class LrcParser
{
    [GeneratedRegex(@"\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]")]
    private static partial Regex Timestamp();

    [GeneratedRegex(@"^\s*\[offset:([+-]?\d+)\]\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex Offset();

    public static LyricTrack Parse(string text, string trackId, string title, string artist, double durationMs)
    {
        if (!double.IsFinite(durationMs) || durationMs <= 0 || durationMs > 86_400_000)
            throw new RequestError("invalid_duration", "durationMs must be positive and at most 24 hours.");
        var entries = new List<(double Time, string Text)>();
        double offset = 0;
        foreach (var raw in text.Replace("\r", "").Split('\n'))
        {
            var line = raw.Trim().TrimStart('\uFEFF');
            var offsetMatch = Offset().Match(line);
            if (offsetMatch.Success)
            {
                if (!double.TryParse(offsetMatch.Groups[1].Value, CultureInfo.InvariantCulture, out offset)
                    || !double.IsFinite(offset) || Math.Abs(offset) > 86_400_000)
                    throw new RequestError("invalid_offset", "Invalid LRC offset.");
                continue;
            }
            var times = new List<Match>();
            var position = 0;
            while (position < line.Length)
            {
                var match = Timestamp().Match(line, position);
                if (!match.Success || match.Index != position) break;
                times.Add(match);
                position += match.Length;
            }
            if (times.Count == 0) continue;
            var lyric = line[position..].Trim();
            foreach (Match timestamp in times)
            {
                var fraction = timestamp.Groups[3].Value;
                var ms = fraction.Length == 0 ? 0 : int.Parse(fraction.PadRight(3, '0'), CultureInfo.InvariantCulture);
                var time = int.Parse(timestamp.Groups[1].Value, CultureInfo.InvariantCulture) * 60_000
                    + int.Parse(timestamp.Groups[2].Value, CultureInfo.InvariantCulture) * 1000 + ms;
                entries.Add((time, lyric));
            }
        }

        var ordered = entries.Select(e => (Time: Math.Max(0, e.Time - offset), e.Text))
            .Where(e => e.Time < durationMs).OrderBy(e => e.Time).ToList();
        var unique = new List<(double Time, string Text)>();
        foreach (var entry in ordered)
        {
            if (unique.Count > 0 && unique[^1].Time == entry.Time)
            {
                if (unique[^1].Text == entry.Text) continue;
                throw new RequestError("ambiguous_timestamps", "Different lines share a timestamp; import requires explicit alignment.");
            }
            unique.Add(entry);
        }
        var lines = new List<LyricLine>();
        for (var i = 0; i < unique.Count; i++)
        {
            var entry = unique[i];
            var end = i + 1 < unique.Count ? unique[i + 1].Time : durationMs;
            // Empty timestamped lines are gap boundaries, not visible lyric lines.
            if (entry.Text.Length > 0 && end > entry.Time)
                lines.Add(new(entry.Time, end, entry.Text, "", []));
        }
        if (lines.Count == 0)
            throw new RequestError("no_synced_lyrics", "No timestamped lyrics within the track duration.");
        return new(1, trackId, title, artist, durationMs, "local-lrc", "line", [.. lines]);
    }
}
