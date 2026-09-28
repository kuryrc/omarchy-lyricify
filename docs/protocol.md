# Local process protocol v2 and state model

The backend enables protocol v2 with `--stdio`. The protocol version and lyric document `schemaVersion: 1` are maintained separately; the product version is defined in [VERSION](../VERSION).

## Transport and handshake

QML starts and owns the backend child process. They exchange UTF-8 JSON Lines over stdin/stdout: stdin accepts requests, stdout carries only responses and events, and stderr carries redacted diagnostics. There is no local HTTP port or project-operated cloud relay. EOF on the parent channel ends the backend session and cleans up subscriptions and asynchronous work.

Each message line is limited to 1 MiB of UTF-8 data. Input, output and internal queues are bounded. Oversized documents return `document_too_large` rather than a partial document. Numeric values must be finite and within their field limits; counters used by JavaScript must remain within its safe integer range. Lyric text is rendered as plain text.

The client sends `hello` at startup. It enters ready state only after validating the protocol version, backend version and required capabilities. Unknown optional fields may be ignored. Unknown client message types or operations return structured errors; missing required fields must not be treated as valid state. Compatibility follows the release manifest, not assumptions based on version ordering.

```json
{"version":2,"type":"request","id":"r1","op":"hello","params":{"clientVersion":"0.2.0-rc.1","supportedProtocols":[2],"clientInstanceId":"ui-demo-1"}}
```

```json
{"version":2,"type":"response","id":"r1","op":"hello","ok":true,"backendSessionId":"b-demo-1","result":{"backendVersion":"0.2.0-rc.1","protocol":2,"capabilities":["playback","lyrics-import"]}}
```

The versions and capabilities above illustrate the format; they do not identify a published release. The backend reports its compiled capabilities. Disabling a lyric source must not change the capability list to imply a missing dependency.

## Message identity and scope

| Field | Lifetime and purpose |
| --- | --- |
| `id` | Unique request identifier within a channel; echoed in the response for correlation |
| `backendSessionId` | New identity on every backend start; rejects messages and pending commands from old processes |
| `seq` | Strictly increasing event sequence within the backend session, assigned in actual write order |
| `playerInstanceId` | The connected player instance; changes with the unique D-Bus owner, not just the app name |
| `trackGeneration` | Increments when the player changes, track identity changes or the track becomes invalid; not persisted across restarts |
| `trackKey` | App namespace and track identity for storage, with an identity-strength grade; a line index or temporary owner cannot substitute for it |
| `discontinuityId` | Identifies position jumps; seeking, resynchronization and recovery cause the UI to replace its anchor |
| `resolutionId` | The current lookup/candidate work for a track generation; a new search or manual selection can invalidate earlier work for the same track |
| `documentId` | Identity of normalized lyric content, independent of the current line index |
| `lyricVersionId` | Source identity combined with a source version/content hash; binds manual selections and timing offsets |

A playback snapshot must be a consistent view of one track generation. Do not combine a new title with the previous track's duration or Position. When metadata arrives in parts, enter a waiting-for-calibration or missing-information state before reading a consistent snapshot. Replaying a track with unchanged identity may retain its generation, but a return to the start is still a discontinuity.

## State snapshots

Events carry complete state rather than field deltas. Position updates do not include the whole lyric document; documents are sent only when loading, manual selection or import changes them. The client rejects events from another `backendSessionId` or with a stale `seq`, and clears the old document immediately on a track change.

```json
{
  "version": 2,
  "type": "event",
  "event": "session.state",
  "backendSessionId": "b-demo-1",
  "seq": 7,
  "scope": {"playerInstanceId":"p-demo-1","trackGeneration":4},
  "payload": {
    "player": {"applicationId":"example-player","displayName":"Example Player"},
    "track": {"trackKey":"example-player:evening","identityStrength":"strong","title":"Evening Signals","artists":["Demo Artist"],"album":"Demo","durationMs":34000,"contentKind":"song"},
    "playback": {"status":"Playing","rate":1,"canPlay":true,"canPause":true,"canNext":true,"canPrevious":true,"canSeekAbsolute":true},
    "position": {"known":true,"positionMsAtSend":18000,"sourceAgeMs":8,"samplingRoundTripMs":2,"discontinuityId":2,"reason":"sample"},
    "lyrics": {"status":"loading","resolutionId":"l4","documentId":null,"lyricVersionId":null,"offsetMs":0}
  }
}
```

