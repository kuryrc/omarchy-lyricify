using System.Text.Json;
using LyricIsland.Backend.Lyrics;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Storage;

namespace LyricIsland.Backend.Sessions;

// Owns result attribution and document locking. D-Bus and HTTP are separate modules.
public sealed class SessionCoordinator : IAsyncDisposable
{
    readonly object gate = new();
    readonly MprisPlayback playback;
    readonly LocalStore store;
    readonly LyricDocuments documents;
    readonly LyricsResolver resolver;
    readonly HashSet<Task> work = [];
    readonly CancellationTokenSource lifetime = new();
    Settings settings;
    PlaybackState state = PlaybackState.Empty;
    LyricDocument? document;
    LyricCandidate[] candidates = [];
    CancellationTokenSource? resolving;
    string resolutionId = Guid.NewGuid().ToString("N"), lyricsStatus = "idle", lyricsError = "";
    bool stopping;
    public event Action<string, TrackScope?, Func<object>>? Event;
    public SessionCoordinator(MprisPlayback playback, LocalStore store, ILyricProvider[]? providers = null)
    {
        this.playback = playback; this.store = store; documents = new(store); settings = store.LoadSettings();
        resolver = new(store, providers ?? ProviderCatalog.All.Select(p => p.Create()).ToArray());
        playback.Changed += OnPlayback;
    }
    public void Start() => playback.Start(settings.PreferredPlayer);
    void InvalidateWork()
    {
        resolving?.Cancel(); resolving = null;
        resolutionId = Guid.NewGuid().ToString("N"); lyricsError = "";
    }
    void OnPlayback(PlaybackState incoming)
    {
        lock (gate)
        {
            if (stopping) return;
            var changed = state.Scope != incoming.Scope;
            var metadataChanged = !SameMatchInput(state.Track, incoming.Track);
            state = incoming;
            if (changed)
            {
                InvalidateWork(); document = null; candidates = [];
                lyricsStatus = incoming.Track is null ? "idle" : "disabled";
                if (incoming.Track is not null)
                {
                    try { document = documents.Find(incoming.Track); }
                    catch (RequestError e) { lyricsStatus = "error"; lyricsError = e.Code; }
                }
                if (document is not null) { lyricsStatus = "ready"; EmitDocument(); }
                else if (incoming.Track is not null && lyricsStatus != "error") StartResolution(false);
            }
            else if (document is null && incoming.Track is not null && metadataChanged)
                StartResolution(true);
            EmitState();
        }
    }
    static bool SameMatchInput(TrackInfo? a, TrackInfo? b) => a is null ? b is null : b is not null
        && a.Title == b.Title && a.Artists.SequenceEqual(b.Artists) && a.Album == b.Album
        && a.DurationMs == b.DurationMs && a.ContentKind == b.ContentKind;
    void StartResolution(bool refresh, LyricCandidate? selection = null)
    {
        InvalidateWork();
        if (state.Track is null) { lyricsStatus = "idle"; return; }
        var track = state.Track; var scope = state.Scope; var resolution = resolutionId; var options = settings;
        var cancellation = new CancellationTokenSource(); resolving = cancellation;
        if (document is null) lyricsStatus = "loading";
        else EmitDocument(); // Keep the locked document while looking for alternatives.
        var task = Task.Run(async () =>
        {
            try
            {
                var result = selection is null
                    ? await resolver.ResolveAsync(track, options, refresh, cancellation.Token)
                    : new Resolution("ready", await resolver.SelectAsync(track, selection, options, cancellation.Token), candidates);
                lock (gate)
                {
                    if (stopping || cancellation.IsCancellationRequested || state.Scope != scope || resolutionId != resolution) return;
                    candidates = result.Candidates;
                    if (result.Document is not null && (document is null || selection is not null))
                    {
                        if (selection is not null) documents.Save(track, result.Document);
                        document = result.Document; EmitDocument();
                    }
                    lyricsStatus = document is null ? result.Status : "ready"; lyricsError = result.Error ?? "";
                    EmitState();
                }
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
            catch (Exception e) when (e is not OutOfMemoryException)
            {
                lock (gate)
                {
                    if (stopping || cancellation.IsCancellationRequested || state.Scope != scope || resolutionId != resolution) return;
                    lyricsStatus = document is null ? "error" : "ready";
                    lyricsError = e is RequestError re ? re.Code : e is OperationCanceledException ? "timeout"
                        : e is IOException or UnauthorizedAccessException ? "storage_error" : "provider_error";
                    EmitState();
                }
            }
        });
        work.Add(task);
        _ = task.ContinueWith(done => { lock (gate) { work.Remove(done); if (resolving == cancellation) resolving = null; cancellation.Dispose(); } }, TaskScheduler.Default);
    }
    void EmitDocument()
    {
        var doc = document!; var resolution = resolutionId;
        Event?.Invoke("lyrics.document", state.Scope, () => new { resolutionId = resolution, doc.DocumentId, doc.LyricVersionId, doc.Document });
    }
    object Snapshot(PlaybackState snapshot, LyricDocument? doc, string resolution, string status, string error, int count) => new
    {
        snapshot.Player, snapshot.Track, snapshot.Playback, position = snapshot.Position(),
        lyrics = new { status, errorCode = error, resolutionId = resolution, documentId = doc?.DocumentId, lyricVersionId = doc?.LyricVersionId, offsetMs = doc?.OffsetMs ?? 0, candidateCount = count }
    };
    void EmitState()
    {
        var snapshot = state; var doc = document; var resolution = resolutionId; var status = lyricsStatus; var error = lyricsError; var count = candidates.Length;
        Event?.Invoke("session.state", state.Scope, () => Snapshot(snapshot, doc, resolution, status, error, count));
    }
    public void EmitCurrent() { lock (gate) { if (document is not null) EmitDocument(); EmitState(); } }
    void RequireScope(TrackScope? scope)
    {
        if (state.Scope is null) throw new RequestError("player_unavailable", "No selected player.");
        if (scope != state.Scope) throw new RequestError("stale_scope", "Track changed.");
    }
    public async Task<object> DispatchAsync(string op, JsonElement args, TrackScope? scope)
    {
        if (op.StartsWith("playback.", StringComparison.Ordinal))
        {
            lock (gate) RequireScope(scope);
            double? ms = args.TryGetProperty("positionMs", out var pos) ? pos.GetDouble() : null;
            await playback.ExecuteAsync(op, scope!, ms); return new { accepted = true };
        }
        switch (op)
        {
            case "lyrics.import":
                TrackInfo track;
                string importingResolution;
                lock (gate)
                {
                    RequireScope(scope);
                    track = state.Track ?? throw new RequestError("player_unavailable", "No track metadata.");
                    importingResolution = resolutionId;
                }
                using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token))
                {
                    timeout.CancelAfter(TimeSpan.FromSeconds(3));
                    var imported = await documents.ImportAsync(args, track, timeout.Token).WaitAsync(timeout.Token);
                    lock (gate)
                    {
                        RequireScope(scope);
                        if (stopping || importingResolution != resolutionId) throw new RequestError("stale_scope", "Lyric selection changed.");
                        documents.Save(track, imported);
                        InvalidateWork(); document = imported; lyricsStatus = "ready";
                        EmitDocument(); EmitState(); return new { imported.DocumentId, imported.LyricVersionId };
                    }
                }
            case "player.list": return new { players = await playback.ListAsync() };
            case "player.select":
                var app = args.GetProperty("applicationId").GetString()!;
                await playback.SelectAsync(app);
                lock (gate) { var updated = settings with { PreferredPlayer = app }; store.SaveSettings(updated); settings = updated; }
                return new { selected = true };
            case "session.resync":
                lock (gate) { if (scope is not null) RequireScope(scope); }
                await playback.ResyncAsync();
                lock (gate)
                {
                    if (scope is not null) RequireScope(scope);
                    EmitState();
                    return new { scope = state.Scope, snapshot = Snapshot(state, document, resolutionId, lyricsStatus, lyricsError, candidates.Length) };
                }
        }
        lock (gate)
        {
            switch (op)
            {
                case "settings.get": return ProviderCatalog.SettingsView(settings);
                case "settings.update":
                    var updated = ProviderCatalog.Update(settings, args);
                    store.SaveSettings(updated); settings = updated; StartResolution(false); EmitState(); return ProviderCatalog.SettingsView(settings);
                case "lyrics.candidates": RequireScope(scope); return new { resolutionId, candidates };
                case "lyrics.refresh": RequireScope(scope); StartResolution(true); EmitState(); return new { resolutionId };
                case "lyrics.select":
                    RequireScope(scope);
                    if (args.GetProperty("resolutionId").GetString() != resolutionId) throw new RequestError("stale_scope", "Candidate list changed.");
                    var selected = candidates.FirstOrDefault(c => c.CandidateId == args.GetProperty("candidateId").GetString())
                        ?? throw new RequestError("stale_scope", "Candidate unavailable.");
                    StartResolution(false, selected); EmitState(); return new { resolutionId };
                case "lyrics.set-offset":
                    RequireScope(scope);
                    if (document is null || !args.TryGetProperty("documentId", out var docId) || docId.GetString() != document.DocumentId
                        || !args.TryGetProperty("lyricVersionId", out var versionId) || versionId.GetString() != document.LyricVersionId)
                        throw new RequestError("stale_scope", "Lyric version changed.");
                    var offset = args.GetProperty("offsetMs").GetDouble();
                    if (!double.IsFinite(offset) || Math.Abs(offset) > 30000) throw new RequestError("invalid_request", "Offset must be within 30 seconds.");
                    var adjusted = document with { OffsetMs = offset }; documents.Save(state.Track!, adjusted); document = adjusted; EmitState(); return new { offsetMs = offset };
                case "cache.clear": store.ClearCache(); return new { cleared = true };
                case "diagnostics.export":
                    var diagnostic = new { backendVersion = BuildInfo.Version, protocol = 2, playerAvailable = state.Player is not null,
                        positionKnown = state.PositionKnown, lyricsStatus, lyricsError,
                        onlineProviders = ProviderCatalog.All.ToDictionary(p => p.Id, p => settings.IsEnabled(p.Id)) };
                    if (args.TryGetProperty("path", out var destination))
                    {
                        var path = destination.GetString() ?? "";
                        if (!Path.IsPathFullyQualified(path)) throw new RequestError("invalid_request", "Choose a local destination.");
                        store.Write(path, diagnostic);
                    }
                    return diagnostic;
                default: throw new RequestError("invalid_request", "Unsupported operation.");
            }
        }
    }
    public async ValueTask DisposeAsync()
    {
        Task[] pending;
        lock (gate) { if (stopping) return; stopping = true; lifetime.Cancel(); InvalidateWork(); pending = work.ToArray(); }
        playback.Changed -= OnPlayback; await playback.DisposeAsync();
        await Task.WhenAll(pending);
    }
}
