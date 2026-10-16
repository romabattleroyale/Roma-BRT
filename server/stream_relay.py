"""Experimental binary video relay for SENTINEL ONE.

Protocol: connect to /stream/<ROOM>, send one JSON role message
({"type":"join","role":"camera"|"viewer"}), then the camera sends binary
JPEG/frame packets. This relay is transport-only: it does not capture or
encode camera video. Use WSS/TLS and short-lived pairing credentials publicly.
"""
from __future__ import annotations

import asyncio
import json
import re
from dataclasses import dataclass, field

from websockets.asyncio.server import ServerConnection
from websockets.exceptions import ConnectionClosed

ROOM_RE = re.compile(r"^[A-Z2-9]{6,10}$")
MAX_FRAME_BYTES = 1024 * 1024
MAX_CONTROL_BYTES = 4096
MAX_STREAM_PEERS = 2


@dataclass
class StreamRoom:
    camera: ServerConnection | None = None
    viewer: ServerConnection | None = None
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


stream_rooms: dict[str, StreamRoom] = {}
stream_rooms_lock = asyncio.Lock()


async def send_control(peer: ServerConnection, payload: dict) -> None:
    await peer.send(json.dumps(payload, separators=(",", ":")))


async def stream_handler(peer: ServerConnection, room_code: str) -> None:
    """Join a single camera/viewer room and forward binary frames camera→viewer."""
    if not ROOM_RE.fullmatch(room_code):
        await peer.close(code=1008, reason="Invalid room code")
        return

    room: StreamRoom | None = None
    role: str | None = None
    joined = False
    try:
        raw = await asyncio.wait_for(peer.recv(), timeout=10)
        if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_CONTROL_BYTES:
            await peer.close(code=1003, reason="Expected role JSON")
            return
        try:
            hello = json.loads(raw)
        except json.JSONDecodeError:
            await peer.close(code=1007, reason="Invalid JSON")
            return
        if not isinstance(hello, dict) or hello.get("type") != "join" or hello.get("role") not in {"camera", "viewer"}:
            await peer.close(code=1008, reason="Send join role camera or viewer")
            return
        role = hello["role"]

        duplicate_role = False
        async with stream_rooms_lock:
            room = stream_rooms.setdefault(room_code, StreamRoom())
            async with room.lock:
                if getattr(room, role) is not None:
                    duplicate_role = True
                    other = None
                else:
                    setattr(room, role, peer)
                    joined = True
                    other = room.viewer if role == "camera" else room.camera
        # Never wait for a WebSocket close handshake while holding either room
        # lock: a slow duplicate client must not block legitimate joins/leaves.
        if duplicate_role:
            await peer.close(code=1013, reason="Role already connected")
            return
        await send_control(peer, {"type": "ready", "role": role, "peerPresent": other is not None})
        if other is not None:
            await send_control(other, {"type": "peer_joined", "role": role})

        async for message in peer:
            if role != "camera":
                await peer.close(code=1008, reason="Viewer cannot send frames")
                break
            if not isinstance(message, bytes):
                await send_control(peer, {"type": "error", "message": "Binary frame required"})
                continue
            if not message or len(message) > MAX_FRAME_BYTES:
                await peer.close(code=1009, reason="Frame too large or empty")
                break
            async with room.lock:
                recipient = room.viewer
            if recipient is not None:
                try:
                    await recipient.send(message)
                except ConnectionClosed:
                    # Viewer handler will clear the slot.
                    continue
    except (ConnectionClosed, asyncio.TimeoutError):
        pass
    finally:
        if joined and room is not None and role is not None:
            async with stream_rooms_lock:
                async with room.lock:
                    if getattr(room, role) is peer:
                        setattr(room, role, None)
                    other = room.viewer if role == "camera" else room.camera
                    empty = room.camera is None and room.viewer is None
                    if empty and stream_rooms.get(room_code) is room:
                        stream_rooms.pop(room_code, None)
            if other is not None:
                try:
                    await send_control(other, {"type": "peer_left", "role": role})
                except ConnectionClosed:
                    pass
