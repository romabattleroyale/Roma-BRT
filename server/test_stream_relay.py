"""Integration tests for the experimental binary video relay."""
import asyncio
import json
import unittest

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from stream_relay import stream_handler, stream_rooms


class StreamRelayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        stream_rooms.clear()
        self.server = await serve(stream_handler, "127.0.0.1", 0, max_size=1024 * 1024)
        self.port = self.server.sockets[0].getsockname()[1]
        self.url = f"ws://127.0.0.1:{self.port}/"

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()
        stream_rooms.clear()

    async def join(self, role, room="TEST234"):
        peer = await connect(self.url + room, max_size=1024 * 1024)
        await peer.send(json.dumps({"type": "join", "role": role}))
        return peer, json.loads(await peer.recv())

    async def test_camera_frame_is_forwarded_as_binary_to_viewer(self):
        camera, ready_camera = await self.join("camera")
        try:
            self.assertEqual(ready_camera["type"], "ready")
            self.assertFalse(ready_camera["peerPresent"])
            viewer, ready_viewer = await self.join("viewer")
            try:
                self.assertTrue(ready_viewer["peerPresent"])
                self.assertEqual(json.loads(await camera.recv())["type"], "peer_joined")
                frame = b"\xff\xd8sentinel-test-jpeg\xff\xd9"
                await camera.send(frame)
                self.assertEqual(await asyncio.wait_for(viewer.recv(), 1), frame)
            finally:
                await viewer.close()
        finally:
            await camera.close()

    async def test_viewer_cannot_send_video_frames(self):
        viewer, _ = await self.join("viewer", "VIEW234")
        try:
            await viewer.send(b"not-allowed")
            with self.assertRaises(ConnectionClosed):
                await asyncio.wait_for(viewer.recv(), 1)
        finally:
            await viewer.close()

    async def test_invalid_role_is_rejected(self):
        peer = await connect(self.url + "TEST234")
        try:
            await peer.send(json.dumps({"type": "join", "role": "admin"}))
            with self.assertRaises(ConnectionClosed):
                await peer.recv()
        finally:
            await peer.close()


if __name__ == "__main__":
    unittest.main()
