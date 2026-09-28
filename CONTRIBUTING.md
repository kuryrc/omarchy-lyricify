# Contributing

The [README](README.md) covers installation, behavior and known limitations. Use [architecture](docs/architecture.md) to find the code responsible for a change, and [testing](docs/testing.md) for regression scenarios and acceptance criteria.

## Build and verify

Development needs the .NET SDK specified in [global.json](global.json), Python 3, Make, Node, OpenSSL, session D-Bus and the Python dbus/PyGObject modules. UI checks also need Omarchy, Quickshell, Qt Quick and Qt Test; package checks need Linux x86_64 and bubblewrap. The installed plugin does not need an SDK.

From the repository root:

```sh
make build         # Build the backend and its test executable
make test-backend   # Protocol, isolated player/provider, storage, runtime and launcher tests
make check          # Also native QML engine, Qt interactions and Omarchy manifest checks
make verify-package # Build candidate; verify notices, SDK-hidden startup, rollback and purge/reprepare
```

Tests use temporary XDG directories and isolated D-Bus services. Keep controlled-player tests off your real Spotify bus. GUI checks use offscreen windows where possible; real Wayland behavior and audio synchronization require separate checks. The [test guide](docs/testing.md) lists coverage and measurement methods.

CI pins Actions to full commits, the Ubuntu-based build container to a digest, and apt packages to a dated archive snapshot with signature checks enabled. The container includes CA certificates; all package downloads use HTTPS, with no rolling-mirror fallback. Tests run as an unprivileged user so file-permission checks remain meaningful. Local builds and CI use the same exact SDK and locked NuGet dependencies; the backend project also pins its bundled runtime version.

Update these build dependencies deliberately: change the workflow pins, SDK or runtime version as appropriate, then restore both projects with `-p:RestoreLockedMode=false` if their dependencies changed. Review and commit the resulting lockfiles. Run `make check` and rebuild/verify the self-contained package before publishing a dependency update. A newer system SDK does not update an installed self-contained backend.

`test.qml` is the root test entry. Quickshell refuses imports outside its configuration scanner root, so this wrapper must stay at the repository root. Assertions live under `tests/`; `LYRIC_ISLAND_TEST_SUITE` selects the suite. `shell.qml` and `live.qml` start developer previews.

## Local preview

```sh
make demo          # Original fixture, no provider calls
make live          # Local player; switches an existing preview instead of opening another
make stop
make reload-live   # Syntax/interaction checks before restarting a preview
```

Use one visible island: disable `kuryrc.lyricify` before starting a preview, and stop the preview before enabling the installed plugin. Demo uses original fixture data; live mode uses your session's player and saved lyric-source choices. Follow the [README installation steps](README.md#install-from-source) to test an installed build.

`make smoke` operates the existing demo. Run it separately from [performance measurements](docs/testing.md#animation-and-resource-measurement), without source edits during either run. Generate README screenshots with `make previews`; it renders production QML offscreen using original fixture data. Reports and local screenshots belong in ignored `artifacts/`.

## Layout and changes

- `core/` owns client state, timing, preferences and lifecycle; `ui/` owns presentation. Backend folders separate playback, session attribution, lyrics, storage and protocol.
- `scripts/runtime.py`, `backend-launch.py`, `launch.py` ship to users. Package/install/preview/check scripts are maintainer tools. See [scripts](scripts/README.md).
- `VERSION` is authoritative. Change it, run `make version`, build and verify. `make package-local` updates artifact metadata but never publishes. A changed version clears old artifact targets until rebuilt.
- Version the data schema, process protocol and product independently. A lyric lookup or storage error must leave playback available.
- Follow [protocol](docs/protocol.md) for process changes, [architecture](docs/architecture.md#persistent-data) for stored data, and [release](docs/release.md) for packaging. Test regressions through the affected public interface: for example, import failures through `lyrics.import` and player reconnects over D-Bus.
- Preserve third-party attribution and modified-source notices. UI/preview contributions use CC BY-SA 4.0; original logic uses MIT. New dependencies need explicit redistribution terms before shipping.

Run `make format` for QML. Move files separately from behavioral changes where possible. In a pull request, explain the behavior change, relevant checks and remaining limitations. Default tests do not call online lyric providers; manual network probes in the test executable are explicit diagnostic tools.

## Documentation

Use English for repository documentation. Write for someone installing, debugging or changing the plugin. Describe the behavior first, then the command or file involved. Give operational steps their prerequisites and expected results. Preserve upstream legal texts in their original form; this documentation convention does not change the app's supported UI languages or multilingual lyric fixtures.

- User-facing changes belong in the README or troubleshooting guide; keep known limitations visible.
- Architecture records responsibilities and design constraints. Protocol records the process contract. Testing records repeatable methods and pass criteria. Release records the packaging and publication procedure.
- Keep individual run logs, review findings and work plans in local `artifacts/`, PR discussions or CI artifacts. Publish release notes for changes users need to know, rather than adding a progress report to the source tree.

When moving documentation, update its links and the relevant pointers in `AGENTS.md`.
