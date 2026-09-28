# Privacy and local data

Playback discovery, song metadata, position and controls use the local session D-Bus through MPRIS. The plugin does not request Spotify credentials, browser cookies, OAuth authorization or a developer account. It has no relay service, telemetry or cloud history synchronization.

## Optional network access

- **Lyrics:** QQ Music and NetEase Music are independently off by default. Enabling one permits direct queries to that service using supported song metadata: title, artists, album and duration. Each search endpoint receives only the fields it supports. QQ uses `c.y.qq.com` / `u.y.qq.com`; NetEase uses `music.163.com` / `interface.music.163.com` / `interface3.music.163.com`, over HTTPS. The service also sees the request IP and headers. Region and service changes can affect availability.
- **Cover art:** independently off by default. When enabled, Qt downloads the HTTPS image URL supplied by the player. Otherwise only local artwork or a placeholder is used. This setting does not enable lyrics.
- **Backend download:** requires separate consent. The plugin manifest fixes the GitHub Release asset's HTTPS URL, size and SHA-256. Every redirect must also use HTTPS; a downgrade is rejected before contacting its target. GitHub's download service sees the request IP and headers. Installing a local backend archive does not download that archive remotely. Building from source can fetch development dependencies.

Disabling a lyric source cancels its in-flight resolution work and prevents new queries. Data already sent cannot be recalled. A selected or cached lyric document may continue to display after online access is disabled.

## Local data

The plugin uses an `omarchy-lyricify/` directory under each XDG root. Custom XDG environment variables override these defaults:

| Default location | Contents |
| --- | --- |
| `~/.config/omarchy-lyricify/` | Language, artwork and lyric-source permissions, display settings and player choice |
| `~/.local/state/omarchy-lyricify/` | Position, download consent and active runtime state |
| `~/.local/share/omarchy-lyricify/` | Imported/manual lyrics, track-specific timing corrections and installed runtimes |
| `~/.cache/omarchy-lyricify/` | Rebuildable lyric search and content cache |

Manual selections and cache entries contain the song information and lyric content needed to restore them. The plugin does not maintain a separate playback-history database or store Spotify passwords.

**Clear cache** keeps imports, manual selections and corrections. **Delete local data**, after confirmation, clears the four plugin-owned directories above, including downloaded runtimes. The plugin stays installed, but its backend must be prepared again. Ordinary Omarchy removal retains this external data. See the [uninstall instructions](../README.md#uninstall) for complete cleanup after removal.

The launcher entry is separate: `$XDG_DATA_HOME/applications/kuryrc.lyricify.desktop`, normally `~/.local/share/applications/kuryrc.lyricify.desktop`. It contains the local launch command and app metadata. Removal hides it through `TryExec`; you can delete the leftover desktop file without affecting lyric data.

## Diagnostics

The JSON exported from settings contains backend/protocol versions, player availability, whether position is known, lyric status/error codes and source settings. It excludes song titles, lyric text, accounts and playback history. Default stderr reports error codes without raw protocol messages or HTTP payloads.

For a bug report, attach diagnostics and reproduction steps. Private playlists and complete lyric files are unnecessary. Development previews and README images use original fixture lyrics and artwork.
