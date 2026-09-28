"""Use the actual Quickshell engine for its statically linked QML types."""
import os
import subprocess

result = subprocess.run(["quickshell", "-n", "-p", "test.qml"],
    env=dict(os.environ, LYRIC_ISLAND_TEST_SUITE="protocol", QT_QPA_PLATFORM="offscreen", WAYLAND_DISPLAY=""),
    capture_output=True, text=True, timeout=15)
output = result.stdout + result.stderr
if result.returncode or "PROTOCOL_TESTS_PASS 8" not in output or "PROTOCOL_TESTS_FAIL" in output:
    raise SystemExit(output)
print("Quickshell receive/clock regression: 8 passed")
