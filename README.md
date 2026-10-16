# SENTINEL ONE
Android-first home-security command center built with Flutter.

## Current state
- Premium dark dashboard with violet/cyan accents.
- Illustrative home plan with camera markers.
- Camera/device list, demo event log, settings and interactive protection switch.
- WebRTC camera-to-viewer session flow is implemented in the app: camera capture, viewer receive-only track, SDP offer/answer and ICE exchange through the signaling WebSocket.
- UI labels demo states explicitly.

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
The app now contains the WebRTC session flow and a signaling relay development service, but **end-to-end streaming has not yet been verified on two physical phones**. No signaling service is deployed for the app, so the server address must be configured before a session can connect. The default local address is a placeholder and must be replaced with the host running the relay. Remote access still needs a published WSS endpoint, authenticated pairing, TURN infrastructure and security hardening. Push notifications, persistent event storage, Tapo RTSP/ONVIF integration and real AR/3D reconstruction are not implemented. The dashboard's plan, device states and event list remain illustrative/demo data; do not rely on this build as a security system.

## Build
Flutter and Android SDK:
```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
The GitHub Actions workflow checks the code and builds an APK artifact. Configure Android signing before distributing a signed release.


## Connection setup UI
Choose whether this phone is the camera or monitor, then select local Wi-Fi or remote access. The next screen lets you enter the signaling server and room code, explicitly start the camera or connect the viewer, and see connection status. Local mode still requires a signaling server reachable from both phones; remote mode requires `wss://`.


## WebRTC signaling service (development foundation)

A minimal WebSocket relay is available in `server/signaling_server.py`. It relays only WebRTC SDP offers/answers and ICE candidates; it does **not** carry video. The service currently uses short room codes as a development join mechanism and is **not production-secure** on its own.

For remote deployment, set the environment variable `SIGNAL_TOKEN` to a long random secret and enter the same token in the app. The relay validates it using a constant-time comparison. The token is a basic shared-secret gate, not full user/account authentication. Before production use, add short-lived per-room credentials, WSS/TLS termination, origin/access controls, rate limiting and monitoring. Remote access also needs TURN credentials and a deployment endpoint. The Flutter app connects to this WebSocket protocol, but the included service is only a development relay. It is not deployed automatically by the GitHub Actions build and is not safe to expose publicly as-is.
