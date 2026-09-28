using System.Text;
using Lyricify.Lyrics.Helpers.General;

namespace LyricIsland.Backend.Lyrics.UpstreamMatching;

internal static class PortableText
{
    // Use Helper's own managed character table, without its optional external
    // ChineseConverter assembly. This is not full phrase-level conversion.
    public static string ToPortableSimplified(this string value) =>
        ChineseConverter.ConvertToSimplifiedChinese(value.Normalize(NormalizationForm.FormKC))
            .Replace("藉", "借").Replace("咀", "嘴").Replace("昇", "升").Replace("髒", "脏");
}
