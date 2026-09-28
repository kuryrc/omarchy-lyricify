"""Session race tests use a separate test executable and an isolated session bus."""
import os
import json
from pathlib import Path
import subprocess
import sys
import time
import unittest
from integration_test import Client, IntegrationTest, ROOT


class LyricsRaces(IntegrationTest):
    # Reuse lifecycle only; the playback suite runs separately against the production binary.
    def test_complete_metadata_retries_without_changing_scope(self):
        self.control.Configure('{"duration":null}')
        self.client.state(lambda s: s["track"]["durationMs"] is None)
        self.client.call("settings.update", {"qqEnabled": True})
        before = self.client.state(lambda s: s["lyrics"]["status"] == "unsupported")
        self.control.Configure('{"duration":120000}')
        after = self.client.state(lambda s: s["lyrics"]["status"] == "ready")
        self.assertEqual(before["scope"], after["scope"])

    def test_offset_from_old_version_cannot_modify_same_content(self):
        self.client.call("settings.update", {"qqEnabled": True})
        before = self.client.state(lambda s: s["lyrics"]["status"] == "ready")["payload"]["lyrics"]
        document = [e["payload"]["document"] for e in self.client.events if e["event"] == "lyrics.document"][-1]
        self.assertTrue(self.client.call("lyrics.import", {"document": document})["ok"])
        after = self.client.call("session.resync")["result"]["snapshot"]["lyrics"]
        self.assertEqual(before["documentId"], after["documentId"])
        self.assertNotEqual(before["lyricVersionId"], after["lyricVersionId"])
        result = self.client.call("lyrics.set-offset", {"documentId": before["documentId"], "lyricVersionId": before["lyricVersionId"], "offsetMs": 175})
        self.assertEqual(result["error"]["code"], "stale_scope")
        self.assertEqual(self.client.call("session.resync")["result"]["snapshot"]["lyrics"]["offsetMs"], 0)

    def test_cached_lyrics_survive_sources_disabled_and_restart(self):
        self.client.call("settings.update", {"qqEnabled": True})
        before = self.client.state(lambda s: s["lyrics"]["status"] == "ready")["payload"]["lyrics"]
        self.client.call("settings.update", {"qqEnabled": False})
        self.client.close()
        self.client = Client(self.temp.name)
        after = self.client.state(lambda s: s["lyrics"]["status"] == "ready")["payload"]["lyrics"]
        self.assertEqual(before["documentId"], after["documentId"])

    def test_cache_write_failure_keeps_usable_document(self):
        cache = Path(self.temp.name) / "XDG_CACHE_HOME/omarchy-lyricify"
        cache.mkdir(parents=True, exist_ok=True)
        cache.chmod(0o555)
        try:
            self.client.call("settings.update", {"qqEnabled": True})
            state = self.client.state(lambda s: s["lyrics"]["status"] in ("ready", "error"))["payload"]
            self.assertEqual(state["lyrics"]["status"], "ready")
            self.assertEqual(state["lyrics"]["errorCode"], "cache_write_failed")
        finally:
            cache.chmod(0o755)

    def test_disabled_provider_never_searches(self):
        self.client.call("lyrics.refresh")
        self.client.state(lambda s: s["lyrics"]["status"] == "disabled")
        self.assertEqual(self.client.call("lyrics.candidates")["result"]["candidates"], [])

    def test_late_a_cannot_replace_b_or_block_control(self):
        self.control.Configure('{"title":"Slow original A","track":3}')
        self.client.state(lambda s: s["track"]["title"] == "Slow original A")
        self.assertTrue(self.client.call("settings.update", {"qqEnabled": True})["ok"])
        started = time.monotonic()
        self.assertTrue(self.client.call("playback.pause")["ok"])
        self.assertLess(time.monotonic() - started, .4)
        self.control.Configure('{"title":"Original B","track":4}')
        self.client.state(lambda s: s["track"]["title"] == "Original B" and s["lyrics"]["status"] == "ready")
        time.sleep(.8)
        state = self.client.call("session.resync")["result"]["snapshot"]
        self.assertEqual(state["track"]["title"], "Original B")
        last = [e for e in self.client.events if e["event"] == "lyrics.document"][-1]
        self.assertEqual(last["payload"]["document"]["lines"][0]["text"], "Original B")

    def test_import_wins_over_late_search_and_disable_cancels(self):
        self.control.Configure('{"title":"Slow original","track":7}')
        self.client.state(lambda s: s["track"]["title"] == "Slow original")
        self.client.call("settings.update", {"qqEnabled": True})
        imported = self.client.call("lyrics.import", {"text": "[00:00]My original choice"})
        self.assertTrue(imported["ok"])
        time.sleep(.8)
        state = self.client.call("session.resync")["result"]["snapshot"]
        self.assertEqual(state["lyrics"]["documentId"], imported["result"]["documentId"])
        self.client.call("lyrics.refresh")
        self.client.call("settings.update", {"qqEnabled": False})
        time.sleep(.8)
        state = self.client.call("session.resync")["result"]["snapshot"]
        self.assertEqual(state["lyrics"]["documentId"], imported["result"]["documentId"])

    def test_rapid_track_changes_keep_last_document(self):
        self.assertTrue(self.client.call("settings.update", {"qqEnabled": True})["ok"])
        for index in range(10):
            title = f"Slow original {index}" if index % 2 == 0 else f"Original {index}"
            self.control.Configure(json.dumps({"title": title, "track": 20 + index}))
            self.client.state(lambda s: s['track'] is not None and s['track']['title'] == title
                              and (index % 2 != 0 or s['lyrics']['status'] == 'loading'))
        current = self.client.state(lambda s: s['track']['title'] == title and s['lyrics']['status'] == 'ready')
        document = current['payload']['lyrics']['documentId']
        # The slow fixture deliberately ignores cancellation. Let old work
        # finish, then verify both the snapshot and the last delivered document.
        time.sleep(.8)
        snapshot = self.client.call('session.resync')['result']['snapshot']
        self.assertEqual(snapshot['track']['title'], title)
        self.assertEqual(snapshot['lyrics']['documentId'], document)
        last = [e for e in self.client.events if e['event'] == 'lyrics.document'][-1]
        self.assertEqual(last['scope'], current['scope'])
        self.assertEqual(last['payload']['document']['lines'][0]['text'], title)
        self.assertTrue(self.client.call('playback.play')['ok'])
        self.client.state(lambda s: s['playback']['status'] == 'Playing')

    def test_provider_error_keeps_player_control(self):
        self.control.Configure('{"title":"Limited original","track":8}')
        self.client.state(lambda s: s["track"]["title"] == "Limited original")
        self.client.call("settings.update", {"qqEnabled": True})
        state = self.client.state(lambda s: s["lyrics"]["status"] == "error")
        self.assertEqual(state["payload"]["lyrics"]["errorCode"], "rate_limited")
        self.assertTrue(self.client.call("playback.pause")["ok"])


if __name__ == "__main__":
    if "--isolated" not in sys.argv:
        env = dict(os.environ, LYRIC_ISLAND_TEST_PROGRAM=str(ROOT / "backend/LyricIsland.Tests/bin/Release/net10.0/LyricIsland.Tests.dll"))
        raise SystemExit(subprocess.call(["dbus-run-session", "--", "/usr/bin/python3", __file__, "--isolated"], cwd=ROOT, env=env))
    suite = unittest.TestSuite(LyricsRaces(name) for name in LyricsRaces.__dict__ if name.startswith("test_"))
    raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
