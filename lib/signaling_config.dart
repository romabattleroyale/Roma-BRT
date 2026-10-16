/// Default WebSocket endpoint used for WebRTC signaling between paired phones.
/// The server exchanges SDP/ICE at `/signal/<ROOM>`; media flows phone-to-phone via WebRTC.
/// Use a TURN relay for networks where direct peer-to-peer ICE cannot connect.
const String defaultSignalingServerUrl =
    'wss://sentinel-one-signaling.onrender.com';