`track`, `player` and position may be explicitly unavailable. An unknown duration is null; missing values must not become zero. `contentKind` is `song/podcast/advertisement/unknown`; unknown means the type cannot be determined reliably. Insufficient identity prevents automatic lookup. Do not guess the content type from the title alone.

Backend availability, player presence, track validity and lyric readiness are four independent states. During backend recovery, retain the last display state but mark controls unavailable. That retained state is not a fresh position sample.

## Timing semantics

1. On receiving MPRIS Position/Seeked data, the backend records a monotonic observation time and D-Bus round-trip duration, bound to the player instance and track generation. Sampling requests recheck their scope on completion.
2. `positionMsAtSend` is the backend's estimated playback position at send time, with the effective playback rate already applied. `sourceAgeMs` is the age of the original sample at send time; the client must not add it again as position compensation.
3. QML records `receivedAt` with its own ElapsedTimer. While playing, the displayed position is `positionMsAtSend + rate × localElapsedSinceReceive`, clamped to a known duration. Paused positions stay fixed. The lyric display adds the user's lyric offset separately.
4. Interprocess transport time remains an error term. Report latency using correlated `session.resync` round trips and local observations. Do not subtract raw Stopwatch/ElapsedTimer readings from different processes or assume RTT/2 gives exact compensation.
5. `reason=seek/track-change/resume/reconnect` or a changed `discontinuityId` replaces the anchor immediately. Only small corrections from ordinary samples may be smoothed. Test the implementation parameters so an incorrect anchor cannot cause prolonged catch-up.
6. Hiding stops frame-by-frame rendering while backend subscriptions remain active. Showing the island again, resuming from sleep or detecting stale state first requests resynchronization. If the backend cannot obtain a fresh position, it reports `known=false` or explicit stale state, and the UI stops advancing word highlights.
7. After a blocked client resumes, buffered events may describe old send times despite a small `sourceAgeMs`. A stall longer than 500 ms invalidates the render anchor. Only the response to the new correlated `session.resync` request restores it; its scope must still match the displayed session. Logind sleep events independently invalidate the backend sample and trigger fresh sampling on wake.
8. A full request queue, timeout or failed resync leaves the anchor invalid. While connected, the client retries after 250 ms when no current resync is pending. A response with a discontinuity older than the latest state is discarded and retried; it must not undo a seek. A further UI stall invalidates any resync already in flight.

Calibration must read the player or use a valid Seeked event. Reading an existing estimate again is not a new sample. Wall-clock time is used only for logs/cache dates, never to advance playback. Targets and sample validity are defined in [testing](testing.md).

## Operations and responses

| Operation | Request scope | Response semantics |
| --- | --- | --- |
| `hello` | Startup handshake | Protocol, version, capabilities and backend session identity |
| `player.list` / `player.select` | Backend session; selection identifies a candidate | List/selection result; actual session state arrives in a separate event |
| `session.resync` | Current player instance and track generation | Request fresh state and return a correlated snapshot; reject stale scope |
| `playback.play` / `playback.pause` | Current player instance and track generation | Command dispatch/call result; snapshots confirm playback state |
| `playback.next` / `playback.previous` | Current player instance and track generation | Non-idempotent operations; no retry across connections |
| `playback.seek` | Current player instance and track generation, finite `positionMs` | Validate derived capability and track object path, then resample after the call |
| `lyrics.refresh` / `lyrics.candidates` | Current track and resolution work | Fetch candidates while keeping the selected document fixed |
| `lyrics.select` | Current track, resolutionId, candidateId | Cancel earlier selection work and commit the user's document |
| `lyrics.import` | Current track and a user-selected local file | Bounded import and format validation; failure preserves the existing document |
| `lyrics.set-offset` | Current track, documentId, lyricVersionId, offsetMs | Save an offset for that specific version; does not control the player |
| `settings.get` / `settings.update` | Backend session | Validate allowed fields, save atomically and return effective settings |
| `cache.clear` | Backend session | Clear rebuildable cache only; retain manual selections and imports |
| `diagnostics.export` | Explicit user action | Redacted versions, status, errors and metrics; no raw protocol export |
| `shutdown` | Current backend session | Stop accepting tasks, cancel work and close the connection |

