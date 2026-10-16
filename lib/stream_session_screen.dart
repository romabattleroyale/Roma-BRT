import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'event_store.dart';
import 'pairing_payload.dart';
import 'signaling_config.dart';

enum StreamRole { camera, viewer }

class StreamSessionScreen extends StatefulWidget {
  const StreamSessionScreen({super.key, required this.role, required this.remote});
  final StreamRole role;
  final bool remote;
  @override
  State<StreamSessionScreen> createState() => _StreamSessionScreenState();
}

class _StreamSessionScreenState extends State<StreamSessionScreen> {
  static const bg = Color(0xFF080B12), panel = Color(0xFF111824), cyan = Color(0xFF48E5F2), violet = Color(0xFF9B7BFF), muted = Color(0xFF8D9AAF);
  final url = TextEditingController();
  final room = TextEditingController();
  final signalToken = TextEditingController();
  final turnUrls = TextEditingController();
  final turnUsername = TextEditingController();
  final turnCredential = TextEditingController();
  final video = RTCVideoRenderer();
  late final Future<void> _rendererReady;
  final pendingIce = <RTCIceCandidate>[];
  // Signals can arrive immediately after the WebSocket joins a room, before
  // the native peer connection and the viewer transceiver have been created.
  final pendingSignals = <Map<String, dynamic>>[];
  bool signalingReady = false;
  WebSocket? socket;
  RTCPeerConnection? peer;
  MediaStream? localStream;
  MediaRecorder? recorder;
  String? recordingPath;
  bool recording = false;
  StreamSubscription? subscription;
  // WebSocket callbacks can overlap while _handle awaits native WebRTC calls.
  // Serialize them to preserve SDP/ICE/peer-left ordering.
  Future<void> _messageQueue = Future<void>.value();
  bool busy = false, linked = false;
  bool peerPresent = false, offerSent = false, creatingOffer = false, localTracksReady = false;
  bool manuallyStopped = false;
  bool wasConnected = false;
  int reconnectAttempts = 0;
  Timer? reconnectTimer;
  Completer<void>? readyCompleter;
  List<Map<String, dynamic>> serverIceServers = <Map<String, dynamic>>[];
  String status = 'Non collegato';
  String? error;
  bool get isCamera => widget.role == StreamRole.camera;

  @override
  void initState() {
    super.initState();
    // Use the managed WSS signaling relay in both modes. On the same Wi-Fi, WebRTC
    // can still establish a direct media path; this avoids requiring a separate
    // laptop/server on the home network just to exchange SDP and ICE.
    url.text = defaultSignalingServerUrl;
    room.text = _newCode();
    _rendererReady = video.initialize();
  }

  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  void _status(String value) { if (mounted) setState(() => status = value); }
  void _error(String value) { if (mounted) setState(() => error = value); }

