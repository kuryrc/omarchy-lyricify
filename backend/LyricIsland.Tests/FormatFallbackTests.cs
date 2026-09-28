using LyricIsland.Backend;
using LyricIsland.Backend.Lyrics;
using LyricIsland.Backend.Playback;

static class FormatFallbackTests
{
    public static int Run()
    {
        var track = new TrackInfo("fixture:fallback", "strong", "Original Signals", ["Fixture"], "First Light", 10000, "song", "");
        const string validWords = "[1000,2000](1000,500,0)Original (2000,1000,0)fixture";
        const string invalidWords = "[1000,2000](1000,2000,0)Original (2000,1000,0)fixture";
        const string lines = "[00:01]Original fallback\n[00:04]Second fixture";
        int passed = 0;
        void Check(bool value, string name) { if (!value) throw new Exception(name); passed++; }
        LyricTrack Parse(string words, string fallback, string wordTranslation = "", string lineTranslation = "") =>
            HelperFormats.ParseWithLineFallback(words, "yrc", fallback, track, "fixture", wordTranslation, lineTranslation);
        bool invalidRejected = false;
        try { HelperFormats.Parse(invalidWords, "yrc", track, "fixture"); }
        catch (RequestError error) when (error.Code == "invalid_lyrics") { invalidRejected = true; }
        Check(invalidRejected, "Fixture must exercise actual overlapping word timing");
        var result = Parse(invalidWords, lines, "[00:01]错误逐字译文", "[00:01]原创逐行译文");
        Check(result.SyncLevel == "line" && result.Lines.All(l => l.Words.Length == 0), "Bad word timing must fall back to real line lyrics");
        Check(result.Lines[0].Text == "Original fallback" && result.Lines[0].Translation == "原创逐行译文", "Fallback uses its matching line text and translation");
        result = Parse(validWords, lines);
        Check(result.SyncLevel == "word" && result.Lines[0].Words[1].StartMs == 2000, "Valid word timing must remain unchanged");
        result = Parse("", lines);
        Check(result.SyncLevel == "line", "Line-only response remains supported");
        result = Parse(validWords, "not timed");
        Check(result.SyncLevel == "word", "Broken unused fallback does not invalidate valid word lyrics");
        foreach (var pair in new[] { (invalidWords, ""), (invalidWords, "not timed"), ("", "") })
        {
            bool rejected = false;
            try { Parse(pair.Item1, pair.Item2); }
            catch (RequestError) { rejected = true; }
            Check(rejected, "Unusable formats must never generate invented lyric timing");
        }
        return passed;
    }
}
