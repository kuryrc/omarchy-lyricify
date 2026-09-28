# Development

- Authorization covers local development and validation. Creating a public repository, pushing, tagging, uploading releases or submitting to the marketplace requires an explicit user request.
- Show one island at a time. Use isolated D-Bus services for automated playback tests and offscreen windows for UI checks where possible. A visible preview and the native plugin are mutually exclusive.
- Read `README.md` for user behavior and known limitations, and `docs/troubleshooting.md` for troubleshooting. Preserve top-edge placement, the center-right default, drag-to-center snapping and the existing clock/weather layout.
- Read `docs/architecture.md` when changing modules, playback or lyric ownership, and `docs/protocol.md` when changing process messages. The supported protocol is v2 only.
- Read `CONTRIBUTING.md` for builds and previews, `docs/testing.md` for methods and pass criteria, and `docs/release.md` for packaging, updates and publication.
- Write repository documentation in English. Preserve upstream legal texts in their original form; UI translations and lyric fixtures may remain multilingual.
- Document usage, design constraints and repeatable maintenance procedures. Update the relevant page when behavior changes and keep known issues in the README. Store work plans, review reports and run logs in ignored `artifacts/` or PR/CI artifacts, rather than adding public progress reports.
- `VERSION` is the sole release-version input; `make version` generates QML/manifest metadata. Keep the root `test.qml`: it is the thin entry required by Quickshell's configuration scanner.
- Read `THIRD_PARTY.md`, `LICENSE` and `NOTICE` before reusing or distributing upstream material. Leave the ignored reference checkout `Lyricify-App/` unchanged. Use original fixtures for previews.
- Logs and diagnostics contain only necessary status information. Exclude credentials, private listening histories, full lyric text and other desktop windows.
