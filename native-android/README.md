# SENTINEL ONE — Native Android rebuild

This is the native Android implementation track, separate from the legacy Flutter client.

## Native stack
- Kotlin + Jetpack Compose for the Android interface.
- CameraX for separate live-stream camera use and guided room photo/video capture.
- Google Nearby Connections for discovery, pairing and nearby streaming payload delivery.
- SceneView/Filament for the navigable 3D room model.
- SceneView ARSceneView + ARCore plane tracking for a preliminary in-room floor/wall survey.

## Camera and streaming prototype
- Camera and monitor roles, nearby device discovery and connection acceptance.
- JPEG frame downscaling/compression and sending as Nearby byte payloads.
- Monitor-side decoding and live frame display.
- Connection state and sent/received frame counters.
- The streaming protocol, frame send/receive callbacks and live-view path are separate from the house scan activities.

## House Builder prototype
- Guided CameraX photo and video capture, stored in separate folders by normalized room name under `SENTINEL_ONE_SCAN`.
- A standalone AR scan screen can use ARCore to detect tracked upward-facing horizontal planes and vertical wall planes while the user slowly surveys the room.
- The largest tracked floor plane's X/Z extents can be written as an **unconfirmed initial estimate** for that room's 2D/3D model. The scan evidence is also saved as JSON per room.
- Editable 2D room outline and a navigable SceneView/Filament 3D model use the same geometry in meters.
- Manual room dimensions and door/window position, width and height adjustments.
- Per-room local JSON project persistence and delayed automatic draft saving.

## Known limitations
- AR plane extents are an initial estimate of the observed plane, **not proof of the complete room perimeter**. Surfaces may only be partially observed and detected planes can change while tracking. Always verify the dimensions with real measurements before treating them as accurate.
- Automatic inference of doors/windows from photos/video, robust photogrammetric reconstruction, and assembly of multiple scans into a multi-room whole-house model are not implemented yet.
- AR support and tracking quality are device- and environment-dependent. On-device validation, including this app on a physical Xiaomi M11i 5G, is still required.
- The Nearby byte-payload path limits individual JPEG frames to 28 KiB, so streaming quality and frame rate are limited.
- Automatic reconnect, persistent secure device identity/pairing, background operation, audio, night mode, motion detection and gallery export are not implemented yet.
- GitHub Actions compiles Kotlin, builds a debug APK and uploads it as the `sentinel-one-debug-apk` artifact for 14 days. It is intended for testing and uses the debug signing key. Codemagic separately builds the release-variant APK.

## Build toolchain
- JDK 17
- Gradle 8.14.4
- Android Gradle Plugin 8.10.1
- Android `compileSdk = 36` (`targetSdk = 35` remains unchanged)

From the repository root, run the compile check with:
```sh
gradle -p native-android compileDebugKotlin
```

GitHub Actions also packages a debug APK. A green build proves compile/package compatibility, not that camera/AR behavior works on a physical device.
