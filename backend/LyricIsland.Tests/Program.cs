using LyricIsland.Backend;
using LyricIsland.Backend.Lyrics;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Protocol;
using LyricIsland.Backend.Sessions;
using LyricIsland.Backend.Storage;

if (args.Contains("--stdio"))
{
    await ProtocolHost.RunAsync(new SessionCoordinator(new MprisPlayback(), new LocalStore(), [new ControlledProvider()]));
    return;
}
if (args.Contains("--probe-match"))
{
    await MatchProbe.RunAsync();
    return;
}
if (args.Contains("--probe-providers"))
{
    var publicTrack = new TrackInfo("probe:public", "weak", "Yellow", ["Coldplay"], "Parachutes", 266773, "song", "");
    foreach (var provider in new ILyricProvider[] { new QqProvider(), new NeteaseProvider() })
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(25));
        try
        {
            var results = await provider.SearchAsync(publicTrack, timeout.Token);
            var first = results.OrderByDescending(c => LyricsResolver.Match(publicTrack, c).Score).FirstOrDefault();
            var doc = first is null ? null : await provider.FetchAsync(first, publicTrack with { DurationMs = first.DurationMs ?? publicTrack.DurationMs }, timeout.Token);
            Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new { provider = provider.Id, candidates = results.Length,
                lines = doc?.Lines.Length, syncLevel = doc?.SyncLevel }));
        }
        catch (Exception e) { Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new { provider = provider.Id,
            error = e is RequestError re ? re.Code : e is OperationCanceledException ? "timeout" : e.GetType().Name,
            detail = e is RequestError detail ? detail.Message : null })); }
    }
    return;
}
int passed = 0;
passed += await MatchingTests.RunAsync();
passed += FormatFallbackTests.Run();
void Check(bool value, string name) { if (!value) throw new Exception(name); passed++; }
var track = new TrackInfo("test:track", "strong", "Original Signals", ["Fixture"], "Original album", 10000, "song", "");
var matching = new LyricCandidate("qq:1", "qq", "1", track.Title, track.Artists, track.Album, 10000);
Check(LyricsResolver.Match(track, matching).Automatic, "Exact metadata");
Check(!LyricsResolver.Match(track, matching with { Title = "Original Signals (Live)" }).Automatic, "Live version rejected");
Check(!LyricsResolver.Match(track, matching with { Title = "Original Signals (Instrumental)" }).Automatic, "Instrumental version rejected");
Check(!LyricsResolver.Match(track, matching with { DurationMs = 16000 }).Automatic, "Different edit rejected");
Check(LyricsResolver.Match(track, matching with { Album = "" }).Automatic, "Album optional for otherwise reliable metadata");
var word = HelperFormats.Parse("[1000,2000](1000,500,0)Original (2000,1000,0)fixture", "yrc", track, "fixture");
Check(word.Lines[0].Words.Length == 2 && word.Lines[0].Words[1].StartMs == 2000, "Actual word timings preserved");
Check(HelperFormats.Parse("[00:01]Original fixture", "lrc", track, "fixture").Lines[0].Words.Length == 0, "Line timing never fabricated");
var a = LyricDocuments.Create(word, "qq:1");
var b = LyricDocuments.Create(word with { TrackId = "another-app:track", Title = "Other header" }, "qq:1");
Check(a.DocumentId == b.DocumentId, "Content identity independent of player metadata");
Check(HelperFormats.Parse("{\"t\":0,\"c\":[{\"tx\":\"Original credits\"}]}\n[1000,2000](1000,500,0)Original (2000,1000,0)fixture", "yrc", track, "fixture").Lines.Length == 1,
    "Untimed YRC credits excluded");
Check(HelperFormats.Parse("[1000,2000]Original (1000,500)fixture(2000,1000)", "qrc", track, "fixture").Lines[0].Words.Length == 2,
    "QRC word timings parsed explicitly");
