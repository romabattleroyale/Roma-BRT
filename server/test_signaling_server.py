"""Integration tests for the WebSocket signaling relay.

Run with: python -m unittest discover -s server -p 'test_*.py'
"""
import asyncio
import json
import unittest

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from signaling_server import handler


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
                self.assertEqual(viewer_ready, {"type": "ready", "peers": 1})
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

    async def test_invalid_room_code_is_rejected(self):
        async with connect(
            f"ws://127.0.0.1:{self.port}/signal/room!"
        ) as peer:
            with self.assertRaises(ConnectionClosed):
                await peer.recv()

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
