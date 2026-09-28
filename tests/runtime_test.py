"""Bootstrap failure boundaries and optional real self-contained activation."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from runtime import RuntimeManager, RuntimeErrorCode


class RuntimeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {key: str(self.root / key) for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME")})
        self.env.start()

    def tearDown(self):
        self.env.stop(); self.temp.cleanup()

    def fixture(self, name="LyricIsland.Backend", link=None, data=b"not-an-elf"):
        package = self.root / "candidate.tar.gz"
        with tarfile.open(package, "w:gz") as tar:
            entry = tarfile.TarInfo(name)
            if link:
                entry.type = tarfile.SYMTYPE; entry.linkname = link
                tar.addfile(entry)
            else:
                entry.size = len(data); tar.addfile(entry, io.BytesIO(data))
        target = {"sha256": hashlib.sha256(package.read_bytes()).hexdigest(), "sizeBytes": package.stat().st_size, "entryPoint": "LyricIsland.Backend", "url": None}
        (self.root / "runtime-manifest.json").write_text(json.dumps({"manifestVersion": 1, "backendVersion": "0.2.0-dev", "supportedProtocols": [2], "targets": {"linux-x64": target}}))
        return RuntimeManager(self.root), package

    def test_missing_runtime_does_not_download(self):
        manager, _ = self.fixture()
        self.assertEqual(manager.status()["status"], "needsRuntime")
        self.assertFalse(manager.status()["downloadAvailable"])
        with self.assertRaisesRegex(RuntimeErrorCode, "download_consent_required"): manager.install()
        self.assertFalse(manager.state.exists())

    def test_bad_hash_keeps_existing_activation(self):
        manager, package = self.fixture()
        package.write_bytes(b"x" * package.stat().st_size)
        with self.assertRaisesRegex(RuntimeErrorCode, "hash_mismatch"): manager.install(package)
        self.assertFalse(manager.state.exists())
        self.assertEqual(list((manager.data / "runtimes").iterdir()), [])

    def test_path_escape_is_rejected(self):
        for name in ("../../escape", "/tmp/escape"):
            manager, package = self.fixture(name)
            with self.assertRaisesRegex(RuntimeErrorCode, "unsafe_archive"): manager.install(package)

    def test_symlink_is_rejected(self):
        manager, package = self.fixture(link="../../escape")
        with self.assertRaisesRegex(RuntimeErrorCode, "unsafe_archive"): manager.install(package)

    def test_wrong_architecture_is_rejected(self):
        manager, package = self.fixture()
        with self.assertRaisesRegex(RuntimeErrorCode, "unsupported_architecture"): manager.install(package)

    def test_missing_rollback_does_not_change_state(self):
        manager, _ = self.fixture()
        with self.assertRaisesRegex(RuntimeErrorCode, "no_compatible_rollback"): manager.rollback()
        self.assertFalse(manager.state.exists())

    def test_cancelled_download_preserves_saved_activation(self):
        manager, _ = self.fixture()
        manager.manifest["targets"]["linux-x64"]["url"] = "https://example.invalid/runtime.tar.gz"
        manager.state.parent.mkdir(parents=True)
        original = '{"schemaVersion":1,"downloadConsent":false}'
        manager.state.write_text(original)
        with patch("urllib.request.urlopen", side_effect=OSError("interrupted")):
            with self.assertRaises(OSError): manager.install(consent=True)
        self.assertEqual(manager.state.read_text(), original)
        self.assertEqual(list((manager.data / "runtimes").iterdir()), [])

    def test_purge_requires_confirmation_and_keeps_other_data(self):
        manager, _ = self.fixture()
        legacy = self.root / "config.json"
        legacy.write_text('{"width":610}')
        owned = []
        for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
            base = Path(os.environ[key]); path = base / "omarchy-lyricify"
            path.mkdir(parents=True); (path / "original").write_text("fixture")
            (base / "other-application").write_text("keep")
            owned.append(path)
        with self.assertRaisesRegex(RuntimeErrorCode, "purge_confirmation_required"): manager.purge()
        self.assertTrue(legacy.exists())
        self.assertTrue(all(path.exists() for path in owned))
        manager.purge(confirmed=True)
        self.assertFalse(legacy.exists())
        self.assertTrue(all(not path.exists() for path in owned))
        self.assertTrue(all((path.parent / "other-application").read_text() == "keep" for path in owned))


def package_integration():
    archive = ROOT / "artifacts" / ("lyric-island-" + (ROOT / "VERSION").read_text().strip() + "-linux-x64.tar.gz")
    if not archive.is_file(): raise SystemExit("Run make package-local first")
    with tempfile.TemporaryDirectory(prefix="lyric-package-") as temporary:
        root = Path(temporary); shutil.copy2(ROOT / "runtime-manifest.json", root)
        env = {key: str(root / key) for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME")}
        with patch.dict(os.environ, env):
            manager = RuntimeManager(root)
            status = manager.install(archive)
            assert status["status"] == "ready", status
            executable = status["path"]
            # Bubblewrap hides the installed SDK and all home/Nix locations.
            command = ["bwrap", "--unshare-all", "--die-with-parent", "--ro-bind", "/usr", "/usr", "--tmpfs", "/usr/share/dotnet",
                       "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64", "--proc", "/proc", "--dev", "/dev",
                       "--tmpfs", "/tmp", "--ro-bind", str(Path(executable).parent), "/runtime", "--clearenv",
                       "--setenv", "HOME", "/tmp", "/runtime/LyricIsland.Backend", "--stdio"]
            request = '{"version":2,"type":"request","id":"bootstrap","op":"hello","params":{"supportedProtocols":[2]}}\n'
            result = subprocess.run(command, input=request, capture_output=True, text=True, timeout=15)
            if result.returncode: raise AssertionError(result.stderr)
            response = json.loads(result.stdout.splitlines()[0])
            assert response["ok"] and response["result"]["backendVersion"] == (ROOT / "VERSION").read_text().strip(), result.stdout
            with tarfile.open(archive) as package:
                for name in ("LICENSE", "NOTICE", "THIRD_PARTY.md", "licenses/CC-BY-SA-4.0.txt", "licenses/Lyricify.Lyrics.Helper.txt"):
                    assert package.extractfile(name).read() == (ROOT / name).read_bytes(), name
            # Reinstallation and compatible rollback leave the saved activation usable.
            assert manager.install(archive)["status"] == "ready"
            first = manager.saved["active"].copy()
            marker = manager.data / "manual-selection.json"
            marker.write_text('{"original":"keep"}')
            updated = root / "updated.tar.gz"
            with tarfile.open(archive, "r:gz") as old, tarfile.open(updated, "w:gz") as new:
                for member in old:
                    new.addfile(member, old.extractfile(member))
                extra = tarfile.TarInfo("local-update-test.txt"); extra.size = 7
                new.addfile(extra, io.BytesIO(b"fixture"))
            manager.manifest["targets"]["linux-x64"].update(sha256=hashlib.sha256(updated.read_bytes()).hexdigest(), sizeBytes=updated.stat().st_size)
            assert manager.install(updated)["status"] == "ready"
            assert manager.saved["active"]["directory"] != first["directory"]
            assert manager.rollback()["status"] == "ready"
            assert manager.saved["active"] == first
            assert marker.read_text() == '{"original":"keep"}'
            assert manager.status()["status"] == "ready"
            assert not list((manager.data / "runtimes").glob(".install-*"))
            record = {"selfContained": True, "sdkHidden": True, "networkNamespaceIsolated": True, "activationHandshake": True,
                      "compatibleRollback": True, "userDataPreserved": True,
                      "archive": archive.name, "archiveSha256": hashlib.sha256(archive.read_bytes()).hexdigest()}
            (ROOT / "artifacts/runtime-validation.json").write_text(json.dumps(record, indent=2) + "\n")
            print("Self-contained activation and SDK-hidden namespace startup: passed")


if __name__ == "__main__":
    if "--package" in sys.argv: package_integration()
    else: unittest.main(verbosity=2)
