# SENTINEL ONE
Android-first home-security command center built with Flutter.

## Current state
- Premium dark dashboard with violet/cyan accents.
- Illustrative home plan with camera markers.
- Camera/device list, demo event log, settings and interactive protection switch.
- UI labels demo states explicitly.

## Limitations
This is a UI foundation, not a functioning surveillance system. Video streaming, secure local device pairing, Android phone sender mode, push notifications, persistent event storage, Tapo RTSP/ONVIF integration and real AR/3D reconstruction are not implemented yet. Do not treat demo status or events as actual security monitoring.

## Build
Flutter 3.27+ and Android SDK:
```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
Connect the repository in Codemagic and use `codemagic.yaml`. Configure Android signing in Codemagic before producing a signed release.
