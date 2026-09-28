"""Real QML client, real backend, fake MPRIS on an isolated bus; no desktop window."""
import json
import os
from pathlib import Path
import signal
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
if "--isolated" not in sys.argv:
    raise SystemExit(subprocess.call(["dbus-run-session", "--", "/usr/bin/python3", __file__, "--isolated"], cwd=ROOT))

import dbus
fake = subprocess.Popen(["/usr/bin/python3", "tests/fake_mpris.py", "org.mpris.MediaPlayer2.spotify"], stdout=subprocess.PIPE, text=True)
assert fake.stdout.readline().strip() == "ready"
control = dbus.Interface(dbus.SessionBus().get_object("org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2"), "org.lyricisland.Test")
with tempfile.TemporaryDirectory() as temporary:
    env = dict(os.environ, LYRIC_ISLAND_TEST_SUITE="live", QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", NO_AT_BRIDGE="1", WAYLAND_DISPLAY="", DBUS_SYSTEM_BUS_ADDRESS=os.environ["DBUS_SESSION_BUS_ADDRESS"], **{key: temporary + "/" + key for key in ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"]})
    config = ROOT / "test.qml"
    with open(temporary + "/quickshell.log", "w+") as log:
        qs = subprocess.Popen(["quickshell", "-n", "-p", str(config)], env=env, stdout=log, stderr=log)
        def ipc(*args):
            return subprocess.check_output(["quickshell", "ipc", "-p", str(config), "call", "liveTest", *args], env=env, text=True, timeout=4).strip()
        def state(): return json.loads(ipc("state"))
        def until(predicate, timeout=7):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                try:
                    value = state()
                    if predicate(value): return value
                except (subprocess.CalledProcessError, json.JSONDecodeError): pass
                time.sleep(.04)
            log.flush(); log.seek(0)
            raise AssertionError("QML state timeout: " + log.read())
        def backend_pid():
            pids = Path(f"/proc/{qs.pid}/task/{qs.pid}/children").read_text().split()
            for pid in pids:
                try:
                    args = Path(f"/proc/{pid}/cmdline").read_bytes()
                    if b"LyricIsland.Backend" in args and b"--stdio" in args: return int(pid)
                except FileNotFoundError: pass
            return None
        try:
            initial = until(lambda s: s["status"] == "ready" and s["available"])
            ipc('command', 'lyrics.import', json.dumps({'text':'[00:00]Original start\n[00:40]Original seek line\n[01:00]Original wake line'}))
            imported = until(lambda s: bool(s['documentId']))['documentId']
            ipc("command", "playback.play", "{}")
            until(lambda s: s["playing"])
            samples = []
            for _ in range(40):
                started = time.monotonic()
                displayed = state()["positionMs"]
                oracle = json.loads(control.Inspect())["positionMs"]
                samples.append({"absoluteErrorMs": abs(displayed - oracle), "observationWindowMs": (time.monotonic() - started) * 1000})
                time.sleep(.04)
            p95 = sorted(s["absoluteErrorMs"] for s in samples)[int(len(samples) * .95) - 1]
            assert p95 <= 100, p95
            # Both island controls and seeks in the player can report Playing
            # before Position advances. An immediate sample alone stays ahead.
            control.Configure('{"seek_buffer_ms":220}')
            player = dbus.Interface(dbus.SessionBus().get_object("org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2"), "org.mpris.MediaPlayer2.Player")
            seek_samples = []
            for source, target in [("island", 30000), ("player", 45000)]:
                if source == "island":
                    ipc("command", "playback.seek", json.dumps({"positionMs": target}))
                else:
                    player.SetPosition(dbus.ObjectPath('/test/track1'), dbus.Int64(target * 1000))
                time.sleep(.5)
                for _ in range(6):
                    displayed = state()["positionMs"]
                    oracle = json.loads(control.Inspect())["positionMs"]
                    error = abs(displayed - oracle)
                    seek_samples.append({"source": source, "absoluteErrorMs": error})
                    assert error <= 100, f"{source} buffered seek did not settle: {error:.1f} ms"
                    time.sleep(.04)
            time.sleep(.5)
            reads = json.loads(control.Inspect())["getAllCalls"]
            time.sleep(.6)
            assert json.loads(control.Inspect())["getAllCalls"] - reads <= 1, "Fast sampling continued after the transition"
            # Real transport backlog: the backend keeps sampling while the QML
            # event loop is stopped. Replaying those events must not set an old anchor.
            os.kill(qs.pid, signal.SIGSTOP)
            try:
                control.Configure('{"position":45000}')
                time.sleep(1.3)
            finally:
                os.kill(qs.pid, signal.SIGCONT)
            resumed = time.monotonic()
            recovery = until(lambda s: s["playing"] and abs(s["positionMs"] - json.loads(control.Inspect())["positionMs"]) <= 100, timeout=.5)
            recovery_ms = (time.monotonic() - resumed) * 1000
            assert recovery['documentId'] == imported and recovery['lineIndex'] == 1
            time.sleep(.2)
            assert abs(state()["positionMs"] - json.loads(control.Inspect())["positionMs"]) <= 100
            control.Sleep(True)
            until(lambda s: not s['playing'])
            control.Configure('{"position":65000}')
            control.Sleep(False)
            wake_started = time.monotonic()
            awake = until(lambda s: s['playing'] and abs(s['positionMs'] - json.loads(control.Inspect())['positionMs']) <= 100, timeout=.5)
            assert awake['documentId'] == imported and awake['lineIndex'] == 2
            wake_ms = (time.monotonic() - wake_started) * 1000
            ipc("ticking", "false")
            time.sleep(.8)
            ipc("ticking", "true")
            shown_at = time.monotonic()
            until(lambda s: s["playing"] and abs(s['positionMs'] - json.loads(control.Inspect())['positionMs']) <= 100, timeout=.5)
            show_ms = (time.monotonic() - shown_at) * 1000
            # The player may restart under the same well-known D-Bus name.
            # QML must discard its old scope and restore the saved document
            # without restarting the backend or accepting old controls.
            reconnects = []
            stable_backend = backend_pid()
            for _ in range(3):
                old_scope = state()['scope']
                fake.terminate(); fake.wait(timeout=3); fake.stdout.close()
                absent = until(lambda s: not s['available'])
                assert not absent['canToggle'] and not absent['documentId']
                fake = subprocess.Popen(["/usr/bin/python3", "tests/fake_mpris.py", "org.mpris.MediaPlayer2.spotify"], stdout=subprocess.PIPE, text=True)
                assert fake.stdout.readline().strip() == "ready"
                control = dbus.Interface(dbus.SessionBus().get_object("org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2"), "org.lyricisland.Test")
                connected_at = time.monotonic()
                restored_player = until(lambda s: s['available'] and s['documentId'] == imported and s['canToggle'])
                assert restored_player['scope']['playerInstanceId'] != old_scope['playerInstanceId']
                assert backend_pid() == stable_backend
                ipc('command', 'playback.play', '{}')
                until(lambda s: s['playing'] and abs(s['positionMs'] - json.loads(control.Inspect())['positionMs']) <= 100)
                reconnects.append({'recoveryMs': (time.monotonic() - connected_at) * 1000,
                                   'savedDocumentRestored': True, 'backendPreserved': True})
            child = backend_pid(); assert child
            epoch = state()["epoch"]
            os.kill(child, signal.SIGKILL)
            recovering = until(lambda s: s["status"] == "recovering")
            assert not recovering["canToggle"]
            restored = until(lambda s: s["status"] == "ready" and s["epoch"] != epoch and s["available"])
            assert restored["available"]
            ipc("enabled", "false")
            until(lambda s: s["status"] == "stopped" and not s["canToggle"])
            end = time.monotonic() + 4
            while backend_pid() and time.monotonic() < end: time.sleep(.05)
            assert backend_pid() is None, "Owned backend survived disable"
            ipc("enabled", "true")
            until(lambda s: s["status"] == "ready" and s["available"])
            report = {"oracle": "isolated fake MPRIS monotonic position", "sampleCount": len(samples), "p95AbsoluteErrorMs": p95,
                      "blockedUiRecoveryMs": recovery_ms,
                      "bufferedSeekSamples": seek_samples,
                      "sleepSignalRecoveryMs": wake_ms,
                      "showRecoveryMs": show_ms, "playerReconnects": reconnects,
                      "maxObservationWindowMs": max(s["observationWindowMs"] for s in samples), "crashRecovery": True,
                      "disableStopsChild": True, "samples": samples}
            (ROOT / "artifacts/qml-clock-validation.json").write_text(json.dumps(report, indent=2) + "\n")
            print(f"Real QML/backend: clock p95 {p95:.2f} ms, crash recovery and disable/re-enable passed")
        finally:
            qs.terminate(); qs.wait(timeout=5)
            fake.terminate(); fake.wait(timeout=3); fake.stdout.close()
