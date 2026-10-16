import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  final video = RTCVideoRenderer();
  final pendingIce = <RTCIceCandidate>[];
  WebSocket? socket;
  RTCPeerConnection? peer;
  MediaStream? localStream;
  StreamSubscription? subscription;
  bool busy = false, linked = false;
  String status = 'Non collegato';
  String? error;
  bool get isCamera => widget.role == StreamRole.camera;

  @override
  void initState() {
    super.initState();
    url.text = widget.remote ? 'wss://INSERISCI-IL-TUO-SERVER' : 'ws://192.168.1.10:8765';
    room.text = _newCode();
    video.initialize();
  }

  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  void _status(String value) { if (mounted) setState(() => status = value); }
  void _error(String value) { if (mounted) setState(() => error = value); }

  Future<void> _start() async {
    if (busy) return;
    final server = url.text.trim();
    final code = room.text.trim().toUpperCase();
    if (!(server.startsWith('ws://') || server.startsWith('wss://'))) {
      _error('Inserisci un indirizzo ws:// o wss:// valido.'); return;
    }
    if (!RegExp(r'^[A-Z2-9]{6,10}$').hasMatch(code)) {
      _error('Il codice stanza deve avere 6–10 caratteri: A–Z e 2–9.'); return;
    }
    if (widget.remote && !server.startsWith('wss://')) {
      _error('Fuori casa è richiesto wss:// con TLS. Non usare ws:// su Internet.'); return;
    }
    setState(() { busy = true; error = null; status = 'Connessione al servizio…'; });
    try {
      await video.initialize();
      final endpoint = Uri.parse(server.endsWith('/') ? server + 'signal/' + code : server + '/signal/' + code);
      socket = await WebSocket.connect(endpoint.toString()).timeout(const Duration(seconds: 12));
      subscription = socket!.listen((data) => _handle(data),
        onDone: () { _status('Servizio disconnesso'); if (mounted) setState(() => linked = false); },
        onError: (Object e) => _error('Errore WebSocket: $e'));
      await _createPeer();
      if (isCamera) {
        localStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {'facingMode': 'environment', 'width': {'ideal': 1280}, 'height': {'ideal': 720}, 'frameRate': {'ideal': 24, 'max': 30}}
        });
        for (final track in localStream!.getTracks()) { await peer!.addTrack(track, localStream!); }
        video.srcObject = localStream;
        _status('Telecamera pronta · codice $code');
      } else {
        await peer!.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
        _status('In attesa della telecamera · codice $code');
      }
      if (mounted) setState(() { busy = false; linked = true; });
    } catch (e) {
      await _cleanup();
      if (mounted) setState(() { busy = false; linked = false; error = 'Collegamento non riuscito: $e\nVerifica server, porta, Wi-Fi e codice stanza.'; status = 'Non collegato'; });
    }
  }

  Future<void> _createPeer() async {
    peer = await createPeerConnection({'sdpSemantics': 'unified-plan', 'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'}
    ]});
    peer!.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _send({'type': 'ice', 'candidate': candidate.toMap()});
      }
    };
    peer!.onConnectionState = (state) {
      _status('WebRTC: ' + state.toString().split('.').last);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (mounted) setState(() => linked = true);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (mounted) setState(() => linked = false);
      }
    };
    peer!.onTrack = (event) {
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
      switch (message['type']) {
        case 'ready':
          _status((message['peers'] as num? ?? 0) > 0 ? 'Dispositivo trovato' : 'Stanza pronta · attendo il secondo telefono');
          break;
        case 'peer_joined':
          if (isCamera && await peer!.getRemoteDescription() == null) {
            final offer = await peer!.createOffer();
            await peer!.setLocalDescription(offer);
            final local = await peer!.getLocalDescription();
            _send({'type': 'offer', 'sdp': local?.sdp, 'descriptionType': local?.type ?? 'offer'});
            _status('Offerta inviata · negoziazione in corso');
          }
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
            if (await peer!.getRemoteDescription() == null) { pendingIce.add(c); } else { await peer!.addCandidate(c); }
          }
          break;
        case 'peer_left':
          _status('L’altro dispositivo si è disconnesso');
          break;
        case 'error':
          _error(message['message']?.toString() ?? 'Errore del server');
          break;
      }
    } catch (e) { _error('Messaggio di segnalazione non valido: $e'); }
  }

  Future<void> _flushIce() async {
    for (final candidate in List<RTCIceCandidate>.from(pendingIce)) { await peer!.addCandidate(candidate); }
    pendingIce.clear();
  }

  Future<void> _stop() async {
    await _cleanup();
    if (mounted) setState(() { busy = false; linked = false; status = 'Sessione terminata'; });
  }

  Future<void> _cleanup() async {
    await subscription?.cancel(); subscription = null;
    _send({'type': 'hangup'});
    await socket?.close(); socket = null;
    final p = peer; peer = null;
    if (p != null) { await p.close(); await p.dispose(); }
    final stream = localStream; localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) { await track.stop(); }
      await stream.dispose();
    }
    video.srcObject = null;
  }

  @override
  void dispose() {
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
        const SizedBox(height: 18),
        _field('Server di segnalazione', url, hint: 'wss://tuo-server.example'),
        const SizedBox(height: 12),
        _field('Codice stanza', room, hint: '8 caratteri', uppercase: true),
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
        const Text('La rete locale richiede un server raggiungibile via Wi-Fi. Fuori casa servono un server WSS pubblicato e, per alcune reti, un relay TURN. Non inserire dati sensibili in server non verificati.', style: TextStyle(color: muted, fontSize: 11, height: 1.45)),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: room.text)), icon: const Icon(Icons.copy_rounded), label: const Text('Copia codice stanza')),
      ]),
    );
  }

  Widget _field(String label, TextEditingController controller, {String? hint, bool uppercase = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
      const SizedBox(height: 7),
      TextField(controller: controller, enabled: !linked && !busy, autocorrect: false,
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
