"""Bootstrap failure boundaries and optional real self-contained activation."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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
        with patch("urllib.request.OpenerDirector.open", side_effect=OSError("interrupted")):
            with self.assertRaises(OSError): manager.install(consent=True)
        self.assertEqual(manager.state.read_text(), original)
        self.assertEqual(list((manager.data / "runtimes").iterdir()), [])

    def test_download_redirects_require_https_on_every_hop(self):
        manager, package = self.fixture(data=b"\x7fELF\x02\x01" + b"\0" * 12 + b"\x3e\x00")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", str(self.root / "key.pem"), "-out", str(self.root / "cert.pem"),
                        "-days", "1", "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        requests = []
        archive = package.read_bytes()

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass

            def do_GET(self):
                secure = isinstance(self.connection, ssl.SSLSocket)
                requests.append(("https" if secure else "http", self.path))
                if self.path == "/archive":
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(archive)))
                    self.end_headers(); self.wfile.write(archive)
                    return
                # /downgrade tests the final URL, /bounce hides HTTP between TLS hops.
                target = (f"http://127.0.0.1:{plain.server_port}/archive" if self.path == "/downgrade"
                          else f"http://127.0.0.1:{plain.server_port}/middle" if self.path == "/bounce"
                          else f"https://127.0.0.1:{tls.server_port}/archive")
                self.send_response(302); self.send_header("Location", target); self.end_headers()

        plain = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        tls = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.root / "cert.pem", self.root / "key.pem")
        tls.socket = context.wrap_socket(tls.socket, server_side=True)
        client = ssl.create_default_context(cafile=str(self.root / "cert.pem"))
        threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in (plain, tls)]
        for thread in threads: thread.start()
        try:
            with patch("ssl._create_default_https_context", return_value=client), \
                    patch("urllib.request.getproxies", return_value={}), patch.object(manager, "handshake"):
                for route in ("/downgrade", "/bounce"):
                    with self.subTest(route=route):
                        requests.clear()
                        manager.manifest["targets"]["linux-x64"]["url"] = f"https://127.0.0.1:{tls.server_port}{route}"
                        with self.assertRaisesRegex(RuntimeErrorCode, "insecure_redirect"):
                            manager.install(consent=True)
                        self.assertEqual(requests, [("https", route)])
                        self.assertFalse(manager.state.exists())
                        self.assertEqual(list((manager.data / "runtimes").iterdir()), [])
                requests.clear()
                manager.manifest["targets"]["linux-x64"]["url"] = f"https://127.0.0.1:{tls.server_port}/safe"
                self.assertEqual(manager.install(consent=True)["status"], "ready")
                self.assertEqual(requests, [("https", "/safe"), ("https", "/archive")])
        finally:
            for server in (plain, tls): server.shutdown(); server.server_close()
            for thread in threads: thread.join(timeout=2)

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
