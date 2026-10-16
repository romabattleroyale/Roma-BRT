"""Minimal WebSocket signaling relay for SENTINEL ONE WebRTC sessions.

This service exchanges SDP/ICE only; media travels over WebRTC, not through
this process. Deploy behind HTTPS/WSS with authentication, rate limiting and
short-lived room credentials before using outside a trusted test network.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import secrets
from collections import defaultdict
from dataclasses import dataclass, field

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

ROOM_RE = re.compile(r"^[A-Z2-9]{6,10}$")
MAX_MESSAGE_BYTES = 64 * 1024
MAX_PEERS_PER_ROOM = 2


@dataclass
class Room:
    peers: set[ServerConnection] = field(default_factory=set)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


rooms: dict[str, Room] = defaultdict(Room)


async def send_json(peer: ServerConnection, payload: dict) -> None:
    await peer.send(json.dumps(payload, separators=(",", ":")))


async def handler(peer: ServerConnection) -> None:
    room_code = ""
    try:
        path = peer.request.path
        parts = path.strip("/").split("/")
        if len(parts) != 2 or parts[0] != "signal":
            await peer.close(code=1008, reason="Invalid signaling path")
            return
        room_code = parts[1].upper()
        if not ROOM_RE.fullmatch(room_code):
            await peer.close(code=1008, reason="Invalid room code")
            return

        room = rooms[room_code]
        async with room.lock:
            if len(room.peers) >= MAX_PEERS_PER_ROOM:
                await peer.close(code=1013, reason="Room is full")
                return
            room.peers.add(peer)
            peers = tuple(p for p in room.peers if p is not peer)

        await send_json(peer, {"type": "ready", "peers": len(peers)})
        for other in peers:
            await send_json(other, {"type": "peer_joined"})

        async for raw in peer:
            if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_MESSAGE_BYTES:
                await peer.close(code=1009, reason="Message too large")
                break
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                await peer.close(code=1007, reason="Invalid JSON")
                break
            if not isinstance(message, dict) or message.get("type") not in {
                "offer", "answer", "ice", "hangup"
            }:
                await send_json(peer, {"type": "error", "message": "Unsupported signal"})
                continue
            async with room.lock:
                recipients = tuple(p for p in room.peers if p is not peer)
            for other in recipients:
                await send_json(other, message)
    except ConnectionClosed:
        pass
    finally:
        if room_code in rooms:
            room = rooms[room_code]
            async with room.lock:
                room.peers.discard(peer)
                remaining = tuple(room.peers)
                if not room.peers:
                    rooms.pop(room_code, None)
            for other in remaining:
                try:
                    await send_json(other, {"type": "peer_left"})
                except ConnectionClosed:
                    pass


async def main() -> None:
    host = os.getenv("SIGNAL_HOST", "127.0.0.1")
    port = int(os.getenv("SIGNAL_PORT", "8765"))
    async with serve(
        handler, host, port, max_size=MAX_MESSAGE_BYTES,
        ping_interval=20, ping_timeout=20,
    ):
        print(f"SENTINEL ONE signaling listening on {host}:{port}")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
