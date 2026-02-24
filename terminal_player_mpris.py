#!/usr/bin/env python3

import argparse
import asyncio
import json
import os
import traceback
import re
import sys
from pathlib import Path

from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method, dbus_property
from dbus_next.constants import PropertyAccess
from dbus_next import Variant


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def sanitize_object_path_segment(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_]", "_", str(value))
    if not cleaned:
        return "track_0"
    return cleaned


class MprisRoot(ServiceInterface):
    def __init__(self, controller):
        super().__init__("org.mpris.MediaPlayer2")
        self.controller = controller

    @method()
    def Raise(self) -> None:
        return

    @method()
    def Quit(self) -> None:
        self.controller.write_reason("quit")
        self.controller.write_command("quit")
        self.controller.send_mpv({"command": ["stop"]})

    @dbus_property(access=PropertyAccess.READ)
    def CanQuit(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanRaise(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def HasTrackList(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Identity(self) -> "s":
        return "Terminal-Player"

    @dbus_property(access=PropertyAccess.READ)
    def DesktopEntry(self) -> "s":
        return "terminal-player"

    @dbus_property(access=PropertyAccess.READ)
    def SupportedUriSchemes(self) -> "as":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def SupportedMimeTypes(self) -> "as":
        return []


class MprisPlayer(ServiceInterface):
    def __init__(self, controller):
        super().__init__("org.mpris.MediaPlayer2.Player")
        self.controller = controller

    @method()
    def Next(self) -> None:
        self.controller.write_reason("next")
        self.controller.write_command("next")
        self.controller.send_mpv({"command": ["stop"]})

    @method()
    def Previous(self) -> None:
        self.controller.write_reason("prev")
        self.controller.write_command("prev")
        self.controller.send_mpv({"command": ["stop"]})

    @method()
    def Pause(self) -> None:
        self.controller.send_mpv({"command": ["set_property", "pause", True]})

    @method()
    def PlayPause(self) -> None:
        self.controller.send_mpv({"command": ["cycle", "pause"]})

    @method()
    def Stop(self) -> None:
        self.controller.write_reason("stop")
        self.controller.write_command("stop")
        self.controller.send_mpv({"command": ["stop"]})

    @method()
    def Play(self) -> None:
        self.controller.send_mpv({"command": ["set_property", "pause", False]})

    @method()
    def Seek(self, Offset: "x") -> None:
        self.controller.send_mpv({"command": ["seek", Offset / 1_000_000.0]})

    @method()
    def SetPosition(self, TrackId: "o", Position: "x") -> None:
        _ = TrackId
        self.controller.send_mpv({"command": ["set_property", "time-pos", Position / 1_000_000.0]})

    @method()
    def OpenUri(self, Uri: "s") -> None:
        _ = Uri
        return

    @dbus_property(access=PropertyAccess.READ)
    def PlaybackStatus(self) -> "s":
        return self.controller.playback_status

    @dbus_property(access=PropertyAccess.READ)
    def LoopStatus(self) -> "s":
        return self.controller.loop_status

    @dbus_property(access=PropertyAccess.READWRITE)
    def Rate(self) -> "d":
        return 1.0

    @Rate.setter
    def Rate(self, value: "d") -> None:
        _ = value
        return

    @dbus_property(access=PropertyAccess.READWRITE)
    def Shuffle(self) -> "b":
        return False

    @Shuffle.setter
    def Shuffle(self, value: "b") -> None:
        _ = value
        return

    @dbus_property(access=PropertyAccess.READ)
    def Metadata(self) -> "a{sv}":
        return self.controller.metadata

    @dbus_property(access=PropertyAccess.READWRITE)
    def Volume(self) -> "d":
        return self.controller.volume

    @Volume.setter
    def Volume(self, value: "d") -> None:
        self.controller.send_mpv({"command": ["set_property", "volume", max(0.0, value * 100.0)]})

    @dbus_property(access=PropertyAccess.READ)
    def Position(self) -> "x":
        return self.controller.position_us

    @dbus_property(access=PropertyAccess.READ)
    def MinimumRate(self) -> "d":
        return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def MaximumRate(self) -> "d":
        return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def CanGoNext(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanGoPrevious(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanPlay(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanPause(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanSeek(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanControl(self) -> "b":
        return True


class Bridge:
    def __init__(self, runtime_dir: Path):
        self.runtime_dir = runtime_dir
        self.socket_path = runtime_dir / "mpv.socket"
        self.command_file = runtime_dir / "command"
        self.reason_file = runtime_dir / "reason"
        self.metadata_file = runtime_dir / "metadata.json"
        self.stop_file = runtime_dir / "mpris.stop"
        self.playback_status = "Stopped"
        self.loop_status = "None"
        self.volume = 1.0
        self.position_us = 0
        self.metadata = {"mpris:trackid": Variant("o", "/com/terminal_player/track/0")}
        self.root = MprisRoot(self)
        self.player = MprisPlayer(self)

    def write_command(self, command: str) -> None:
        try:
            self.command_file.write_text(command, encoding="utf-8")
        except Exception:
            pass

    def write_reason(self, reason: str) -> None:
        try:
            self.reason_file.write_text(reason, encoding="utf-8")
        except Exception:
            pass

    def load_metadata(self) -> None:
        data = read_json(self.metadata_file)
        track_id = sanitize_object_path_segment(data.get("track_id", "0"))
        title = data.get("title", "Unknown")
        artist = data.get("artist", "Unknown")
        album = data.get("album", "Unknown")
        url = data.get("url", "")
        art_url = data.get("art_url", "")
        length_us = int(float(data.get("length_us", 0)))

        md = {
            "mpris:trackid": Variant("o", f"/com/terminal_player/track/{track_id}"),
            "xesam:title": Variant("s", title),
            "xesam:artist": Variant("as", [artist] if artist else []),
            "xesam:album": Variant("s", album),
        }
        if url:
            md["xesam:url"] = Variant("s", url)
        if art_url:
            md["mpris:artUrl"] = Variant("s", art_url)
        if length_us > 0:
            md["mpris:length"] = Variant("x", length_us)
        self.metadata = md

    async def send_request(self, payload: dict) -> dict:
        if not self.socket_path.exists():
            return {}
        try:
            reader, writer = await asyncio.open_unix_connection(str(self.socket_path))
            writer.write((json.dumps(payload) + "\n").encode("utf-8"))
            await writer.drain()
            line = await asyncio.wait_for(reader.readline(), timeout=0.3)
            writer.close()
            await writer.wait_closed()
            if not line:
                return {}
            return json.loads(line.decode("utf-8", errors="ignore"))
        except Exception:
            return {}

    async def get_property(self, name: str):
        response = await self.send_request({"command": ["get_property", name]})
        return response.get("data")

    def send_mpv(self, payload: dict) -> None:
        if not self.socket_path.exists():
            return
        try:
            with socket_unix(str(self.socket_path)) as sock:
                sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        except Exception:
            pass

    async def poll(self) -> None:
        self.load_metadata()
        previous = (self.playback_status, self.volume, self.position_us)
        while True:
            if self.stop_file.exists():
                break

            paused = await self.get_property("pause")
            time_pos = await self.get_property("time-pos")
            volume = await self.get_property("volume")

            if paused is None and not self.socket_path.exists():
                self.playback_status = "Stopped"
            elif paused is True:
                self.playback_status = "Paused"
            else:
                self.playback_status = "Playing"

            if isinstance(time_pos, (int, float)):
                self.position_us = int(float(time_pos) * 1_000_000)

            if isinstance(volume, (int, float)):
                self.volume = max(0.0, min(1.0, float(volume) / 100.0))

            current = (self.playback_status, self.volume, self.position_us)
            if current != previous:
                self.player.emit_properties_changed(
                    {
                        "PlaybackStatus": self.playback_status,
                        "Volume": self.volume,
                        "Position": self.position_us,
                        "Metadata": self.metadata,
                    }
                )
                previous = current

            await asyncio.sleep(0.5)

    async def run(self) -> int:
        bus = await MessageBus().connect()
        await bus.request_name("org.mpris.MediaPlayer2.terminalplayer")
        bus.export("/org/mpris/MediaPlayer2", self.root)
        bus.export("/org/mpris/MediaPlayer2", self.player)
        self.player.emit_properties_changed({"Metadata": self.metadata, "PlaybackStatus": self.playback_status})
        await self.poll()
        return 0


class socket_unix:
    def __init__(self, path: str):
        import socket

        self._socket_module = socket
        self.path = path
        self.sock = None

    def __enter__(self):
        self.sock = self._socket_module.socket(self._socket_module.AF_UNIX, self._socket_module.SOCK_STREAM)
        self.sock.settimeout(0.2)
        self.sock.connect(self.path)
        return self.sock

    def __exit__(self, exc_type, exc, tb):
        try:
            if self.sock is not None:
                self.sock.close()
        except Exception:
            pass
        return False


def resolve_bus_address() -> str:
    env_addr = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "").strip()
    if env_addr:
        return env_addr

    uid = os.getuid()
    user_bus = Path(f"/run/user/{uid}/bus")
    if user_bus.exists():
        return f"unix:path={user_bus}"

    return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-dir", required=True)
    args = parser.parse_args()

    runtime_dir = Path(args.runtime_dir)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    bridge = Bridge(runtime_dir)
    bus_address = resolve_bus_address()
    if bus_address:
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = bus_address

    try:
        return asyncio.run(bridge.run())
    except KeyboardInterrupt:
        return 0
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
