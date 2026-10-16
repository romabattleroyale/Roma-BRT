# SENTINEL ONE — Native Android

SENTINEL ONE is being rebuilt as a **native Android application in Kotlin**. The active client is under `native-android/`; the previous Flutter client and its relay/server infrastructure have been removed from this branch.

## Native stack
- Kotlin and Jetpack Compose for the Android interface.
- CameraX for camera capture.
- Google Nearby Connections for discovery, pairing and direct nearby payload delivery.
- No Flutter, Dart, WebRTC, Render signaling server, Docker relay or Python backend in this project.

## Implemented in the current prototype
- Select this phone as **Camera** or **Monitor**.
- Discover nearby monitors and request a connection.
- Capture JPEG frames on the camera phone, reduce their size, and send them over Nearby Connections.
- Decode and display received frames on the monitor phone.
- Show connection status and sent/received frame counters.
- Switch between the front and rear camera while connected.
- Release the CameraX capture use case when stopping or disconnecting.

## Still in development
- End-to-end connection and live playback must be tested on two physical Android phones.
- Current frame size/rate is intentionally limited by Nearby byte-payload constraints.
- QR pairing, remembered trusted devices, reconnection, background camera service, audio, recording, motion detection, notifications, IP camera integrations and the full security dashboard are not yet implemented in this Kotlin prototype.
- Do not rely on this prototype as a production security system.

## Project layout
- `native-android/` — Android application and Gradle build.
- `.github/workflows/native-android.yml` — compile-only Kotlin check; it does not create an APK.
- `codemagic.yaml` — native Android build workflow for the repository owner to run when ready.

## Compile locally
Requires JDK 17 and Gradle 8.9 or compatible:

```sh
gradle -p native-android compileDebugKotlin
```

APK packaging is intentionally left to the repository owner via Codemagic. Do not treat a successful Kotlin compile as proof that pairing and live video work on real devices.
