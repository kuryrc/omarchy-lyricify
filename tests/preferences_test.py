"""Persist settings through real QML file I/O and a replaced plugin checkout."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="lyric-preferences-") as temporary:
    folder = Path(temporary)
    plugin = folder / "plugin"
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", WAYLAND_DISPLAY="", NO_AT_BRIDGE="1",
        XDG_CONFIG_HOME=str(folder / "config"), XDG_STATE_HOME=str(folder / "state"), XDG_DATA_HOME=str(folder / "data"), XDG_CACHE_HOME=str(folder / "cache"))
    saved_path = folder / "config/omarchy-lyricify/ui.json"
    def checkout(legacy=False):
        plugin.mkdir()
        for name in ("core", "assets"):
            shutil.copytree(ROOT / name, plugin / name)
        (plugin / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/runtime.py", plugin / "scripts/runtime.py")
        shutil.copy2(ROOT / "runtime-manifest.json", plugin / "runtime-manifest.json")
        if legacy:
            (plugin / "config.json").write_text(json.dumps({"width": 610, "offsetX": 300, "monitor": "old-monitor", "hideFullscreen": False, "pauseCollapseMs": 3000}))
        (plugin / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "core" as Core
ShellRoot {
    Core.UiPreferences { id: prefs }
    IpcHandler {
        target: "preferencesTest"
        function state(): string { return JSON.stringify({loaded: prefs.loaded, display: prefs.display, language: prefs.language, error: prefs.error}); }
        function change(): void { prefs.saveLanguage("zh_CN"); prefs.saveDisplay("width", 680); prefs.saveDisplay("monitor", "new-monitor"); prefs.saveDisplay("hideFullscreen", true); prefs.saveDisplay("pauseCollapseMs", 10000); }
    }
}''')
    def run(change=False):
        with (folder / "log").open("w+") as log:
            process = subprocess.Popen(["quickshell", "-n", "-p", str(plugin / "shell.qml")], env=environment, stdout=log, stderr=log)
            try:
                def ipc(method):
                    return subprocess.check_output(["quickshell", "ipc", "-p", str(plugin / "shell.qml"), "call", "preferencesTest", method], env=environment, text=True, stderr=subprocess.DEVNULL, timeout=3)
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    try:
                        state = json.loads(ipc("state"))
                        if state["loaded"] and (not change or state["display"]["width"] == 610): break
                    except (subprocess.CalledProcessError, json.JSONDecodeError): pass
                    time.sleep(.05)
                else:
                    log.seek(0)
                    raise AssertionError(log.read())
                assert state["error"] == "", state
                if change:
                    assert state["display"]["monitor"] == "old-monitor", state
                    ipc("change")
                    deadline = time.monotonic() + 3
                    while time.monotonic() < deadline:
                        if saved_path.exists():
                            saved = json.loads(saved_path.read_text())
                            if saved.get("display", {}).get("pauseCollapseMs") == 10000: break
                        time.sleep(.05)
                    else: raise AssertionError("UI preferences did not persist")
                return state
            finally:
                process.terminate(); process.wait(timeout=5)
    checkout(legacy=True)
    run(change=True)
    assert not (plugin / "config.json").exists(), "Legacy source was not retired"
    assert list(saved_path.parent.glob("legacy-display-*.json")), "Legacy backup not preserved"
    shutil.rmtree(plugin)  # Simulate normal Omarchy removal, retaining XDG user data.
    checkout()
    state = run()
    assert state["display"] == {"width": 680, "offsetX": 300, "monitor": "new-monitor", "hideFullscreen": True, "pauseCollapseMs": 10000}, state
    assert state["language"] == "zh_CN", state
    (plugin / "config.json").write_text(json.dumps({"width": 610}))
    # Purge owns both XDG data and legacy files in its installation root.
    # Exercise the temporary checkout, never the developer's real source tree.
    subprocess.run(["python3", str(plugin / "scripts/runtime.py"), "purge", "--confirm-user-data-deletion"], env=environment, check=True, capture_output=True)
    assert not (plugin / "config.json").exists(), "Purge left a pre-migration legacy file"
    state = run()
    assert state["display"]["width"] == 520 and state["language"] == "auto", state
    print("QML preferences: legacy retirement, rapid writes, remove/reinstall and purge/restart passed")
