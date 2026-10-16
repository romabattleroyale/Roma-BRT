import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Client for SENTINEL ONE's custom binary-frame relay.
///
/// Protocol: connect to /stream/<ROOM>, send a JSON join message, then exchange
/// binary JPEG frames. This transport deliberately does not use WebRTC/SDP/ICE.
/// Camera capture/encoding and viewer rendering are owned by the Flutter screen.
enum SentinelStreamRole { camera, viewer }

class SentinelStreamTransport {
  SentinelStreamTransport({
    required this.server,
    required this.room,
    required this.role,
    this.token,
    this.onFrame,
    this.onStatus,
    this.onError,
  });

  final Uri server;
  final String room;
  final SentinelStreamRole role;
  final String? token;
  final FutureOr<void> Function(Uint8List frame)? onFrame;
  final void Function(String status)? onStatus;
  final void Function(Object error)? onError;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;
  bool _ready = false;

  bool get isConnected => !_closed && _ready && _socket?.readyState == WebSocket.open;

  Future<void> connect() async {
    if (_closed) throw StateError('Transport già chiuso');
    if (_socket != null) throw StateError('Transport già avviato');
    if (!RegExp(r'^[A-Z2-9]{6,10}$').hasMatch(room)) {
      throw const FormatException('Codice stanza non valido');
    }
    if (server.scheme != 'ws' && server.scheme != 'wss') {
      throw const FormatException('Il server deve usare ws:// o wss://');
    }
    if (server.scheme != 'wss' && server.host != 'localhost' &&
        server.host != '127.0.0.1' && server.host != '10.0.2.2') {
      throw const FormatException('Fuori dalla rete locale è richiesto WSS/TLS');
    }

    final endpoint = server.replace(
      path: '/stream/${room.toUpperCase()}',
      query: null,
      fragment: null,
    );
    final cleanToken = token?.trim() ?? '';
    final socket = await WebSocket.connect(
      endpoint.toString(),
      headers: cleanToken.isEmpty ? null : {'Authorization': 'Bearer $cleanToken'},
    ).timeout(const Duration(seconds: 12));
    if (_closed) {
      await socket.close();
      return;
    }
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 20);
    _subscription = socket.listen(
      (dynamic message) {
        if (message is String) {
          _handleControl(message);
        } else if (message is List<int>) {
          if (role != SentinelStreamRole.viewer) return;
          final frame = Uint8List.fromList(message);
          if (frame.isEmpty || frame.lengthInBytes > 1024 * 1024) return;
          try {
            final result = onFrame?.call(frame);
            if (result is Future<void>) unawaited(result.catchError((Object e) {
              onError?.call(e);
            }));
          } catch (e) {
            onError?.call(e);
          }
        }
      },
      onError: (Object e) {
        _ready = false;
        onStatus?.call('Errore trasporto');
        onError?.call(e);
      },
      onDone: () {
        _ready = false;
        onStatus?.call('Trasporto disconnesso');
      },
      cancelOnError: false,
    );
    socket.add(jsonEncode({
      'type': 'join',
      'role': role == SentinelStreamRole.camera ? 'camera' : 'viewer',
    }));
    onStatus?.call('Connessione al relay');
  }

  void _handleControl(String raw) {
    try {
      final message = jsonDecode(raw);
      if (message is! Map<String, dynamic>) return;
      switch (message['type']) {
        case 'ready':
          _ready = true;
          onStatus?.call(message['peerPresent'] == true
              ? 'Dispositivo trovato'
              : 'In attesa dell’altro dispositivo');
          break;
        case 'peer_joined':
          onStatus?.call('Dispositivo collegato');
          break;
        case 'peer_left':
          onStatus?.call('Dispositivo disconnesso');
          break;
        case 'error':
          onError?.call(StateError(message['message']?.toString() ?? 'Errore relay'));
          break;
      }
    } catch (e) {
      onError?.call(FormatException('Messaggio relay non valido: $e'));
    }
  }

  /// Send one already encoded JPEG frame. Frames over 1 MiB are rejected.
  void sendJpeg(Uint8List jpeg) {
    if (role != SentinelStreamRole.camera) {
      throw StateError('Solo la telecamera può inviare fotogrammi');
    }
    if (!isConnected) throw StateError('Relay non connesso');
    if (jpeg.isEmpty || jpeg.lengthInBytes > 1024 * 1024) {
      throw ArgumentError.value(jpeg.lengthInBytes, 'jpeg.lengthInBytes',
          'Il fotogramma deve essere tra 1 byte e 1 MiB');
    }
    _socket!.add(jpeg);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ready = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure, 'Session ended');
      } catch (_) {}
    }
    onStatus?.call('Trasporto chiuso');
  }
}
