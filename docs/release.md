# Release and maintenance

This guide covers packaging and publication. Installation instructions and current limitations belong in the [README](../README.md).

## Versions

`VERSION` is the release input; the tag is exactly `v` followed by that value. Use dotted prerelease identifiers and mark candidates as GitHub prereleases.

| Release | Version / tag |
| --- | --- |
| Candidate | `0.2.0-rc.2` / `v0.2.0-rc.2` |
| First accepted release | `0.2.0` / `v0.2.0` |
| Compatible fix | `0.2.1` / `v0.2.1` |
| Next feature release | `0.3.0` / `v0.3.0` |

Increment the candidate number when its contents change. Keep published tags and assets immutable. Do not publish `-dev` versions or use build metadata (`+...`). Follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html); before 1.0, incompatible changes increment the minor version and need migration notes.

Promoting a candidate requires updating `VERSION`, regenerating metadata and rebuilding. Changing a release title or prerelease flag does not change the embedded backend version. CI checks tag/version agreement.

## Build a candidate

Update `VERSION`, then run:

```sh
make version
make check
```

Commit the source and version on a preparation branch before packaging:

```sh
make verify-package
```

This builds and checks the self-contained Linux x86_64 backend, including SDK-hidden activation, cleanup and reinstallation. It writes the archive, checksum and `build-provenance.json` under `artifacts/`, and updates `runtime-manifest.json`.

Check that:

- The manifest's version, size and SHA-256 match the archive.
- Provenance records a reachable source commit, source/build-input hashes and SDK/runtime versions. A null `backendSourceCommit` means the inputs were uncommitted: commit and rebuild.
- The package includes LICENSE, NOTICE, dependency locks, third-party licenses, Helper modification notes and the bundled .NET notices. Review [THIRD_PARTY](../THIRD_PARTY.md) after dependency changes.

Keep backend inputs unchanged while preparing the final download manifest. Its source commit may precede the metadata commit. Rebuild after amending or squashing the recorded source commit. Local manifests may have a null URL; the published default branch must have a working download entry. Build commands do not upload or publish.

## Validate installation

Use the [source installation](../README.md#install-from-source) for local checks. Confirm the running version and backend handshake; see [reloading an updated plugin](troubleshooting.md#reloading-an-updated-plugin) when Omarchy retains old QML.

Then test the candidate through the README's Git installation on a clean Omarchy machine without the .NET SDK. Check first-run consent, HTTPS download, preparation, launcher opening, quit/reopen, update, disable/remove, reinstall and data cleanup. Preparation failures must leave settings usable. A local archive test does not establish public delivery or native-library compatibility.

Keep plugin ID `kuryrc.lyricify` stable. Native load registers the launcher; backend preparation must work without an installer hook. In Omarchy 4.0.3, `plugin add --yes` alone does not enable a plugin: use `--enable` or explicitly enable it afterward.

## Publish and submit

Publication requires maintainer authorization.

1. Freeze the reviewed source and supported environment. Collect [test results](testing.md), record remaining limitations in the README, and write release notes with user-visible changes and migration steps.
2. Set the fixed asset URL in `runtime-manifest.json` with its exact size and SHA-256. Verify the packaged source inputs, commit the final metadata and run remote CI on that commit.
3. Publish the authorized candidate archive, checksum and provenance with the tag pointing to that final commit. Verify the public download before advancing the default branch to it; Omarchy installs from the default branch.
4. Complete the fresh installation checks above. Experimental candidates must disclose missing validation. A public beta requires passing automated checks and all applicable desktop, synchronization, performance and installation checks in [testing](testing.md). Explain inapplicable cases; do not label an untested supported feature inapplicable. A stable release also requires resolving beta feedback and reviewing compatibility again.
5. Submit the exact final commit through the [marketplace Issue form](https://plugins.omarchy.org/publish.html), following the current [submission rules](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md). Include installation, dependencies, licensing, privacy and the root `preview.png`. Automated validation and maintainer approval are separate.

At submission, CI, tag, default-branch HEAD, marketplace validation and security review must agree on the final commit. Any later commit, including documentation changes, needs fresh marketplace validation. Generate preview images with `make previews`. Keep detailed logs in PR/CI artifacts, not new repository reports.

## Update and rollback

Keep every referenced asset available and immutable. Runtime activation verifies the archive and version/protocol handshake before switching; partial downloads must never replace a complete runtime. Stopping the old backend must not replay pending controls.

With the plugin disabled and previews stopped:

```sh
python3 scripts/runtime.py rollback
```

Rollback selects a previous compatible local backend with the same version and protocol; it is not a general application downgrade. A full downgrade also needs matching UI source and readable data schemas. Schema changes need migration, backup and recovery tests.

A system SDK update does not patch the bundled runtime. Rebuild under a new release version when binary inputs change, and rerun package checks.
