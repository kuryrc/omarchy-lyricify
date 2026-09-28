"""Parse our QML with the installed Qt formatter; runtime checks remain separate."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
paths = [root / name for name in ("LyricIsland.qml", "shell.qml", "live.qml")]
for folder in ("core", "ui"):
    paths.extend(sorted((root / folder).glob("*.qml")))
for path in paths:
    subprocess.run(["qmlformat", str(path)], stdout=subprocess.DEVNULL, check=True)
subprocess.run(["qmllint", *map(str, paths)], check=True)
print(f"QML syntax OK: {len(paths)} files (runtime loading tested separately)")
