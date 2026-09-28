using Lyricify.Lyrics.Searchers;
using LyricIsland.Backend.Playback;

namespace LyricIsland.Backend.Lyrics;

public sealed record LyricCandidate(string CandidateId, string Provider, string ProviderId, string Title,
    string[] Artists, string Album, double? DurationMs, int Score = 0, bool Automatic = false, string[]? Reasons = null);
public interface ILyricProvider
{
    string Id { get; }
    Task<LyricCandidate[]> SearchAsync(TrackInfo track, CancellationToken token);
    Task<LyricTrack> FetchAsync(LyricCandidate candidate, TrackInfo track, CancellationToken token);
}
public sealed class QqProvider : ILyricProvider
{
    public string Id => "qq";
    readonly Lyricify.Lyrics.Providers.Web.QQMusic.Api api = new();
    public Task<LyricCandidate[]> SearchAsync(TrackInfo track, CancellationToken token) => ProviderTransport.RunAsync(Id, async () =>
    {
        var result = await api.Search(track.Title + " " + string.Join(" ", track.Artists.Select(ArtistNames.Normalize)), Lyricify.Lyrics.Providers.Web.QQMusic.Api.SearchTypeEnum.SONG_ID);
        var songs = result?.Req_1?.Data?.Body?.Song?.List;
        if (songs is null) throw new RequestError("provider_error", "Provider search response unavailable.");
        return songs.Take(20).Select(song => { var s = new QQMusicSearchResult(song); return new LyricCandidate("qq:" + s.Id, Id, s.Id, s.Title, s.Artists, s.Album, s.DurationMs); }).ToArray();
    }, token);
    public Task<LyricTrack> FetchAsync(LyricCandidate candidate, TrackInfo track, CancellationToken token) => ProviderTransport.RunAsync(Id, async () =>
    {
        var result = await api.GetLyricsAsync(candidate.ProviderId);
        if (string.IsNullOrWhiteSpace(result?.Lyrics)) throw new RequestError("no_lyrics", "No lyrics available.");
        // Helper 0.2.0's type detector is a stub. Recognize the QRC line header explicitly.
        var format = System.Text.RegularExpressions.Regex.IsMatch(result.Lyrics, @"(?m)^\[\d+,\d+\]") ? "qrc" : "lrc";
        return HelperFormats.Parse(result.Lyrics, format, track, Id, result.Trans ?? "");
    }, token);
}
public sealed class NeteaseProvider : ILyricProvider
{
    public string Id => "netease";
    readonly Lyricify.Lyrics.Providers.Web.Netease.Api api = new();
    public Task<LyricCandidate[]> SearchAsync(TrackInfo track, CancellationToken token) => ProviderTransport.RunAsync(Id, async () =>
    {
        var result = await api.SearchNew(track.Title + " " + string.Join(" ", track.Artists.Select(ArtistNames.Normalize)));
        if (result?.Code != 200) throw new RequestError("provider_error", "Provider search response unavailable.");
        return (result.Result?.Songs ?? []).Take(20).Select(song => { var s = new NeteaseSearchResult(song); return new LyricCandidate("netease:" + s.Id, Id, s.Id, s.Title, s.Artists, s.Album, s.DurationMs); }).ToArray();
    }, token);
    public Task<LyricTrack> FetchAsync(LyricCandidate candidate, TrackInfo track, CancellationToken token) => ProviderTransport.RunAsync(Id, async () =>
    {
        var result = await api.GetLyricNew(candidate.ProviderId);
        if (result?.Code != 200) throw new RequestError("provider_error", "Provider lyric response unavailable.");
        return HelperFormats.ParseWithLineFallback(result.Yrc?.Lyric ?? "", "yrc", result.Lrc?.Lyric ?? "", track, Id,
            result.Ytlrc?.Lyric ?? "", result.Tlyric?.Lyric ?? "");
    }, token);
}
