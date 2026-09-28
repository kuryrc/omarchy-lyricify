"""Measure our preview's animation callbacks and process resources, not presentation FPS."""
import argparse
import json
import os
import pathlib
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--seconds", type=int, default=60)
args = parser.parse_args()
if not 1 <= args.seconds <= 600:
    parser.error("seconds must be in 1..600")
base = ["quickshell", "ipc", "-p", str(root / "shell.qml"), "call", "lyricIsland"]
def ipc(*args):
    return subprocess.check_output(base + list(args), text=True, timeout=5).strip()
instances = json.loads(subprocess.check_output(["quickshell", "list", "-p", str(root / "shell.qml"), "--json"], text=True))
if len(instances) != 1:
    raise SystemExit("Run exactly one make demo instance first")
pid = instances[0]["pid"]
def resources():
    stat = pathlib.Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
    return (int(stat[11]) + int(stat[12])) / os.sysconf("SC_CLK_TCK"), int(stat[21]) * os.sysconf("SC_PAGE_SIZE")

def displays():
    monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"], text=True, timeout=5))
    return [{key: m.get(key) for key in ("name", "width", "height", "scale", "refreshRate", "dpmsStatus")} for m in monitors]

def locked():
    return subprocess.check_output(["omarchy-shell", "lock", "isLocked"], text=True, timeout=5).strip() != "false"

display_start = displays()
if not display_start or not all(m["dpmsStatus"] for m in display_start):
    raise SystemExit("Wake displays before measuring visible animation")
if locked():
    raise SystemExit("Unlock the desktop before measuring visible animation")

ipc("preview", "true"); ipc("available", "true"); ipc("setShown", "true")
ipc("simulateFullscreen", "false"); ipc("expand", "false"); ipc("pause", "false")
if json.loads(ipc("state"))["fullscreen"]:
    raise SystemExit("Exit the fullscreen window on the island's display before measuring visible animation")
ipc("resetMetrics")
start = time.monotonic()
cpu_start, _ = resources()
peak_rss = 0
state_changes = []
previous_state = None
interruption = None
while time.monotonic() - start < args.seconds:
    time.sleep(max(0, min(1, args.seconds - (time.monotonic() - start))))
    _, rss = resources()
    peak_rss = max(peak_rss, rss)
    current = json.loads(ipc("state"))
    state = {key: current[key] for key in ("shown", "playing", "fullscreen", "expanded", "dragging")}
    state.update(locked=locked(), displaysOn=all(m["dpmsStatus"] for m in displays()))
    if state != previous_state:
        state_changes.append(dict(wallSeconds=round(time.monotonic()-start, 3), **state))
        previous_state = state
    if not (state["shown"] and state["playing"] and not state["expanded"] and not state["dragging"] and not state["locked"] and state["displaysOn"]):
        interruption = "Visible compact playback was interrupted; restart the measurement."
        break
cpu_end, rss = resources()
elapsed = time.monotonic() - start
report = json.loads(ipc("metrics"))
report.update(wallSeconds=elapsed, cpuPercentOneCore=100*(cpu_end-cpu_start)/elapsed,
              rssMiB=rss/1048576, peakSampledRssMiB=peak_rss/1048576,
              scenario="original fixture loop; compact; no real audio",
              displayStart=display_start, displayEnd=displays())
report["stateChanges"] = state_changes
report["requestedSeconds"] = args.seconds
report["completedRequestedDuration"] = elapsed >= args.seconds
report["callbackTimeCoverage"] = report["seconds"] / elapsed
report["validContinuousSample"] = (
    report["completedRequestedDuration"] and interruption is None
    and .95 <= report["callbackTimeCoverage"] <= 1.05
    and all(m["dpmsStatus"] for m in report["displayEnd"])
    and all(s["shown"] and s["playing"] and not s["expanded"] and not s["dragging"] and not s["locked"] and s["displaysOn"] for s in state_changes)
)
if not report["validContinuousSample"]:
    report["note"] = interruption or "Interrupted or incomplete sample; do not treat percentiles as continuous visible playback performance."
out = root / "artifacts/preview-metrics.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
raise SystemExit(0 if report["validContinuousSample"] else 1)
