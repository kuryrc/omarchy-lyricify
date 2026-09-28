"""Fixed-manifest runtime installation. No shell commands or implicit downloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


class RuntimeErrorCode(Exception):
    pass


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".runtime-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(value, out, indent=2); out.write("\n"); out.flush(); os.fsync(out.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp): os.unlink(temp)


class RuntimeManager:
    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.manifest = json.loads((self.root / "runtime-manifest.json").read_text())
        if self.manifest.get("manifestVersion") != 1 or 2 not in self.manifest.get("supportedProtocols", []):
            raise RuntimeErrorCode("incompatible_backend")
        home = Path.home()
        self.data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")) / "omarchy-lyricify"
        self.state = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "omarchy-lyricify/runtime.json"
        self.saved = json.loads(self.state.read_text()) if self.state.exists() else {"schemaVersion": 1, "downloadConsent": False}
        if self.saved.get("schemaVersion") != 1: raise RuntimeErrorCode("storage_error")

    def target(self):
        if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
            raise RuntimeErrorCode("unsupported_architecture")
        return self.manifest["targets"].get("linux-x64")

    def entry(self, record):
        if not isinstance(record, dict) or record.get("protocol") != 2: return None
        directory = record.get("directory", "")
        entry = record.get("entryPoint", "")
        if not directory or "/" in directory or directory in (".", "..") or not entry or "/" in entry or entry in (".", ".."): return None
        path = self.data / "runtimes" / directory / entry
        if path.is_symlink() or not path.is_file() or not os.access(path, os.X_OK): return None
        if hashlib.sha256(path.read_bytes()).hexdigest() != record.get("entrySha256"): return None
        return path

    def status(self):
        target = self.target()
        development = self.root / "backend/LyricIsland.Backend/bin/Release/net10.0/LyricIsland.Backend.dll"
        if development.is_file() and shutil.which("dotnet"):
            return {"status": "development", "path": str(development), "version": self.manifest["backendVersion"]}
        current = self.saved.get("active")
        path = self.entry(current)
        if path and current.get("backendVersion") == self.manifest["backendVersion"]:
            return {"status": "ready", "path": str(path), "version": current["backendVersion"],
                    "downloadAvailable": bool(target and target.get("url")), "sizeBytes": target.get("sizeBytes", 0) if target else 0,
                    "updatePending": bool(target and current.get("sha256") != target.get("sha256"))}
        return {"status": "needsRuntime", "downloadAvailable": bool(target and target.get("url")),
                "sizeBytes": target.get("sizeBytes", 0) if target else 0, "version": self.manifest["backendVersion"],
                "downloadConsent": self.saved.get("downloadConsent", False)}

    def install(self, archive=None, consent=False):
        target = self.target()
        if not target: raise RuntimeErrorCode("release_not_available")
        digest, size = target.get("sha256", ""), target.get("sizeBytes", 0)
        if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest) or not isinstance(size, int) or not 0 < size <= 250_000_000:
            raise RuntimeErrorCode("invalid_manifest")
        if archive is None and not (consent or self.saved.get("downloadConsent")):
            raise RuntimeErrorCode("download_consent_required")
        runtimes = self.data / "runtimes"
        runtimes.mkdir(parents=True, exist_ok=True)
        if runtimes.is_symlink(): raise RuntimeErrorCode("unsafe_runtime_directory")
        with tempfile.TemporaryDirectory(prefix=".install-", dir=runtimes) as work:
            work = Path(work); package = work / "runtime.tar.gz"
            if archive is not None:
                if Path(archive).stat().st_size != size: raise RuntimeErrorCode("size_mismatch")
                shutil.copyfile(archive, package)
            else:
                url = target.get("url", "")
                if not isinstance(url, str) or not url.startswith("https://"): raise RuntimeErrorCode("release_not_available")
                request = urllib.request.Request(url, headers={"User-Agent": "LyricIsland/" + self.manifest["backendVersion"]})
                with urllib.request.urlopen(request, timeout=20) as response, package.open("wb") as out:
                    if not response.url.startswith("https://"): raise RuntimeErrorCode("insecure_redirect")
                    total = 0
                    while chunk := response.read(65536):
                        total += len(chunk)
                        if total > size: raise RuntimeErrorCode("size_mismatch")
                        out.write(chunk)
            if package.stat().st_size != size: raise RuntimeErrorCode("size_mismatch")
            if hashlib.sha256(package.read_bytes()).hexdigest() != digest: raise RuntimeErrorCode("hash_mismatch")
            extracted = work / "files"; extracted.mkdir()
            with tarfile.open(package, "r:gz") as tar:
                members, unpacked = [], 0
                for member in tar:
                    members.append(member); unpacked += member.size
                    if len(members) > 3000 or unpacked > 600_000_000: raise RuntimeErrorCode("archive_too_large")
                names = set()
                for member in members:
                    name = PurePosixPath(member.name)
                    if name.is_absolute() or ".." in name.parts or not (member.isfile() or member.isdir()) or member.name in names:
                        raise RuntimeErrorCode("unsafe_archive")
                    names.add(member.name)
                tar.extractall(extracted, members=members, filter="data")
            entry = target.get("entryPoint", "")
            if not entry or "/" in entry or entry in (".", ".."): raise RuntimeErrorCode("invalid_manifest")
            executable = extracted / entry
            if not executable.is_file(): raise RuntimeErrorCode("missing_entrypoint")
            with executable.open("rb") as binary: header = binary.read(20)
            if header[:6] != b"\x7fELF\x02\x01" or header[18:20] != b"\x3e\x00": raise RuntimeErrorCode("unsupported_architecture")
            executable.chmod(0o755)
            self.handshake(executable)
            directory = self.manifest["backendVersion"] + "-" + digest[:16]
            if "/" in directory or directory.startswith("."): raise RuntimeErrorCode("invalid_manifest")
            destination = runtimes / directory
            if destination.exists():
                # An existing immutable artifact is only reused after its entry hash matches.
                if destination.is_symlink() or not (destination / entry).is_file() or hashlib.sha256((destination / entry).read_bytes()).digest() != hashlib.sha256(executable.read_bytes()).digest():
                    raise RuntimeErrorCode("runtime_conflict")
            else: extracted.rename(destination)
            record = {"directory": directory, "entryPoint": entry, "protocol": 2, "backendVersion": self.manifest["backendVersion"],
                      "sha256": digest, "entrySha256": hashlib.sha256((destination / entry).read_bytes()).hexdigest()}
            previous = self.saved.get("active")
            if previous != record: self.saved["previous"] = previous
            self.saved.update(active=record, downloadConsent=bool(consent or self.saved.get("downloadConsent")))
            atomic_json(self.state, self.saved)
        return self.status()

    def handshake(self, executable):
        request = {"version": 2, "type": "request", "id": "bootstrap", "op": "hello", "params": {"supportedProtocols": [2], "clientVersion": self.manifest["backendVersion"], "clientInstanceId": "bootstrap"}}
        # Probe with isolated data; it must not trigger user-enabled providers or rewrite preferences.
        with tempfile.TemporaryDirectory(prefix="lyric-bootstrap-") as temporary:
            env = dict(os.environ, **{key: temporary + "/" + key for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME")})
            result = subprocess.run([str(executable), "--stdio"], input=json.dumps(request) + "\n", capture_output=True, text=True, timeout=10, env=env)
        if result.returncode: raise RuntimeErrorCode("runtime_start_failed")
        if len(result.stdout) > 2_000_000: raise RuntimeErrorCode("invalid_handshake")
        response = next((json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')), {})
        if not response.get("ok") or response.get("result", {}).get("protocol") != 2 or response.get("result", {}).get("backendVersion") != self.manifest["backendVersion"]:
            raise RuntimeErrorCode("incompatible_backend")

    def rollback(self):
        previous = self.saved.get("previous")
        path = self.entry(previous)
        if not path or previous.get("backendVersion") != self.manifest["backendVersion"]: raise RuntimeErrorCode("no_compatible_rollback")
        self.handshake(path)
        self.saved["active"], self.saved["previous"] = previous, self.saved.get("active")
        atomic_json(self.state, self.saved)
        return self.status()

    def purge(self, confirmed=False):
        if not confirmed: raise RuntimeErrorCode("purge_confirmation_required")
        roots = [("XDG_CONFIG_HOME", ".config"), ("XDG_STATE_HOME", ".local/state"), ("XDG_DATA_HOME", ".local/share"), ("XDG_CACHE_HOME", ".cache")]
        paths = {Path(os.environ.get(key, Path.home() / fallback)) / "omarchy-lyricify" for key, fallback in roots}
        for path in paths:
            if not path.is_absolute() or path.is_symlink(): raise RuntimeErrorCode("unsafe_data_directory")
        # A pre-migration checkout may still carry old user display settings.
        # Remove that legacy input too, otherwise restart would resurrect it.
        legacy = self.root / "config.json"
        if legacy.is_symlink(): raise RuntimeErrorCode("unsafe_data_directory")
        if legacy.exists(): legacy.unlink()
        for path in paths:
            if path.exists(): shutil.rmtree(path)
        return {"status": "purged"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["status", "install", "rollback", "purge"])
    parser.add_argument("--archive"); parser.add_argument("--consent", action="store_true")
    parser.add_argument("--confirm-user-data-deletion", action="store_true")
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
    try:
        manager = RuntimeManager()
        if args.operation == "status": result = manager.status()
        elif args.operation == "rollback": result = manager.rollback()
        elif args.operation == "purge": result = manager.purge(args.confirm_user_data_deletion)
        else: result = manager.install(args.archive, args.consent)
        print(json.dumps({"ok": True, **result}))
    except Exception as error:
        code = str(error) if isinstance(error, RuntimeErrorCode) else "runtime_error"
        print(json.dumps({"ok": False, "error": code})); return 1
    return 0


if __name__ == "__main__": raise SystemExit(main())
