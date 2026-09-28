using LyricIsland.Backend;
using LyricIsland.Backend.Lyrics;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Storage;

static class MatchingTests
{
    public static async Task<int> RunAsync()
    {
        var directory = Path.Combine(Path.GetTempPath(), "lyric-matching-" + Guid.NewGuid().ToString("N"));
        var variables = new[] { "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME" };
        var original = variables.ToDictionary(v => v, Environment.GetEnvironmentVariable);
        int passed = 0;
        void Check(bool condition, string name) { if (!condition) throw new Exception(name); passed++; }
        try
        {
            foreach (var variable in variables) Environment.SetEnvironmentVariable(variable, Path.Combine(directory, variable));
            var store = new LocalStore();
            var track = new TrackInfo("fixture:matching", "strong", "Original Signals", ["Fixture Artist"], "First Light", 295533, "song", "");
            var first = new LyricCandidate("netease:a", "netease", "a", track.Title, track.Artists, track.Album, 296124);
            var duplicate = first with { CandidateId = "netease:b", ProviderId = "b" };
            var netease = new CandidateProvider("netease") { Candidates = [duplicate, first] };
            var qq = new CandidateProvider("qq");
            var resolver = new LyricsResolver(store, [netease, qq]);
            var settings = new Settings().WithSource("netease", true);
            Task<Resolution> Resolve() => resolver.ResolveAsync(track, settings, true, CancellationToken.None);

            var international = track with { Artists = ["Khalil Fong"] };
            netease.Candidates = [first with { Artists = ["方大同"] }];
            var localized = await resolver.ResolveAsync(international, settings, true, CancellationToken.None);
            Check(localized.Status == "ready" && localized.Document is not null,
                "Helper artist aliases must automatically load Chinese-source lyrics for an English player credit");
            foreach (var (english, chinese) in new[] { ("Khalil Fong", "方大同"), ("Jay Chou", "周杰伦"), ("Eason Chan", "陳奕迅"), ("JJ Lin", "林俊杰") })
            {
                Check(LyricsResolver.Match(track with { Artists = ["  " + english.ToUpperInvariant() + "  "] }, first with { Artists = [chinese] }).Automatic,
                    "Helper aliases survive case, spacing and traditional/simplified normalization");
                Check(LyricsResolver.Match(track with { Artists = [chinese] }, first with { Artists = [english] }).Automatic,
                    "Artist aliases apply to both the player and the lyric source");
            }
            Check(LyricsResolver.Match(international, first with { Artists = ["方大同", "Guest Artist"] }).Automatic,
                "Artist aliases retain incomplete collaboration-credit matching");
            Check(!LyricsResolver.Match(international, first with { Artists = ["Another Artist"] }).Automatic,
                "Matching title, album and duration cannot substitute an unrelated artist");
            Check(!LyricsResolver.Match(international, first with { Artists = ["方大同"], Title = track.Title + " (Live)" }).Automatic,
                "Artist aliases do not override recording-version conflicts");
            Check(ArtistNames.Normalize("Unlisted Fixture Performer") == "unlisted fixture performer",
                "Unknown artists are normalized without inventing aliases");
            store.ClearCache();
            netease.Fetched.Clear();
            netease.Candidates = [duplicate, first];

            var found = await Resolve();
            Check(found.Status == "ready" && netease.Fetched.Count == 1, "Equivalent matches must load without manual selection");
            var selected = netease.Fetched[^1];
            netease.Candidates = [first, duplicate];
            await Resolve();
            Check(netease.Fetched[^1] == selected, "Provider response order cannot change an equivalent selection");
            var searches = netease.Searches;
            var fetches = netease.Fetched.Count;
            var cached = await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
            Check(cached.Document?.DocumentId == found.Document?.DocumentId && netease.Searches == searches && netease.Fetched.Count == fetches,
                "Automatic selection must reuse cache without a new search");

            var compilation = first with { CandidateId = "netease:compilation", Album = "Collected Signals", DurationMs = track.DurationMs };
            netease.Candidates = [compilation];
            Check((await Resolve()).Status == "ready", "Compilation album alone must not block the same recording");
            netease.Candidates = [compilation with { Album = "" }];
            Check((await Resolve()).Status == "ready", "Missing album alone must not block a strong recording match");
            netease.Candidates = [compilation, first];
            await Resolve();
            Check(netease.Fetched[^1] == first.CandidateId, "Matching album wins over an equally eligible compilation");
            netease.Candidates = [first with { DurationMs = track.DurationMs }, duplicate];
            await Resolve();
            Check(netease.Fetched[^1] == first.CandidateId, "Closer duration breaks equivalent metadata ties");

            var collaboration = first with { CandidateId = "netease:collaboration", Artists = ["Fixture Artist", "Guest Artist"], DurationMs = track.DurationMs };
            netease.Candidates = [collaboration];
            Check((await Resolve()).Status == "ready", "A player omitting guest credits must still load matching collaboration lyrics");
            var expandedCredits = track with { Artists = collaboration.Artists };
            Check(LyricsResolver.Match(expandedCredits, first).Automatic, "A lyric source omitting guest credits can match the same primary artist");
            Check(LyricsResolver.Match(track, collaboration with { Album = "Collected Signals" }).Automatic,
                "Incomplete collaboration credits still allow ordinary release differences");
            netease.Candidates = [collaboration, first];
            await Resolve();
            Check(netease.Fetched[^1] == first.CandidateId, "Complete artist agreement ranks above partial collaboration credits");
            Check(LyricsResolver.Match(expandedCredits, collaboration with { Artists = ["Guest Artist", "Fixture Artist"] }).Automatic,
                "The same full credit set can be reordered");
            Check(LyricsResolver.Match(track, collaboration with { Artists = ["  FIXTURE ARTIST  ", "Guest Artist"] }).Automatic,
                "Collaboration credits use normalized names");
            foreach (var candidate in new[] {
                collaboration with { Artists = ["Another Artist", "Fixture Artist"] },
                collaboration with { Artists = ["Guest Artist"] },
                collaboration with { Artists = ["Another Artist"] },
                collaboration with { Title = track.Title + " (Live)" },
                collaboration with { Album = "Live Recordings" },
                collaboration with { DurationMs = track.DurationMs + 6000 },
                collaboration with { DurationMs = null }
            })
                Check(!LyricsResolver.Match(track, candidate).Automatic,
                    "Collaboration matching must retain primary-artist, title, version and duration requirements");
            Check(LyricsResolver.Match(expandedCredits, collaboration with { Artists = ["Fixture Artist", "Different Guest"] }).Automatic,
                "Helper accepts differing guest credits when primary artist, title, release and duration agree");
            Check(!LyricsResolver.Match(track with { Artists = [""] }, first with { Artists = [""] }).Automatic,
                "Blank artist credits cannot establish a match");

            foreach (var title in new[] { "Night’s Signal", "Night's Signal (feat. Guest Artist)", "Night's Signal [with Guest Artist]" })
                Check(LyricsResolver.Match(track with { Title = "Night's Signal" }, first with { Title = title }).Automatic,
                    "Upstream name matching accepts punctuation and featured-credit variants: " + title);
            Check(LyricsResolver.Match(track, first with { DurationMs = track.DurationMs + 2500 }).Automatic,
                "Upstream duration grade allows small release-length differences");
            Check(LyricsResolver.Match(track with { Title = "記憶中的光", Artists = ["測試歌手"] },
                    first with { Title = "记忆中的光", Artists = ["测试歌手"] }).Automatic,
                "Portable upstream character normalization supports traditional and simplified credits");
            Check(!LyricsResolver.Match(track, first with { Title = new string('x', 513) }).Automatic,
                "Untrusted provider metadata cannot allocate an unbounded similarity matrix");

            foreach (var title in new[] { track.Title + " (Live)", track.Title + " (Instrumental)", track.Title + " (Remastered 2020)", "Different Signal" })
            {
                netease.Candidates = [first with { Title = title }];
                Check((await Resolve()).Status == "ambiguous", "Different title or version must require a choice: " + title);
            }
            foreach (var album in new[] { "First Light (Live)", "First Light (Instrumental)", "First Light (Remastered 2020)", "First Light (Acoustic)", "First Light (Remix)", "现场精选", "伴奏合集" })
            {
                netease.Candidates = [first with { Album = album }];
                Check((await Resolve()).Status == "ambiguous", "Album-only recording version must not auto-match: " + album);
            }
            foreach (var candidate in new[] { first with { Artists = ["Another Artist"] }, first with { DurationMs = track.DurationMs + 6000 }, first with { DurationMs = null } })
            {
                netease.Candidates = [candidate];
                Check((await Resolve()).Status == "ambiguous", "Artist or timing uncertainty must require a choice");
            }

            Check(!LyricsResolver.Match(track with { Album = "First Light (2011 Remaster)" }, first with { Album = "First Light (2020 Remaster)" }).Automatic,
                "Different remaster years in album metadata must not auto-match");
            Check(LyricsResolver.Match(track with { Album = "First Light (2020 Remaster)" }, first with { Album = "Collected Signals (2020 Remaster)" }).Automatic,
                "Equivalent remaster releases can match across compilations");
            Check(!LyricsResolver.Match(track with { Album = "First Light (Radio Edit)" }, first with { Album = "First Light (Extended)" }).Automatic,
                "Different edit types must not auto-match");

            netease.Candidates = [compilation with { CandidateId = "netease:live", ProviderId = "live", Album = "Live Recordings" }, compilation];
            await Resolve();
            Check(netease.Fetched[^1] == compilation.CandidateId, "An eligible studio recording wins over a version conflict");

            netease.Candidates = [first];
            qq.Candidates = [first with { CandidateId = "qq:a", Provider = "qq" }];
            var totalFetches = qq.Fetched.Count + netease.Fetched.Count;
            found = await resolver.ResolveAsync(track, settings.WithSource("qq", true), true, CancellationToken.None);
            Check(found.Status == "ready" && qq.Fetched.Count + netease.Fetched.Count == totalFetches + 1,
                "Two enabled providers must not force manual selection or fetch both documents");
            Check(found.Candidates.Length == 2, "Alternatives remain available for manual replacement");

            netease.Candidates = [first, duplicate];
            foreach (var code in new[] { "invalid_lyrics", "no_lyrics", "no_synced_lyrics", "ambiguous_timestamps", "document_too_large" })
            {
                netease.Failures[first.CandidateId] = code;
                var count = netease.Fetched.Count;
                found = await Resolve();
                Check(found.Status == "ready" && netease.Fetched.Skip(count).SequenceEqual(new[] { first.CandidateId, duplicate.CandidateId }),
                    "Unusable candidate must fall through to another eligible recording: " + code);
            }
            foreach (var code in new[] { "rate_limited", "timeout", "provider_error" })
            {
                netease.Failures[first.CandidateId] = code;
                var count = netease.Fetched.Count;
                found = await Resolve();
                Check(found.Status == "error" && found.Error == code && netease.Fetched.Count == count + 1,
                    "Transport failure must not cause more candidate requests: " + code);
            }
            netease.Failures[first.CandidateId] = "invalid_lyrics";
            netease.Candidates = [first, duplicate with { Title = track.Title + " (Live)" }];
            var previousFetches = netease.Fetched.Count;
            found = await Resolve();
            Check(found.Status == "error" && netease.Fetched.Count == previousFetches + 1,
                "Fallback must not bypass recording-version constraints");

            netease.Candidates = [first, duplicate, first with { CandidateId = "netease:c" }, first with { CandidateId = "netease:d" }];
            foreach (var candidate in netease.Candidates) netease.Failures[candidate.CandidateId] = "no_lyrics";
            store.ClearCache();
            previousFetches = netease.Fetched.Count;
            found = await Resolve();
            Check(found.Status == "notFound" && netease.Fetched.Count == previousFetches + 3, "Automatic fallback is bounded to three candidates");
            Check(!Directory.EnumerateFiles(store.Cache).Any(), "Candidate failures must not cache a false absence of lyrics");
            netease.Failures.Clear();
            netease.Candidates = [first, duplicate];
            found = await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
            Check(found.Status == "ready", "A recovered candidate can resolve immediately without negative-cache expiry");

            using var cancellation = new CancellationTokenSource();
            netease.BeforeFetch = _ => cancellation.Cancel();
            previousFetches = netease.Fetched.Count;
            bool cancelled = false;
            try { await resolver.ResolveAsync(track, settings, true, cancellation.Token); }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { cancelled = true; }
            Check(cancelled && netease.Fetched.Count == previousFetches + 1, "Track cancellation stops candidate fallback immediately");
            return passed;
        }
        finally
        {
            foreach (var variable in variables) Environment.SetEnvironmentVariable(variable, original[variable]);
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }

    sealed class CandidateProvider(string id) : ILyricProvider
    {
        public string Id => id;
        public LyricCandidate[] Candidates { get; set; } = [];
        public List<string> Fetched { get; } = [];
        public Dictionary<string, string> Failures { get; } = [];
        public Action<CancellationToken>? BeforeFetch { get; set; }
        public int Searches { get; private set; }
        public Task<LyricCandidate[]> SearchAsync(TrackInfo track, CancellationToken token) { Searches++; return Task.FromResult(Candidates); }
        public Task<LyricTrack> FetchAsync(LyricCandidate candidate, TrackInfo track, CancellationToken token)
        {
            Fetched.Add(candidate.CandidateId);
            BeforeFetch?.Invoke(token);
            token.ThrowIfCancellationRequested();
            if (Failures.TryGetValue(candidate.CandidateId, out var code)) throw new RequestError(code, "Original fixture failure");
            return Task.FromResult(HelperFormats.Parse("[00:01]Original matching fixture", "lrc", track, Id));
        }
    }
}
