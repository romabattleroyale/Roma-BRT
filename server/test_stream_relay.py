"""Integration tests for the experimental binary video relay."""
import asyncio
import json
import unittest
from urllib.parse import urlsplit

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from stream_relay import stream_handler, stream_rooms


async def test_handler(peer):
    room_code = urlsplit(peer.request.path).path.strip("/").upper()
    await stream_handler(peer, room_code)


class StreamRelayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        stream_rooms.clear()
        self.server = await serve(test_handler, "127.0.0.1", 0, max_size=1024 * 1024)
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
                frame = b"\\xff\\xd8sentinel-test-jpeg\\xff\\xd9"
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

    async def test_invalid_room_code_is_rejected(self):
        peer = await connect(self.url + "ROOM!")
        try:
            with self.assertRaises(ConnectionClosed):
                await peer.recv()
        finally:
            await peer.close()

    async def test_camera_disconnect_notifies_viewer_and_cleans_room(self):
        camera, _ = await self.join("camera", "LEAVE23")
        viewer, _ = await self.join("viewer", "LEAVE23")
        try:
            self.assertEqual(json.loads(await camera.recv())["type"], "peer_joined")
            await camera.close()
            notice = json.loads(await asyncio.wait_for(viewer.recv(), 1))
            self.assertEqual(notice, {"type": "peer_left", "role": "camera"})
            for _ in range(20):
                room = stream_rooms.get("LEAVE23")
                if room is not None and room.camera is None:
                    break
                await asyncio.sleep(0.01)
            self.assertIsNone(stream_rooms["LEAVE23"].camera)
        finally:
            await viewer.close()
            await camera.close()

    async def test_duplicate_camera_role_is_rejected_without_replacing_first(self):
        camera, _ = await self.join("camera", "DUPL234")
        duplicate = None
        try:
            duplicate = await connect(self.url + "DUPL234")
            await duplicate.send(json.dumps({"type": "join", "role": "camera"}))
            with self.assertRaises(ConnectionClosed):
                await asyncio.wait_for(duplicate.recv(), 1)
            self.assertIsNotNone(stream_rooms["DUPL234"].camera)
        finally:
            if duplicate is not None:
                await duplicate.close()
            await camera.close()


if __name__ == "__main__":
    unittest.main()
