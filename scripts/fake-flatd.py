#!/usr/bin/env python3
"""A fake flatd for Arestia on the simulator and in screenshots: the flat service's contract v1.2 as the app sees it
(HTTPS only, with an identity the app pins through a pairing code; REST, the event stream over a WebSocket, Bonjour as
`_flatd._tcp`) with made-up devices, and a stand-in 3D page at `/viewer` that speaks the viewer's bridge (BRIDGE.md v1).
The viewer answers with a quoted ETag and Cache-Control: no-store, or an empty 304 for a matching If-None-Match.
Standard library only; Bonjour through macOS's own `dns-sd`, the identity's key and certificate through `openssl`.

    python3 scripts/fake-flatd.py                      # port 8790, Bonjour name "flatd (fake)"
    python3 scripts/fake-flatd.py --port 8791 --no-bonjour --travel 8 --extra
    python3 scripts/fake-flatd.py --pairing            # only print the pairing code (same options), and exit

It prints its pairing code, the JSON the real `flatd pair` shows as a QR code:
`{"url": "https://127.0.0.1:8790", "token": …, "spki_sha256": …}`. In the simulator: copy it
(`xcrun simctl pbcopy <udid>`) and paste it on Arestia's connect screen. Or skip the screen:
    xcrun simctl launch <udid> de.ares-empire.arestia -flatdPairing '<the code>'
The unit tests' live suite takes the same code (`ArestiaTests/TrustTests.swift`, `LiveFlatdTests`).

Its identity (a P-256 key and a self-signed certificate, made on first use) is kept in `build/fake-flatd/` (not in
git), so a pairing survives a restart; `--new-identity` makes another, as if flatd had lost its key (the app must then
refuse to talk to it until paired again). The test hooks need `curl -k https://…` now.

Never the real flatd: it runs on its own port (not 8787/8788) with its own key, and no real device is behind it.

Made-up devices: Fan 1, Fan 2 (plugs with timers), Blind 1 (with a favourite spot), Blind 2 (without); `--extra` adds
Lamp 1. Mode `cooking` (both fans on and Blind 1 up; ended: fans off, Blind 1 to its favourite), scenes `air_out` (both
fans for 30 min, Blind 1 up) and `all_down`. Blinds travel 100 % in `--travel` seconds and report every second.

For a page that is not public (the real 3D viewer), `--viewer <file>` reads it at each /viewer request, and
`--devices <file>` gives the devices that page knows. Both stay local files, never in this repo. With either, the fake
listens on 127.0.0.1 only, without Bonjour, and makes up a fresh key (printed) unless --host and --key say otherwise.

Test hooks (with the key, like everything else): POST /fake/press?id=<rollo>&command=up|down (a wall switch, source
`device`), POST /fake/switch?id=<fan>&on=1|0 (the plug's own button), POST /fake/online?id=<id>&online=0|1,
POST /fake/fail?id=<id> (its next command answers 504), POST /fake/drop (closes every event stream),
POST /fake/reset (back to the start state), GET /fake/requests (how many requests arrived so far, this one included).
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import secrets
import select
import signal
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
DEFAULT_KEY = "fakeflatd0123456789abcdef"   # letters and digits, no y or z: typed the same on a German keyboard


def now_iso(at: float | None = None) -> str:
    """flatd's form: UTC with microseconds and a Z ("2026-11-19T18:02:11.123456Z")."""
    moment = dt.datetime.fromtimestamp(at if at is not None else time.time(), dt.timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


class Flat:
    """The made-up flat: devices, modes, scenes, timers and blinds that move."""

    def __init__(self, travel: float, extra: bool, devices: list[dict] | None = None):
        self.travel = travel
        self.extra = extra
        self.custom = devices                # --devices: ids and names from a local file instead of the made-up ones
        self.lock = threading.RLock()
        self.listeners: list = []          # callables taking an event dict
        self.fail_next: set[str] = set()
        self.requests_seen = 0             # HTTP requests received (after TLS), for GET /fake/requests
        self.reset()

    def reset(self) -> None:
        with self.lock:
            switch = lambda: {"on": False, "off_at": None, "online": True, "power_w": 0.0, "updated_at": now_iso()}
            self.devices = {
                "fan:fan_1": {"id": "fan:fan_1", "kind": "fan", "label": "Fan 1", "room": "living",
                              "driver": "fake", "controls": ["on", "for_s"], "state": switch()},
                "fan:fan_2": {"id": "fan:fan_2", "kind": "fan", "label": "Fan 2", "room": "kitchen",
                              "driver": "fake", "controls": ["on", "for_s"], "state": switch()},
                "rollo:blind_1": {"id": "rollo:blind_1", "kind": "rollo", "label": "Blind 1", "room": "living",
                                  "driver": "fake", "controls": ["command", "position"],
                                  "state": {"position": 60, "moving": None, "target": None, "favourite": 60,
                                            "online": True, "updated_at": now_iso()}},
                "rollo:blind_2": {"id": "rollo:blind_2", "kind": "rollo", "label": "Blind 2", "room": "living",
                                  "driver": "fake", "controls": ["command", "position"],
                                  "state": {"position": 0, "moving": None, "target": None, "favourite": None,
                                            "online": True, "updated_at": now_iso()}},
            }
            if self.extra:
                self.devices["light:lamp_1"] = {"id": "light:lamp_1", "kind": "light", "label": "Lamp 1",
                                                "room": "hall", "driver": "fake", "controls": ["on", "for_s"],
                                                "state": switch()}
            if self.custom is not None:
                self.devices = {}
                for entry in self.custom:
                    kind = entry.get("kind") or entry["id"].split(":")[0]
                    if kind == "rollo":
                        state = {"position": entry.get("position", 0), "moving": None, "target": None,
                                 "favourite": entry.get("favourite"), "online": True, "updated_at": now_iso()}
                        controls = ["command", "position"]
                    else:
                        state, controls = switch(), ["on", "for_s"]
                    self.devices[entry["id"]] = {"id": entry["id"], "kind": kind, "label": entry.get("label", entry["id"]),
                                                 "room": entry.get("room"), "driver": "fake", "controls": controls,
                                                 "state": state}
            # Cooking: every fan and the first blind with a favourite spot (the contract's shape, whatever the ids).
            fans = [i for i, d in self.devices.items() if d["kind"] == "fan"]
            blinds = [i for i, d in self.devices.items() if d["kind"] == "rollo"]
            self.cooking_blind = next((i for i in blinds if self.devices[i]["state"].get("favourite") is not None),
                                      blinds[0] if blinds else None)
            near = fans + ([self.cooking_blind] if self.cooking_blind else [])
            self.modes = {"cooking": {"id": "cooking", "label": "Cooking", "active": False, "since": None,
                                      "devices": near}}
            self.scenes = {
                "air_out": {"id": "air_out", "label": "Air out", "devices": near},
                "all_down": {"id": "all_down", "label": "All blinds down", "devices": blinds},
            }
            self.timers: dict[str, float] = {}       # switch id -> when it goes off
            self.motion: dict[str, dict] = {}        # rollo id -> {"from", "to", "start"}
            self.fail_next.clear()

    # --- events ---------------------------------------------------------------------------------------------------

    def emit(self, event: dict) -> None:
        for listener in list(self.listeners):
            listener(event)

    def set_state(self, device_id: str, changes: dict, source: str) -> None:
        # Emitted under the lock, so a stream's snapshot (taken under it too) never misses an event or sees it twice.
        with self.lock:
            state = self.devices[device_id]["state"]
            state.update(changes)
            state["updated_at"] = now_iso()
            self.emit({"type": "state", "id": device_id, "state": dict(state), "source": source})

    def snapshot(self) -> dict:
        with self.lock:
            return {"type": "snapshot", "devices": json.loads(json.dumps(list(self.devices.values()))),
                    "modes": json.loads(json.dumps(list(self.modes.values())))}

    # --- commands -------------------------------------------------------------------------------------------------

    def command(self, device_id: str, body: dict, source: str) -> tuple[int, dict]:
        """Applies a POST /api/devices/{id} body; returns (status, answer)."""
        with self.lock:
            device = self.devices.get(device_id)
            if device is None:
                return 404, {"error": f"unknown device {device_id}"}
            if device_id in self.fail_next:
                self.fail_next.discard(device_id)
                return 504, {"error": f"{device['label']} did not answer"}
            if not device["state"].get("online", True):
                return 504, {"error": f"{device['label']} is offline"}
            if "command" in device["controls"]:
                return self.rollo(device, body, source)
            return self.switch(device, body, source)

    def switch(self, device: dict, body: dict, source: str) -> tuple[int, dict]:
        if set(body) - {"on", "for_s"} or not isinstance(body.get("on"), bool):
            return 400, {"error": 'body must be {"on": true|false} with an optional "for_s"'}
        on, for_s = body["on"], body.get("for_s")
        if for_s is not None and (not isinstance(for_s, (int, float)) or isinstance(for_s, bool) or for_s <= 0):
            return 400, {"error": "for_s must be a positive number of seconds"}
        if on and for_s:
            self.timers[device["id"]] = time.time() + for_s
            off_at = now_iso(self.timers[device["id"]])
        else:
            self.timers.pop(device["id"], None)
            off_at = None
        self.set_state(device["id"], {"on": on, "off_at": off_at, "power_w": 38.0 if on else 0.0}, source)
        return 200, json.loads(json.dumps(device))

    def rollo(self, device: dict, body: dict, source: str) -> tuple[int, dict]:
        state = device["state"]
        if len(body) != 1:
            return 400, {"error": 'body must be {"command": …} or {"position": n}'}
        if "position" in body:
            target = body["position"]
            if not isinstance(target, (int, float)) or isinstance(target, bool) or not 0 <= target <= 100:
                return 400, {"error": "position must be 0 to 100"}
            target = round(target)
        else:
            command = body.get("command")
            if command == "up":
                target = 0
            elif command == "down":
                target = 100
            elif command == "favourite":
                if state.get("favourite") is None:
                    return 409, {"error": f"{device['label']} has no favourite spot"}
                target = state["favourite"]
            elif command == "stop":
                if device["id"] in self.motion:
                    self.motion.pop(device["id"])
                    self.set_state(device["id"], {"moving": None, "target": None}, source)
                return 200, json.loads(json.dumps(device))
            else:
                return 400, {"error": "command must be up, down, favourite or stop"}
        position = state.get("position") or 0
        if target == position:
            self.motion.pop(device["id"], None)
            self.set_state(device["id"], {"moving": None, "target": None}, source)
        else:
            self.motion[device["id"]] = {"from": position, "to": target, "start": time.time()}
            self.set_state(device["id"], {"moving": "down" if target > position else "up", "target": target}, source)
        return 200, json.loads(json.dumps(device))

    def set_mode(self, mode_id: str, active: bool) -> tuple[int, dict]:
        with self.lock:
            mode = self.modes.get(mode_id)
            if mode is None:
                return 404, {"error": f"unknown mode {mode_id}"}
            failed: dict[str, str] = {}
            fans = [i for i in mode["devices"] if self.devices[i]["kind"] == "fan"]
            blind = self.cooking_blind
            if active:
                steps = [(fan, {"on": True}) for fan in fans] + ([(blind, {"command": "up"})] if blind else [])
                if not mode["active"]:
                    mode["since"] = now_iso()
                mode["active"] = True
            elif mode["active"]:
                steps = [(fan, {"on": False}) for fan in fans] + ([(blind, {"command": "favourite"})] if blind else [])
                mode["active"] = False
                mode["since"] = None
            else:
                steps = []
            for device_id, body in steps:
                status, answer = self.command(device_id, body, f"mode:{mode_id}")
                if status != 200:
                    failed[device_id] = answer.get("error", str(status))
            answer = dict(mode)
            self.emit({"type": "mode", "mode": dict(mode), "source": "api"})
        return 200, {**answer, "failed": failed}

    def run_scene(self, scene_id: str) -> tuple[int, dict]:
        with self.lock:
            scene = self.scenes.get(scene_id)
            if scene is None:
                return 404, {"error": f"unknown scene {scene_id}"}
            if scene_id == "air_out":
                steps = [(i, {"on": True, "for_s": 1800} if self.devices[i]["kind"] == "fan" else {"command": "up"})
                         for i in scene["devices"]]
            else:
                steps = [(i, {"command": "down"}) for i in scene["devices"]]
            failed = {}
            for device_id, body in steps:
                status, answer = self.command(device_id, body, f"scene:{scene_id}")
                if status != 200:
                    failed[device_id] = answer.get("error", str(status))
            return 200, {**scene, "failed": failed}

    # --- time passing ---------------------------------------------------------------------------------------------

    def tick(self) -> None:
        """Timers run out, blinds move one step (called every second)."""
        with self.lock:
            moment = time.time()
            for device_id, at in list(self.timers.items()):
                if at <= moment:
                    self.timers.pop(device_id)
                    self.set_state(device_id, {"on": False, "off_at": None, "power_w": 0.0}, "timer")
            for device_id, move in list(self.motion.items()):
                distance = move["to"] - move["from"]
                travelled = (moment - move["start"]) / self.travel * 100
                if travelled >= abs(distance):
                    self.motion.pop(device_id)
                    self.set_state(device_id, {"position": move["to"], "moving": None, "target": None}, "device")
                else:
                    position = round(move["from"] + travelled * (1 if distance > 0 else -1))
                    self.set_state(device_id, {"position": position}, "device")


class WebSocket:
    """One event stream: RFC 6455 framing, text out, pings answered, closes read."""

    def __init__(self, sock: socket.socket):
        self.sock = sock
        self.lock = threading.Lock()
        self.open = True
        # A client that stops reading is dropped after 2 s instead of holding every broadcast (and the flat's lock).
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, struct.pack("ll", 2, 0))

    def send_text(self, text: str) -> None:
        self.send_frame(0x1, text.encode())

    def send_frame(self, opcode: int, payload: bytes) -> None:
        header = bytes([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header += bytes([length])
        elif length < 65536:
            header += bytes([126]) + struct.pack(">H", length)
        else:
            header += bytes([127]) + struct.pack(">Q", length)
        with self.lock:
            if not self.open:
                return
            try:
                self.sock.sendall(header + payload)
            except OSError:
                self.open = False

    def close(self, code: int = 1000) -> None:
        self.send_frame(0x8, struct.pack(">H", code))
        self.open = False
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def read_forever(self) -> None:
        try:
            while self.open:
                head = self._read(2)
                opcode, length = head[0] & 0x0F, head[1] & 0x7F
                if length == 126:
                    length = struct.unpack(">H", self._read(2))[0]
                elif length == 127:
                    length = struct.unpack(">Q", self._read(8))[0]
                mask = self._read(4) if head[1] & 0x80 else b"\0\0\0\0"
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(self._read(length)))
                if opcode == 0x8:
                    self.close()
                elif opcode == 0x9:
                    self.send_frame(0xA, payload)
        except (OSError, ConnectionError):
            pass
        self.open = False

    def _read(self, count: int) -> bytes:
        data = b""
        while len(data) < count:
            # A TLS socket must not be read and written at once from two threads: wait until there is something to
            # read, then read under the lock the writers use.
            if not self.sock.pending() and not select.select([self.sock], [], [], 1.0)[0]:
                if not self.open:
                    raise ConnectionError("closed")
                continue
            with self.lock:
                chunk = self.sock.recv(count - len(data))
            if not chunk:
                raise ConnectionError("closed")
            data += chunk
        return data


def make_handler(flat: Flat, key: str, latency: float, viewer_file: Path | None):
    sockets: list[WebSocket] = []

    def broadcast(event: dict) -> None:
        text = json.dumps(event)
        for ws in list(sockets):
            if ws.open:
                ws.send_text(text)
            else:
                sockets.remove(ws)

    flat.listeners.append(broadcast)

    class Handler(BaseHTTPRequestHandler):
        server_version = "fake-flatd/1.2"
        protocol_version = "HTTP/1.1"

        def log_message(self, format, *args):       # one short line per request
            sys.stderr.write("fake-flatd: %s %s\n" % (self.command, self.path.split("?")[0]))

        def answer(self, status: int, body, content_type="application/json", extra=None) -> None:
            data = body if isinstance(body, bytes) else json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            for name, value in (extra or {}).items():
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(data)

        def authorized(self, query: dict) -> bool:
            header = self.headers.get("Authorization", "")
            if header == f"Bearer {key}":
                return True
            # Only the event stream takes the key in the URL (contract v1.1).
            return urlparse(self.path).path == "/api/events" and query.get("token", [""])[0] == key

        def refuse(self) -> None:
            self.answer(401, {"error": "missing or wrong token"}, extra={"WWW-Authenticate": "Bearer"})

        def body(self):
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b""
            if not raw:
                return {}
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                return None

        def do_OPTIONS(self):
            self.answer(204, b"", extra={"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                                         "Access-Control-Allow-Headers": "Authorization, Content-Type"})

        def do_GET(self):
            url = urlparse(self.path)
            query = parse_qs(url.query)
            with flat.lock:
                flat.requests_seen += 1
                seen = flat.requests_seen
            if url.path == "/fake/requests" and self.authorized(query):
                # How many requests (this one included) got past the TLS handshake since the start: a client that
                # refused this identity must not have added any (ArestiaTests, LiveFlatdTests).
                return self.answer(200, {"requests": seen})
            if url.path == "/api/health":
                return self.answer(200, {"ok": True, "version": "1.1.0-fake"})
            if not self.authorized(query):
                return self.refuse()
            if url.path == "/api/devices":
                return self.answer(200, {"devices": flat.snapshot()["devices"]})
            if url.path.startswith("/api/devices/"):
                device = flat.devices.get(unquote(url.path[len("/api/devices/"):]))
                return self.answer(200, device) if device else self.answer(404, {"error": "unknown device"})
            if url.path == "/api/modes":
                return self.answer(200, {"modes": flat.snapshot()["modes"]})
            if url.path == "/api/scenes":
                return self.answer(200, {"scenes": list(flat.scenes.values())})
            if url.path == "/api/history":
                return self.answer(200, {"events": []})
            if url.path == "/viewer":
                # Only the header carries the key here (contract v1.1), as for every other endpoint but the events.
                try:
                    viewer = viewer_file.read_bytes() if viewer_file is not None else VIEWER.encode()
                except FileNotFoundError:
                    return self.answer(404, {"error": "no viewer configured"})
                etag = '"' + hashlib.sha256(viewer).hexdigest()[:16] + '"'
                matches = [tag.strip().removeprefix("W/")
                           for tag in self.headers.get("If-None-Match", "").split(",")]
                if etag in matches or "*" in matches:
                    self.send_response(304)
                    self.send_header("ETag", etag)
                    self.send_header("Cache-Control", "no-store")
                    return self.end_headers()
                return self.answer(200, viewer, "text/html; charset=utf-8", extra={"ETag": etag})
            if url.path == "/api/events":
                return self.events()
            self.answer(404, {"error": "not found"})

        def do_POST(self):
            url = urlparse(self.path)
            query = parse_qs(url.query)
            with flat.lock:
                flat.requests_seen += 1
            if not self.authorized(query):
                return self.refuse()
            body = self.body()
            if body is None or not isinstance(body, dict):
                return self.answer(400, {"error": "body must be a JSON object"})
            if latency:
                time.sleep(latency)
            if url.path.startswith("/api/devices/"):
                return self.answer(*flat.command(unquote(url.path[len("/api/devices/"):]), body, "api"))
            if url.path.startswith("/api/modes/"):
                active = body.get("active")
                if not isinstance(active, bool):
                    return self.answer(400, {"error": 'body must be {"active": true|false}'})
                return self.answer(*flat.set_mode(unquote(url.path[len("/api/modes/"):]), active))
            if url.path.startswith("/api/scenes/"):
                return self.answer(*flat.run_scene(unquote(url.path[len("/api/scenes/"):])))
            if url.path.startswith("/fake/"):
                return self.fake(url.path, {k: v[0] for k, v in query.items()})
            self.answer(404, {"error": "not found"})

        def fake(self, path: str, query: dict):
            device_id = query.get("id", "")
            if path == "/fake/reset":
                with flat.lock:                  # the fresh snapshot before any newer event
                    flat.reset()
                    broadcast(flat.snapshot())
            elif path == "/fake/drop":
                for ws in list(sockets):
                    ws.close(1013)
            elif device_id not in flat.devices:
                return self.answer(404, {"error": "unknown device"})
            elif path == "/fake/press":
                with flat.lock:
                    flat.rollo(flat.devices[device_id], {"command": query.get("command", "up")}, "device")
            elif path == "/fake/switch":
                with flat.lock:
                    flat.switch(flat.devices[device_id], {"on": query.get("on") == "1"}, "device")
            elif path == "/fake/online":
                flat.set_state(device_id, {"online": query.get("online") == "1"}, "poll")
            elif path == "/fake/fail":
                flat.fail_next.add(device_id)
            else:
                return self.answer(404, {"error": "unknown hook"})
            self.answer(200, {"ok": True})

        def events(self):
            key_header = self.headers.get("Sec-WebSocket-Key")
            if self.headers.get("Upgrade", "").lower() != "websocket" or not key_header:
                return self.answer(400, {"error": "a WebSocket is expected here"})
            accept = base64.b64encode(hashlib.sha1((key_header + WS_GUID).encode()).digest()).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            self.wfile.flush()
            ws = WebSocket(self.connection)
            with flat.lock:                      # no event between the snapshot and joining the broadcast
                ws.send_text(json.dumps(flat.snapshot()))
                sockets.append(ws)
            ws.read_forever()
            self.close_connection = True

    return Handler


# The stand-in 3D page: the bridge of the viewer's BRIDGE.md v1 with plain tiles instead of the flat (the real page is
# private and only flatd serves it). Taps send requests to the app; the app's messages show as they arrive.
VIEWER = r"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>fake flatd viewer</title>
<style>
:root{--bg:#050507;--ink:#f6f7fb;--muted:#8a909c;--card:#14161c;--edge:#2a2d35;--accent:#ff9a62}
html.light{--bg:#ecedf2;--ink:#0a0c12;--muted:#5d6472;--card:#fff;--edge:#d8dbe2;--accent:#a8481a}
*{box-sizing:border-box}html,body{margin:0;background:transparent;color:var(--ink);font:15px -apple-system,system-ui}
main{padding:calc(env(safe-area-inset-top) + 18px) 18px calc(env(safe-area-inset-bottom) + var(--bars,0px) + 18px)}
h1{font-size:13px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin:0 0 14px}
#line{color:var(--muted);font-size:13px;margin-bottom:14px;min-height:18px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.tile{background:var(--card);border:1px solid var(--edge);border-radius:16px;padding:14px;min-height:96px}
.tile.on{border-color:var(--accent)}.tile.busy{opacity:.55}
.name{font-weight:600}.state{color:var(--muted);font-size:13px;margin-top:4px}
.win{height:44px;border:1px solid var(--edge);border-radius:6px;margin-top:10px;position:relative;overflow:hidden}
.fabric{position:absolute;left:0;right:0;top:0;background:var(--muted);opacity:.6}
.row{display:flex;gap:6px;margin-top:10px}button{flex:1;font:inherit;padding:8px 0;border-radius:10px;
border:1px solid var(--edge);background:transparent;color:var(--ink)}
#mode{display:none;margin-bottom:14px}#mode.show{display:flex;gap:10px;align-items:center}
#mode span{flex:1;color:var(--accent);font-weight:600}
</style></head><body><main>
<h1>Stand-in flat</h1><div id="line"></div>
<div id="mode"><span id="modeText">Cooking</span><button id="endMode" style="flex:0 0 90px">End</button></div>
<div class="grid" id="grid"></div></main>
<script>
const host = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.flat3d;
const devices = new Map(), modes = new Map(), busy = new Set();
let reqs = 0;
function post(m){ m.v = 1; if (host) host.postMessage(m); }
function request(id, body){ const reqId = 'r' + (++reqs); busy.add(id); render(); post({type:'request', reqId, id, body}); pending[reqId] = id; }
const pending = {};
function render(){
  const grid = document.getElementById('grid'); grid.innerHTML = '';
  for (const d of devices.values()){
    const t = document.createElement('div'); const s = d.state || {};
    t.className = 'tile' + (s.on ? ' on' : '') + (busy.has(d.id) ? ' busy' : ''); t.dataset.id = d.id;
    t.innerHTML = '<div class="name"></div><div class="state"></div>';
    t.querySelector('.name').textContent = d.label;
    if (d.kind === 'rollo'){
      t.querySelector('.state').textContent = (s.moving ? 'moving ' + s.moving + ' · ' : '') + (s.position ?? '?') + ' %';
      t.insertAdjacentHTML('beforeend', '<div class="win"><div class="fabric"></div></div><div class="row"><button data-c="up">▲</button>' + (s.favourite != null ? '<button data-c="favourite">●</button>' : '') + '<button data-c="down">▼</button></div>');
      t.querySelector('.fabric').style.height = (s.position || 0) + '%';
      t.querySelectorAll('button').forEach(b => b.onclick = e => { e.stopPropagation(); request(d.id, {command: b.dataset.c}); });
    } else {
      const left = s.off_at ? Math.max(0, Math.ceil((Date.parse(s.off_at) - Date.now()) / 60000)) : null;
      t.querySelector('.state').textContent = s.online === false ? 'not answering' : (s.on ? 'on' + (left != null ? ' · off in ' + left + ' min' : '') : 'off');
      t.onclick = () => { post({type:'haptic', style:'light'}); request(d.id, {on: !s.on}); };
    }
    grid.appendChild(t);
  }
  const cooking = modes.get('cooking'); const m = document.getElementById('mode');
  m.className = cooking && cooking.active ? 'show' : '';
}
document.getElementById('endMode').onclick = () => { const reqId = 'r' + (++reqs); post({type:'mode', reqId, id:'cooking', body:{active:false}}); };
window.flat3d = { receive(msg){
  if (!msg || typeof msg !== 'object') return false;
  if (msg.type === 'snapshot'){ devices.clear(); for (const d of msg.devices || []) devices.set(d.id, d); modes.clear(); for (const x of msg.modes || []) modes.set(x.id, x); }
  else if (msg.type === 'state'){ const d = devices.get(msg.id); if (!d) return false; d.state = Object.assign({}, d.state, msg.state); }
  else if (msg.type === 'mode'){ modes.set(msg.mode.id, msg.mode); }
  else if (msg.type === 'result'){ const id = pending[msg.reqId]; delete pending[msg.reqId]; busy.delete(id); document.getElementById('line').textContent = msg.ok ? '' : (msg.message || msg.error); }
  else if (msg.type === 'connection'){ document.getElementById('line').textContent = msg.status === 'offline' ? 'Not connected · last known state' : ''; }
  else if (msg.type === 'config'){ document.documentElement.className = msg.theme === 'light' ? 'light' : ''; if (msg.insets) document.documentElement.style.setProperty('--bars', (msg.insets.bottom || 0) + 'px'); document.querySelector('h1').textContent = 'Stand-in flat · ' + (msg.lighting === 'day' ? 'always day' : 'real sun'); }
  else return false;
  render(); return true; } };
setInterval(render, 15000);
post({type:'ready', devices:['fan:fan_1','fan:fan_2','rollo:blind_1','rollo:blind_2'], modes:['cooking']});
</script></body></html>
"""


IDENTITY_DIR = Path(__file__).resolve().parent.parent / "build" / "fake-flatd"


def identity(fresh: bool) -> tuple[Path, Path, str]:
    """The fake's key and certificate (made with openssl on first use, or anew), and its pin: the SHA-256 of the
    certificate's SubjectPublicKeyInfo, as flatd's contract defines `spki_sha256`."""
    key, cert = IDENTITY_DIR / "key.pem", IDENTITY_DIR / "cert.pem"
    if fresh or not (key.exists() and cert.exists()):
        IDENTITY_DIR.mkdir(parents=True, exist_ok=True)
        key.unlink(missing_ok=True)
        cert.unlink(missing_ok=True)
        previous = os.umask(0o077)
        try:
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)],
                           check=True, capture_output=True)
        finally:
            os.umask(previous)
        subprocess.run(["openssl", "req", "-new", "-x509", "-key", str(key), "-subj", "/CN=flatd", "-days", "730",
                        "-out", str(cert)], check=True, capture_output=True)
    public = subprocess.run(["openssl", "x509", "-in", str(cert), "-pubkey", "-noout"], check=True,
                            capture_output=True).stdout
    spki = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "der"], input=public, check=True,
                          capture_output=True).stdout
    return key, cert, hashlib.sha256(spki).hexdigest()


class TLSServer(ThreadingHTTPServer):
    """HTTPS only, as flatd on the home network. The handshake runs in each connection's own thread."""
    daemon_threads = True

    def __init__(self, address, handler, context: ssl.SSLContext):
        super().__init__(address, handler)
        self.socket = context.wrap_socket(self.socket, server_side=True, do_handshake_on_connect=False)

    def finish_request(self, request, client_address):
        try:
            request.settimeout(5)
            request.do_handshake()
            request.settimeout(None)
        except (OSError, ssl.SSLError):
            return          # not TLS, or a client that refused this identity: nothing was served
        super().finish_request(request, client_address)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--port", type=int, default=8790)
    parser.add_argument("--host", help="where to listen (default 0.0.0.0; 127.0.0.1 with --viewer or --devices)")
    parser.add_argument("--key", help="the key the app must send (default: a made-up fixed one; a fresh random one "
                                      "with --viewer or --devices)")
    parser.add_argument("--name", default="flatd (fake)", help="the Bonjour instance name")
    parser.add_argument("--no-bonjour", action="store_true")
    parser.add_argument("--travel", type=float, default=20, help="seconds a blind takes from open to closed")
    parser.add_argument("--latency", type=float, default=0, help="seconds every command waits before it answers")
    parser.add_argument("--extra", action="store_true", help="add a lamp besides the fans and blinds")
    parser.add_argument("--viewer", help="serve this HTML file at /viewer instead of the stand-in page "
                                         "(a local file; never commit a private page)")
    parser.add_argument("--devices", help='a local JSON list of devices instead of the made-up ones: '
                                          '[{"id": "fan:…", "label": "…"}, {"id": "rollo:…", "favourite": 48}, …]')
    parser.add_argument("--pairing", action="store_true", help="print the pairing code only, and exit")
    parser.add_argument("--new-identity", action="store_true",
                        help="make a new key and certificate, as if flatd had lost its identity")
    args = parser.parse_args()
    if args.port in (8787, 8788):
        sys.exit("8787 and 8788 are the real flatd's ports; pick another one.")

    private = bool(args.viewer or args.devices)
    # Local private files stay on this Mac: only loopback, no Bonjour, and a key nobody else knows (the simulator reaches
    # 127.0.0.1). Opening them to the network takes an explicit --host.
    if args.host is None:
        args.host = "127.0.0.1" if private else "0.0.0.0"
    if args.key is None:
        args.key = secrets.token_hex(16) if private else DEFAULT_KEY
    if private and args.host == "127.0.0.1":
        args.no_bonjour = True
    key_file, cert_file, pin = identity(args.new_identity)
    pairing = json.dumps({"url": f"https://127.0.0.1:{args.port}", "token": args.key, "spki_sha256": pin},
                         separators=(",", ":"))
    if args.pairing:
        if private and args.key != DEFAULT_KEY and "--key" not in sys.argv:
            sys.exit("With --viewer or --devices the key is made up anew on every start: pass --key to both runs, "
                     "or copy the pairing code the running fake printed.")
        print(pairing)
        return
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert_file, key_file)
    devices = json.loads(open(args.devices).read()) if args.devices else None
    viewer_file = Path(args.viewer) if args.viewer else None
    flat = Flat(travel=args.travel, extra=args.extra, devices=devices)
    server = TLSServer((args.host, args.port), make_handler(flat, args.key, args.latency, viewer_file), context)

    def ticking():
        while True:
            time.sleep(1)
            flat.tick()

    threading.Thread(target=ticking, daemon=True).start()
    bonjour = None
    if not args.no_bonjour:
        bonjour = subprocess.Popen(["dns-sd", "-R", args.name, "_flatd._tcp", "local", str(args.port), "version=fake"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop(*_):
        # Out of serve_forever through the same path as Ctrl-C (shutdown() from this thread would wait for itself).
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    print(f"fake flatd on https://127.0.0.1:{args.port}  identity: {' '.join(pin[i:i + 4] for i in range(0, 16, 4))}"
          + ("" if args.no_bonjour else f"  Bonjour: {args.name!r}"), flush=True)
    print(f"pairing code: {pairing}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if bonjour:
            bonjour.terminate()


if __name__ == "__main__":
    main()
