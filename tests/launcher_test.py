"""Launch routing never opens a second preview or terminates the shared shell."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shutil
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("launcher", ROOT / "scripts/launch.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTest(unittest.TestCase):
    def test_public_checkout_registers_and_removed_checkout_hides_launcher(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            # Include spaces to exercise Desktop Entry string escaping.
            script = folder / "git checkout/scripts/launch.py"
            script.parent.mkdir(parents=True)
            shutil.copy2(ROOT / "scripts/launch.py", script)
            environment = dict(os.environ, XDG_DATA_HOME=str(folder / "data"))
            subprocess.run(["python3", str(script), "--register"], env=environment, check=True)
            entry = folder / "data/applications/kuryrc.lyricify.desktop"
            def visible():
                result = subprocess.check_output(["/usr/bin/python3", "-c",
                    "from gi.repository import Gio\nimport sys\ntry: print(Gio.DesktopAppInfo.new_from_filename(sys.argv[1]) is not None)\nexcept TypeError: print(False)", str(entry)], text=True)
                return result.strip() == "True"
            self.assertTrue(visible())
            script.unlink()
            self.assertFalse(visible(), "Removed plugin left a visible broken app entry")
            shutil.copy2(ROOT / "scripts/launch.py", script)
            self.assertTrue(visible(), "Reinstallation did not restore the entry")

    def test_reuses_owned_preview_and_opens_settings(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "manifest.json").write_text(json.dumps({"id": launcher.PLUGIN_ID}))
            config = str(root / "live.qml")
            listing = subprocess.CompletedProcess([], 0, json.dumps([{"config_path": config}]))
            with patch.object(launcher.subprocess, "run", return_value=listing) as run:
                launcher.launch(True)
                calls = [c.args[0] for c in run.call_args_list]
                self.assertEqual(calls[1:], [
                    ["quickshell", "ipc", "-p", config, "call", "lyricIsland", "openIsland"],
                    ["quickshell", "ipc", "-p", config, "call", "lyricIsland", "settings", "true"],
                ])

    def test_absent_preview_enables_and_summons_native_plugin(self):
        with patch.object(launcher.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "[]")) as run:
            launcher.launch()
            calls = [c.args[0] for c in run.call_args_list]
            self.assertEqual(calls[1], ["omarchy", "plugin", "enable", launcher.PLUGIN_ID])
            self.assertEqual(calls[2][:4], ["omarchy-shell", "shell", "summon", launcher.PLUGIN_ID])


if __name__ == "__main__":
    unittest.main()