Requests after the handshake include `backendSessionId`; track-related requests also include scope. Operations such as next-track recheck scope before execution and target the unique D-Bus owner, so a new process cannot inherit commands through a reused well-known name. The protocol cannot give the player cross-process atomic transaction guarantees that the player itself does not provide.

```json
{"version":2,"type":"request","id":"r8","op":"playback.seek","backendSessionId":"b-demo-1","scope":{"playerInstanceId":"p-demo-1","trackGeneration":4},"params":{"positionMs":20000}}
```

```json
{"version":2,"type":"response","id":"r8","op":"playback.seek","backendSessionId":"b-demo-1","ok":false,"error":{"code":"stale_scope","retryable":false}}
```

`ok=true` means the result defined by that operation. It does not necessarily mean the audio output changed or playback started. Buttons may show a bounded pending state; player snapshots provide final confirmation. Do not blindly resend a timed-out control command whose outcome is unknown. Refresh state first so the user can decide.

`settings.get` returns `sources: [{id,name,chineseName,enabled}]`. Updates use `settings.update {sources:{netease:true}}` and accept registered IDs only. The older qqEnabled/neteaseEnabled fields remain migration-compatible inputs but are no longer used by the regular UI. `lyrics.set-offset` must include both documentId and lyricVersionId; identical content does not permit an old correction request to cross source versions.

A bounded deduplication record handles repeated request IDs within a session. The same ID and content returns the original or existing task result; the same ID with different content is rejected. A restart clears the record and changes session identity. Clients must not resend old requests to the new session. Consecutive seek-bar targets may be coalesced before dispatch; a call already sent cannot be treated as recalled.

## Documents and asynchronous results

A `lyrics.document` event carries scope, resolutionId, documentId, lyricVersionId and the complete `document`. Documents use schemaVersion 1 of the [lyric model](architecture.md); the envelope adds source information. The content hash excludes volatile fields such as player-local identity, allowing identical lyric content to be reused.

`session.state` references documentId. The UI enters lyric-ready state only after receiving the complete document for that scope. A changed document identity must rebind content, measurements and highlighting even when the active line index is unchanged. Switching lyrics loads the target version's offset instead of inheriting another version's correction.

A track change updates scope and clears the old document before starting resolution. Already-completed work may still have queued results after cancellation, so both SessionCoordinator and the client check ownership. Manual selection, import and a new search increment resolutionId, preventing an old search for the same track from overwriting a user action.

## Bounded work and errors

Input parsing, playback commands and lyric work can progress independently. Lyric network tasks do not occupy the playback command path. One writer serializes stdout messages. Pending obsolete position snapshots may be coalesced, but responses and documents must not be silently lost. A persistently slow consumer that exceeds bounds terminates the connection with a recoverable error rather than allowing unbounded memory growth.

Stable error codes include at least `invalid_request / unsupported_version / incompatible_backend / stale_scope / unsupported_capability / player_unavailable / timeout / rate_limited / no_lyrics / ambiguous_match / document_too_large / invalid_lyrics / storage_error / backend_unavailable`. Not-found results, uncertain matches and lyric network failures do not change player connection state. The localization layer maps error codes to user messages.

Low-level exceptions are not sent directly to the user-facing UI or default logs. The client shows a short explanation and retry/settings entry; diagnostics retain redacted error codes and correlation IDs. See [automated checks](testing.md#automated-checks) for protocol, lyric-race and runtime tests.
