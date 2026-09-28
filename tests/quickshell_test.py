"""Use the actual Quickshell engine for its statically linked QML types."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--resync", action="store_true", help="Run only clock resynchronization regressions")
parser.add_argument("--isolated", action="store_true", help=argparse.SUPPRESS)
args = parser.parse_args()
if not args.isolated:
    raise SystemExit(subprocess.call(["dbus-run-session", "--", sys.executable, __file__, *sys.argv[1:], "--isolated"], cwd=ROOT))

with tempfile.TemporaryDirectory() as temporary:
    env = dict(os.environ, LYRIC_ISLAND_TEST_SUITE="protocol", LYRIC_ISLAND_TEST_FILTER="",
               QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", NO_AT_BRIDGE="1", WAYLAND_DISPLAY="",
               **{key: temporary + "/" + key for key in ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"]})
    command = ["quickshell", "-n", "-p", str(ROOT / "test.qml")]
    if not args.resync:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        if result.returncode or "PROTOCOL_TESTS_PASS 8" not in output or "PROTOCOL_TESTS_FAIL" in output:
            raise SystemExit(output)
        print("Quickshell receive/clock regression: 8 passed")

    env["LYRIC_ISLAND_TEST_FILTER"] = "resync"
    with open(temporary + "/quickshell.log", "w+") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=log)

        def ipc(*values):
            result = subprocess.run(["quickshell", "ipc", "-p", str(ROOT / "test.qml"),
                                     "call", "resyncTest", *map(str, values)],
                                    env=env, text=True, capture_output=True, timeout=3, check=True)
            if not result.stdout.strip():
                raise AssertionError("Empty IPC response for " + str(values) + ": " + result.stderr)
            if values[0] in ("inspect", "sample", "reveal", "stall", "reply") and not result.stdout.strip().startswith("{"):
                raise AssertionError("Invalid IPC response for " + str(values) + ": " + result.stdout + result.stderr)
            return result.stdout.strip()

        def inspect():
            return json.loads(ipc("inspect"))

        def until(predicate):
            end = time.monotonic() + 2
            while time.monotonic() < end:
                try:
                    state = inspect()
                    if predicate(state):
                        return state
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    pass
                time.sleep(.02)
            raise AssertionError("QML state did not reach the expected resync state")

        def reset(position=10000):
            ipc("reset")
            state = json.loads(ipc("sample", position, 1))
            assert state["playing"]

        def reply(request, position=60000, discontinuity=2, code=""):
            return json.loads(ipc("reply", request, position, discontinuity, code))

        def recover(position=60000, discontinuity=2):
            request = until(lambda s: bool(s["request"]))["request"]
            state = reply(request, position, discontinuity)
            assert state["playing"] and position <= state["position"] < position + 500, state
            assert not state["request"]

        def backpressure():
            reset()
            pending = [ipc("request", "player.list") for _ in range(32)]
            assert all(pending)
            state = json.loads(ipc("stall"))
            assert not state["playing"] and state["position"] < 20000, "Buffered events restored the stalled clock"
            time.sleep(.35)
            state = inspect()
            assert not state["playing"] and not state["request"] and len(state["pending"]) == 32
            reply(pending[0])
            request = until(lambda s: bool(s["request"]))["request"]
            time.sleep(.35)
            state = inspect()
            assert state["request"] == request and len(state["pending"]) == 32, "Duplicate resync request"
            state = json.loads(ipc("sample", 40000, 1))
            assert not state["playing"], "Buffered event bypassed the pending response"
            recover()

        def failed_response(code):
            reset()
            request = json.loads(ipc("reveal"))["request"]
            assert request
            state = reply(request, code=code)
            assert not state["request"], "Resync failure retried immediately without a delay"
            state = json.loads(ipc("sample", 20000, 1))
            assert not state["playing"], code + " allowed a buffered event to restore the clock"
            recover()

        def superseded_response():
            for start, target in [(10000, 60000), (80000, 20000)]:
                reset(start)
                request = json.loads(ipc("reveal"))["request"]
                assert request
                ipc("sample", target, 2)
                state = reply(request, start, 1)
                assert not state["playing"], "An old resync response restored an obsolete seek position"
                assert state["snapshot"]["position"]["discontinuityId"] == 2
                recover(target)

        failures = []
        try:
            until(lambda s: True)
            for name, test in [("queue backpressure", backpressure),
                               ("request timeout", lambda: failed_response("timeout")),
                               ("request error", lambda: failed_response("backend_unavailable")),
                               ("seek response ordering", superseded_response)]:
                try:
                    test()
                    print("PASS " + name, flush=True)
                except AssertionError as error:
                    failures.append(name + ": " + str(error))
                    print("FAIL " + failures[-1], flush=True)
            if failures:
                raise AssertionError("; ".join(failures))
            print("Quickshell resync regression: 4 passed")
        except Exception:
            log.flush(); log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            try:
                ipc("quit")
                process.wait(timeout=3)
            except (subprocess.SubprocessError, OSError):
                process.kill(); process.wait(timeout=3)
