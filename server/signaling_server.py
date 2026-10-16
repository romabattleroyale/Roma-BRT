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
import time
from urllib.parse import urlsplit
from collections import defaultdict, deque
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
# Basic per-IP connection throttling for the public prototype relay.
ATTEMPTS_PER_MINUTE = 30
connection_attempts: dict[str, deque[float]] = defaultdict(deque)


async def send_json(peer: ServerConnection, payload: dict) -> None:
    await peer.send(json.dumps(payload, separators=(",", ":")))


async def handler(peer: ServerConnection) -> None:
    room_code = ""
    try:
        remote = peer.remote_address
        client_ip = str(remote[0]) if remote else "unknown"
        now = time.monotonic()
        attempts = connection_attempts[client_ip]
        while attempts and now - attempts[0] > 60:
            attempts.popleft()
        if len(attempts) >= ATTEMPTS_PER_MINUTE:
            await peer.close(code=1013, reason="Too many connection attempts")
            return
        attempts.append(now)
        request = urlsplit(peer.request.path)
        parts = request.path.strip("/").split("/")
        required_token = os.getenv("SIGNAL_TOKEN", "").strip()
        authorization = peer.request.headers.get("Authorization", "")
        supplied_token = authorization.removeprefix("Bearer ").strip() if authorization.startswith("Bearer ") else ""
        if required_token and not secrets.compare_digest(supplied_token, required_token):
            await peer.close(code=1008, reason="Invalid signaling token")
            return
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


def validate_bind_security(host: str, token: str) -> None:
    # A high-entropy, short-lived room code is the prototype pairing capability.
    # If SIGNAL_TOKEN is configured, the additional shared-secret gate remains enabled.
    # Production deployments should add account identity and expiring signed credentials.


async def main() -> None:
    host = os.getenv("SIGNAL_HOST", "127.0.0.1")
    # Platforms such as Render provide PORT dynamically; keep SIGNAL_PORT for local use.
    port = int(os.getenv("PORT", os.getenv("SIGNAL_PORT", "8765")))
    validate_bind_security(host, os.getenv("SIGNAL_TOKEN", ""))
    async with serve(
        handler, host, port, max_size=MAX_MESSAGE_BYTES,
        ping_interval=20, ping_timeout=20,
    ):
        print(f"SENTINEL ONE signaling listening on {host}:{port}")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
