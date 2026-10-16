import 'dart:convert';

/// Validated data encoded in the SENTINEL ONE camera pairing QR.
class PairingPayload {
  const PairingPayload({required this.server, required this.room});

  final Uri server;
  final String room;

  /// Validates the signaling service base URL used by both manual setup and QR pairing.
  /// Only a root endpoint is accepted; session paths are appended by the app.
  static Uri parseServer(String raw) {
    final server = Uri.tryParse(raw.trim());
    if (server == null ||
        (server.scheme != 'ws' && server.scheme != 'wss') ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        (server.path.isNotEmpty && server.path != '/') ||
        server.hasQuery ||
        server.hasFragment) {
      throw const FormatException('Invalid signaling endpoint');
    }
    return server;
  }

  /// Parses a QR payload and rejects malformed endpoints or room codes.
  /// Credentials must never be embedded in the QR URL.
  static PairingPayload parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Expected a JSON object');

    final rawServer = decoded['server'];
    final rawRoom = decoded['room'];
    if (rawServer is! String || rawRoom is! String) {
      throw const FormatException('Missing server or room');
    }

    final server = parseServer(rawServer);

    final room = rawRoom.trim().toUpperCase();
    if (!RegExp(r'^[A-Z2-9]{6,10}$').hasMatch(room)) {
      throw const FormatException('Invalid room code');
    }

    return PairingPayload(server: server, room: room);
  }
}
