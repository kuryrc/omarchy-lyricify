using System.Diagnostics;
using System.Net;
using Lyricify.Lyrics.Providers.Web;

namespace LyricIsland.Backend.Lyrics;

// Helper 0.2.0 shares mutable default HTTP headers. Serialize its API calls and
// supply cancellation, host limits, response bounds and rate limiting below them.
public sealed class ProviderTransport : DelegatingHandler
{
    static readonly SemaphoreSlim gate = new(1);
    static readonly AsyncLocal<CancellationToken> requestToken = new();
    static readonly AsyncLocal<string?> provider = new();
    readonly Dictionary<string, long> nextRequest = [];
    static readonly Lazy<HttpClient> client = new(() => new(new ProviderTransport()) { Timeout = TimeSpan.FromSeconds(12), MaxResponseContentBufferSize = 1048576 });
    public ProviderTransport() : this(new SocketsHttpHandler { AllowAutoRedirect = false, AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate, UseCookies = false }) { }
    public ProviderTransport(HttpMessageHandler transport) : base(transport) { }
    public static async Task<T> RunAsync<T>(string source, Func<Task<T>> operation, CancellationToken token)
    {
        await gate.WaitAsync(token);
        try
        {
            requestToken.Value = token; provider.Value = source;
            BaseApi.HttpClient = client.Value;
            return await operation();
        }
        finally { requestToken.Value = default; provider.Value = null; gate.Release(); }
    }
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, requestToken.Value);
        var uri = request.RequestUri ?? throw new RequestError("invalid_request", "Missing provider URI.");
        var source = provider.Value;
        var allowed = ProviderCatalog.All.FirstOrDefault(p => p.Id == source)?.Hosts ?? [];
        if (!allowed.Contains(uri.Host)) throw new RequestError("invalid_request", "Unexpected provider host.");
        if (uri.Scheme == "http") request.RequestUri = new UriBuilder(uri) { Scheme = "https", Port = 443 }.Uri;
        else if (uri.Scheme != "https") throw new RequestError("invalid_request", "HTTPS required.");
        if (nextRequest.TryGetValue(source!, out var next))
        {
            var wait = (next - Stopwatch.GetTimestamp()) * 1000d / Stopwatch.Frequency;
            if (wait > 1000) throw new RequestError("rate_limited", "Provider retry interval is active.");
            if (wait > 0) await Task.Delay(TimeSpan.FromMilliseconds(wait), linked.Token);
        }
        nextRequest[source!] = Stopwatch.GetTimestamp() + Stopwatch.Frequency;
        var response = await base.SendAsync(request, linked.Token);
        if (response.StatusCode == HttpStatusCode.TooManyRequests)
        {
            var retry = response.Headers.RetryAfter?.Delta ?? (response.Headers.RetryAfter?.Date - DateTimeOffset.UtcNow) ?? TimeSpan.FromSeconds(60);
            nextRequest[source!] = Stopwatch.GetTimestamp() + (long)(Math.Max(1, retry.TotalSeconds) * Stopwatch.Frequency);
            response.Dispose(); throw new RequestError("rate_limited", "Provider asked to retry later.");
        }
        try
        {
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > 1048576) throw new RequestError("document_too_large", "Provider response too large.");
            await response.Content.LoadIntoBufferAsync(1048576, linked.Token);
            return response;
        }
        catch { response.Dispose(); throw; }
    }
}
