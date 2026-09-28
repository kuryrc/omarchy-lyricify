"""Real backend process against a real isolated D-Bus service (no network)."""
import json
import os
import pathlib
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class Client:
    def __init__(self, directory):
        env = dict(os.environ, **{key: directory + "/" + key for key in ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"]})
        program = os.environ.get("LYRIC_ISLAND_TEST_PROGRAM", str(ROOT / "backend/LyricIsland.Backend/bin/Release/net10.0/LyricIsland.Backend.dll"))
        self.p = subprocess.Popen(["dotnet", program, "--stdio"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        self.messages = queue.Queue()
        self.events, self.responses, self.scope, self.epoch, self.next_id = [], {}, None, "", 0
        def read():
            for line in self.p.stdout:
                self.messages.put(json.loads(line))
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        self.state_cursor = 0
        hello = self.call("hello", {"supportedProtocols": [2], "clientVersion": "test", "clientInstanceId": "test"})
        assert hello["ok"], hello
        self.epoch = hello["backendSessionId"]

    def pump(self, timeout=5):
        item = self.messages.get(timeout=timeout)
        if item["type"] == "event":
            self.events.append(item)
            if item["event"] == "session.state":
                self.scope = item.get("scope")
        else:
            self.responses[item.get("id")] = item
        return item

    def send(self, op, params=None, **extra):
        self.next_id += 1
        msg = {"version": 2, "type": "request", "id": str(self.next_id), "op": op, "params": params or {}, "backendSessionId": self.epoch, "scope": self.scope, **extra}
        self.p.stdin.write(json.dumps(msg) + "\n"); self.p.stdin.flush()
        return msg

    def response(self, id):
        deadline = time.monotonic() + 6
        while id not in self.responses:
            self.pump(max(.01, deadline - time.monotonic()))
        return self.responses.pop(id)

    def call(self, op, params=None, **extra):
        return self.response(self.send(op, params, **extra)["id"])

    def state(self, predicate=lambda s: s["player"] is not None):
        deadline = time.monotonic() + 6
        while True:
            while self.state_cursor < len(self.events):
                item = self.events[self.state_cursor]
                self.state_cursor += 1
                if item.get("event") == "session.state" and predicate(item["payload"]):
                    return item
            self.pump(max(.01, deadline - time.monotonic()))

    def close(self):
        if self.p.poll() is None:
            self.p.stdin.close()
            self.p.wait(timeout=6)
        self.reader.join(timeout=1)
        if self.p.stderr.closed:
            return
        error = self.p.stderr.read()
        self.p.stdout.close(); self.p.stderr.close()
        if self.p.returncode != 0:
            raise AssertionError(f"Backend exit {self.p.returncode}: {error}")


class IntegrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import dbus
        os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = os.environ['DBUS_SESSION_BUS_ADDRESS']
        cls.bus = dbus.SessionBus()
        cls.fake = subprocess.Popen(["/usr/bin/python3", str(ROOT / "tests/fake_mpris.py"), "org.mpris.MediaPlayer2.spotify"], stdout=subprocess.PIPE, text=True)
        assert cls.fake.stdout.readline().strip() == "ready"
        cls.control = dbus.Interface(cls.bus.get_object("org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2"), "org.lyricisland.Test")

    @classmethod
    def tearDownClass(cls):
        cls.fake.terminate(); cls.fake.wait(timeout=5); cls.fake.stdout.close()

    def setUp(self):
        self.control.Configure('{"reset":true}')
        self.temp = tempfile.TemporaryDirectory()
        self.client = Client(self.temp.name)
        self.initial = self.client.state()

    def tearDown(self):
        self.client.close(); self.temp.cleanup()

    def test_hello_and_initial_snapshot(self):
        state = self.initial["payload"]
        self.assertEqual(state["player"]["applicationId"], "spotify")
        self.assertEqual(state["playback"]["status"], "Paused")
        self.assertEqual(state["track"]["identityStrength"], "strong")
        self.assertTrue(state["position"]["known"])
        self.assertAlmostEqual(state["position"]["positionMsAtSend"], 1500, delta=1)

    def test_play_pause_seek_and_rate(self):
        self.assertTrue(self.client.call("playback.play")["ok"])
        state = self.client.state(lambda s: s["playback"]["status"] == "Playing")
        self.control.Configure('{"rate":2}')
        self.client.state(lambda s: s["playback"]["rate"] == 2)
        self.assertTrue(self.client.call("playback.seek", {"positionMs": 25000})["ok"])
        moved = self.client.state(lambda s: s["position"]["positionMsAtSend"] >= 25000)
        self.assertGreater(moved["payload"]["position"]["discontinuityId"], state["payload"]["position"]["discontinuityId"])
        self.assertTrue(self.client.call("playback.pause")["ok"])
        paused = self.client.state(lambda s: s["playback"]["status"] == "Paused")
        oracle = json.loads(self.control.Inspect())["positionMs"]
        self.assertAlmostEqual(oracle, paused["payload"]["position"]["positionMsAtSend"], delta=50)

    def test_sleep_invalidates_position_and_resume_resamples(self):
        self.assertTrue(self.client.call('playback.play')['ok'])
        self.client.state(lambda s: s['playback']['status'] == 'Playing')
        self.control.Sleep(True)
        try:
            suspended = self.client.state(lambda s: not s['position']['known'])
            self.control.Configure('{"position":45000}')
        finally:
            self.control.Sleep(False)
        started = time.monotonic()
        resumed = self.client.state(lambda s: s['position']['known'] and s['position']['positionMsAtSend'] >= 45000)
        self.assertLess(time.monotonic() - started, .5)
        self.assertGreater(resumed['payload']['position']['discontinuityId'], suspended['payload']['position']['discontinuityId'])
        self.assertEqual(resumed['payload']['position']['reason'], 'resume')

    def test_unknown_duration_position_and_capabilities(self):
        for args in [{"duration": 0}, {"duration": 120000, "known": False}, {"known": True, "control": False}]:
            self.control.Configure(json.dumps(args))
            self.client.state(lambda s: not s["playback"]["canSeekAbsolute"])
            self.assertFalse(self.client.call("playback.seek", {"positionMs": 0})["ok"])
        self.assertEqual(json.loads(self.control.Inspect())["calls"]["SetPosition"], 0)

    def test_stale_scope_and_deduplication(self):
        old_scope = self.client.scope
        msg = self.client.send("playback.next")
        self.assertTrue(self.client.response(msg["id"])["ok"])
        self.client.state(lambda s: s["track"]["trackKey"].endswith("2"))
        self.client.p.stdin.write(json.dumps(msg) + "\n"); self.client.p.stdin.flush()
        self.assertTrue(self.client.response(msg["id"])["ok"])
        self.assertEqual(json.loads(self.control.Inspect())["calls"]["Next"], 1)
        reply = self.client.call("playback.pause", scope=old_scope)
        self.assertEqual(reply["error"]["code"], "stale_scope")
        msg["op"] = "playback.previous"
        self.client.p.stdin.write(json.dumps(msg) + "\n"); self.client.p.stdin.flush()
        self.assertEqual(self.client.response(msg["id"])["error"]["code"], "invalid_request")

    def test_real_spotify_metadata_types(self):
        self.control.Configure('{"spotify_types":true,"duration":90000}')
        state = self.client.state(lambda s: s["track"]["durationMs"] == 90000)
        self.assertTrue(state["payload"]["playback"]["canSeekAbsolute"])
        self.assertTrue(self.client.call("playback.seek", {"positionMs": 2000})["ok"])
        self.assertEqual(json.loads(self.control.Inspect())["calls"]["SetPosition"], 1)

    def test_malformed_and_oversized_recovery(self):
        self.client.p.stdin.write("{\n" + "x" * 1048577 + "\n"); self.client.p.stdin.flush()
        self.assertTrue(self.client.call("settings.get")["ok"])
        self.assertEqual(self.client.call("settings.get", backendSessionId="old")["error"]["code"], "stale_scope")

    def test_import_replace_offset_persist_and_reject_invalid(self):
        first = self.client.call("lyrics.import", {"text": "[00:00]Original first line"})
        self.assertTrue(first["ok"], first)
        first_doc = first["result"]["documentId"]
        second = self.client.call("lyrics.import", {"text": "[00:00]Original replacement"})
        self.assertTrue(second["ok"])
        doc = second["result"]["documentId"]
        self.assertNotEqual(first_doc, doc)
        self.assertEqual(self.client.call("lyrics.set-offset", {"documentId": first_doc, "offsetMs": 50})["error"]["code"], "stale_scope")
        self.assertTrue(self.client.call("lyrics.set-offset", {"documentId": doc, "lyricVersionId": second["result"]["lyricVersionId"], "offsetMs": 100})["ok"])
        self.assertFalse(self.client.call("lyrics.import", {"text": "no timestamps"})["ok"])
        self.assertTrue(self.client.call("cache.clear")["ok"])
        self.client.close(); self.client = Client(self.temp.name)
        state = self.client.state()
        self.assertEqual(state["payload"]["lyrics"]["documentId"], doc)
        self.assertEqual(state["payload"]["lyrics"]["offsetMs"], 100)

    def test_expanded_import_keeps_current_lyrics_and_playback(self):
        self.control.Configure('{"duration":120000}')
        self.client.state(lambda s: s["track"]["durationMs"] == 120000)
        selected = self.client.call("lyrics.import", {"text": "[00:00]Original fixture"})
        self.assertTrue(selected["ok"], selected)
        repeated = "".join(f"[{i // 60:02}:{i % 60:02}]" for i in range(100)) + "x" * 300000
        rejected = self.client.call("lyrics.import", {"text": repeated})
        self.assertEqual(rejected["error"]["code"], "document_too_large")
        current = self.client.call("session.resync")["result"]["snapshot"]["lyrics"]
        self.assertEqual(current["documentId"], selected["result"]["documentId"])
        self.assertTrue(self.client.call("playback.play")["ok"])
        self.client.state(lambda s: s["playback"]["status"] == "Playing")

    def test_lrc_parser_cases_through_import(self):
        self.control.Configure('{"duration":10000}')
        self.client.state(lambda s: s["track"]["durationMs"] == 10000)
        cases = [
            ("[offset:100]\n[00:01.00][00:04.000]星光\n[00:06.00]\n[00:07.20]Home", [900, 3900, 7100]),
            ("[00:03.123]Third\n[00:01.2]First\n[00:02.34]Second", [1200, 2340, 3123]),
            ("[00:01]Meet at [01:23] tonight", [1000]),
        ]
        for text, starts in cases:
            with self.subTest(text=text):
                reply = self.client.call("lyrics.import", {"text": text})
                self.assertTrue(reply["ok"], reply)
                document = [event["payload"]["document"] for event in self.client.events if event["event"] == "lyrics.document"][-1]
                self.assertEqual([line["startMs"] for line in document["lines"]], starts)
                self.assertTrue(all(not line["words"] for line in document["lines"]))
                self.assertEqual(document["syncLevel"], "line")
        reply = self.client.call("lyrics.import", {"text": "[00:01]Original\n[00:01]翻译"})
        self.assertEqual(reply["error"]["code"], "ambiguous_timestamps")
        self.assertFalse(self.client.call("lyrics.import", {"text": 123})["ok"])

    def test_epoch_changes_and_monotonic_event_sequence(self):
        epoch = self.client.epoch
        self.client.call("session.resync")
        seqs = [e["seq"] for e in self.client.events]
        self.assertEqual(seqs, sorted(set(seqs)))
        self.client.close(); self.client = Client(self.temp.name)
        self.assertNotEqual(epoch, self.client.epoch)

    def test_local_file_import_and_redacted_diagnostics(self):
        path = pathlib.Path(self.temp.name) / "original.lrc"
        path.write_text("\ufeff[00:01]Private original fixture", encoding="utf-8")
        imported = self.client.call("lyrics.import", {"path": str(path)})
        self.assertTrue(imported["ok"], imported)
        identity = imported["result"]["documentId"]
        path.write_bytes(b"\xff\xfeinvalid")
        self.assertFalse(self.client.call("lyrics.import", {"path": str(path)})["ok"])
        self.assertEqual(self.client.call("session.resync")["result"]["snapshot"]["lyrics"]["documentId"], identity)
        destination = pathlib.Path(self.temp.name) / "diagnostics.json"
        response = self.client.call("diagnostics.export", {"path": str(destination)})
        self.assertTrue(response["ok"])
        diagnostic = json.loads(destination.read_text())
        self.assertEqual(diagnostic, response["result"])
        self.assertEqual(set(diagnostic), {"backendVersion", "protocol", "playerAvailable", "positionKnown", "lyricsStatus", "lyricsError", "onlineProviders"})
        self.assertNotIn("Private original fixture", destination.read_text())

    def test_special_file_import_does_not_block_control_or_shutdown(self):
        fifo = pathlib.Path(self.temp.name) / "input.lrc"
        os.mkfifo(fifo)
        imported = self.client.send("lyrics.import", {"path": str(fifo)})
        time.sleep(.1)
        command = self.client.send("playback.play")
        deadline = time.monotonic() + 2
        try:
            while command["id"] not in self.client.responses and time.monotonic() < deadline:
                try:
                    self.client.pump(.1)
                except queue.Empty:
                    pass
            self.assertIn(command["id"], self.client.responses, "Import blocked playback")
            self.assertTrue(self.client.response(command["id"])["ok"])
            self.assertEqual(self.client.response(imported["id"])["error"]["code"], "invalid_request")
            self.client.close()
        finally:
            if self.client.p.poll() is None:
                self.client.p.kill()
                self.client.p.wait(timeout=2)
                # A failing regression must still close descriptors and remove the FIFO.
                self.client.p.stdout.close()
                self.client.p.stderr.close()

    def test_broken_saved_selection_preserves_player(self):
        self.assertTrue(self.client.call("lyrics.import", {"text": "[00:00]Original fixture"})["ok"])
        self.client.close()
        saved = next((pathlib.Path(self.temp.name) / "XDG_DATA_HOME/omarchy-lyricify/selections").glob("*.json"))
        original = saved.read_text()
        for case in ("unreadable", "null_record", "null_selection", "invalid_timeline"):
            with self.subTest(case=case):
                value = json.loads(original)
                if case == "null_record": value = None
                if case == "null_selection": value["selection"] = None
                if case == "invalid_timeline": value["selection"]["document"] = None
                saved.write_text(json.dumps(value))
                if case == "unreadable": saved.chmod(0)
                try:
                    self.client = Client(self.temp.name)
                    state = self.client.state(lambda s: s["lyrics"]["status"] == "error")["payload"]
                    self.assertIsNotNone(state["player"])
                    self.assertEqual(state["lyrics"]["errorCode"], "storage_error")
                    self.assertTrue(self.client.call("playback.pause")["ok"])
                finally:
                    self.client.close()
                    saved.chmod(0o600)

    def test_owner_reuse_invalidates_old_scope(self):
        old = self.client.scope
        self.fake.terminate(); self.fake.wait(timeout=3); self.fake.stdout.close()
        self.client.state(lambda s: s["player"] is None)
        type(self).fake = subprocess.Popen(["/usr/bin/python3", str(ROOT / "tests/fake_mpris.py"), "org.mpris.MediaPlayer2.spotify"], stdout=subprocess.PIPE, text=True)
        self.assertEqual(self.fake.stdout.readline().strip(), "ready")
        import dbus
        type(self).control = dbus.Interface(self.bus.get_object("org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2"), "org.lyricisland.Test")
        self.client.state()
        self.assertNotEqual(old["playerInstanceId"], self.client.scope["playerInstanceId"])
        self.assertEqual(self.client.call("playback.pause", scope=old)["error"]["code"], "stale_scope")

    def test_other_player_selection_is_sticky_and_persists(self):
        other = subprocess.Popen(["/usr/bin/python3", str(ROOT / "tests/fake_mpris.py"), "org.mpris.MediaPlayer2.fixture"], stdout=subprocess.PIPE, text=True)
        self.assertEqual(other.stdout.readline().strip(), "ready")
        try:
            self.assertTrue(self.client.call("player.select", {"applicationId": "fixture"})["ok"])
            self.client.state(lambda s: s["player"] and s["player"]["applicationId"] == "fixture")
            self.control.Configure('{"status":"Playing"}')
            result = self.client.call("session.resync")["result"]["snapshot"]
            self.assertEqual(result["player"]["applicationId"], "fixture")
            self.client.close(); self.client = Client(self.temp.name)
            self.assertEqual(self.client.state()["payload"]["player"]["applicationId"], "fixture")
        finally:
            other.terminate(); other.wait(timeout=3); other.stdout.close()

    def test_yrc_word_import_and_version_offsets(self):
        first = self.client.call("lyrics.import", {"format": "yrc", "text": "[1000,2000](1000,500,0)Original (2000,1000,0)fixture"})
        self.assertTrue(first["ok"], first)
        identity = first["result"]["documentId"]
        self.assertTrue(self.client.call("lyrics.set-offset", {"documentId": identity, "lyricVersionId": first["result"]["lyricVersionId"], "offsetMs": 250})["ok"])
        self.assertTrue(self.client.call("lyrics.import", {"text": "[00:01]Alternate version"})["ok"])
        restored = self.client.call("lyrics.import", {"format": "yrc", "text": "[1000,2000](1000,500,0)Original (2000,1000,0)fixture"})
        self.assertTrue(restored["ok"], restored)
        result = self.client.call("session.resync")["result"]["snapshot"]
        self.assertEqual(result["lyrics"]["offsetMs"], 250)
        self.assertTrue(any(e["event"] == "lyrics.document" and e["payload"]["document"]["syncLevel"] == "word" for e in self.client.events))


if __name__ == "__main__":
    if "--isolated" not in sys.argv:
        raise SystemExit(subprocess.call(["dbus-run-session", "--", "/usr/bin/python3", __file__, "--isolated"], cwd=ROOT))
    sys.argv.remove("--isolated")
    unittest.main(verbosity=2)
