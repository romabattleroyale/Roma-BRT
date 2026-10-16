# SENTINEL ONE
Android-first home-security command center built with Flutter.

## Current state
- Dark dashboard with violet/cyan accents.
- Home plan editor: manually place, rename and remove camera markers; positions persist locally on the phone. This is not automatic AR/3D reconstruction.
- Device list and event log start empty; no fake connected cameras or fake alarm events are presented.
- The primary camera-phone-to-monitor-phone flow now uses the experimental custom WebSocket JPEG relay at `/stream/<ROOM>`. The camera phone captures frames, encodes JPEG and sends them through the server; the viewer renders received frames. This is a server-relayed stream, not direct LAN transport and not WebRTC.
- The older WebRTC implementation and `/signal/<ROOM>` signaling route remain in the repository, but the current camera/viewer entry screens route through the custom JPEG transport.
- Protection remains marked as not configured until real devices are linked.
- Session lifecycle events are stored locally on-device (up to 100 entries), and the user can clear the history.
- The camera role includes experimental local MP4 recording; Android MediaRecorder support must be validated on a physical device.
- A VLC-backed RTSP player can open compatible IP camera streams. Tapo/EZVIZ support depends on the specific model/firmware exposing a local stream; this is not vendor-cloud integration.
- IP camera profiles can be saved, selected and deleted; stream URLs, which may contain credentials, are stored using Android secure storage.
- Optional image-difference motion analysis runs locally while an RTSP stream is open. It is a basic detector, not a certified alarm system.

## Local and remote viewing
- **Current transport:** both local and remote modes connect to the configured WebSocket relay. Local mode does not currently make a direct phone-to-phone LAN connection.
- **Remote mode:** requires a reachable WSS deployment and internet access on both devices.
- **Pairing:** the QR contains the relay URL and random room code. If `SIGNAL_TOKEN` is configured on the server, enter the same token manually on both phones.
- **Security:** the room code is a prototype pairing capability, not account authentication. It currently does not expire automatically; stop the camera session and generate a new code to end that pairing.
- **Bandwidth:** JPEG video is relayed through the server, so server bandwidth, latency, and free-host sleep limits can affect playback.

## Current limitations and safety
End-to-end streaming has **not yet been verified on two physical phones**. Passing automated tests confirms the server protocol and static checks, not camera permissions, device-specific YUV encoding, real-world frame rate, Render availability or live playback. The default endpoint `wss://sentinel-one-signaling.onrender.com` must be confirmed Live and running the latest server code before testing; its hostname in the app does not prove deployment health.

Not implemented: account-based camera access, automatically expiring per-device credentials, ONVIF device discovery, Tapo/EZVIZ cloud integration, secure RTSP-to-remote gateway, automatic AR/3D home reconstruction, and production-grade alarm delivery. The dashboard overview drawing remains illustrative; the separate plan editor saves manually placed markers. Do not rely on this development build as a security system.

## Deploy the relay (Render blueprint)
A starter deployment blueprint is provided in `render.yaml`. In Render, create a Blueprint from this repository and confirm the `sentinel-one-signaling` web service. The blueprint binds to the platform-assigned port and does not create a `SIGNAL_TOKEN` secret by default.

1. Confirm the service is Live in Render and deploys the latest commit containing `server/stream_relay.py`.
2. On the camera phone, open the camera role and display the pairing QR.
3. On the monitor phone, scan the QR and connect. If a `SIGNAL_TOKEN` is configured, enter it manually on both devices.
4. Test first with both phones on the same Wi-Fi, then separately test the monitor over mobile data.
5. To end a pairing, stop the camera session and generate a new room code.

The server exposes `/stream/<ROOM>` for binary JPEG relay and the legacy `/signal/<ROOM>` route for WebRTC signaling. It allows one camera and one viewer per stream room and applies basic per-IP connection throttling. This is a development service, not production-hardened; configure TLS/WSS, strong credentials and monitoring before wider use. Free hosting may sleep when idle and relay video bandwidth can be costly.

## Checks and manual Android build
GitHub Actions runs Python server tests, Flutter static analysis and Flutter tests. **The GitHub Actions workflows do not build an APK.** The repository owner handles APK builds manually through Codemagic.

For a local build environment with Flutter and Android SDK:
```sh
flutter create --platforms=android --org com.sentinelone .
python3 tool/configure_android.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Configure Android signing before distributing a signed release.

## Connection setup UI
Choose whether this phone is the camera or monitor, then select local Wi-Fi or remote access. Enter the relay URL and room code, explicitly start the camera or connect the viewer, and check the displayed connection status. The camera role displays a QR containing the relay URL and room code; the monitor can scan it. The QR does not include a shared token. Both modes currently use the configured WebSocket relay, so selecting local mode does not guarantee direct LAN routing.

## Legacy WebRTC signaling
The `/signal/<ROOM>` route remains available for the older WebRTC implementation and relays SDP offers/answers and ICE candidates; it does not carry media. The primary camera/viewer screens currently use the custom JPEG route instead. TURN configuration is relevant to the legacy WebRTC flow, not a substitute for verifying the custom relay deployment.
