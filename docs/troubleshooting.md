# Troubleshooting

Start with the message shown in the island or settings. Player connection, lyric retrieval and lyric timing are separate: a connected player can still have no matching lyrics.

## The island is missing

Open **Lyric Island** from the application launcher. Settings can open even when no player is running. If the launcher entry is missing, enable the installed plugin once:

```sh
omarchy plugin enable kuryrc.lyricify
```

Start the Spotify desktop app and select a song. Check **Music player** in settings if more than one player is running. By default, the island hides in fullscreen and becomes a small capsule after pausing. **Island display** lets you change these settings, select a monitor or restore the default position.

If two islands appear during development, run `make stop` from the checkout that started the preview, then enable the installed plugin. Keep a standalone preview and the native plugin mutually exclusive.

## Lyrics do not appear

| Message or symptom | Meaning and next step |
| --- | --- |
| **Enable lyrics in settings**; older builds: **Online lyrics are off** | Online sources are disabled. Enable QQ Music or NetEase Music under **Lyric sources**, or import a local file. A separate Spotify login inside the plugin is not required. |
| **Finding lyrics…** | A lookup is running. If it ends with an error, follow that message. |
| **Choose lyrics in settings** | Candidates were found, but none met the automatic matching rules. Choose the correct recording in **Lyric matches**. Having multiple candidates alone does not require manual selection. |
| **No lyrics found** / **No timed lyrics available** | The enabled source did not provide usable timed lyrics. Try the other source or import a matching local file. |
| **Lyric request timed out** / **Lyric source is unavailable** | Check your connection, then use **Search again** or try another source. Service and regional availability can change. |
| **Lyric source is rate-limiting** | Wait before using **Search again**; avoid repeated retries. |
| **This lyric version could not be parsed** / **has overlapping timing** | Choose another lyric version or import a valid timed file. |
| **Saved lyrics could not be read** | A saved file is unreadable or invalid. Check access to the plugin's [data directories](privacy.md#local-data) and export diagnostics. Back up imports and corrections before changing those files. |
| **Lyrics temporarily unavailable** | Open settings for the specific error. Export diagnostics if it remains unexplained. |
| **Automatic lyrics unavailable for this content** | The player reported unsupported content or insufficient song metadata. Automatic lookup is skipped; local import is available where a usable track is present. |

Choose candidates for the same artist and recording. Live, remix and studio versions can have different timing even when their titles match. Manual choices and timing corrections are saved for an identifiable track; they are not shared automatically between music apps.

Disabling a source stops new requests to it. Previously selected or cached lyrics can still appear. **Clear cache** removes rebuildable results while keeping imports and manual corrections; it does not reset a saved manual choice.

## Highlighting or translation is missing

Word highlighting requires real word timestamps from the source. An ordinary LRC file advances by line. The plugin does not invent word timing or translate lyrics; a second language appears only when the lyric source supplies it.

During a long intro, instrumental gap or outro, song information replaces the lyric line. This is expected when no lyric is active.

## Lyrics are early or late

First check that the selected lyrics belong to the same recording. For a constant offset, adjust the lyric timing in settings: **positive means earlier**, negative means later. The correction is tied to that track and lyric version, and does not seek the player.

A changing delay after seeking or resuming is different from a fixed lyric offset. Playback synchronization and sleep recovery have [known limitations](../README.md#compatibility-and-known-limitations). Report how the delay starts and whether it settles. Include the audio output path, such as speakers or Bluetooth; a match to the player's reported position does not establish audible alignment.

## The playback component cannot start

| Message | Next step |
| --- | --- |
| **This build has no downloadable playback component** | The checkout has no download entry in `runtime-manifest.json`. Use a published candidate or the [source installation](../README.md#install-from-source); enabling online lyric sources will not install the component. |
| **Download verification failed** / **The download is incomplete** | Retry preparation from settings. Keep the published checksum unchanged. |
| **Update required** / **The playback component version is incompatible** | Install the matching plugin and backend version together, then reload the plugin. |
| **This build supports Linux x86_64 only** | No compatible backend is supplied for the current architecture. |
| **The playback component could not start** | Export diagnostics and include your system and desktop versions when reporting the problem. |

Backend preparation, online lyrics and online cover art have separate consent settings. **Delete local data** also removes the installed backend, so it must be prepared again afterward.

## Reloading an updated plugin

Disable the installed plugin before copying a new source build. After installation, rescan and enable it as shown in the [installation steps](../README.md#install-from-source).

Omarchy may retain already-loaded QML after a rescan. Check the running version with `omarchy-shell lyricIsland state`. If the old version remains, restart the shared shell while the desktop is unlocked:

```sh
omarchy restart shell
```

This briefly reloads the bar and other shell plugins. It is not necessary for ordinary lyric-source or display-setting changes.

## Reporting a problem

Use **Export diagnostics** in settings. Include the plugin version, Omarchy/Quickshell versions, music player, steps to reproduce, expected result and actual result. For display issues, include resolution, scale, monitor arrangement and fullscreen state. For timing issues, include the output device and whether the problem follows a seek, pause or resume.

Diagnostics omit song titles, lyric text and account details. Do not include Spotify credentials, cookies, private playlists or complete lyric files. Crop screenshots to the plugin. [Privacy and local data](privacy.md) describes what is stored and sent.
