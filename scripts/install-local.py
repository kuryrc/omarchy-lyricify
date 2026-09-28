"""Copy runtime files only; preserve installed configuration and unrelated plugins."""
import json
import os
import pathlib
import shutil
import subprocess
from runtime import RuntimeManager

root = pathlib.Path(__file__).resolve().parents[1]
config_root = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config"))
target = config_root / "omarchy/plugins/kuryrc.lyricify"
if target.is_symlink():
    raise SystemExit("Refusing a symlink installation target")
if target.exists() and (target / "manifest.json").exists():
    if json.loads((target / "manifest.json").read_text())["id"] != "kuryrc.lyricify":
        raise SystemExit("Installation target belongs to another plugin")
    subprocess.run(["omarchy", "plugin", "validate", str(target)], check=True)
elif target.exists() and any(target.iterdir()):
    raise SystemExit("Installation target is not an existing Lyric Island plugin")
subprocess.run(["omarchy", "plugin", "validate", str(root)], check=True)
# Activation verifies the local asset before changing the installed UI.
version = (root / "VERSION").read_text().strip()
archive = root / "artifacts" / f"lyric-island-{version}-linux-x64.tar.gz"
if not archive.is_file():
    raise SystemExit("Run make package-local first")
RuntimeManager(root).install(archive)
target.mkdir(parents=True, exist_ok=True)
for name in ("manifest.json", "runtime-manifest.json", "LyricIsland.qml", "LICENSE", "NOTICE", "THIRD_PARTY.md"):
    shutil.copy2(root / name, target / name)
for name in ("core", "ui", "assets", "fixtures", "licenses"):
    shutil.copytree(root / name, target / name, dirs_exist_ok=True)
(target / "scripts").mkdir(exist_ok=True)
for name in ("runtime.py", "backend-launch.py", "launch.py"):
    shutil.copy2(root / "scripts" / name, target / "scripts" / name)
subprocess.run(["omarchy", "plugin", "validate", str(target)], check=True)
subprocess.run(["python3", str(target / "scripts/launch.py"), "--register"], check=True)
print(f"Installed runtime files: {target}")
print("Self-contained backend verified and activated locally. Nothing was published.")
print("User settings retained in XDG config. Plugin enable state and bar layout unchanged.")
