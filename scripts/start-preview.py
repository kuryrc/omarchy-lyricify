"""Reuse this repository's preview when switching modes; never overlay two islands."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
mode = sys.argv[1] if len(sys.argv) > 1 else "demo"
if mode not in ("demo", "live"):
    raise SystemExit("Expected demo or live")
try:
    host = subprocess.run(["omarchy-shell", "shell", "listPlugins"], capture_output=True, text=True, timeout=4)
    if host.returncode == 0 and host.stdout.lstrip().startswith("["):
        if any(plugin.get("id") == "kuryrc.lyricify" and plugin.get("enabled") for plugin in json.loads(host.stdout)):
            raise SystemExit("Lyric Island is already enabled in Omarchy. Disable the native plugin before starting a development preview: omarchy plugin disable kuryrc.lyricify")
except FileNotFoundError:
    pass  # Independent Quickshell development is also supported.
except subprocess.TimeoutExpired:
    raise SystemExit("Omarchy is not responding; cannot verify whether an island is already active")
for name in ("shell.qml", "live.qml"):
    config = root / name
    result = subprocess.run(["quickshell", "list", "-p", str(config), "--json"], capture_output=True, text=True)
    instances = json.loads(result.stdout) if result.returncode == 0 and result.stdout.lstrip().startswith("[") else []
    if any(Path(instance["config_path"]).resolve() == config for instance in instances):
        subprocess.run(["quickshell", "ipc", "-p", str(config), "call", "lyricIsland", "preview", "true" if mode == "demo" else "false"], check=True)
        print("Switched existing island to " + mode)
        raise SystemExit(0)
os.execvp("quickshell", ["quickshell", "-n", "-p", str(root / ("shell.qml" if mode == "demo" else "live.qml"))])
