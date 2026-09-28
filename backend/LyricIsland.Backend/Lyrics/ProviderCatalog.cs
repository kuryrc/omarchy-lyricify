using System.Text.Json;
using LyricIsland.Backend.Storage;

namespace LyricIsland.Backend.Lyrics;

public sealed record ProviderRegistration(string Id, string Name, string ChineseName, string LegacySetting,
    string[] Hosts, Func<ILyricProvider> Create);

// One registration point for source identity, consent, UI labels and transport scope.
public static class ProviderCatalog
{
    public static readonly ProviderRegistration[] All = [
        new("qq", "QQ Music", "QQ 音乐", "qqEnabled", ["c.y.qq.com", "u.y.qq.com"], () => new QqProvider()),
        new("netease", "NetEase Music", "网易云音乐", "neteaseEnabled",
            ["music.163.com", "interface.music.163.com", "interface3.music.163.com"], () => new NeteaseProvider())
    ];

    public static object SettingsView(Settings settings) => new {
        settings.SchemaVersion, settings.PreferredPlayer, settings.CacheLimitMb,
        sources = All.Select(p => new { p.Id, p.Name, p.ChineseName, enabled = settings.IsEnabled(p.Id) }).ToArray()
    };

    public static Settings Update(Settings settings, JsonElement args)
    {
        var updated = settings;
        foreach (var field in args.EnumerateObject())
        {
            if (field.Name == "cacheLimitMb") updated = updated with { CacheLimitMb = field.Value.GetInt32() };
            else if (field.Name == "sources")
            {
                foreach (var source in field.Value.EnumerateObject())
                {
                    if (!All.Any(p => p.Id == source.Name)) throw new RequestError("invalid_request", "Unknown lyric source.");
                    updated = updated.WithSource(source.Name, source.Value.GetBoolean());
                }
            }
            else if (All.FirstOrDefault(p => p.LegacySetting == field.Name) is { } legacy)
                updated = updated.WithSource(legacy.Id, field.Value.GetBoolean());
            else throw new RequestError("invalid_request", "Unknown setting.");
        }
        if (updated.CacheLimitMb is < 1 or > 512) throw new RequestError("invalid_request", "Cache size must be 1–512 MiB.");
        return updated;
    }
}
