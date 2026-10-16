"""Integration tests for QR pairing and room-scoped WebRTC signaling."""
import unittest

from aiohttp.test_utils import TestClient, TestServer

from signaling_server import create_app


class PairingTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.client = TestClient(TestServer(create_app()))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()

    async def test_ticket_is_single_use_and_credentials_are_room_scoped(self):
        created = await self.client.post("/pair/create", json={})
        self.assertEqual(created.status, 200)
        pair = await created.json()
        room = pair["room"]
        self.assertRegex(room, r"^[A-Z2-9]{8}$")
        self.assertTrue(pair["ticket"])
        self.assertTrue(pair["cameraToken"])
        waiting = await self.client.post("/pair/status", json={"room": room, "cameraToken": pair["cameraToken"]})
        self.assertEqual((await waiting.json())["paired"], False)

        consumed = await self.client.post("/pair/consume", json={"ticket": pair["ticket"]})
        self.assertEqual(consumed.status, 200)
        viewer = await consumed.json()
        self.assertEqual(viewer["room"], room)
        self.assertTrue(viewer["viewerToken"])
        ready = await self.client.post("/pair/status", json={"room": room, "cameraToken": pair["cameraToken"]})
        self.assertEqual((await ready.json())["paired"], True)

        reused = await self.client.post("/pair/consume", json={"ticket": pair["ticket"]})
        self.assertEqual(reused.status, 410)

        denied = await self.client.get(f"/signal/{room}")
        self.assertEqual(denied.status, 401)

        camera_ws = await self.client.ws_connect(
            f"/signal/{room}", headers={"Authorization": "Bearer " + pair["cameraToken"]}
        )
        self.assertEqual((await camera_ws.receive_json())["type"], "ready")
        viewer_ws = await self.client.ws_connect(
            f"/signal/{room}", headers={"Authorization": "Bearer " + viewer["viewerToken"]}
        )
        self.assertEqual((await viewer_ws.receive_json())["type"], "ready")
        self.assertEqual((await camera_ws.receive_json())["type"], "peer_joined")
        await viewer_ws.close()
        await camera_ws.close()

    async def test_unknown_ticket_is_rejected(self):
        response = await self.client.post("/pair/consume", json={"ticket": "this-is-an-unknown-ticket-with-enough-length"})
        self.assertEqual(response.status, 410)

    async def test_health_endpoint(self):
        response = await self.client.get("/health")
        self.assertEqual(response.status, 200)
        self.assertEqual((await response.json())["status"], "ok")


if __name__ == "__main__":
    unittest.main()
