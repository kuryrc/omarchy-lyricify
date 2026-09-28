using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Sessions;
using LyricIsland.Backend.Storage;

namespace LyricIsland.Backend.Protocol;

public sealed class ProtocolHost
{
    const int Limit = 1048576;
    readonly string epoch = Guid.NewGuid().ToString("N");
    readonly Channel<Func<long, object>> output = Channel.CreateBounded<Func<long, object>>(256);
    readonly CancellationTokenSource stop = new();
    readonly Dictionary<string, (string Fingerprint, Task<object> Response)> requests = [];
    readonly SessionCoordinator session;
    bool greeted;
    int active;
    ProtocolHost(SessionCoordinator session)
    {
        this.session = session;
        session.Event += (name, scope, payload) =>
        {
            if (greeted) Queue(seq => new { version = 2, type = "event", @event = name, backendSessionId = epoch, seq, scope, payload = payload() });
        };
    }
    void Queue(Func<long, object> value)
    {
        if (!output.Writer.TryWrite(value)) { Console.Error.WriteLine("protocol_backpressure"); stop.Cancel(); }
    }
    object Error(string? id, string? op, string code, string message) => new { version = 2, type = "response", id, op, ok = false, backendSessionId = epoch, error = new { code, message } };
    object Success(string id, string op, object result) => new { version = 2, type = "response", id, op, ok = true, backendSessionId = epoch, result };
    public static async Task RunAsync()
    {
        var session = new SessionCoordinator(new MprisPlayback(), new LocalStore());
        await RunAsync(session);
    }
    public static async Task RunAsync(SessionCoordinator session)
    {
        var host = new ProtocolHost(session);
        await host.RunLoopAsync();
    }
    async Task WriteAsync()
    {
        long seq = 0;
        await using var stream = Console.OpenStandardOutput();
        await foreach (var value in output.Reader.ReadAllAsync())
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(value(++seq), LocalStore.Json);
            if (bytes.Length > Limit) { Console.Error.WriteLine("protocol_output_too_large"); stop.Cancel(); break; }
            await stream.WriteAsync(bytes, stop.Token);
            await stream.WriteAsync("\n"u8.ToArray(), stop.Token);
            await stream.FlushAsync(stop.Token);
        }
    }
    async Task RunLoopAsync()
    {
        var writer = WriteAsync();
        _ = writer.ContinueWith(_ => stop.Cancel(), CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.Default);
        try
        {
            await foreach (var line in LinesAsync(Console.OpenStandardInput(), stop.Token))
            {
                string? id = null, op = null;
                try
                {
                    if (line is null) throw new RequestError("invalid_request", "Request exceeds 1 MiB.");
                    using var json = JsonDocument.Parse(line);
                    var req = json.RootElement;
                    if (req.ValueKind != JsonValueKind.Object) throw new RequestError("invalid_request", "Expected object.");
                    id = req.GetProperty("id").GetString(); op = req.GetProperty("op").GetString();
                    if (string.IsNullOrEmpty(id) || id.Length > 128 || string.IsNullOrEmpty(op) || op.Length > 64) throw new RequestError("invalid_request", "Invalid request identity.");
                    if (req.GetProperty("version").GetInt32() != 2) throw new RequestError("unsupported_version", "Expected version 2.");
                    if (req.GetProperty("type").GetString() != "request") throw new RequestError("invalid_request", "Expected request type.");
                    var args = req.TryGetProperty("params", out var param) ? param.Clone() : JsonSerializer.SerializeToElement(new { });
                    if (args.ValueKind != JsonValueKind.Object) throw new RequestError("invalid_request", "Expected params object.");
                    if (op == "hello")
                    {
                        if (greeted || !args.GetProperty("supportedProtocols").EnumerateArray().Any(v => v.GetInt32() == 2)) throw new RequestError("incompatible_backend", "No compatible protocol or repeated hello.");
                        var reply = Success(id, op, new { backendVersion = BuildInfo.Version, protocol = 2, capabilities = new[] { "playback", "lyrics-import", "lyrics-offset", "lyrics-online", "lyrics-candidates", "diagnostics" } });
                        Queue(_ => reply); greeted = true; session.EmitCurrent(); session.Start(); continue;
                    }
                    if (!greeted || req.GetProperty("backendSessionId").GetString() != epoch) throw new RequestError("stale_scope", "Backend handshake required.");
                    if (op == "shutdown") { var reply = Success(id, op, new { stopping = true }); Queue(_ => reply); break; }
                    // Bound both concurrent requests and deduplication memory. A duplicate joins the same task.
                    var fingerprint = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(line));
                    if (requests.TryGetValue(id, out var previous))
                    {
                        if (previous.Fingerprint != fingerprint) throw new RequestError("invalid_request", "Request id reused with different payload.");
                        if (!previous.Response.IsCompleted) continue;
                        var cached = await previous.Response; Queue(_ => cached); continue;
                    }
                    if (Volatile.Read(ref active) >= 32) throw new RequestError("rate_limited", "Too many pending requests.");
                    if (requests.Count >= 256)
                    {
                        var evict = requests.FirstOrDefault(pair => pair.Value.Response.IsCompleted).Key;
                        if (evict is null) throw new RequestError("rate_limited", "Request retention is full.");
                        requests.Remove(evict);
                    }
                    var scope = req.TryGetProperty("scope", out var sc) ? sc.Deserialize<TrackScope>(LocalStore.Json) : null;
                    Interlocked.Increment(ref active);
                    var task = ExecuteAsync(id, op, args, scope);
                    requests.Add(id, (fingerprint, task));
                    // Evict only completed entries, never an in-flight command.
                }
                catch (Exception e) when (e is RequestError or JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
                {
                    var response = Error(id, op, e is RequestError re ? re.Code : "invalid_request", e is RequestError r ? r.Message : "Malformed request."); Queue(_ => response);
                }
            }
        }
        catch (OperationCanceledException) { }
        finally
        {
            // EOF is ownership loss: stop D-Bus work and finish pending operations before closing stdout.
            await session.DisposeAsync();
            try { await Task.WhenAll(requests.Values.Select(r => r.Response)).WaitAsync(TimeSpan.FromSeconds(3)); } catch (TimeoutException) { }
            output.Writer.TryComplete();
            try { await writer; } catch (Exception e) when (e is IOException or OperationCanceledException) { }
        }
    }
    async Task<object> ExecuteAsync(string id, string op, JsonElement args, TrackScope? scope)
    {
        await Task.Yield();
        object response;
        try { response = Success(id, op, await session.DispatchAsync(op, args, scope)); }
        catch (Exception e) when (e is not OutOfMemoryException)
        {
            var code = e switch { RequestError re => re.Code, TimeoutException => "timeout", IOException or UnauthorizedAccessException => "storage_error", OperationCanceledException => "backend_unavailable", Tmds.DBus.Protocol.DBusErrorReplyException => "player_unavailable", _ => "invalid_request" };
            response = Error(id, op, code, e is RequestError error ? error.Message : "Operation failed.");
        }
        finally { Interlocked.Decrement(ref active); }
        Queue(_ => response); return response;
    }
    static async IAsyncEnumerable<byte[]?> LinesAsync(Stream stream, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken token)
    {
        var chunk = new byte[8192]; using var line = new MemoryStream(); bool oversized = false;
        int read;
        while ((read = await stream.ReadAsync(chunk, token)) > 0)
        {
            for (var i = 0; i < read; i++)
            {
                if (chunk[i] == 10) { yield return oversized ? null : line.ToArray(); line.SetLength(0); oversized = false; }
                else if (line.Length < Limit) line.WriteByte(chunk[i]); else oversized = true;
            }
        }
        if (line.Length != 0 || oversized) yield return oversized ? null : line.ToArray();
    }
}
