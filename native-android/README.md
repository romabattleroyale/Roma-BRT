# SENTINEL ONE — Native Android rebuild

This is the new Android-native implementation track. It is separate from the legacy Flutter client while the native path is built and validated.

## Architecture
- Kotlin + Jetpack Compose for a native Android interface.
- Google Nearby Connections for device discovery and pairing between nearby Android phones.
- The pairing path does not depend on the Render signaling endpoint or WebRTC.
- The first milestone is direct discovery and connection; live camera payload streaming, permissions hardening, reconnect handling, recording and end-to-end two-device verification remain follow-up work.

## Build
From this directory, with JDK 17 and Gradle 8.9:
`gradle assembleDebug`

The GitHub Actions workflow builds the native debug APK and uploads it as an artifact. This project has not yet been validated on two physical phones.
