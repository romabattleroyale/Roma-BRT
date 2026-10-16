/// Shared development signaling endpoint used for both LAN and remote setup.
/// The relay exchanges SDP/ICE only; it does not proxy the video stream.
const String defaultSignalingServerUrl =
    'wss://sentinel-one-signaling.onrender.com';
