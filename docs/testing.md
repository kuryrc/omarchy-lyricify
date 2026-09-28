# Testing

See [CONTRIBUTING](../CONTRIBUTING.md#build-and-verify) for dependencies and build commands. Test cases live with the code; this page covers how to run them and what needs a real desktop.

## Automated checks

```sh
make check                                      # Full local checks
python3 tests/quickshell_test.py --resync         # Clock recovery cases only
```

Use focused tests while developing. The resync tests cover queue saturation, timeout/error responses and a seek overtaking a resync response; they also run in the full suite.

| Area | Tests |
| --- | --- |
| Timeline, artwork and translations | JavaScript tests in [tests/](../tests/) |
| Lyric parsing, matching, providers and storage | [Backend tests](../backend/LyricIsland.Tests/) |
| Player/protocol integration and lyric races | [integration_test.py](../tests/integration_test.py), [lyrics_integration_test.py](../tests/lyrics_integration_test.py) |
| QML messages, clock and recovery | [quickshell_test.py](../tests/quickshell_test.py), [live_qml_test.py](../tests/live_qml_test.py) |
| Controls and layout | [Qt interaction tests](../tests/qml/) |
| Startup, preferences and launcher | [startup_test.py](../tests/startup_test.py), [preferences_test.py](../tests/preferences_test.py), [launcher_test.py](../tests/launcher_test.py) |
| Download, activation, rollback and cleanup | [runtime_test.py](../tests/runtime_test.py), [runtime_lifecycle_test.py](../tests/runtime_lifecycle_test.py) |

Player integration uses production code with a fake MPRIS service on an isolated D-Bus and temporary data directories. Keep these tests off the user's player bus. Exercise regressions through the affected interface, including delayed or reordered responses. The expected contracts are in [protocol](protocol.md) and [architecture](architecture.md); matching rules are in [UpstreamMatching](../backend/LyricIsland.Backend/Lyrics/UpstreamMatching/README.md).

## Desktop acceptance

Check the installed plugin on x86_64 Omarchy. Use Spotify and a second real MPRIS player for playback compatibility, and record their results separately.

| Area | Check |
| --- | --- |
| Playback and recovery | Play/pause, change tracks, seek from both the island and player, restart the player/backend, hide/show, and suspend/resume the machine. Controls must recover and lyrics must follow fresh position samples without showing the previous track. Check missing capabilities and non-song content. |
| Lyrics and settings | Enable each provider separately, check automatic matching, choose/import another lyric version and adjust its offset. Verify persistence after restart, cache clearing and source disable. Provider failures must leave playback usable; requests require opt-in. |
| Display | Check drag/center snap, expansion, long/bilingual lyrics, pause behavior, fullscreen/workspace changes, output disconnects and scaling. Settings and the launcher must remain usable without a player. |
| Installation | Follow the README on a clean machine without the .NET SDK. Check consent, download, launcher, quit/reopen, update, disable/remove, reinstall and purge. Confirm the running version and a single owned backend; removal retains user data, while purge removes only documented plugin data. Preparation failures must remain retryable from settings. |
| Errors and diagnostics | Verify useful error messages and exported diagnostics. Exclude credentials, song history and full lyrics as described in [privacy](privacy.md#diagnostics). |

Use valid outputs for display checks: nonzero dimensions and successful buffer allocation. QML loading or IPC responding does not prove that frames were displayed. Package-only installation checks also do not establish clean-machine compatibility; follow the [release installation checks](release.md#validate-installation).

## Synchronization measurement

Compare against the fake player's independent monotonic clock, then actual Spotify Position reads. Record sample age, track identity, query round trips and UI observation times; compare positions at the same observation time. Do not compare an estimate against its own anchor.

- Normal visible playback: absolute error **p95 ≤ 100 ms**.
- After a track change or seek: correct position within **500 ms**, when the player responds promptly. Include players that briefly report Playing while their position is stationary after seeking.
- Report control response time separately from UI update time. List advertisements, unknown/stale positions and transition samples separately with counts and reasons; do not silently drop failures.

Player position, lyric timestamps and audible output are separate measurements. Audio alignment needs a separate check that records speakers/Bluetooth and any manual offset.

## Animation and resource measurement

Disable the installed plugin before starting a standalone preview:

```sh
make demo
python3 scripts/measure-preview.py --seconds 600
make stop
```

Re-enable the installed plugin afterward. Keep compact playback visible and running for the full **10 minutes** at **60 Hz**. Pausing, expansion, dragging, reloads, fullscreen hiding, screen lock or DPMS interrupt the run; restart the interval. The script exits nonzero when it detects an interruption. Do not combine partial runs or exclude slow frames.

Qt callback targets are **p95 ≤ 18 ms** and **p99 ≤ 20 ms**. Retain the maximum, intervals over 25 ms, wall duration, callback coverage and visibility/display state from `artifacts/preview-metrics.json`. Inspect the presented image separately: callback timing is not compositor presentation timing. Measure hidden and paused states separately.

Report backend CPU/RSS, restart count and message rate separately from UI usage. For the native plugin, measure incremental shell usage; do not attribute the entire shell to the plugin. For the preview, measure its process.

## Recording results

Keep the tested commit/archive identity, desktop/player versions, display resolution/scale/refresh rate, commands and pass/fail/untested results in ignored `artifacts/` or PR/CI artifacts. Distinguish fake-player, offscreen, real-desktop and audio evidence. Current limitations belong in the [README](../README.md#compatibility-and-known-limitations), and promotion criteria in the [release guide](release.md#publish-and-submit).