var temporary = Path.Combine(Path.GetTempPath(), "lyric-model-" + Guid.NewGuid().ToString("N"));
var variables = new[] { "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME" };
var original = variables.ToDictionary(v => v, Environment.GetEnvironmentVariable);
try
{
    foreach (var variable in variables) Environment.SetEnvironmentVariable(variable, Path.Combine(temporary, variable));
    var store = new LocalStore();
    var source = new CountingProvider();
    var resolver = new LyricsResolver(store, [source]);
    var settings = new Settings().WithSource("qq", true);
    var found = await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
    Check(found.Status == "ready" && source.Searches == 1 && source.Fetches == 1, "Successful provider lookup");
    var cached = await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
    Check(cached.Document?.DocumentId == found.Document?.DocumentId && source.Searches == 1 && source.Fetches == 1, "Positive cache avoids network");
    File.WriteAllText(Directory.GetFiles(store.Cache, "*.json").Single(), "{invalid");
    await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
    Check(source.Searches == 2 && source.Fetches == 2, "Corrupt rebuildable cache is replaced");
    var docs = new LyricDocuments(store);
    docs.Save(track, found.Document! with { OffsetMs = 125 });
    store.ClearCache();
    Check(docs.Find(track)?.OffsetMs == 125 && !Directory.EnumerateFiles(store.Cache).Any(), "Cache clear preserves manual choice and offset");
    source.Empty = true;
    Check((await resolver.ResolveAsync(track, settings, false, CancellationToken.None)).Status == "notFound", "Empty provider result");
    var calls = source.Searches;
    await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
    Check(source.Searches == calls, "Negative cache avoids repeated search");
    store.ClearCache(); source.Empty = false; source.Failed = true;
    await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
    await resolver.ResolveAsync(track, settings, false, CancellationToken.None);
    Check(source.Searches == calls + 2 && !Directory.EnumerateFiles(store.Cache).Any(), "Provider failures never become negative cache");
    Directory.CreateDirectory(store.Config);
    File.WriteAllText(Path.Combine(store.Config, "settings.json"), "{\"schemaVersion\":1,\"qqEnabled\":true,\"neteaseEnabled\":false}");
    var migrated = store.LoadSettings();
    Check(migrated.IsEnabled("qq") && !migrated.IsEnabled("netease"), "Legacy source consent is preserved without opting in new sources");
    var generic = ProviderCatalog.Update(migrated, System.Text.Json.JsonSerializer.SerializeToElement(new { sources = new { qq = false, netease = true } }));
    store.SaveSettings(generic);
    Check(!store.LoadSettings().IsEnabled("qq") && store.LoadSettings().IsEnabled("netease"), "Generic source consent round-trips through storage");
    bool unknownSourceRejected = false;
    try { ProviderCatalog.Update(generic, System.Text.Json.JsonSerializer.SerializeToElement(new { sources = new { unknown = true } })); }
    catch (RequestError error) when (error.Code == "invalid_request") { unknownSourceRejected = true; }
    Check(unknownSourceRejected, "Only registered sources can acquire online permission");
    store.SaveSettings(new Settings(SchemaVersion: 99));
    var before = File.ReadAllText(Path.Combine(store.Config, "settings.json"));
    bool rejected = false;
    try { store.LoadSettings(); } catch (RequestError e) when (e.Code == "storage_error") { rejected = true; }
    Check(rejected && File.ReadAllText(Path.Combine(store.Config, "settings.json")) == before, "Future settings schema preserved unchanged");
}
finally
{
    foreach (var variable in variables) Environment.SetEnvironmentVariable(variable, original[variable]);
    if (Directory.Exists(temporary)) Directory.Delete(temporary, true);
}
var httpCalls = 0;
using (var http = new HttpClient(new ProviderTransport(new StubHttp((_, _) =>
{
    httpCalls++;
    var response = new HttpResponseMessage(System.Net.HttpStatusCode.TooManyRequests);
    response.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(60));
    return Task.FromResult(response);
}))))
{
    for (var retry = 0; retry < 2; retry++)
    {
        bool limited = false;
        try { await ProviderTransport.RunAsync("qq", () => http.GetAsync("https://c.y.qq.com/fixture"), CancellationToken.None); }
        catch (RequestError e) when (e.Code == "rate_limited") { limited = true; }
        Check(limited && httpCalls == 1, "429 Retry-After prevents another HTTP request");
    }
}
using (var http = new HttpClient(new ProviderTransport(new StubHttp((_, _) => Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
    { Content = new ByteArrayContent(new byte[1048577]) })))))
{
    bool bounded = false;
    try { await ProviderTransport.RunAsync("qq", () => http.GetAsync("https://c.y.qq.com/fixture"), CancellationToken.None); }
    catch (RequestError e) when (e.Code == "document_too_large") { bounded = true; }
    Check(bounded, "Oversized HTTP response rejected");
}
using (var http = new HttpClient(new ProviderTransport(new StubHttp(async (_, token) =>
    { await Task.Delay(30000, token); return new HttpResponseMessage(System.Net.HttpStatusCode.OK); }))))
using (var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(30)))
{
    bool cancelled = false;
    try { await ProviderTransport.RunAsync("qq", () => http.GetAsync("https://c.y.qq.com/fixture"), cancellation.Token); }
    catch (OperationCanceledException) { cancelled = true; }
    Check(cancelled, "Resolution cancellation reaches the HTTP request");
}
Console.WriteLine($"Lyrics model/transport tests: {passed} passed");

// Only compiled into the test host. Deliberately ignores cancellation to prove attribution.
sealed class ControlledProvider : ILyricProvider
{
    public string Id => "qq";
    public async Task<LyricCandidate[]> SearchAsync(TrackInfo track, CancellationToken token)
    {
        await Task.Delay(track.Title.Contains("slow", StringComparison.OrdinalIgnoreCase) ? 700 : 15);
        if (track.Title.Contains("limited", StringComparison.OrdinalIgnoreCase)) throw new RequestError("rate_limited", "Fixture rate limit.");
        return [new("qq:" + track.TrackKey, "qq", track.TrackKey, track.Title, track.Artists, track.Album, track.DurationMs)];
    }
    public async Task<LyricTrack> FetchAsync(LyricCandidate candidate, TrackInfo track, CancellationToken token)
    {
        await Task.Delay(15);
        return HelperFormats.Parse("[00:00]" + track.Title, "lrc", track, "fixture-provider");
    }
}

sealed class CountingProvider : ILyricProvider
{
    public string Id => "qq";
    public int Searches { get; private set; }
    public int Fetches { get; private set; }
    public bool Empty { get; set; }
    public bool Failed { get; set; }
    public Task<LyricCandidate[]> SearchAsync(TrackInfo track, CancellationToken token)
    {
        Searches++;
        if (Failed) throw new RequestError("provider_error", "Original fixture failure.");
        return Task.FromResult<LyricCandidate[]>(Empty ? [] : [new("qq:fixture", Id, "fixture", track.Title, track.Artists, track.Album, track.DurationMs)]);
    }
    public Task<LyricTrack> FetchAsync(LyricCandidate candidate, TrackInfo track, CancellationToken token)
    {
        Fetches++;
        return Task.FromResult(HelperFormats.Parse("[00:01]Original cached fixture", "lrc", track, "fixture"));
    }
}

sealed class StubHttp(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> operation) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => operation(request, token);
}
