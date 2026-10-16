import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'stream_session_screen.dart';

const _bg = Color(0xFF080B12);
const _panel = Color(0xFF111824);
const _violet = Color(0xFF9B7BFF);
const _cyan = Color(0xFF48E5F2);
const _muted = Color(0xFF8D9AAF);
const _signalServer = 'wss://sentinel-one-signaling.onrender.com';
const _apiBase = 'https://sentinel-one-signaling.onrender.com';

class PairingQrScreen extends StatefulWidget {
  const PairingQrScreen({super.key, required this.isCamera});
  final bool isCamera;
  @override
  State<PairingQrScreen> createState() => _PairingQrScreenState();
}

class _PairingQrScreenState extends State<PairingQrScreen> {
  bool _scanning = false;
  bool _loading = false;
  bool _consuming = false;
  String? _message;
  String? _room;
  String? _ticket;
  String? _cameraToken;
  Timer? _expiryTimer;
  Timer? _pollTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    if (widget.isCamera) _createPairing();
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(Uri.parse('$_apiBase$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final textBody = await response.transform(utf8.decoder).join();
      dynamic decoded;
      try {
        decoded = textBody.isEmpty ? <String, dynamic>{} : jsonDecode(textBody);
      } catch (_) {
        decoded = <String, dynamic>{'message': textBody};
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map ? decoded['message']?.toString() : null;
        throw HttpException(message ?? 'Il servizio di associazione ha risposto con HTTP ${response.statusCode}.');
      }
      if (decoded is! Map<String, dynamic>) throw const FormatException('Risposta del server non valida.');
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _createPairing() async {
    if (mounted) setState(() { _loading = true; _message = null; });
    try {
      final result = await _post('/pair/create', {});
      if (!mounted) return;
      setState(() {
        _room = result['room'] as String?;
        _ticket = result['ticket'] as String?;
        _cameraToken = result['cameraToken'] as String?;
        _loading = false;
        _message = _ticket == null ? 'Il server non ha restituito il codice QR.' : 'QR valido per 3 minuti. Scansionalo dall’altro telefono.';
      });
      _expiryTimer?.cancel();
      _pollTimer?.cancel();
      if (_ticket != null && _cameraToken != null) {
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkPairing());
      }
      _expiryTimer = Timer(const Duration(minutes: 3), () {
        if (mounted && _ticket != null) setState(() { _ticket = null; _message = 'QR scaduto. Generane uno nuovo.'; });
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _message = 'Impossibile creare il QR: $e'; });
    }
  }

  String get _payload => jsonEncode({
    'type': 'sentinel_pair',
    'version': 1,
    'room': _room,
    'ticket': _ticket,
    'server': _signalServer,
  });

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _consuming) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final data = jsonDecode(raw);
        if (data is! Map || data['type'] != 'sentinel_pair' ||
            data['version'] != 1 || data['room'] is! String ||
            data['ticket'] is! String || data['server'] != _signalServer) {
          throw const FormatException('QR non valido per SENTINEL ONE.');
        }
        final room = (data['room'] as String).toUpperCase();
        if (!RegExp(r'^[A-Z2-9]{8}$').hasMatch(room)) {
          throw const FormatException('Codice di associazione non valido.');
        }
        setState(() { _consuming = true; _scanning = false; _message = 'Associazione sicura in corso…'; });
        final result = await _post('/pair/consume', {'ticket': data['ticket']});
        if (!mounted) return;
        final viewerRoom = result['room'] as String? ?? room;
        final token = result['viewerToken'] as String?;
        if (token == null || token.isEmpty) throw const FormatException('Il server non ha restituito le credenziali video.');
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => StreamSessionScreen(
          role: StreamRole.viewer,
          remote: true,
          initialServer: result['server'] as String? ?? _signalServer,
          initialRoom: viewerRoom,
          initialToken: token,
          autoStart: true,
          pairedSession: true,
        )));
        return;
      } catch (e) {
        if (mounted) setState(() { _consuming = false; _message = 'Associazione non riuscita: $e'; });
        return;
      }
    }
  }

  Future<void> _checkPairing() async {
    if (_navigated || _room == null || _cameraToken == null) return;
    try {
      final result = await _post('/pair/status', {'room': _room, 'cameraToken': _cameraToken});
      if (result['paired'] == true && mounted && !_navigated) _startCameraSession();
    } catch (_) {
      // A sleeping/free signaling service can be temporarily unreachable; keep the QR visible.
    }
  }

  void _startCameraSession() {
    final room = _room;
    final token = _cameraToken;
    if (room == null || token == null || _navigated) return;
    _navigated = true;
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => StreamSessionScreen(
      role: StreamRole.camera,
      remote: true,
      initialServer: _signalServer,
      initialRoom: room,
      initialToken: token,
      autoStart: true,
      pairedSession: true,
    )));
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(backgroundColor: _bg, title: Text(widget.isCamera ? 'Associa telecamera' : 'Aggiungi telecamera')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(22), border: Border.all(color: _violet.withValues(alpha: .28))),
        child: Column(children: [
          Icon(widget.isCamera ? Icons.videocam_rounded : Icons.qr_code_scanner_rounded, color: _cyan, size: 34),
          const SizedBox(height: 12),
          Text(widget.isCamera ? 'Associa questo telefono come telecamera' : 'Aggiungi una telecamera',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(widget.isCamera
            ? 'Apri SENTINEL ONE sul secondo telefono e scansiona questo QR. Poi avvia la telecamera.'
            : 'Scansiona il QR mostrato dal telefono che vuoi usare come telecamera.',
            textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.45)),
          const SizedBox(height: 22),
          if (widget.isCamera) ...[
            if (_loading)
              const SizedBox(height: 230, child: Center(child: CircularProgressIndicator()))
            else if (_ticket != null)
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(data: _payload, version: QrVersions.auto, size: 230))
            else
              Container(height: 230, alignment: Alignment.center, child: const Icon(Icons.qr_code_2_rounded, color: _muted, size: 72)),
            if (_room != null) ...[
              const SizedBox(height: 14),
              Text('Codice $_room', style: const TextStyle(color: _cyan, fontWeight: FontWeight.w800, letterSpacing: 2)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _loading ? null : _createPairing,
              icon: const Icon(Icons.refresh_rounded), label: const Text('Genera nuovo QR'),
              style: FilledButton.styleFrom(backgroundColor: _violet, minimumSize: const Size.fromHeight(50))),
            const SizedBox(height: 10),
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('Quando l’altro telefono scansiona il QR, la telecamera si avvia automaticamente.', textAlign: TextAlign.center, style: TextStyle(color: _cyan, height: 1.4))),
          ] else ...[
            if (_scanning)
              ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(height: 320, child: MobileScanner(onDetect: _onDetect)))
            else
              Container(height: 180, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF192435), borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.qr_code_scanner_rounded, color: _cyan, size: 76)),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _consuming ? null : () => setState(() { _scanning = !_scanning; _message = null; }),
              icon: Icon(_scanning ? Icons.close_rounded : Icons.camera_alt_rounded),
              label: Text(_consuming ? 'Associazione…' : (_scanning ? 'Ferma scansione' : 'Scansiona QR code')),
              style: FilledButton.styleFrom(backgroundColor: _violet, minimumSize: const Size.fromHeight(50))),
          ],
          if (_message != null) ...[
            const SizedBox(height: 14),
            Text(_message!, style: const TextStyle(color: _cyan, height: 1.45)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      const Text('Il QR usa un ticket monouso a scadenza breve. Le credenziali video vengono scambiate direttamente con il servizio cifrato e non sono il token amministrativo del server.',
        style: TextStyle(color: _muted, fontSize: 11, height: 1.5)),
    ]),
  );
}
