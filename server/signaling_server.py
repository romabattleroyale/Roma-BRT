"""SENTINEL ONE signaling and short-lived QR pairing service.

WebRTC media is peer-to-peer; this service handles pairing and SDP/ICE only.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
import re
import secrets
import time
from collections import defaultdict
from dataclasses import dataclass, field
from urllib.parse import urlsplit

from aiohttp import web, WSMsgType

ROOM_RE = re.compile(r"^[A-Z2-9]{6,10}$")
MAX_MESSAGE_BYTES = 64 * 1024
MAX_PEERS_PER_ROOM = 2
PAIR_TTL_SECONDS = 180
ROOM_TTL_SECONDS = 24 * 60 * 60


@dataclass
class Room:
    camera_token_hash: str
    viewer_token_hash: str
    expires_at: float
    peers: set[web.WebSocketResponse] = field(default_factory=set)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


@dataclass
class PairTicket:
    room: str
    camera_token: str
    expires_at: float


rooms: dict[str, Room] = {}
tickets: dict[str, PairTicket] = {}
rate_windows: dict[str, list[float]] = defaultdict(list)


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _new_room() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    while True:
        code = "".join(secrets.choice(alphabet) for _ in range(8))
        if code not in rooms:
            return code


def _rate_limit(request: web.Request, key: str, limit: int = 20) -> None:
    now = time.monotonic()
    entries = [stamp for stamp in rate_windows[key] if now - stamp < 60]
    if len(entries) >= limit:
        raise web.HTTPTooManyRequests(text="Troppe richieste. Riprova tra poco.")
    entries.append(now)
    rate_windows[key] = entries


async def create_pair(request: web.Request) -> web.Response:
    _rate_limit(request, "create:" + (request.remote or "unknown"), 10)
    now = time.time()
    for code in [code for code, room in rooms.items() if room.expires_at <= now]:
        rooms.pop(code, None)
    for ticket in [key for key, item in tickets.items() if item.expires_at <= now]:
        tickets.pop(ticket, None)
    room_code = _new_room()
    camera_token = secrets.token_urlsafe(32)
    ticket = secrets.token_urlsafe(32)
    rooms[room_code] = Room(
        camera_token_hash=_hash(camera_token),
        viewer_token_hash="",
        expires_at=now + ROOM_TTL_SECONDS,
    )
    tickets[_hash(ticket)] = PairTicket(room_code, camera_token, now + PAIR_TTL_SECONDS)
    return web.json_response({
        "room": room_code,
        "ticket": ticket,
        "cameraToken": camera_token,
        "expiresIn": PAIR_TTL_SECONDS,
        "server": request.app["public_server"],
    })


async def consume_pair(request: web.Request) -> web.Response:
    _rate_limit(request, "consume:" + (request.remote or "unknown"), 30)
    try:
        body = await request.json()
    except (json.JSONDecodeError, web.HTTPBadRequest):
        raise web.HTTPBadRequest(text="Richiesta non valida.")
    ticket = body.get("ticket") if isinstance(body, dict) else None
    if not isinstance(ticket, str) or len(ticket) < 20:
        raise web.HTTPBadRequest(text="Codice QR non valido.")
    pair = tickets.pop(_hash(ticket), None)
    if pair is None or pair.expires_at <= time.time():
        raise web.HTTPGone(text="QR scaduto o già utilizzato. Genera un nuovo codice dal telefono telecamera.")
    room = rooms.get(pair.room)
    if room is None or room.expires_at <= time.time() or room.viewer_token_hash:
        raise web.HTTPGone(text="Associazione non più disponibile. Genera un nuovo QR.")
    viewer_token = secrets.token_urlsafe(32)
    room.viewer_token_hash = _hash(viewer_token)
    return web.json_response({
        "room": pair.room,
        "viewerToken": viewer_token,
        "expiresIn": int(room.expires_at - time.time()),
        "server": request.app["public_server"],
    })


async def pair_status(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except (json.JSONDecodeError, web.HTTPBadRequest):
        raise web.HTTPBadRequest(text="Richiesta non valida.")
    room_code = body.get("room") if isinstance(body, dict) else None
    camera_token = body.get("cameraToken") if isinstance(body, dict) else None
    if not isinstance(room_code, str) or not ROOM_RE.fullmatch(room_code):
        raise web.HTTPBadRequest(text="Stanza non valida.")
    room = rooms.get(room_code)
    if room is None or room.expires_at <= time.time():
        raise web.HTTPGone(text="Associazione scaduta.")
    if not isinstance(camera_token, str) or not secrets.compare_digest(_hash(camera_token), room.camera_token_hash):
        raise web.HTTPUnauthorized(text="Credenziale telecamera non valida.")
    return web.json_response({"paired": bool(room.viewer_token_hash)})


async def websocket_signal(request: web.Request) -> web.StreamResponse:
    code = request.match_info.get("room", "").upper()
    if not ROOM_RE.fullmatch(code):
        raise web.HTTPBadRequest(text="Codice stanza non valido.")
    room = rooms.get(code)
    if room is None or room.expires_at <= time.time():
        raise web.HTTPGone(text="Associazione scaduta. Scansiona un nuovo QR.")
    authorization = request.headers.get("Authorization", "")
    supplied = authorization.removeprefix("Bearer ").strip() if authorization.startswith("Bearer ") else ""
    supplied_hash = _hash(supplied) if supplied else ""
    if not (secrets.compare_digest(supplied_hash, room.camera_token_hash) or
            (room.viewer_token_hash and secrets.compare_digest(supplied_hash, room.viewer_token_hash))):
        raise web.HTTPUnauthorized(text="Credenziale di associazione non valida.")

    ws = web.WebSocketResponse(max_msg_size=MAX_MESSAGE_BYTES, heartbeat=20)
    await ws.prepare(request)
    async with room.lock:
        if len(room.peers) >= MAX_PEERS_PER_ROOM:
            await ws.close(code=1013, message=b"Room is full")
            return ws
        room.peers.add(ws)
        peers = tuple(peer for peer in room.peers if peer is not ws)
    await ws.send_json({"type": "ready", "peers": len(peers)})
    for other in peers:
        await other.send_json({"type": "peer_joined"})
    try:
        async for message in ws:
            if message.type == WSMsgType.TEXT:
                try:
                    payload = json.loads(message.data)
                except json.JSONDecodeError:
                    await ws.close(code=1007, message=b"Invalid JSON")
                    break
                if not isinstance(payload, dict) or payload.get("type") not in {"offer", "answer", "ice", "hangup"}:
                    await ws.send_json({"type": "error", "message": "Unsupported signal"})
                    continue
                async with room.lock:
                    recipients = tuple(peer for peer in room.peers if peer is not ws)
                for other in recipients:
                    await other.send_json(payload)
            elif message.type in (WSMsgType.ERROR, WSMsgType.CLOSE, WSMsgType.CLOSED):
                break
    finally:
        async with room.lock:
            room.peers.discard(ws)
            remaining = tuple(room.peers)
        for other in remaining:
            try:
                await other.send_json({"type": "peer_left"})
            except (ConnectionError, RuntimeError):
                pass
    return ws


async def health(request: web.Request) -> web.Response:
    return web.json_response({"service": "sentinel-one-signaling", "status": "ok"})


def create_app() -> web.Application:
    app = web.Application(client_max_size=16 * 1024)
    app["public_server"] = os.getenv(
        "PUBLIC_SERVER", "wss://sentinel-one-signaling.onrender.com"
    ).rstrip("/")
    app.router.add_get("/health", health)
    app.router.add_post("/pair/create", create_pair)
    app.router.add_post("/pair/consume", consume_pair)
    app.router.add_post("/pair/status", pair_status)
    app.router.add_get("/signal/{room}", websocket_signal)
    return app


if __name__ == "__main__":
    host = os.getenv("SIGNAL_HOST", "127.0.0.1")
    port = int(os.getenv("PORT", os.getenv("SIGNAL_PORT", "8765")))
    web.run_app(create_app(), host=host, port=port, print=lambda msg: print(msg))
