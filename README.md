# SENTINEL ONE
Android-first home-security command center built with Flutter.

## Current state
- Premium dark dashboard with violet/cyan accents.
- Home plan editor: manually place, rename and remove camera markers; positions persist locally on the phone. This is not automatic AR/3D reconstruction.
- Device list and event log start empty; no fake connected cameras or fake alarm events are presented.
- WebRTC camera-to-viewer session flow is implemented in the app: camera capture, viewer receive-only track, SDP offer/answer and ICE exchange through the signaling WebSocket.
- Protection remains marked as not configured until real devices are linked.
- Actual session lifecycle events are stored locally on-device (up to 100 entries), and the user can clear the history.
- The camera role includes experimental local MP4 recording and an in-app recording library; Android MediaRecorder support must be validated on a physical device.
- A VLC-backed RTSP player can open compatible local IP camera streams, including Tapo/EZVIZ models only when the specific model/firmware exposes RTSP. This is not vendor-cloud integration.
- For an open RTSP stream, optional on-device image-difference analysis can log motion events and show local Android notifications. It runs only while that screen is active and is a basic detector, not a certified alarm system.

## Product requirement: local and remote viewing
SENTINEL ONE must support viewing cameras both at home and away from home:
- **Local mode:** prefer a direct connection over the home Wi-Fi/LAN when the viewer and camera phone are on the same network.
- **Remote mode:** allow an authenticated viewer to connect over the internet, including when the viewer uses mobile data.
- **Secure pairing:** each camera phone must be explicitly paired with the user's account or home, and access must be revocable.
- **Transport security:** use encrypted connections and short-lived credentials; do not expose an unauthenticated camera stream to the public internet.
- **Connectivity:** use WebRTC for live video where appropriate, a secure signaling service for pairing/session setup, and a TURN relay when direct peer-to-peer connectivity is blocked by NAT or carrier networks.
- **Privacy and resilience:** clearly show connection status, avoid recording by default, and never label a demo state as a real camera state.

Remote viewing is a core requirement, not an optional later add-on. Local Wi-Fi alone cannot provide access from outside the home. The remote signaling/relay service and Android permissions must be configured and tested before this can be considered a functioning security system.

## Current limitations
The app now contains the WebRTC session flow and a signaling relay development service, but **end-to-end streaming has not yet been verified on two physical phones**. The app now pre-fills the known development relay endpoint `wss://sentinel-one-signaling.onrender.com` in remote mode. The QR pairs the phones using a random room code, so no shared server token is required for the prototype relay. A `SIGNAL_TOKEN` can still be configured for private deployments; if enabled, it must be entered on both phones. The code is a pairing capability, not full account authentication. The default local address `ws://192.168.1.10:8765` is only a LAN placeholder and must be replaced with the actual host running the relay. Remote access still needs end-to-end validation, TURN infrastructure, stronger per-device pairing and security hardening. Push notifications, persistent event storage, Tapo/EZVIZ cloud integration, ONVIF discovery, secure RTSP-to-WebRTC gateway for remote IP cameras and real AR/3D reconstruction are not implemented. The dashboard overview drawing remains illustrative; the separate plan editor saves user-placed markers locally. Device integrations and security controls are not yet production-ready; do not rely on this build as a security system.

## Deploy the signaling relay (Render blueprint)

A starter deployment blueprint is provided in `render.yaml`. In Render, create a new Blueprint from this repository and confirm the `sentinel-one-signaling` web service. The blueprint binds the relay to the platform-assigned port; it does **not** currently create a `SIGNAL_TOKEN` secret. The prototype therefore relies on the random room code and is not suitable as a production security service. After deployment:

1. The current app default is `wss://sentinel-one-signaling.onrender.com`. Confirm the service is Live in Render before testing; do not append `/signal/...` because the app adds that path itself.
2. Open the app on the camera phone and show the pairing QR. On the monitor phone, scan it; no shared token needs to be copied for the prototype relay.
3. Test with both phones first on the same Wi-Fi. For some carrier/NAT combinations, remote media also requires TURN credentials configured in the app.
4. To revoke a pairing, stop the camera session and generate a new room code.

This deploys only the signaling relay; it does not provision TURN or verify real-device video. The relay treats a random 8-character room code as a pairing capability while the camera is waiting for its peer and applies basic per-IP connection throttling. The room code does not currently expire automatically; stop the session and generate a new code to revoke it. This is not full account authentication and is not production-hardened. The free service may sleep when idle. Its hostname being configured does not prove the relay is reachable or media negotiation succeeds; verify on two physical phones before relying on it.

## Build
Flutter and Android SDK (the Android platform folder is generated by CI rather than committed):
```sh
flutter create --platforms=android --org com.sentinelone .
python3 tool/configure_android.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
The GitHub Actions workflow checks the code and builds an APK artifact. Configure Android signing before distributing a signed release.


## Connection setup UI
Choose whether this phone is the camera or monitor, then select local Wi-Fi or remote access. The next screen lets you enter the signaling server and room code, explicitly start the camera or connect the viewer, and see connection status. The camera role can display a pairing QR containing only the signaling URL and room code; the monitor can scan it to fill those fields. The QR carries the signaling URL and random room code; no shared token is needed unless the server operator explicitly enables one. Local mode still requires a signaling server reachable from both phones; remote mode requires `wss://`. A TURN relay may still be required by restrictive networks.


## WebRTC signaling service (development foundation)

A minimal WebSocket relay is available in `server/signaling_server.py`. It relays only WebRTC SDP offers/answers and ICE candidates; it does **not** carry video. The service currently uses short room codes as a development join mechanism and is **not production-secure** on its own.

For a private test deployment, you can set `SIGNAL_TOKEN` to a long random secret; enter the same token manually on both phones because the QR code does not contain it. The relay validates it using a constant-time comparison. This token is a basic shared-secret gate, not full user/account authentication. Before production use, add short-lived per-device/per-room credentials, WSS/TLS termination, origin/access controls, stronger rate limiting and monitoring. Remote access may also need TURN credentials. The included service is only a development relay, is not deployed by the GitHub Actions build, and must not be treated as a production-ready security system.
