# SENTINEL ONE
Android-first home-security command center built with Flutter.

## Current state
- Premium dark dashboard with violet/cyan accents.
- Illustrative home plan with camera markers.
- Camera/device list, demo event log, settings and interactive protection switch.
- Local camera preview now uses the WebRTC media engine, preparing the capture path for peer-to-peer video.
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
This repository currently contains the Flutter UI foundation, not a functioning surveillance system. The WebRTC camera preview captures video locally, but it does not yet send it to another phone. Actual peer-to-peer live streaming, secure local pairing, remote signaling/TURN infrastructure, authentication, push notifications, persistent event storage, Tapo RTSP/ONVIF integration and real AR/3D reconstruction are not implemented yet. Do not treat demo status or events as actual security monitoring.

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
The app now includes an explicit connection setup screen for choosing the intended camera/viewer workflow and understanding local vs remote requirements. This is setup guidance only: it does not establish a session or transmit video until a signaling service and WebRTC transport are implemented and configured.


## WebRTC signaling service (development foundation)

A minimal WebSocket relay is available in `server/signaling_server.py`. It relays only WebRTC SDP offers/answers and ICE candidates; it does **not** carry video. The service currently uses short room codes as a development join mechanism and is **not production-secure** on its own.

Before deployment or use outside a trusted test environment, add authenticated short-lived room tokens, WSS/TLS termination, origin/access controls, rate limiting and monitoring. Remote access also needs TURN credentials and a deployment endpoint. The Flutter app does not yet connect to this service, so cross-device streaming is not enabled in the current APK.
