using System.Security.Cryptography;
using System.Text.Json;
using LyricIsland.Backend.Playback;
using LyricIsland.Backend.Storage;

namespace LyricIsland.Backend.Lyrics;

public sealed record LyricDocument(string DocumentId, string LyricVersionId, LyricTrack Document, double OffsetMs = 0);
public sealed record SavedSelection(int SchemaVersion, string TrackKey, LyricDocument Selection);

public sealed class LyricDocuments(LocalStore store)
{
    public static bool IsContentError(string code) => code is "invalid_lyrics" or "no_lyrics" or "no_synced_lyrics" or "ambiguous_timestamps" or "document_too_large";

    static string Hash(string text) => Convert.ToHexStringLower(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text)));
    string SelectionPath(TrackInfo track) => Path.Combine(store.Data, "selections", Hash(track.TrackKey) + ".json");
    string OffsetPath(TrackInfo track, LyricDocument doc) => Path.Combine(store.Data, "offsets", Hash(track.TrackKey + "\n" + doc.LyricVersionId) + ".json");
    public LyricDocument WithSavedOffset(TrackInfo track, LyricDocument doc) => track.IdentityStrength == "strong"
        ? doc with { OffsetMs = store.Read<double?>(OffsetPath(track, doc)) ?? 0 } : doc;
    public LyricDocument? Find(TrackInfo track)
    {
        if (track.IdentityStrength != "strong") return null;
        var saved = store.Read<SavedSelection>(SelectionPath(track));
        if (saved is null) return null;
        if (saved.SchemaVersion != 1 || saved.TrackKey != track.TrackKey || saved.Selection is null
            || saved.Selection.Document is null || string.IsNullOrWhiteSpace(saved.Selection.DocumentId)
            || string.IsNullOrWhiteSpace(saved.Selection.LyricVersionId)
            || !double.IsFinite(saved.Selection.OffsetMs) || Math.Abs(saved.Selection.OffsetMs) > 30000)
            throw new RequestError("storage_error", "Invalid saved selection.");
        try { Validate(saved.Selection.Document); }
        catch (RequestError) { throw new RequestError("storage_error", "Invalid stored timeline; original preserved."); }
        return saved.Selection;
    }
    public void Save(TrackInfo track, LyricDocument document)
    {
        // Weak metadata identities may collide; never silently reuse them across sessions.
        if (track.IdentityStrength == "strong")
        {
            store.Write(OffsetPath(track, document), document.OffsetMs);
            store.Write(SelectionPath(track), new SavedSelection(1, track.TrackKey, document));
        }
    }
    public async Task<LyricDocument> ImportAsync(JsonElement args, TrackInfo track, CancellationToken cancellation)
    {
        if (args.TryGetProperty("path", out var filePath))
        {
            var path = filePath.GetString() ?? "";
            if (!Path.IsPathFullyQualified(path)) throw new RequestError("invalid_request", "Select a local file.");
            using var input = LocalFile.OpenRead(path);
            if (input.Length > 900000) throw new RequestError("document_too_large", "Import exceeds size limit.");
            var bytes = new byte[900001]; int count = 0, read;
            while (count < bytes.Length && (read = await input.ReadAsync(bytes.AsMemory(count), cancellation)) != 0) count += read;
            if (count > 900000) throw new RequestError("document_too_large", "Import exceeds size limit.");
            var text = new System.Text.UTF8Encoding(false, true).GetString(bytes, 0, count).TrimStart('\uFEFF');
            var format = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
            args = format == "json" ? JsonSerializer.SerializeToElement(new { document = JsonSerializer.Deserialize<JsonElement>(text) })
                : JsonSerializer.SerializeToElement(new { text, format });
        }
        LyricTrack document;
        cancellation.ThrowIfCancellationRequested();
        if (args.TryGetProperty("document", out var json))
            document = json.Deserialize<LyricTrack>(LocalStore.Json) ?? throw new RequestError("invalid_lyrics", "Missing document.");
        else
        {
            var text = args.GetProperty("text").GetString() ?? "";
            var format = args.TryGetProperty("format", out var fmt) ? fmt.GetString() ?? "lrc" : "lrc";
            document = HelperFormats.Parse(text, format, track, "local-" + format);
        }
        Validate(document);
        return WithSavedOffset(track, Create(document, "local"));
    }
    public static LyricDocument Create(LyricTrack document, string version)
    {
        Validate(document);
        var hash = Hash(JsonSerializer.Serialize(new { document.SyncLevel, document.Lines }, LocalStore.Json));
        return new(hash, version + ":" + hash, document);
    }
    public static void Validate(LyricTrack document)
    {
        static bool Time(double n) => double.IsFinite(n) && n >= 0 && n <= 86400000;
        if (document.SchemaVersion != 1 || !Time(document.DurationMs) || document.DurationMs == 0 || document.Lines is null || document.Lines.Length > 10000)
            throw new RequestError("invalid_lyrics", "Invalid timeline.");
        double end = 0;
        foreach (var line in document.Lines)
        {
            if (line is null || line.Text is null || line.Translation is null || line.Words is null || !Time(line.StartMs) || !Time(line.EndMs) || line.StartMs < end || line.EndMs <= line.StartMs || line.EndMs > document.DurationMs)
                throw new RequestError("invalid_lyrics", "Overlapping or invalid lyric lines.");
            double wordEnd = line.StartMs;
            foreach (var word in line.Words)
            {
                if (word is null || word.Text is null || !Time(word.StartMs) || !Time(word.EndMs) || word.StartMs < wordEnd || word.EndMs <= word.StartMs || word.EndMs > line.EndMs)
                    throw new RequestError("invalid_lyrics", "Invalid word timing.");
                wordEnd = word.EndMs;
            }
            if (line.Words.Length > 0 && string.Concat(line.Words.Select(w => w.Text)) != line.Text)
                throw new RequestError("invalid_lyrics", "Word text does not match line.");
            end = line.EndMs;
        }
        // Repeated LRC timestamps can expand small input into a large JSON document.
        // Count streamed output and stop before allocating the complete expansion.
        using var budget = new DocumentSizeStream();
        JsonSerializer.Serialize(budget, document, LocalStore.Json);
    }

    sealed class DocumentSizeStream : Stream
    {
        long written;
        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => written;
        public override long Position { get => written; set => throw new NotSupportedException(); }
        public override void Write(byte[] buffer, int offset, int count) => Write(buffer.AsSpan(offset, count));
        public override void Write(ReadOnlySpan<byte> buffer)
        {
            if (buffer.Length > 900000 - written)
                throw new RequestError("document_too_large", "Lyric document exceeds protocol limit.");
            written += buffer.Length;
        }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
    }
}
