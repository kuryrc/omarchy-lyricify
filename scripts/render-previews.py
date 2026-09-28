"""Render actual QML with original fixtures; capture no desktop or account data."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
output = ROOT / "assets/previews"
output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="lyric-preview-render-") as temporary:
    root = Path(temporary)
    for name in ("core", "ui", "assets", "fixtures"):
        shutil.copytree(ROOT / name, root / name)
    qml = '''import QtQuick
import Quickshell
import "core" as Core
import "ui" as Ui
ShellRoot {
    id: root
    property int captured: 0
    function capture(item, path, width, height) {
        item.grabToImage(function(result) {
            if (!result.saveToFile(path)) throw new Error("Preview capture failed");
            root.captured++;
            if (root.captured === 2) Qt.quit();
        }, Qt.size(width, height));
    }
    Core.DemoPlayback { id: player; tickEnabled: false; demoPosition: 3300; property string language: "en"; property string statusText: "Original animation fixture" }
    Core.UiPreferences { id: preferences; language: "en" }
    QtObject {
        id: backend
        property bool ready: false
        property string status: "stopped"
        property var scope: null
        property var snapshot: null
        property var bootstrap: ({ready: false, updatePending: false, error: "", downloadAvailable: false, status: "needsRuntime"})
    }
    FloatingWindow {
        visible: true
        implicitWidth: 760; implicitHeight: 640
        color: "#14191f"
        Rectangle {
            id: overview
            anchors.fill: parent
            color: "#14191f"
            Text { x: 105; y: 20; text: "LYRIC ISLAND  /  COMPACT"; color: "#92a6a4"; font.pixelSize: 11; font.letterSpacing: 1.6 }
            Ui.IslandShape {
                x: 90; y: 52; width: 580; height: 86
                Ui.IslandContent { anchors.fill: parent; playback: player; motion: false }
            }
            Text { x: 105; y: 197; text: "EXPANDED  /  PLAYBACK & LYRICS"; color: "#92a6a4"; font.pixelSize: 11; font.letterSpacing: 1.6 }
            Ui.IslandShape {
                x: 90; y: 230; width: 580; height: 348
                Ui.IslandContent { anchors.fill: parent; playback: player; expanded: true; motion: false }
            }
        }
    }
    FloatingWindow {
        visible: true
        implicitWidth: 680; implicitHeight: 810
        color: "#14191f"
        Rectangle {
            id: settings
            anchors.fill: parent
            color: "#14191f"
            Ui.SettingsPanel {
                x: 20; y: 20; width: 640; height: 770
                backend: backend
                preferences: preferences
                demo: true
                settings: ({sources: [
                    {id: "qq", name: "QQ Music", chineseName: "QQ 音乐", enabled: false},
                    {id: "netease", name: "NetEase Music", chineseName: "网易云音乐", enabled: false}
                ]})
            }
        }
    }
    Timer {
        interval: 1000; running: true
        onTriggered: {
            root.capture(overview, OUTPUT_ISLAND, 1520, 1280);
            root.capture(settings, OUTPUT_SETTINGS, 1360, 1620);
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.error("Capture timed out"); Qt.quit(); } }
}'''.replace("OUTPUT_ISLAND", json.dumps(str(ROOT / "preview.png"))).replace("OUTPUT_SETTINGS", json.dumps(str(output / "settings.png")))
    entry = root / "shell.qml"
    entry.write_text(qml)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", WAYLAND_DISPLAY="", NO_AT_BRIDGE="1", XDG_CONFIG_HOME=str(root / "config"))
    result = subprocess.run(["quickshell", "-n", "-p", str(entry)], env=env, capture_output=True, text=True, timeout=12)
    if result.returncode or "Error" in result.stdout + result.stderr or not all(path.is_file() for path in (ROOT / "preview.png", output / "settings.png")):
        raise SystemExit(result.stdout + result.stderr)
print("Rendered original fixture using production QML: preview.png, assets/previews/settings.png")
