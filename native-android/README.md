# SENTINEL ONE — Native Android rebuild

This is the native Android implementation track, separate from the legacy Flutter client.

## Native stack
- Kotlin + Jetpack Compose for the Android interface.
- CameraX for camera capture.
- Google Nearby Connections for discovery, pairing and nearby payload delivery.
- No Render or WebRTC dependency in this native pairing path.

## Current prototype functions
- Camera and monitor roles.
- Nearby device discovery and connection acceptance.
- Camera capture at a low-resolution, low-frame-rate prototype setting.
- JPEG frame downscaling/compression and sending as Nearby byte payloads.
- Monitor-side decoding and live frame display.
- Connection state and sent/received frame counters.
- Compile-only CI validation. CI does not package an APK; APK generation is handled separately by the project owner in Codemagic.

## Known limitations
- This is a first native streaming prototype, not a production-ready security camera app.
- The Nearby byte-payload path deliberately limits individual JPEG frames to 28 KiB, so image quality and frame rate are limited.
- Automatic reconnect, secure device identity/pairing persistence, background operation, audio, recording, night mode, motion detection and gallery export are not implemented yet.
- Compilation and code checks are not a substitute for validation on two physical Android phones. The end-to-end link still needs that verification.

## Compile-only check
With JDK 17 and Gradle 8.9:
`gradle compileDebugKotlin`

This checks Kotlin sources without creating an APK.
