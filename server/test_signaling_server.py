"""Integration tests for the WebSocket signaling relay.

Run with: python -m unittest discover -s server -p 'test_*.py'
"""
import asyncio
import base64
import json
import os
import time
import unittest
from unittest.mock import patch

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from signaling_server import handler, ice_server_config, validate_bind_security


class SignalingRelayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.server = await serve(handler, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]
        self.url = f"ws://127.0.0.1:{self.port}/signal/TEST234"

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()

    async def test_two_peers_exchange_signals(self):
        async with connect(self.url) as sender:
            ready = json.loads(await sender.recv())
            self.assertEqual(ready["type"], "ready")
            self.assertEqual(ready["peers"], 0)

            async with connect(self.url) as viewer:
                viewer_ready = json.loads(await viewer.recv())
                self.assertEqual(viewer_ready["type"], "ready")
                self.assertEqual(viewer_ready["peers"], 1)
                self.assertTrue(viewer_ready["iceServers"])
                joined = json.loads(await sender.recv())
                self.assertEqual(joined["type"], "peer_joined")

                offer = {"type": "offer", "sdp": "test-sdp"}
                await sender.send(json.dumps(offer))
                self.assertEqual(json.loads(await viewer.recv()), offer)

                answer = {"type": "answer", "sdp": "test-answer"}
                await viewer.send(json.dumps(answer))
                self.assertEqual(json.loads(await sender.recv()), answer)

                candidate = {"type": "ice", "candidate": {"candidate": "test"}}
                await sender.send(json.dumps(candidate))
                self.assertEqual(json.loads(await viewer.recv()), candidate)


    async def test_ice_server_config_supports_multiple_stun_urls(self):
        with patch.dict(os.environ, {
            "STUN_URLS": "stun:first.example:3478, stun:second.example:3478",
        }, clear=True):
            servers = ice_server_config()
        self.assertEqual(servers[0]["urls"], [
            "stun:first.example:3478",
            "stun:second.example:3478",
        ])

    async def test_invalid_turn_ttl_falls_back_to_default(self):
        with patch.dict(os.environ, {
            "TURN_URLS": "turn:turn.example:3478",
            "TURN_SHARED_SECRET": "server-only-secret",
            "TURN_TTL_SECONDS": "not-a-number",
        }, clear=True):
            servers = ice_server_config()
        expiry = int(servers[1]["username"].split(":", 1)[0])
        self.assertGreaterEqual(expiry, int(time.time()) + 3599)

    async def test_ice_server_config_reads_turn_credentials_from_environment(self):
        with patch.dict(os.environ, {
            "STUN_URLS": "stun:stun.example:3478",
            "TURN_URLS": "turn:turn.example:3478,turns:turn.example:5349",
            "TURN_USERNAME": "sentinel-user",
            "TURN_CREDENTIAL": "test-secret",
        }, clear=True):
            servers = ice_server_config()
        self.assertEqual(servers[0]["urls"], "stun:stun.example:3478")
        self.assertEqual(servers[1]["urls"], ["turn:turn.example:3478", "turns:turn.example:5349"])
        self.assertEqual(servers[1]["username"], "sentinel-user")
        self.assertEqual(servers[1]["credential"], "test-secret")

    async def test_ice_server_config_generates_expiring_turn_credentials(self):
        with patch.dict(os.environ, {
            "TURN_URLS": "turn:turn.example:3478",
            "TURN_SHARED_SECRET": "server-only-secret",
            "TURN_USERNAME": "sentinel",
            "TURN_TTL_SECONDS": "3600",
        }, clear=True):
            servers = ice_server_config()
        username = servers[1]["username"]
        credential = servers[1]["credential"]
        expiry = int(username.split(":", 1)[0])
        self.assertGreaterEqual(expiry, int(time.time()) + 299)
        self.assertTrue(username.endswith(":sentinel"))
        self.assertEqual(len(base64.b64decode(credential)), 20)
        self.assertNotIn("server-only-secret", json.dumps(servers))

    async def test_ice_server_config_has_public_stun_fallback(self):
        with patch.dict(os.environ, {}, clear=True):
            servers = ice_server_config()
        self.assertEqual(servers, [{"urls": "stun:stun.l.google.com:19302"}])

    async def test_public_bind_supports_random_room_code_pairing(self):
        # Random room codes are the prototype pairing capability. An optional
        # global token can still be enabled for private deployments.
        validate_bind_security("0.0.0.0", "")
        validate_bind_security("127.0.0.1", "")
        validate_bind_security("0.0.0.0", "configured-secret")

    async def test_invalid_room_code_is_rejected(self):
        async with connect(
            f"ws://127.0.0.1:{self.port}/signal/room!"
        ) as peer:
            with self.assertRaises(ConnectionClosed):
                await peer.recv()


    async def test_configured_token_rejects_missing_or_wrong_token(self):
        with patch.dict("os.environ", {"SIGNAL_TOKEN": "secret-for-tests"}):
            for headers in ({}, {"Authorization": "Bearer wrong"}):
                async with connect(self.url, additional_headers=headers) as peer:
                    with self.assertRaises(ConnectionClosed):
                        await peer.recv()

    async def test_configured_token_accepts_matching_token(self):
        with patch.dict("os.environ", {"SIGNAL_TOKEN": "secret-for-tests"}):
            async with connect(self.url, additional_headers={"Authorization": "Bearer secret-for-tests"}) as peer:
                ready = json.loads(await peer.recv())
                self.assertEqual(ready["type"], "ready")
                self.assertEqual(ready["peers"], 0)
                self.assertTrue(ready["iceServers"])

    async def test_third_peer_is_rejected(self):
        async with connect(self.url) as first:
            await first.recv()
            async with connect(self.url) as second:
                await second.recv()
                await first.recv()  # peer_joined
                third = await connect(self.url)
                try:
                    with self.assertRaises(ConnectionClosed):
                        await third.recv()
                finally:
                    await third.close()


if __name__ == "__main__":
    unittest.main()
