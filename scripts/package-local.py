"""Build a local self-contained candidate; performs no upload, tag, push or release."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parents[1]
artifacts = root / "artifacts"
artifacts.mkdir(exist_ok=True)
project = root / "backend/LyricIsland.Backend"
subprocess.run(["python3", str(root / "scripts/release-metadata.py"), "--check"], check=True)
release_version = (root / "VERSION").read_text().strip()
subprocess.run(["dotnet", "restore", str(project), "-r", "linux-x64", "--nologo"], check=True)
inputs = {}
for path in sorted(project.rglob("*")):
    if path.is_file() and not {"bin", "obj"}.intersection(path.relative_to(project).parts) and path.suffix in (".cs", ".csproj", ".xml", ".json"):
        inputs[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
revision = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=root, capture_output=True, text=True)
# A commit identifies the binary only when its build inputs are committed.
# Local experiments still get an input digest, but must not claim HEAD as source.
changes = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all", "--",
                          "backend/LyricIsland.Backend", "VERSION"], cwd=root, capture_output=True, text=True)
source_commit = revision.stdout.strip() if revision.returncode == 0 and changes.returncode == 0 and not changes.stdout else None
inputs["VERSION"] = hashlib.sha256((root / "VERSION").read_bytes()).hexdigest()
source_hash = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
manifest = {"manifestVersion": 1, "backendVersion": release_version, "backendSourceCommit": source_commit,
            "backendSourceSha256": source_hash, "supportedProtocols": [2], "targets": {}}
with tempfile.TemporaryDirectory(prefix="runtime-build-", dir=artifacts) as temporary:
    bundle = Path(temporary) / "bundle"
    subprocess.run(["dotnet", "publish", str(project), "--no-restore", "-r", "linux-x64", "--self-contained", "true", "-c", "Release", "-o", str(bundle), "--nologo"], check=True)
    if list(bundle.glob("*Chinese*")) or list(bundle.glob("*CHTCHS*")):
        raise SystemExit("Unexpected Chinese conversion dependency in artifact")
    shutil.copytree(root / "licenses", bundle / "licenses")
    matching = project / "Lyrics/UpstreamMatching"
    shutil.copy2(matching / "README.md", bundle / "licenses/Lyricify.Matching.CHANGES.md")
    shutil.copy2(matching / "source-provenance.json", bundle / "licenses/Lyricify.Matching.source.json")
    shutil.copy2(root / "LICENSE", bundle / "LICENSE")
    shutil.copy2(root / "THIRD_PARTY.md", bundle / "THIRD_PARTY.md")
    shutil.copy2(root / "NOTICE", bundle / "NOTICE")
    # The framework version selects the exact restored runtime license material.
    runtime_config = json.loads((bundle / "LyricIsland.Backend.runtimeconfig.json").read_text())
    version = next(f["version"] for f in runtime_config["runtimeOptions"]["includedFrameworks"] if f["name"] == "Microsoft.NETCore.App")
    package_cache = Path(subprocess.check_output(["dotnet", "nuget", "locals", "global-packages", "--list"], text=True).strip().split(": ", 1)[1])
    runtime_package = package_cache / "microsoft.netcore.app.runtime.linux-x64" / version
    license_files = [p for p in runtime_package.iterdir() if p.is_file() and ("license" in p.name.lower() or "notice" in p.name.lower())]
    if not license_files: raise SystemExit("Runtime license material missing")
    for path in license_files: shutil.copy2(path, bundle / "licenses" / ("dotnet-" + path.name))
    provenance = {"candidateOnly": True, "sourceCommit": manifest["backendSourceCommit"], "sourceSha256": source_hash,
                  "runtimeVersion": version, "inputs": inputs}
    (bundle / "build-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    shutil.copy2(project / "packages.lock.json", bundle / "packages.lock.json")
    archive = artifacts / f"lyric-island-{release_version}-linux-x64.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for path in sorted(bundle.rglob("*")):
            if path.is_file(): tar.add(path, arcname=path.relative_to(bundle), recursive=False)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    manifest["targets"]["linux-x64"] = {"url": None, "sha256": digest, "sizeBytes": archive.stat().st_size, "entryPoint": "LyricIsland.Backend"}
    (root / "runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (artifacts / "build-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    (artifacts / (archive.name + ".sha256")).write_text(digest + "  " + archive.name + "\n")
print(json.dumps({"archive": str(archive), "sizeBytes": archive.stat().st_size, "sha256": digest, "runtimeVersion": version, "published": False}, indent=2))
