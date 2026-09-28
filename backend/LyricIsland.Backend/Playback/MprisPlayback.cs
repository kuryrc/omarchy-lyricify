using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Channels;
using LyricIsland.DBus;
using Tmds.DBus.Protocol;

namespace LyricIsland.Backend.Playback;

// All D-Bus details stay here. Callers see immutable snapshots and scoped commands.
public sealed class MprisPlayback : IAsyncDisposable
{
    const string Prefix = "org.mpris.MediaPlayer2.";
    readonly CancellationTokenSource stop = new();
    readonly Channel<bool> dirty = Channel.CreateBounded<bool>(new BoundedChannelOptions(1) { FullMode = BoundedChannelFullMode.DropOldest });
    readonly SemaphoreSlim refresh = new(1);
    readonly List<IDisposable> subscriptions = [];
    DBusConnection? connection;
    LyricIsland.DBus.DBus? bus;
    Player? player;
    string? selectedName, selectedOwner, trackPath;
    string preferredApplication = "spotify";
    long generation, discontinuity, revision;
    bool seekPending;
    Task? loop, ticker;
    public PlaybackState State { get; private set; } = PlaybackState.Empty;
    public event Action<PlaybackState>? Changed;

    public void Start(string application = "spotify")
    {
        preferredApplication = application.StartsWith(Prefix, StringComparison.Ordinal) ? application[Prefix.Length..] : application;
        loop = RunAsync();
        ticker = TickAsync();
    }
    void Signal() { Interlocked.Increment(ref revision); dirty.Writer.TryWrite(true); }
    async Task TickAsync()
    {
        try { using var timer = new PeriodicTimer(TimeSpan.FromSeconds(3)); while (await timer.WaitForNextTickAsync(stop.Token)) dirty.Writer.TryWrite(true); }
        catch (OperationCanceledException) { }
    }
    async Task RunAsync()
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                connection = new(new DBusConnectionOptions(DBusAddress.Session ?? throw new IOException("No session bus")) { OnException = _ => Signal() });
                await connection.ConnectAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3), stop.Token);
                bus = new DBusService(connection, "org.freedesktop.DBus").CreateDBus("/org/freedesktop/DBus");
                using var names = await bus.WatchNameOwnerChangedAsync(change => { if (change.Name.StartsWith(Prefix, StringComparison.Ordinal)) Signal(); }, false);
                Signal();
                while (await dirty.Reader.WaitToReadAsync(stop.Token))
                {
                    while (dirty.Reader.TryRead(out _)) { }
                    await RefreshAsync("sample");
                    if (connection.DisconnectedAsync().IsCompleted) break;
                }
            }
            catch (Exception e) when (e is not OutOfMemoryException) { if (!stop.IsCancellationRequested) Console.Error.WriteLine("playback_connection_unavailable"); }
            finally { ClearPlayer(); connection?.Dispose(); connection = null; bus = null; Publish(PlaybackState.Empty); }
            try { await Task.Delay(1000, stop.Token); } catch (OperationCanceledException) { }
        }
    }
    void ClearPlayer()
    {
        foreach (var sub in subscriptions) sub.Dispose();
        subscriptions.Clear(); player = null; selectedOwner = null; selectedName = null; trackPath = null;
    }
    void Publish(PlaybackState value) { State = value; Changed?.Invoke(value); }
    public async Task<string[]> ListAsync()
    {
        var conn = connection ?? throw new RequestError("player_unavailable", "Session bus unavailable.");
        return (await conn.ListServicesAsync().WaitAsync(TimeSpan.FromSeconds(2), stop.Token))
            .Where(n => n.StartsWith(Prefix, StringComparison.Ordinal)).Order().ToArray();
    }
    public async Task SelectAsync(string application)
    {
        if (!Regex.IsMatch(application, @"^[A-Za-z0-9_.-]{1,160}$")) throw new RequestError("invalid_request", "Invalid application identifier.");
        await refresh.WaitAsync(stop.Token);
        try { preferredApplication = application.StartsWith(Prefix, StringComparison.Ordinal) ? application[Prefix.Length..] : application; ClearPlayer(); Publish(PlaybackState.Empty); Signal(); }
        finally { refresh.Release(); }
        await RefreshAsync("reconnect");
    }
    public async Task ResyncAsync() => await RefreshAsync("resume");
    async Task RefreshAsync(string reason)
    {
        await refresh.WaitAsync(stop.Token);
        try
        {
            if (connection is null || bus is null) return;
            var names = await ListAsync();
            if (selectedName is not null)
            {
                string? owner = names.Contains(selectedName) ? await bus.GetNameOwnerAsync(selectedName).WaitAsync(TimeSpan.FromSeconds(2), stop.Token) : null;
                if (owner != selectedOwner) { ClearPlayer(); Publish(PlaybackState.Empty); }
            }
            if (player is null)
            {
                var candidates = names.Where(n => n == Prefix + preferredApplication || n.StartsWith(Prefix + preferredApplication + ".", StringComparison.Ordinal)).ToArray();
                var choices = new List<(string Name, string Owner, Player Proxy, bool Active)>();
                foreach (var name in candidates.Take(32))
                {
                    try
                    {
                        var owner = await bus.GetNameOwnerAsync(name).WaitAsync(TimeSpan.FromSeconds(2), stop.Token);
                        var proxy = new DBusService(connection, owner).CreatePlayer("/org/mpris/MediaPlayer2");
                        var props = await proxy.GetNullablePropertiesAsync().WaitAsync(TimeSpan.FromSeconds(2), stop.Token);
                        choices.Add((name, owner, proxy, props.PlaybackStatus == "Playing" && props.Metadata?.ContainsKey("xesam:title") == true));
                    }
                    catch (DBusErrorReplyException) { }
                }
                if (choices.Count == 0) return;
                var chosen = choices.OrderByDescending(c => c.Active).ThenBy(c => c.Name, StringComparer.Ordinal).First();
                selectedName = chosen.Name; selectedOwner = chosen.Owner; player = chosen.Proxy;
                var bound = player;
                subscriptions.Add(await player.WatchPropertiesChangedAsync(_ => { if (player == bound) Signal(); }, false));
                subscriptions.Add(await player.WatchSeekedAsync((long _) => { if (player == bound) { seekPending = true; Signal(); } }, false));
                reason = "reconnect";
            }
            var before = Interlocked.Read(ref revision);
            var started = Stopwatch.GetTimestamp();
            var values = await player.GetNullablePropertiesAsync().WaitAsync(TimeSpan.FromSeconds(2), stop.Token);
            // An event arriving during GetAll can make the response belong to an old track.
            if (before != Interlocked.Read(ref revision)) { dirty.Writer.TryWrite(true); return; }
            var received = Stopwatch.GetTimestamp();
            var metadata = values.Metadata ?? [];
            var app = selectedName![Prefix.Length..].Split('.')[0];
            var track = Normalize(app, metadata);
            var path = TrackPath(metadata);
            var changed = State.Player?.InstanceId != selectedOwner || State.Track?.TrackKey != track?.TrackKey || trackPath != path;
            if (changed) { generation++; reason = "track-change"; }
            else if (seekPending) reason = "seek";
            else if (State.Playback.Status != "Playing" && values.PlaybackStatus == "Playing") reason = "resume";
            if (reason != "sample") discontinuity++;
            seekPending = false; trackPath = path;
            var rate = values.Rate is double r && double.IsFinite(r) && r > 0 && r <= 16 ? r : 1;
            var control = values.CanControl == true;
            var position = values.Position;
            Publish(new(new(app, app == "spotify" ? "Spotify" : app, selectedOwner!), track,
                new(values.PlaybackStatus ?? "Stopped", rate, control && values.CanPlay == true,
                    control && values.CanPause == true, control && values.CanGoNext == true,
                    control && values.CanGoPrevious == true, control && values.CanSeek == true &&
                    track?.DurationMs > 0 && position >= 0 && path is not null && path != "/org/mpris/MediaPlayer2/TrackList/NoTrack"),
                new(selectedOwner!, generation), position >= 0, Math.Max(0, (position ?? 0) / 1000d), received,
                Stopwatch.GetElapsedTime(started, received).TotalMilliseconds, discontinuity, reason));
        }
        catch (DBusErrorReplyException) { /* Discovery retries on the next event or timer, never spins. */ }
        finally { refresh.Release(); }
    }
    public async Task ExecuteAsync(string operation, TrackScope scope, double? position)
    {
        // Capture the unique owner proxy. Well-known name reuse cannot redirect a command.
        var target = player; var state = State; var path = trackPath;
        if (target is null || state.Player is null) throw new RequestError("player_unavailable", "No selected player.");
        if (state.Scope != scope) throw new RequestError("stale_scope", "Playback session changed.");
        var cap = state.Playback;
        Task call = operation switch
        {
            "playback.play" when cap.CanPlay => target.PlayAsync(),
            "playback.pause" when cap.CanPause => target.PauseAsync(),
            "playback.next" when cap.CanNext => target.NextAsync(),
            "playback.previous" when cap.CanPrevious => target.PreviousAsync(),
            "playback.seek" when cap.CanSeekAbsolute && position is double p && double.IsFinite(p) && p >= 0 && p <= state.Track!.DurationMs => target.SetPositionAsync(new ObjectPath(path!), checked((long)(p * 1000))),
            _ => throw new RequestError("unsupported_capability", "Operation unavailable for this player state.")
        };
        await call.WaitAsync(TimeSpan.FromSeconds(2), stop.Token);
        if (operation == "playback.seek") seekPending = true;
        Signal();
    }
    static VariantValue? Value(Dictionary<string, VariantValue> data, string key, VariantValueType type)
        => data.TryGetValue(key, out var value) && value.Type == type ? value : (VariantValue?)null;
    static string Text(Dictionary<string, VariantValue> data, string key) => Value(data, key, VariantValueType.String)?.GetString() ?? "";
    static string? TrackPath(Dictionary<string, VariantValue> data)
    {
        // Spotify 1.2.96 sends a string here, although MPRIS specifies an object path.
        // Accept only strings that are valid paths; never reinterpret a Spotify URI as one.
        var path = Value(data, "mpris:trackid", VariantValueType.ObjectPath)?.GetObjectPathAsString()
            ?? Text(data, "mpris:trackid");
        return Regex.IsMatch(path, @"^/(?:[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*)?$") ? path : null;
    }
    static TrackInfo? Normalize(string app, Dictionary<string, VariantValue> data)
    {
        var title = Text(data, "xesam:title");
        var artists = Value(data, "xesam:artist", VariantValueType.Array)?.GetArray<string>() ?? [];
        var album = Text(data, "xesam:album");
        // Real Spotify also uses uint64 for length. Bound before converting to signed units.
        var unsigned = Value(data, "mpris:length", VariantValueType.UInt64)?.GetUInt64();
        var length = Value(data, "mpris:length", VariantValueType.Int64)?.GetInt64()
            ?? (unsigned is <= 86400000000 ? (long?)unsigned : null);
        double? duration = length is > 0 and <= 86400000000 ? length / 1000d : null;
        var url = Text(data, "xesam:url");
        if (title.Length == 0 && url.Length == 0) return null;
        var id = Regex.Match(url, @"^(?:spotify:|https://open\.spotify\.com/)(track|episode|ad)[:/]([A-Za-z0-9]{22})(?:\?.*)?$");
        var strong = app == "spotify" && id.Success;
        var kind = strong ? id.Groups[1].Value switch { "track" => "song", "episode" => "podcast", _ => "advertisement" } : "unknown";
        var fingerprint = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(System.Text.Json.JsonSerializer.Serialize(new { title, artists, album, duration }))));
        return new(strong ? $"spotify:{id.Groups[1].Value}:{id.Groups[2].Value}" : $"{app}:metadata:{fingerprint}",
            strong ? "strong" : "weak", title, artists, album, duration, kind, Text(data, "mpris:artUrl"));
    }
    public async ValueTask DisposeAsync()
    {
        await stop.CancelAsync(); dirty.Writer.TryComplete(); connection?.Dispose();
        if (loop is not null) await loop;
        if (ticker is not null) await ticker;
        stop.Dispose(); refresh.Dispose();
    }
}
