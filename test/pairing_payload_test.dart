import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel_one/pairing_payload.dart';
import 'package:sentinel_one/signaling_config.dart';

void main() {
  group('PairingPayload', () {
    test('parses valid WSS endpoint and normalizes room code', () {
      final payload = PairingPayload.parse(jsonEncode({
        'server': defaultSignalingServerUrl,
        'room': 'ab23cd45',
      }));

      expect(payload.server.scheme, 'wss');
      expect(payload.server.host, 'sentinel-one-signaling.onrender.com');
      expect(payload.room, 'AB23CD45');
    });

    test('rejects a malformed server URL', () {
      expect(
        () => PairingPayload.parse(jsonEncode({
          'server': 'https://example.com',
          'room': 'AB23CD45',
        })),
        throwsFormatException,
      );
    });

    test('rejects credentials embedded in the QR server URL', () {
      expect(
        () => PairingPayload.parse(jsonEncode({
          'server': 'wss://user:secret@example.com',
          'room': 'AB23CD45',
        })),
        throwsFormatException,
      );
    });

    test('rejects invalid room codes', () {
      expect(
        () => PairingPayload.parse(jsonEncode({
          'server': defaultSignalingServerUrl,
          'room': 'bad-room!',
        })),
        throwsFormatException,
      );
    });

    test('rejects a QR payload with missing fields', () {
      expect(
        () => PairingPayload.parse(jsonEncode({'server': defaultSignalingServerUrl})),
        throwsFormatException,
      );
    });
  });
}
