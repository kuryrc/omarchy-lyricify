"""Original, isolated MPRIS fixture. Never uses the real desktop session bus."""
import json
import sys
import time
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"
TEST = "org.lyricisland.Test"
DBusGMainLoop(set_as_default=True)


class SleepManager(dbus.service.Object):
    def __init__(self, bus):
        self.name = dbus.service.BusName('org.freedesktop.login1', bus=bus)
        super().__init__(bus, '/org/freedesktop/login1')

    @dbus.service.signal('org.freedesktop.login1.Manager', signature='b')
    def PrepareForSleep(self, sleeping):
        pass


class Player(dbus.service.Object):
    def __init__(self, bus):
        self.name = dbus.service.BusName(sys.argv[1], bus=bus)
        super().__init__(bus, "/org/mpris/MediaPlayer2")
        self.reset()

    def reset(self):
        self.status, self.rate, self.position, self.anchor = "Paused", 1.0, 1500, time.monotonic()
        self.track, self.duration, self.known, self.control, self.title = 1, 120000, True, True, "Original fixture"
        self.calls = {key: 0 for key in ["Play", "Pause", "Next", "Previous", "SetPosition"]}
        self.spotify_types = False
        self.seek_buffer_ms = 0
        self.get_all_calls = 0

    def position_now(self):
        return self.position + (max(0, time.monotonic() - self.anchor) * 1000 * self.rate if self.status == "Playing" else 0)

    def values(self):
        metadata = {"xesam:title": dbus.String(self.title), "xesam:artist": dbus.Array(["Fixture artist"], signature="s"),
                    "xesam:album": dbus.String("Original tests"), "xesam:url": dbus.String("spotify:track:" + str(self.track).zfill(22)),
                    "mpris:trackid": dbus.ObjectPath("/test/track" + str(self.track))}
        if self.duration:
            metadata["mpris:length"] = (dbus.UInt64 if self.spotify_types else dbus.Int64)(self.duration * 1000)
        if self.spotify_types:
            metadata["mpris:trackid"] = dbus.String("/test/track" + str(self.track))
        values = {"PlaybackStatus": dbus.String(self.status), "Rate": dbus.Double(self.rate), "Metadata": dbus.Dictionary(metadata, signature="sv")}
        for key in ["CanControl", "CanPlay", "CanPause", "CanGoNext", "CanGoPrevious", "CanSeek"]:
            values[key] = dbus.Boolean(self.control)
        if self.known:
            values["Position"] = dbus.Int64(self.position_now() * 1000)
        return values

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        self.get_all_calls += 1
        return self.values()

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, property):
        return self.values()[property]

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changes, invalidated):
        pass

    @dbus.service.signal(PLAYER, signature="x")
    def Seeked(self, position):
        pass

    @dbus.service.method(PLAYER)
    def Play(self):
        self.calls["Play"] += 1
        self.position, self.anchor, self.status = self.position_now(), time.monotonic(), "Playing"
        self.PropertiesChanged(PLAYER, {"PlaybackStatus": self.status}, [])

    @dbus.service.method(PLAYER)
    def Pause(self):
        self.calls["Pause"] += 1
        self.position, self.anchor, self.status = self.position_now(), time.monotonic(), "Paused"
        self.PropertiesChanged(PLAYER, {"PlaybackStatus": self.status}, [])

    @dbus.service.method(PLAYER)
    def Next(self):
        self.calls["Next"] += 1
        self.track += 1
        self.position, self.anchor = 0, time.monotonic()
        self.PropertiesChanged(PLAYER, {"Metadata": self.values()["Metadata"]}, [])

    @dbus.service.method(PLAYER)
    def Previous(self):
        self.calls["Previous"] += 1
        self.track = max(1, self.track - 1)
        self.position, self.anchor = 0, time.monotonic()
        self.PropertiesChanged(PLAYER, {"Metadata": self.values()["Metadata"]}, [])

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, path, position):
        if path == "/test/track" + str(self.track):
            self.calls["SetPosition"] += 1
            # Spotify can keep reporting Playing while its seek buffer fills.
            self.position, self.anchor = position / 1000, time.monotonic() + self.seek_buffer_ms / 1000
            self.Seeked(position)

    @dbus.service.method(TEST, in_signature="s", out_signature="s")
    def Configure(self, text):
        args = json.loads(text)
        if args.pop("reset", False):
            self.reset()
        self.position, self.anchor = self.position_now(), time.monotonic()
        for key, value in args.items():
            setattr(self, key, value)
        self.PropertiesChanged(PLAYER, self.values(), [])
        return json.dumps(self.calls)

    @dbus.service.method(TEST, out_signature="s")
    def Inspect(self):
        return json.dumps({"calls": self.calls, "positionMs": self.position_now(), "status": self.status,
                           "getAllCalls": self.get_all_calls})

    @dbus.service.method(TEST, in_signature='b')
    def Sleep(self, sleeping):
        sleep_manager.PrepareForSleep(sleeping)


sleep_manager = SleepManager(dbus.SessionBus()) if sys.argv[1] == 'org.mpris.MediaPlayer2.spotify' else None
player = Player(dbus.SessionBus())
print("ready", flush=True)
GLib.MainLoop().run()
