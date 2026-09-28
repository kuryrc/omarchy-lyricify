"""Format atomically so a running Quickshell never reads a truncated QML file."""
import pathlib
import subprocess
import tempfile
import os

root = pathlib.Path(__file__).resolve().parents[1]
paths = [root / name for name in ("LyricIsland.qml", "shell.qml", "live.qml")]
for folder in ("core", "ui"):
    paths.extend(sorted((root / folder).glob("*.qml")))
for path in paths:
    data = subprocess.check_output(["qmlformat", str(path)])
    if data == path.read_bytes():
        continue
    with tempfile.NamedTemporaryFile(dir=path.parent, suffix=".tmp", delete=False) as temp:
        temp.write(data)
        temp_path = pathlib.Path(temp.name)
    temp_path.chmod(path.stat().st_mode)
    os.replace(temp_path, path)
