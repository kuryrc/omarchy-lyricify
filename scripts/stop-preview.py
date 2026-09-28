"""Stop only the preview instance identified by this repository's absolute config path."""
import json
import pathlib
import signal
import os
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[1]
configs = {root / name for name in ("shell.qml", "live.qml")}
output = subprocess.check_output(["quickshell", "list", "--all", "--json"], text=True)
instances = json.loads(output) if output.lstrip().startswith("[") else []
for instance in instances:
    config = pathlib.Path(instance["config_path"]).resolve()
    if config not in configs:
        continue
    pid = instance["pid"]
    process = pathlib.Path(f"/proc/{pid}")
    if not process.exists(): continue
    start_time = (process / "stat").read_text().rsplit(") ", 1)[1].split()[19]
    def same_process():
        try:
            return (process / "stat").read_text().rsplit(") ", 1)[1].split()[19] == start_time
        except FileNotFoundError:
            return False
    try:
        subprocess.run(["quickshell", "kill", "-p", str(config)], check=True, timeout=3)
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        pass
    deadline = time.monotonic() + 2
    while same_process() and time.monotonic() < deadline: time.sleep(.05)
    if same_process():
        os.kill(pid, signal.SIGTERM)
        time.sleep(.5)
    if same_process():
        os.kill(pid, signal.SIGKILL)
    print(f"Stopped preview {instance['id']}")
