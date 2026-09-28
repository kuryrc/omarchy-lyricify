# Release and maintenance

This guide is for maintainers building and publishing the plugin. User installation and removal are covered in the [README](../README.md). Keep [known limitations](../README.md#compatibility-and-known-limitations) accurate until the corresponding [acceptance checks](testing.md) pass.

## Build a candidate

`VERSION` is the release input. Update it, generate the QML/manifest metadata, and run the checks:

```sh
make version
make check
```

Commit the source and VERSION before packaging, then run:

```sh
make verify-package
```

This builds a self-contained Linux x86_64 backend, verifies activation without an SDK, and exercises runtime cleanup and reinstallation. It produces a versioned archive, `.sha256` file and `build-provenance.json` under `artifacts/`, and updates `runtime-manifest.json`.

Check the candidate before using it:

- The manifest's version, byte size and SHA-256 match the archive. A version change clears old targets; rebuild instead of relabeling an archive.
- The provenance records the backend source commit and input hashes. `backendSourceCommit` is null when those build inputs are uncommitted; commit them and rebuild for a release candidate.
- The package carries the dependency lock file, LICENSE, NOTICE, third-party licenses, Helper modification notes and the actual bundled .NET notices. Review [THIRD_PARTY](../THIRD_PARTY.md) whenever dependencies or runtime versions change.
- Record the commands, build identity and results in the release PR or CI artifacts. Local measurements belong in ignored `artifacts/`; keep user-facing limitations in the README.

Commit the generated manifest separately if necessary. Its source commit identifies the backend inputs, which must remain unchanged when adding documentation or the download URL. Local candidate manifests may have a null URL. None of the `make` commands upload, push, tag or submit anything.

## Validate installation

Use the [source installation](../README.md#install-from-source) for local native checks. The plugin ID is `kuryrc.lyricify`; keep it stable across releases. Native load registers the application entry, so registration does not depend on the local installer.

In Omarchy 4.0.3, `plugin add` clones and validates a repository. Use `--enable`, accept its interactive enable prompt, or enable the plugin afterward. `--yes` alone does not enable it. There is no post-install dependency hook; backend preparation must work from the installed plugin itself. See [Omarchy's authoring documentation](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md).

Verify the running version and backend handshake after installation. A file copied to disk does not establish which QML or binary is active. Follow [reloading an updated plugin](troubleshooting.md#reloading-an-updated-plugin) if the host retains old QML.

A local archive test does not validate public HTTPS delivery or a clean machine's native-library compatibility. Once an authorized candidate asset is available, test a fresh Omarchy Git installation without the .NET SDK: first-run consent, download, preparation, launcher opening, quit/reopen, update, disable/remove, reinstall and explicit data cleanup. The settings window must remain usable when preparation fails.

## Publish and submit

Publication requires maintainer authorization. The local build commands do not grant it.

1. Freeze the reviewed source and supported software matrix. Complete the applicable playback, lyric, recovery, performance and package checks in [testing](testing.md).
2. Publish the authorized candidate repository and fixed prerelease archive with its checksum and provenance. Set that asset's HTTPS URL in `runtime-manifest.json`, retaining its exact size and hash. Verify that backend inputs still match the recorded source commit.
3. Run remote CI and the fresh Git-installation checks above. Keep the release marked as a candidate while required checks fail or remain unperformed. Promote it only after those checks pass.
4. Write release notes describing user-visible changes, compatibility, known issues and any migration steps. Keep detailed run logs with the release/CI artifacts.
5. Submit the exact reviewed commit to the [community marketplace](https://plugins.omarchy.org/publish.html), following its current [submission rules](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md). Include the installation instructions, dependencies, license scope, privacy behavior and preview. Automated validation and maintainer approval are separate steps.

The root `preview.png` is shared by the README and marketplace submission; generate it with `make previews`. Check marketplace requirements again before submitting. The repository's [CI workflow](../.github/workflows/check.yml) runs portable build, test and package checks without an upload step. Quickshell/Wayland checks run on Omarchy.

## Update and rollback

Omarchy updates the plugin from the repository's default branch. Keep every referenced runtime asset available and immutable while that plugin revision remains installable. The manifest selects an exact backend by version, HTTPS URL, size and SHA-256; never substitute a moving `latest` asset.

Runtime activation verifies the archive and a real version/protocol handshake before switching. Failed or partial downloads leave the previous complete runtime intact. Switching stops the old child; pending playback commands are not replayed. Offline fallback and runtime rollback require the same backend version and protocol contract. Full application rollback also needs matching UI source and readable data schemas.

With the plugin disabled and previews stopped, `python3 scripts/runtime.py rollback` selects a previous compatible local runtime. It is not a general downgrade across product versions. Schema changes need migration, backup and recovery tests; [architecture](architecture.md#persistent-data) describes data ownership and [privacy](privacy.md#local-data) lists user locations.

Rebuild self-contained packages when their embedded .NET runtime needs updates. Installing a new system SDK does not update an already-distributed runtime. Use a new release version for changed binary inputs, rerun the package checks, and keep compatibility claims limited to verified systems and players.
