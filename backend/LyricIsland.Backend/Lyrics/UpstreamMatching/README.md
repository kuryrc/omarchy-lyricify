# Lyricify matching compatibility subset

Source: [Lyricify Lyrics Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper/tree/a139e385b032b9abfca4c060627776cf9c3147ad/Lyricify.Lyrics.Helper/Searchers/Helpers), NuGet 0.2.0, commit `a139e385b032b9abfca4c060627776cf9c3147ad`.
Copyright WXRIW / Lyricify contributors. Apache-2.0; full license is at `licenses/Lyricify.Lyrics.Helper.txt` in the repository and packaged runtime.

The four comparison files preserve upstream name/artist/duration scores and aggregate match grades. They are source imports, not a second independently tuned scoring system. Network access and parsing still use the pinned NuGet assembly.

Changes from the pinned files:

- Local namespace avoids collisions with the NuGet types. Aggregate comparison accepts upstream `TrackMultiArtistMetadata` on both sides, so it does not depend on a searcher's network interface.
- Replace `ToSC(true)` with Helper's managed `ChineseConverter.ConvertToSimplifiedChinese` table, Unicode FormKC and the same four character corrections. The optional external ChineseConverter assembly is excluded from distribution; direct upstream name/artist comparisons otherwise throw `FileNotFoundException`. Phrase-level conversions can differ.
- Use invariant case folding, reject empty artist lists as unknown, and fix the lowercase `Various` comparison.
- Correct the symmetric bracket comparison's repeated variable and the non-nullable score overloads' self-recursion.
- No changes to aggregate weights, thresholds or similarity algorithm. String similarity and string helpers are called from the original NuGet DLL.

`LyricMatchPolicy` is the sole application adapter: it bounds metadata, checks explicit recording-version conflicts, chooses an automatic acceptance floor, and supplies human-readable evidence. Scores are grades, not probabilities. Update this subset deliberately with regression checks when changing the pinned library version.

Before comparison and provider search, `ArtistNames` reuses `ArtistHelper.ArtistNamePairs` directly from the pinned NuGet assembly. Known international/local artist names are normalized on both sides; the table is not copied or maintained independently. Unlisted or conflicting aliases are not inferred from matching song titles.
