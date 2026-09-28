# Testing and acceptance

This guide defines regression scenarios, measurement methods and release criteria. Development dependencies and commands are in [CONTRIBUTING](../CONTRIBUTING.md); current product limitations are in the [README](../README.md#compatibility-and-known-limitations).

For each run, record the build version, environment, steps, raw evidence and pass/fail/untested results in local `artifacts/` or the corresponding PR/CI artifacts. Retain results tied to the source and archive for a release. Simulated results do not replace real-desktop acceptance.

## Automated test entry points

| Coverage | Location |
| --- | --- |
| Timeline, artwork and translated UI messages | `tests/*.test.cjs` |
| Backend models, matching and provider behavior | `backend/LyricIsland.Tests/` |
| Production v2 process and isolated MPRIS | `tests/integration_test.py`, `tests/lyrics_integration_test.py` |
| Actual QML client, clock and reconnect | `tests/quickshell/`, `tests/live_qml_test.py` |
| Mouse, controls, dragging and lifecycle | `tests/qml/` |
| Startup, preference persistence and launcher | `tests/startup_test.py`, `tests/preferences_test.py`, `tests/launcher_test.py` |
| Candidate package, rollback, purge and preparation | `tests/runtime_test.py`, `tests/runtime_lifecycle_test.py` |

## Environment and isolation

Automated playback tests run a fake MPRIS service on an isolated session D-Bus. Its independent monotonic clock generates controlled positions and injects delays, reordered events and missing capabilities. These tests must not operate the developer's real player. Protocol integration starts the production backend; UI tests use the actual message interface rather than changing internal state to obtain a result.

For real-desktop checks, record Omarchy, Hyprland, Quickshell, Qt and .NET build versions, the Spotify version and installation method, and display resolution, scale and refresh rate. Use an x86_64 Omarchy environment and a second real MPRIS player to check compatibility. Record results separately for the fake service, second player and Spotify.

## Playback and protocol

| ID | Scenario | Required evidence |
| --- | --- | --- |
| P01 | Handshake, capabilities and protocol version | Ready only after compatibility checks; explicit errors for an old backend or missing capabilities, without restart loops masking incompatibility |
| P02 | Invalid JSON, oversized messages and non-finite numbers | Bounded error recovery; later valid requests still work, with no unbounded allocation |
| P03 | Events from old processes, reordered events and different scopes | Current state is preserved; old requests become invalid after restart |
| P04 | Slow lyric work while controls arrive | Pause/seek do not wait for network requests; stdout messages are not interleaved or corrupted |
| P05 | EOF, shutdown and duplicate request IDs | Clean exit; no duplicate execution in one session or replay of non-idempotent commands across restarts |
| P06 | Multiple players, pause and explicit selection | Spotify is preferred by default; selection remains stable on pause; commands reach the displayed instance |
| P07 | Owner disappears, service name is reused or player reconnects | Old instance becomes invalid; reconnection has a new identity, with no duplicate subscriptions or leftover work |
| P08 | Missing duration, unknown position or limited capabilities | Correct derived controls; unknown duration is not zero; unsupported absolute seek is not sent |
| P09 | Metadata arrives in parts; same title, different recording | Old/new fields are not mixed; weak identity does not persist an incorrect match; track generation is correct |
| P10 | Seek, pause/resume and rate changes | Correct stopping, jumps and interpolation; snapshots confirm control results |
| P11 | System date changes, long stalls and stale samples | Monotonic progress is unaffected by wall-clock changes; stale samples cannot affect a new instance or track |
| P12 | Real Spotify playback, track changes, pause and seek | Reviewable operation records; an initial paused state alone does not establish completion |
| P13 | Real exit/reconnect, hide/show and sleep recovery | Recovery uses fresh samples without prolonged catch-up or flashes of old lyrics |
| P14 | Synchronization error and response time | Meet the measurement targets below; retain raw samples and uncertainty |
| P15 | Second player, Connect and non-song content | Second player passes the same contract; Connect does not imply a known output device; unavailable cross-device scenarios remain explicitly untested and outside expanded support claims |

## Lyrics

| ID | Scenario | Required evidence |
| --- | --- | --- |
| L01 | Ordinary LRC, real word timing, no translation and instrumental gaps | Correct fallback without invented word timestamps; preserve parser edge-case coverage |
| L02 | Track or document changes while the line index stays the same | Document identity changes refresh content, measurements and highlighting; old text does not remain |
| L03 | Invalid/oversized files, FIFO/special files and complex formats | Structured rejection or documented fallback; an existing usable document is preserved |
| L04 | Source permissions and first network access | No online lookup before opt-in; disabling a source cancels in-flight work and blocks new requests |
| L05 | Request A is slow, B completes first, then A completes | Only B is displayed, even if cancellation of A fails |
| L06 | Manual selection followed by completion of an earlier search for the same track | The manual choice survives the old resolution result |
| L07 | Timeout, HTTP 429, disconnection and parse failure | Distinct states; honor Retry-After; playback controls remain responsive |
| L08 | Live/remastered/instrumental/edited recordings and insufficient metadata | Uncertain matches show song information; grades are not probabilities; candidates are explainable |
| L08a | Multiple candidates, duplicates across providers, compilations and missing albums | Select a reliable candidate automatically with stable ordering; fetch one document; explicit recording conflicts still require selection |
| L08b | First candidate has unusable word timing, missing lyrics or a network failure | Fall back to real line timing from the same candidate; content failures try at most 3 eligible candidates; network failure/cancellation stops the attempt without caching a false no-lyrics result |
| L08c | Incomplete collaborators, shared guest artists and conflicting credits | Helper grades handle collaboration credits and punctuation; complete credits rank first within a grade; guest-only overlap, empty artists and clear recording/duration conflicts are rejected |
| L08d | International/local artist names, simplified/traditional Chinese, case and collaborations | Reuse Helper's alias table with identical normalization for search and matching; support English names on either side; unrelated artists and different recordings remain ineligible for automatic selection |
| L09 | Manual selection, valid cache and online results coexist | Correct precedence; a selected document is not automatically replaced by a later higher-quality candidate |
| L10 | Saved offsets, stale requests for identical content from another lyric version, and different apps | Apply only to the matching track and lyric version; positive means earlier; player position does not change |
| L11 | Positive/negative cache, corruption, eviction and offline use | Distinguish no-lyrics results from network errors; clearing cache preserves imports and manual corrections |
| L12 | Restart, storage permissions/invalid structures, migration and atomic-write failures | Recover previous settings, report storage errors while preserving playback, and retain previously valid records |

## UI and performance

| ID | Scenario | Required evidence |
| --- | --- | --- |
| U01 | Bilingual lines, expansion, long lines, word timing and paused seeking | Original fixtures and real documents render correctly; existing UI regressions pass |
| U02 | Drag/snap/restore, buttons, seek bar and click-through | Position changes and controls remain separate; ordinary island display does not take keyboard focus |
| U03 | Real fullscreen, workspace changes, output changes and scaling | Hide only according to the island's display/workspace; distinguish controlled Wayland outputs from physical-display evidence |
| U04 | Visible playback, pause, hidden state and continuous 10-minute playback | Follow the timing/resource rules below; no runaway backend or continuous unnecessary frame loop |
| U05 | English/Simplified Chinese, first source selection and settings restart | Language and preferences take effect; user settings do not expose internal debug structures |
| U06 | Missing backend, crashes, repeated failures and incompatible versions | Preserve recent information and a clear status; disable controls correctly; bounded retries allow manual recovery |
| U07 | Explicit diagnostic export and default logs | Versions/errors are diagnosable; no song history, full lyrics or account credentials by default |

### Synchronization measurement

First validate the algorithm against independent ground truth from the fake MPRIS service. Then compare Spotify with actual Position reads. Record query send/response times, sample age, UI observation time and track generation. Project both positions to the same observation time and include the uncertainty interval from round-trip latency. Comparing an estimate to the same anchor just assigned does not establish zero error.

Targets for valid samples during normal visible playback: absolute error p95 ≤ 100ms; after a track change or seek, recover the correct position within 500ms when the player responds promptly. Record user action to player response separately from response to UI update. Lyric download time is not playback-clock calibration time. List advertisements, unknown positions, stale samples and track-transition samples separately, with reasons and counts; do not silently discard failed samples.

Player position, lyric timestamps and actual audio output are separate error sources. For audible synchronization checks, record the output path and manual correction. MPRIS agreement alone does not establish acoustic alignment with Bluetooth or speakers.

### Animation and resource measurement

Disable the installed native plugin, start `make demo`, then run:

```sh
python3 scripts/measure-preview.py --seconds 600
```

The script reads the running standalone preview and writes Qt callbacks, visibility, display state and process resources to `artifacts/preview-metrics.json`. Keep playback visible and running throughout the measurement. Avoid expansion, dragging, source reloads or `make smoke` during sampling. Afterward, use `make stop` to exit the preview and restore the native plugin. Actual presentation and audio synchronization require separate checks.

In the specified 60Hz environment, measure at least 10 minutes of continuous visible playback. Qt animation callback targets are p95 ≤ 18ms and p99 ≤ 20ms. Also report the maximum, count of intervals over 25ms and sustained stalls, and inspect the presented image. Label callback statistics separately from compositor presentation evidence; state explicitly when presentation timing was not measured.

Record wall-clock sampling duration, accumulated callback time, visible/paused/fullscreen/DPMS states and coverage. Reloads, interactions that change the scenario or missing time invalidate a claim of continuous playback. Only a declared startup warm-up may be excluded; retain slow frames during the run. Measure hidden and paused states separately rather than using them to lower average CPU usage.

Record QML and C# CPU/RSS separately, along with backend restart counts and message rates. For the native plugin, report the host's incremental usage and the backend's usage. For a standalone preview, report its process. Do not attribute the whole Omarchy shell's usage to the plugin. Short development samples do not establish full release acceptance.

## Installation and release

| ID | Scenario | Required evidence |
| --- | --- | --- |
| R01 | Clean x86_64 machine without the .NET SDK | Native plugin add and first-run preparation complete; native-library and minimum runtime requirements are clear |
| R02 | Download cancellation, disconnection and leftover temporary files | Retry works; the old version remains complete; partial downloads are never started |
| R03 | Wrong architecture, incorrect hash and unsafe archive paths | Activation is rejected; writes remain within plugin-owned directories |
| R04 | Incompatible UI/backend and old processes retained after reload | Runtime handshake detects incompatibility; new files on disk are not mistaken for the running version |
| R05 | Compatible previous backend, or incompatible backend while offline | Controlled compatible fallback; otherwise explicit preparation state, without upgrade/restart loops |
| R06 | Broken update, configuration migration and rollback | Preserve a working binary and recoverable data; UI/backend versions remain compatible |
| R07 | Repeated enable, disable, reload and removal | No duplicate backend for one instance or leftover process after disable; other plugins and the bar remain unchanged |
| R08 | Normal removal, reinstall and complete purge | Normal removal retains display preferences, selections and offsets; purge covers the documented directories without deleting unrelated data; re-preparation requires no UI restart |
| R09 | Release assets and marketplace submission material | Traceable source/assets, complete licenses, reproducible README instructions and matching manifest/archive hashes |

## Release acceptance

A public beta requires every applicable mandatory case above to pass. Explain the conditions and support scope for cases that do not apply; skipping a case cannot replace validation of a supported feature. Qt controls, protocol behavior, real-desktop behavior, lyric providers and the complete installation path need separate evidence. A stable release also requires resolution of outstanding public-beta feedback and a renewed compatibility review. Marketplace approval is recorded separately; follow the [release guide](release.md).
