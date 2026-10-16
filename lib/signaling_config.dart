/// Default WebSocket endpoint used by the custom JPEG relay for pairing and video frames.
/// The server must expose `/stream/<ROOM>` and be deployed with WSS for Internet use.
const String defaultSignalingServerUrl =
    'wss://sentinel-one-signaling.onrender.com';
