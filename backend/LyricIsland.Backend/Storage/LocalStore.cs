using System.Text.Json;

namespace LyricIsland.Backend.Storage;

public sealed record Settings(int SchemaVersion = 1, string PreferredPlayer = "spotify",
    Dictionary<string, bool>? Sources = null, int CacheLimitMb = 64)
{
    public bool IsEnabled(string id) => Sources?.GetValueOrDefault(id) == true;
    public Settings WithSource(string id, bool enabled) => this with { Sources = new(Sources ?? []) { [id] = enabled } };
}

public sealed class LocalStore
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public string Data { get; } = DirectoryFor("XDG_DATA_HOME", ".local/share");
    public string Cache { get; } = DirectoryFor("XDG_CACHE_HOME", ".cache");
    public string Config { get; } = DirectoryFor("XDG_CONFIG_HOME", ".config");
    static string DirectoryFor(string variable, string fallback) => Path.Combine(
        Environment.GetEnvironmentVariable(variable) is { Length: > 0 } path && Path.IsPathRooted(path)
            ? path : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), fallback), "omarchy-lyricify");
    public T? Read<T>(string path)
    {
        if (!File.Exists(path)) return default;
        try
        {
            using var input = LocalFile.OpenRead(path);
            if (input.Length > 1048576) throw new RequestError("storage_error", "Stored document exceeds limit.");
            var bytes = new byte[1048577];
            var count = input.ReadAtLeast(bytes, bytes.Length, throwOnEndOfStream: false);
            if (count > 1048576) throw new RequestError("storage_error", "Stored document exceeds limit.");
            var value = JsonSerializer.Deserialize<T>(bytes.AsSpan(0, count), Json);
            return value is null ? throw new RequestError("storage_error", "Stored document is null.") : value;
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException or RequestError)
        { throw new RequestError("storage_error", "Stored document is unreadable or invalid; original preserved."); }
    }
    public void Write<T>(string path, T value)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value, Json);
        if (bytes.Length > 1000000) throw new RequestError("document_too_large", "Stored document exceeds limit.");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { file.Write(bytes); file.Flush(true); }
            File.Move(temp, path, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public Settings LoadSettings()
    {
        var saved = Read<JsonElement?>(Path.Combine(Config, "settings.json"));
        var settings = saved?.Deserialize<Settings>(Json) ?? new();
        if (settings.SchemaVersion != 1) throw new RequestError("storage_error", "Unsupported settings schema.");
        // Legacy flags are read at the storage boundary only. New sources use the
        // extensible map; a missing entry never opts a user into network access.
        if (saved is JsonElement json && settings.Sources is null)
        {
            foreach (var source in Lyrics.ProviderCatalog.All)
                if (json.TryGetProperty(source.LegacySetting, out var flag)) settings = settings.WithSource(source.Id, flag.GetBoolean());
        }
        return settings;
    }
    public void SaveSettings(Settings settings) => Write(Path.Combine(Config, "settings.json"), settings);
    public void ClearCache()
    {
        if (!Directory.Exists(Cache)) return;
        foreach (var file in Directory.EnumerateFiles(Cache, "*.json", SearchOption.TopDirectoryOnly)) File.Delete(file);
    }
}
