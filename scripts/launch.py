#!/usr/bin/env python3
"""Register/open the installed plugin, or reuse its existing preview."""
import json
import os
from pathlib import Path
import subprocess
import sys

PLUGIN_ID = "kuryrc.lyricify"


def register():
    """Runs on native plugin load too; Git installs have no post-install hook.

    TryExec hides the launcher automatically when Omarchy removes its checkout.
    A disabled plugin keeps its launcher so it can be opened again.
    """
    script = Path(__file__).resolve()
    applications = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    escaped = str(script).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%").replace("`", "\\`").replace("$", "\\$")
    # TryExec is a desktop string value, not an Exec argument; escape spaces there.
    try_exec = str(script).replace("\\", "\\\\").replace(" ", "\\s")
    text = ("[Desktop Entry]\nType=Application\nName=Lyric Island\nName[zh_CN]=歌词灵动岛\n"
            f'TryExec={try_exec}\nExec=python3 "{escaped}"\nIcon=audio-x-generic\nTerminal=false\nCategories=AudioVideo;Audio;\nActions=Settings;\n'
            f'[Desktop Action Settings]\nName=Settings\nName[zh_CN]=设置\nExec=python3 "{escaped}" --settings\n')
    target = applications / (PLUGIN_ID + ".desktop")
    if not target.exists() or target.read_text() != text:
        temporary = target.with_suffix(".desktop.tmp")
        temporary.write_text(text)
        temporary.replace(target)


def launch(settings=False):
    result = subprocess.run(["quickshell", "list", "--all", "--json"], capture_output=True, text=True, check=True, timeout=5)
    for instance in json.loads(result.stdout):
        config = Path(instance["config_path"])
        if config.name not in ("live.qml", "shell.qml"):
            continue
        manifest = config.parent / "manifest.json"
        if not manifest.is_file() or json.loads(manifest.read_text()).get("id") != PLUGIN_ID:
            continue
        subprocess.run(["quickshell", "ipc", "-p", str(config), "call", "lyricIsland", "openIsland"], check=True, timeout=5)
        if settings:
            subprocess.run(["quickshell", "ipc", "-p", str(config), "call", "lyricIsland", "settings", "true"], check=True, timeout=5)
        return
    # Omarchy's enable operation is idempotent. Summon is necessary even for a
    # keepLoaded panel, especially with no player or no prepared runtime.
    subprocess.run(["omarchy", "plugin", "enable", PLUGIN_ID], check=True, timeout=10)
    subprocess.run(["omarchy-shell", "shell", "summon", PLUGIN_ID, json.dumps({"settings": settings})], check=True, timeout=5)


if __name__ == "__main__":
    if "--register" in sys.argv:
        register()
    else:
        launch("--settings" in sys.argv)
