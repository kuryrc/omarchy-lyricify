"""Exercise production startup modules in an installed layout, without a runtime.

Offscreen Qt has no layer-shell backend, so a FloatingWindow hosts the real
SettingsPanel. Actual PanelWindow composition is checked on the local desktop.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="lyric-first-start-") as temporary:
    root = Path(temporary) / "plugin"
    root.mkdir()
    for name in ["runtime-manifest.json", "manifest.json"]:
        shutil.copy2(ROOT / name, root / name)
    for name in ["core", "ui", "assets", "fixtures"]:
        shutil.copytree(ROOT / name, root / name)
    (root / "scripts").mkdir()
    for name in ["runtime.py", "backend-launch.py"]:
        shutil.copy2(ROOT / "scripts" / name, root / "scripts" / name)
    (root / "live.qml").write_text('''
import QtQuick
import Quickshell
import Quickshell.Io
import "core" as Core
import "ui" as Ui
ShellRoot {
    id: shell
    property bool settingsOpen: false
    property int promptCount: 0
    Core.BackendClient { id: client; active: lifecycle.running }
    Core.IslandSession {
        id: lifecycle
        runtimeStatus: client.bootstrap.status
        backendStatus: client.status
        onSettingsRequested: { shell.settingsOpen = true; shell.promptCount++; }
        onExitRequested: Qt.callLater(Qt.quit)
    }
    Core.UiPreferences { id: preferences }
    FloatingWindow {
        id: window
        visible: shell.settingsOpen
        implicitWidth: 640
        implicitHeight: 760
        Ui.SettingsPanel {
            anchors.fill: parent
            backend: client
            preferences: preferences
            onCloseRequested: shell.settingsOpen = false
            onExitRequested: lifecycle.stop()
        }
    }
    IpcHandler {
        target: "lyricIsland"
        function state(): string {
            return JSON.stringify({settingsOpen: shell.settingsOpen, windowVisible: window.visible,
                available: client.ready, runtimeStatus: client.bootstrap.status,
                needsSetup: lifecycle.needsSetup, prompted: lifecycle.prompted, running: lifecycle.running,
                promptCount: shell.promptCount});
        }
        function settings(value: bool): string { shell.settingsOpen = value; return "ok"; }
        function openIsland(): string { lifecycle.start(); return "ok"; }
        function quit(): string { Qt.callLater(lifecycle.stop); return "ok"; }
    }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", WAYLAND_DISPLAY="", HYPRLAND_INSTANCE_SIGNATURE="", NO_AT_BRIDGE="1",
        **{key: temporary + "/" + key for key in ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"]})
    with (Path(temporary) / "quickshell.log").open("w+") as log:
        process = subprocess.Popen(["quickshell", "-n", "-p", str(root / "live.qml")], env=env, stdout=log, stderr=log)
        try:
            def ipc(*args):
                return subprocess.check_output(["quickshell", "ipc", "-p", str(root / "live.qml"), "call", "lyricIsland", *args], env=env, text=True, stderr=subprocess.DEVNULL, timeout=3)
            deadline = time.monotonic() + 8
            observed = None
            while time.monotonic() < deadline:
                if process.poll() is not None: break
                try:
                    observed = json.loads(ipc("state"))
                    if observed["settingsOpen"]: break
                except (subprocess.CalledProcessError, json.JSONDecodeError): pass
                time.sleep(.05)
            if not observed or not observed["settingsOpen"]:
                log.flush(); log.seek(0)
                raise AssertionError("First-install settings never appeared: " + log.read())
            assert observed["available"] is False
            assert observed["runtimeStatus"] == "needsRuntime"
            ipc("settings", "false")
            assert json.loads(ipc("state"))["settingsOpen"] is False
            assert ipc("openIsland").strip() == "ok"
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                if json.loads(ipc("state"))["settingsOpen"]: break
                time.sleep(.05)
            else:
                log.flush(); log.seek(0)
                raise AssertionError("Setup did not reopen: " + ipc("state") + log.read())
            assert json.loads(ipc("state"))["promptCount"] == 2
            ipc("quit")
            process.wait(timeout=5)
            assert process.returncode == 0
            log.flush(); log.seek(0)
            errors = [line for line in log if any(s in line for s in ["Failed to load configuration", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign"]) ]
            assert not errors, errors
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
print("Installed startup modules: missing runtime, setup UI, reopen and quit passed (offscreen host)")
