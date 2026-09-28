"""Read and exercise only this project's running demo through its scoped IPC."""
import json
import os
import pathlib
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[1]
def ipc(method, *args):
    deadline = time.monotonic() + 5
    while True:
        result = subprocess.run(["quickshell", "ipc", "-p", str(root / "shell.qml"), "call", "lyricIsland", method,
                                 *[str(a).lower() if isinstance(a, bool) else str(a) for a in args]],
                                capture_output=True, text=True, check=True, timeout=5)
        if "Not ready to accept queries" not in result.stdout:
            return result.stdout.strip()
        if time.monotonic() > deadline:
            raise RuntimeError("Preview is still reloading")
        time.sleep(.1)
def state():
    return json.loads(ipc("state"))
def wait_for(predicate, timeout=2):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        if predicate(state()): return
        time.sleep(.05)
    raise AssertionError(state())

original_offset = state()["offsetX"]
if subprocess.check_output(["omarchy-shell", "lock", "isLocked"], text=True).strip() != "false":
    raise SystemExit("Desktop is locked; unlock before running the visible Wayland smoke test")
if state()["fullscreen"]:
    raise SystemExit("Exit the fullscreen window on the island's display before the visible smoke test")
try:
    ipc("preview", True); ipc("setShown", True); ipc("available", True)
    ipc("simulateFullscreen", False); ipc("expand", False)
    ipc("pause", True); ipc("seek", 2000)
    wait_for(lambda s: s["shown"] and s["lineIndex"] == 0)
    time.sleep(.2)
    assert state()["positionMs"] == 2000
    ipc("seek", 18000); assert state()["lineIndex"] == 2
    wait_for(lambda s: s["render"]["scrollPx"] > 0 and s["render"]["highlightPx"] > 0)
    render = state()["render"]
    assert render["scrollPx"] <= render["textWidth"] - render["viewportWidth"]
    ipc("seek", 20000)
    wait_for(lambda s: abs(s["render"]["scrollPx"] - min(
        s["render"]["textWidth"] - s["render"]["viewportWidth"],
        s["render"]["highlightPx"] - s["render"]["viewportWidth"] * .58)) < .1)
    ipc("seek", 25000)
    wait_for(lambda s: s["lineIndex"] == 3 and not s["render"]["wordSynced"])
    ipc("seek", 6600); assert state()["lineIndex"] == -1
    ipc("seek", 2000); assert state()["lineIndex"] == 0
    ipc("expand", True)
    wait_for(lambda s: s["expanded"] and s["height"] > 340)
    ipc("expand", False)
    wait_for(lambda s: s["collapsed"], timeout=6)
    ipc("pause", False)
    wait_for(lambda s: s["playing"] and not s["collapsed"] and s["positionMs"] > 2000)
    ipc("simulateFullscreen", True); wait_for(lambda s: not s["shown"])
    count = json.loads(ipc("metrics"))["samples"]
    time.sleep(.2)
    assert json.loads(ipc("metrics"))["samples"] == count
    ipc("simulateFullscreen", False); wait_for(lambda s: s["shown"])
    ipc("available", False); wait_for(lambda s: not s["shown"])
    ipc("available", True); wait_for(lambda s: s["shown"])
    ipc("movePreview", -original_offset + 12, False)
    wait_for(lambda s: s["dragging"] and s["snapped"] and s["offsetX"] == 0)
    ipc("movePreview", -original_offset + 24, False)
    assert state()["offsetX"] == 0
    ipc("movePreview", -original_offset, True)
    wait_for(lambda s: not s["dragging"] and s["offsetX"] == 0 and not s["positionError"])
    directory = pathlib.Path(os.environ.get("LYRIC_ISLAND_STATE_DIR") or
                             (os.environ.get("XDG_STATE_HOME", str(pathlib.Path.home() / ".local/state")) + "/omarchy-lyricify"))
    file = directory / "preview-position.json"
    deadline = time.monotonic() + 3
    while not file.exists() or json.loads(file.read_text())["offsetX"] != 0:
        if time.monotonic() > deadline: raise AssertionError("Position was not saved")
        time.sleep(.05)
    print("PASS: pause, seek, gaps, expand, collapse, resume, fullscreen/player exit simulation, center snap and position persistence")
finally:
    ipc("movePreview", original_offset - state()["offsetX"], True)
    ipc("available", True); ipc("simulateFullscreen", False); ipc("expand", False)
    ipc("offset", 0); ipc("seek", 1000); ipc("pause", False)