  Future<void> _start({bool reconnect = false}) async {
    if (busy || !mounted) return;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    if (!reconnect) { manuallyStopped = false; reconnectAttempts = 0; }
    final server = url.text.trim();
    final code = room.text.trim().toUpperCase();
    late final Uri serverUri;
    try {
      serverUri = PairingPayload.parseServer(server);
    } on FormatException {
      _error('Inserisci l’indirizzo base ws:// o wss:// del servizio, senza percorso, query o credenziali.');
      return;
    }
    if (!RegExp(r'^[A-Z2-9]{6,10}$').hasMatch(code)) {
      _error('Il codice stanza deve avere 6–10 caratteri: A–Z e 2–9.'); return;
    }
    // Pairing uses the random room code and QR. A server-side SIGNAL_TOKEN is
    // supported for private deployments, but is not required for the managed prototype relay.
    if (widget.remote && !server.startsWith('wss://')) {
      _error('Fuori casa è richiesto wss:// con TLS. Non usare ws:// su Internet.'); return;
    }
    setState(() { busy = true; linked = false; error = null; status = 'Connessione al servizio…'; });
    peerPresent = false; offerSent = false; creatingOffer = false; localTracksReady = false;
    signalingReady = false; pendingIce.clear(); pendingSignals.clear(); wasConnected = false;
    try {
      await _rendererReady;
      final baseEndpoint = serverUri.replace(path: '/signal/$code', query: null, fragment: null);
      final token = signalToken.text.trim();
      final endpoint = baseEndpoint;
      readyCompleter = Completer<void>();
      serverIceServers = <Map<String, dynamic>>[];
      socket = await WebSocket.connect(
        endpoint.toString(),
        headers: token.isEmpty ? null : {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 12));
      final activeSocket = socket!;
      subscription = activeSocket.listen((data) {
        _messageQueue = _messageQueue.then((_) async {
          // Ignore messages queued by an old session after reconnect/stop.
          if (identical(socket, activeSocket)) await _handle(data);
        }).catchError((Object e) {
          _error('Errore nella coda dei messaggi WebRTC: $e');
        });
      },
        onDone: () async {
          if (!identical(socket, activeSocket)) return;
          // Drain messages received before the socket closed, then ensure this
          // callback still belongs to the active session before cleaning it.
          try { await _messageQueue; } catch (_) {}
          if (!identical(socket, activeSocket)) return;
          if (readyCompleter != null && !readyCompleter!.isCompleted) {
            readyCompleter!.completeError(StateError('Il server ha chiuso la sessione prima del messaggio ready'));
          }
          // Do not cancel the subscription from inside its own onDone callback.
          await _cleanup(cancelSubscription: false);
          if (mounted) setState(() { busy = false; linked = false; status = 'Servizio disconnesso'; });
          _scheduleReconnect();
        },
        onError: (Object e) {
          if (!identical(socket, activeSocket)) return;
          if (readyCompleter != null && !readyCompleter!.isCompleted) readyCompleter!.completeError(e);
          _error('Errore WebSocket: $e');
        });
      await readyCompleter!.future.timeout(const Duration(seconds: 8));
      unawaited(EventStore.record('Sessione avviata', isCamera ? 'Telefono impostato come telecamera' : 'Monitor in attesa della telecamera'));
      await _createPeer();
      if (isCamera) {
        localStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {'facingMode': 'environment', 'width': {'ideal': 1280}, 'height': {'ideal': 720}, 'frameRate': {'ideal': 24, 'max': 30}}
        });
        for (final track in localStream!.getTracks()) { await peer!.addTrack(track, localStream!); }
        localTracksReady = true;
        await _maybeCreateOffer();
        video.srcObject = localStream;
        _status('Telecamera pronta · codice $code');
      } else {
        await peer!.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
        _status('In attesa della telecamera · codice $code');
      }
      // Start processing SDP/ICE only after the peer and role-specific tracks
      // or transceiver exist. This prevents early signals being discarded.
      signalingReady = true;
      final queuedSignals = List<Map<String, dynamic>>.from(pendingSignals);
      pendingSignals.clear();
      for (final queued in queuedSignals) {
        await _handle(jsonEncode(queued));
      }
      // A signaling socket is not a live video connection. Only onConnectionState
      // may mark the session as linked once WebRTC reaches Connected.
      if (mounted) setState(() { busy = false; });
    } catch (e) {
      await _cleanup();
      if (mounted) setState(() { busy = false; linked = false; error = 'Collegamento non riuscito: $e\nVerifica server, porta, Wi-Fi e codice stanza.'; status = 'Non collegato'; });
      _scheduleReconnect();
    }
  }

  Future<void> _toggleRecording() async {
    if (recording) {
      await _stopRecording();
      return;
    }
    final stream = localStream;
    if (!isCamera || stream == null) {
      _error('Avvia prima la telecamera per registrare.');
      return;
    }
    try {
      final tracks = stream.getVideoTracks();
      if (tracks.isEmpty) throw StateError('Traccia video non disponibile');
      final root = await getApplicationDocumentsDirectory();
      final folder = Directory('${root.path}/recordings');
      await folder.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final path = '${folder.path}/sentinel_$stamp.mp4';
      final active = MediaRecorder();
      await active.start(path, videoTrack: tracks.first);
      recorder = active;
      recordingPath = path;
      if (mounted) setState(() { recording = true; error = null; });
      unawaited(EventStore.record('Registrazione avviata', 'Registrazione video locale sul telefono telecamera'));
    } catch (e) {
      recorder = null;
      if (mounted) setState(() => recording = false);
      _error('Registrazione non disponibile su questo dispositivo: $e');
    }
  }

  Future<void> _stopRecording() async {
    final active = recorder;
    if (active == null) return;
    try {
      await active.stop();
      final path = recordingPath;
      if (path != null) unawaited(EventStore.record('Registrazione salvata', path));
    } catch (e) {
      _error('Impossibile completare la registrazione: $e');
    } finally {
      recorder = null;
      recordingPath = null;
      if (mounted) setState(() => recording = false);
    }
  }

  Future<void> _createPeer() async {
    final iceServers = serverIceServers.isNotEmpty
        ? serverIceServers.map((entry) => Map<String, dynamic>.from(entry)).toList()
        : <Map<String, dynamic>>[{'urls': 'stun:stun.l.google.com:19302'}];
    final urls = turnUrls.text.split(',').map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
    if (urls.isNotEmpty) {
      final server = <String, dynamic>{'urls': urls};
      if (turnUsername.text.trim().isNotEmpty) server['username'] = turnUsername.text.trim();
      if (turnCredential.text.isNotEmpty) server['credential'] = turnCredential.text;
      iceServers.add(server);
    }
    peer = await createPeerConnection({'sdpSemantics': 'unified-plan', 'iceServers': iceServers});
    final currentPeer = peer!;
    currentPeer.onIceCandidate = (candidate) {
      if (!identical(peer, currentPeer)) return;
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _send({'type': 'ice', 'candidate': candidate.toMap()});
      }
    };
    currentPeer.onConnectionState = (state) {
      if (!identical(peer, currentPeer)) return;
      _status('WebRTC: ' + state.toString().split('.').last);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (!wasConnected) unawaited(EventStore.record('Video collegato', isCamera ? 'Trasmissione WebRTC attiva' : 'Flusso video ricevuto'));
        wasConnected = true;
        reconnectAttempts = 0;
        if (mounted) setState(() => linked = true);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (wasConnected) unawaited(EventStore.record('Connessione video interrotta', state.toString().split('.').last));
        wasConnected = false;
        if (mounted) setState(() => linked = false);
      }
    };
    currentPeer.onTrack = (event) {
      if (!identical(peer, currentPeer)) return;
      if (!isCamera && event.streams.isNotEmpty) {
        video.srcObject = event.streams.first;
        _status('Video ricevuto');
        if (mounted) setState(() {});
      }
    };
  }

  void _send(Map<String, dynamic> value) {
    if (socket?.readyState == WebSocket.open) socket!.add(jsonEncode(value));
  }

  Future<void> _handle(dynamic raw) async {
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = message['type'];
      if (!signalingReady && (type == 'offer' || type == 'answer' || type == 'ice')) {
        if (pendingSignals.length >= 256) {
          _error('Troppi messaggi in attesa dal servizio di segnalazione.');
          return;
        }
        pendingSignals.add(message);
        return;
      }
      switch (type) {
        case 'ready':
          final configuredIce = message['iceServers'];
          if (configuredIce is List) {
            serverIceServers = configuredIce.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
          }
          if (readyCompleter != null && !readyCompleter!.isCompleted) readyCompleter!.complete();
          peerPresent = (message['peers'] as num? ?? 0) > 0;
          _status(peerPresent ? 'Dispositivo trovato' : 'Stanza pronta · attendo il secondo telefono');
          if (peerPresent) await _maybeCreateOffer();
          break;
        case 'peer_joined':
          peerPresent = true;
          if (isCamera) await _maybeCreateOffer();
          break;
        case 'offer':
          if (!isCamera) {
            final sdp = message['sdp'] as String?;
            if (sdp == null) throw const FormatException('Offerta senza SDP');
            await peer!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
            await _flushIce();
            final answer = await peer!.createAnswer();
            await peer!.setLocalDescription(answer);
            final local = await peer!.getLocalDescription();
            _send({'type': 'answer', 'sdp': local?.sdp, 'descriptionType': local?.type ?? 'answer'});
            _status('Risposta inviata · collegamento in corso');
          }
          break;
        case 'answer':
          if (isCamera) {
            final sdp = message['sdp'] as String?;
            if (sdp == null) throw const FormatException('Risposta senza SDP');
            await peer!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
            await _flushIce();
            _status('Risposta ricevuta · collegamento in corso');
          }
          break;
        case 'ice':
          final rawCandidate = message['candidate'];
          if (rawCandidate is Map) {
            final c = RTCIceCandidate(rawCandidate['candidate'] as String?, rawCandidate['sdpMid'] as String?, (rawCandidate['sdpMLineIndex'] as num?)?.toInt());
            if (await peer!.getRemoteDescription() == null) {
              if (pendingIce.length >= 256) {
                _error('Troppi candidati ICE in attesa; verifica il dispositivo remoto.');
                return;
              }
              pendingIce.add(c);
            } else {
              await peer!.addCandidate(c);
            }
          }
          break;
        case 'peer_left':
          peerPresent = false;
          offerSent = false;
          creatingOffer = false;
          pendingIce.clear();
          _status('L’altro dispositivo si è disconnesso');
          if (mounted) setState(() => linked = false);
          // A closed WebRTC peer connection cannot be reused for the next
          // viewer. Rebuild it while keeping the camera's local capture alive.
          await _resetPeerAfterRemoteLeft();
          break;
        case 'error':
          _error(message['message']?.toString() ?? 'Errore del server');
          break;
      }
    } catch (e) { _error('Messaggio di segnalazione non valido: $e'); }
  }

  Future<void> _resetPeerAfterRemoteLeft() async {
    final oldPeer = peer;
    peer = null;
    if (oldPeer != null) {
      try { await oldPeer.close(); } catch (_) {}
      try { await oldPeer.dispose(); } catch (_) {}
    }
    if (!mounted || !signalingReady) return;
    try {
      await _createPeer();
      if (isCamera) {
        final stream = localStream;
        if (stream != null) {
          for (final track in stream.getTracks()) {
            await peer!.addTrack(track, stream);
          }
          localTracksReady = true;
        } else {
          localTracksReady = false;
        }
      } else {
        await peer!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }
    } catch (e) {
      _error('Impossibile ripristinare il collegamento WebRTC: $e');
    }
  }

  Future<void> _maybeCreateOffer() async {
    if (!isCamera || !peerPresent || !localTracksReady || offerSent || creatingOffer || peer == null) return;
    creatingOffer = true;
    try {
      if (await peer!.getRemoteDescription() != null) return;
      final offer = await peer!.createOffer();
      await peer!.setLocalDescription(offer);
      final local = await peer!.getLocalDescription();
      if (local?.sdp == null) throw StateError('SDP locale non disponibile');
      _send({'type': 'offer', 'sdp': local!.sdp, 'descriptionType': local.type ?? 'offer'});
      offerSent = true;
      _status('Offerta inviata · negoziazione in corso');
    } finally {
      creatingOffer = false;
    }
  }

  Future<void> _flushIce() async {
    for (final candidate in List<RTCIceCandidate>.from(pendingIce)) { await peer!.addCandidate(candidate); }
    pendingIce.clear();
  }

  Future<void> _scanPairingQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _PairingQrScannerScreen()),
    );
    if (!mounted || scanned == null) return;
    try {
      final pairing = PairingPayload.parse(scanned);
      setState(() {
        url.text = pairing.server.toString();
        room.text = pairing.room;
        error = null;
      });
    } on FormatException {
      _error('QR non valido. Scansiona il codice generato da SENTINEL ONE.');
    }
  }

  void _scheduleReconnect() {
    if (!mounted || manuallyStopped || reconnectTimer?.isActive == true || reconnectAttempts >= 8) return;
    final seconds = min(30, 1 << reconnectAttempts);
    reconnectAttempts++;
    if (mounted) setState(() { busy = false; linked = false; status = 'Riconnessione automatica tra ${seconds}s…'; });
    reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (mounted && !manuallyStopped) _start(reconnect: true);
    });
  }

  Future<void> _stop() async {
    manuallyStopped = true;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    await _cleanup();
    unawaited(EventStore.record('Sessione terminata', isCamera ? 'Trasmissione telecamera arrestata' : 'Monitor disconnesso'));
    if (mounted) setState(() { busy = false; linked = false; status = 'Sessione terminata'; });
  }

  Future<void> _cleanup({bool cancelSubscription = true}) async {
    if (recorder != null) await _stopRecording();
    final activeSubscription = subscription;
    subscription = null;
    if (cancelSubscription) {
      await activeSubscription?.cancel();
    }
    signalingReady = false;
    pendingSignals.clear();
    pendingIce.clear();

    // Detach the socket before awaiting close: its onDone callback can fire
    // during the close handshake. Without detaching first, onDone may start a
    // second cleanup concurrently and dispose the same native WebRTC objects.
    final activeSocket = socket;
    _send({'type': 'hangup'});
    socket = null;
    await activeSocket?.close();

    final p = peer;
    peer = null;
    if (p != null) {
      try { await p.close(); } finally { await p.dispose(); }
    }
    final stream = localStream;
    localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try { await track.stop(); } catch (_) {}
      }
      await stream.dispose();
    }
    video.srcObject = null;
  }

  @override
  void dispose() {
    if (recorder != null) unawaited(_stopRecording());
    if (socket != null && !manuallyStopped) unawaited(EventStore.record('Sessione terminata', 'Schermata chiusa'));
    manuallyStopped = true;
    reconnectTimer?.cancel();
    subscription?.cancel(); socket?.close(); peer?.close(); peer?.dispose();
    final stream = localStream;
    if (stream != null) { for (final track in stream.getTracks()) { track.stop(); } stream.dispose(); }
    video.srcObject = null; video.dispose(); url.dispose(); room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, title: Text(isCamera ? 'Telecamera · trasmissione' : 'Monitor · ricezione')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(height: MediaQuery.sizeOf(context).height * .43, clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(22), border: Border.all(color: cyan.withValues(alpha: .25))),
          child: Stack(fit: StackFit.expand, children: [
            RTCVideoView(video, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
            Align(alignment: Alignment.topLeft, child: Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: linked ? const Color(0xFF47E0A0) : const Color(0xFFFFC66D), size: 8),
                const SizedBox(width: 7), Text(linked ? 'COLLEGATO' : 'IN ATTESA', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
              ])))
          ])),
        const SizedBox(height: 18),
        Text(status, style: const TextStyle(color: cyan, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Text(isCamera ? 'Avvia la sessione e condividi il codice con il monitor. Il video parte quando il secondo dispositivo si collega.' : 'Inserisci lo stesso server e codice del telefono telecamera. Il video apparirà dopo la negoziazione WebRTC.', style: const TextStyle(color: muted, height: 1.45)),
        if (isCamera && localStream != null) ...[
          OutlinedButton.icon(
            onPressed: recording ? _stopRecording : _toggleRecording,
            icon: Icon(recording ? Icons.stop_circle_outlined : Icons.fiber_manual_record_rounded),
            label: Text(recording ? 'Ferma e salva registrazione' : 'Avvia registrazione locale · beta'),
            style: OutlinedButton.styleFrom(
              foregroundColor: recording ? const Color(0xFFFF6B80) : cyan,
              side: BorderSide(color: recording ? const Color(0xFFFF6B80) : cyan),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (recording) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Registrazione attiva · file privato sul telefono', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFF6B80), fontSize: 11)),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 18),
        _field('Server di segnalazione', url, hint: 'wss://tuo-server.example', onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        _field('Codice stanza', room, hint: '8 caratteri', uppercase: true, onChanged: (_) => setState(() {})),
        if (isCamera) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              const Text('ABBINAMENTO QR', style: TextStyle(color: cyan, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              const Text('Sul telefono monitor scansiona questo codice. Contiene solo server e codice stanza, mai il token di accesso.',
                textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11, height: 1.4)),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: jsonEncode({'server': url.text.trim(), 'room': room.text.trim().toUpperCase()}),
                  size: 184,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ]),
          ),
        ] else ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy || linked ? null : _scanPairingQr,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scansiona QR della telecamera'),
          ),
        ],
        const SizedBox(height: 10),
        _field('Token aggiuntivo (facoltativo)', signalToken, hint: 'Solo se il gestore del server lo richiede'),
        const SizedBox(height: 18),
        const Text('Relay TURN (facoltativo)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 6),
        const Text('Necessario su alcune reti, soprattutto per accesso remoto. Inserisci dati del tuo provider TURN; separa più URL con virgole.', style: TextStyle(color: muted, fontSize: 11, height: 1.4)),
        const SizedBox(height: 10),
        _field('URL TURN', turnUrls, hint: 'turn:host:3478, turns:host:5349'),
        const SizedBox(height: 10),
        _field('Nome utente TURN', turnUsername, hint: 'Nome utente'),
        const SizedBox(height: 10),
        _field('Credenziale TURN', turnCredential, hint: 'Password o token'),
        if (isCamera) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () { room.text = _newCode(); setState(() {}); }, icon: const Icon(Icons.refresh_rounded), label: const Text('Nuovo codice'))),
        if (error != null) Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF351923), borderRadius: BorderRadius.circular(12)),
          child: Text(error!, style: const TextStyle(color: Color(0xFFFFA6B5), height: 1.4))),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: busy ? null : (socket == null ? _start : _stop),
          icon: Icon(socket == null ? Icons.link_rounded : Icons.link_off_rounded),
          label: Text(busy ? 'Connessione…' : (socket == null ? (isCamera ? 'Avvia telecamera' : 'Collega al video') : 'Termina sessione')),
          style: FilledButton.styleFrom(backgroundColor: violet, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16))),
        const SizedBox(height: 12),
        const Text('Il server WSS preconfigurato scambia solo i messaggi di segnalazione: non trasporta il video. Sullo stesso Wi-Fi WebRTC tenta una connessione video diretta tra i telefoni; alcune reti possono comunque richiedere TURN. Usa solo servizi di segnalazione fidati.', style: TextStyle(color: muted, fontSize: 11, height: 1.45)),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: room.text)), icon: const Icon(Icons.copy_rounded), label: const Text('Copia codice stanza')),
      ]),
    );
  }

  Widget _field(String label, TextEditingController controller, {String? hint, bool uppercase = false, ValueChanged<String>? onChanged}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
      const SizedBox(height: 7),
      TextField(controller: controller, onChanged: onChanged, enabled: !linked && !busy, autocorrect: false,
        textCapitalization: uppercase ? TextCapitalization.characters : TextCapitalization.none,
        inputFormatters: uppercase ? [FilteringTextInputFormatter.allow(RegExp('[A-Za-z2-9]')), LengthLimitingTextInputFormatter(10), _UpperCaseFormatter()] : null,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(hintText: hint, filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
    ]);
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
    newValue.copyWith(text: newValue.text.toUpperCase(), selection: newValue.selection);
}

class _PairingQrScannerScreen extends StatefulWidget {
  const _PairingQrScannerScreen();
  @override
  State<_PairingQrScannerScreen> createState() => _PairingQrScannerScreenState();
}

class _PairingQrScannerScreenState extends State<_PairingQrScannerScreen> {
  bool _completed = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080B12),
    appBar: AppBar(backgroundColor: const Color(0xFF080B12), title: const Text('Scansiona abbinamento')),
    body: Stack(fit: StackFit.expand, children: [
      MobileScanner(onDetect: (capture) {
        if (_completed || capture.barcodes.isEmpty) return;
        final value = capture.barcodes.first.rawValue;
        if (value == null || value.isEmpty) return;
        _completed = true;
        Navigator.of(context).pop(value);
      }),
      Align(alignment: Alignment.bottomCenter, child: Container(
        margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .78), borderRadius: BorderRadius.circular(16)),
        child: const Text('Inquadra il QR mostrato sul telefono telecamera. Il codice stanza autorizza l’abbinamento; non contiene password.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.white, height: 1.4)),
      )),
    ]),
  );
}
