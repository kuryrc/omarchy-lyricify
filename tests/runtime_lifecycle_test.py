"""Actual packaged runtime: ready -> purge -> prepare -> ready, isolated from Spotify."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
if "--isolated" not in sys.argv:
    raise SystemExit(subprocess.call(["dbus-run-session", "--", sys.executable, __file__, "--isolated"], cwd=ROOT))
sys.path.insert(0, str(ROOT / "scripts"))
from runtime import RuntimeManager

version = (ROOT / "VERSION").read_text().strip()
archive = ROOT / "artifacts" / f"lyric-island-{version}-linux-x64.tar.gz"
with tempfile.TemporaryDirectory(prefix="lyric-lifecycle-") as temporary:
    folder = Path(temporary)
    plugin = folder / "plugin"
    plugin.mkdir()
    for name in ("core", "ui", "assets", "scripts"):
        shutil.copytree(ROOT / name, plugin / name, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy2(ROOT / "runtime-manifest.json", plugin / "runtime-manifest.json")
    for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
        os.environ[key] = str(folder / key)
    installed = RuntimeManager(plugin).install(archive)
    assert installed["status"] == "ready"
    (plugin / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "core" as Core
import "ui" as Ui
ShellRoot {
    Core.BackendClient { id: client }
    Core.UiPreferences { id: preferences }
    FloatingWindow {
        visible: true
        Ui.SettingsPanel { anchors.fill: parent; backend: client; preferences: preferences }
    }
    IpcHandler {
        target: "lifecycleTest"
        function state(): string {
            return JSON.stringify({runtimeStatus:client.bootstrap.status, runtimeReady:client.bootstrap.ready,
                backendStatus:client.status, backendReady:client.ready});
        }
        function purge(): void { client.purgeData(); }
        function retry(): void { client.retry(); }
    }
}''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", WAYLAND_DISPLAY="", NO_AT_BRIDGE="1")
    with (folder / "log").open("w+") as log:
        process = subprocess.Popen(["quickshell", "-n", "-p", str(plugin / "shell.qml")], stdout=log, stderr=log, env=env)
        try:
            def ipc(method):
                return subprocess.check_output(["quickshell", "ipc", "-p", str(plugin / "shell.qml"), "call", "lifecycleTest", method], env=env, text=True, stderr=subprocess.DEVNULL, timeout=3)
            def until(predicate):
                end = time.monotonic() + 10
                while time.monotonic() < end:
                    try:
                        state = json.loads(ipc("state"))
                        if predicate(state): return state
                    except (subprocess.CalledProcessError, json.JSONDecodeError): pass
                    time.sleep(.05)
                log.flush(); log.seek(0)
                raise AssertionError("Lifecycle did not settle: " + log.read())
            until(lambda s: s["backendReady"])
            ipc("purge")
            state = until(lambda s: s["runtimeStatus"] == "purged")
            assert not state["backendReady"] and not state["runtimeReady"], state
            assert not Path(installed["path"]).exists()
            ipc("retry")
            state = until(lambda s: s["runtimeStatus"] == "needsRuntime")
            assert not state["backendReady"]
            RuntimeManager(plugin).install(archive)
            ipc("retry")
            until(lambda s: s["backendReady"] and s["runtimeReady"])
            print("Packaged runtime: purge clears readiness, retry exposes setup, reinstall reconnects without QML restart")
        finally:
            process.terminate()
            process.wait(timeout=5)

# Slow preparation is an Adapter at the process seam. The actual QML scheduler
# must stop it and run purge, not silently discard the user's intent.
with tempfile.TemporaryDirectory(prefix="lyric-busy-purge-") as temporary:
    folder = Path(temporary)
    shutil.copytree(ROOT / "core", folder / "core")
    (folder / "scripts").mkdir()
    (folder / "scripts/runtime.py").write_text('''import json, sys, time
from pathlib import Path
operation = sys.argv[1]
with (Path(__file__).parents[1] / "operations").open("a") as log:
    log.write(operation + "\\n")
print(json.dumps({"ok": True, "status": {"status":"needsRuntime", "install":"downloading", "purge":"purged"}[operation]}), flush=True)
if operation == "install": time.sleep(10)
''')
    (folder / "shell.qml").write_text('''import QtQuick
import Quickshell
import "core" as Core
ShellRoot {
    id: root
    property int step: 0
    Core.RuntimeBootstrap { id: runtime }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (root.step === 0 && runtime.status === "needsRuntime") {
                root.step = 1; runtime.download();
            } else if (root.step === 1 && runtime.status === "downloading" && runtime.received) {
                root.step = 2; runtime.purge();
            } else if (root.step === 2 && runtime.status === "purged") {
                console.log("BUSY_PURGE_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.quit() }
}''')
    result = subprocess.run(["quickshell", "-n", "-p", str(folder / "shell.qml")],
        env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", WAYLAND_DISPLAY="", NO_AT_BRIDGE="1"),
        capture_output=True, text=True, timeout=8)
    assert "BUSY_PURGE_PASS" in result.stdout + result.stderr, result.stdout + result.stderr
    assert (folder / "operations").read_text().splitlines() == ["status", "install", "purge"]
    print("Busy runtime: pending download cancelled before purge, no lost request")
