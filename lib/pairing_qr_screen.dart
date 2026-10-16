import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _bg = Color(0xFF080B12);
const _panel = Color(0xFF111824);
const _violet = Color(0xFF9B7BFF);
const _cyan = Color(0xFF48E5F2);
const _muted = Color(0xFF8D9AAF);

class PairingQrScreen extends StatefulWidget {
  const PairingQrScreen({super.key, required this.isCamera});
  final bool isCamera;
  @override
  State<PairingQrScreen> createState() => _PairingQrScreenState();
}

class _PairingQrScreenState extends State<PairingQrScreen> {
  final _room = TextEditingController(text: _newRoom());
  bool _scanning = false;
  String? _message;

  static String _newRoom() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  String get _payload => jsonEncode({
    'type': 'sentinel_pair',
    'version': 1,
    'room': _room.text.trim().toUpperCase(),
    'server': 'wss://sentinel-one-signaling.onrender.com',
  });

  @override
  void dispose() { _room.dispose(); super.dispose(); }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final data = jsonDecode(raw);
        if (data is! Map || data['type'] != 'sentinel_pair' ||
            data['version'] != 1 || data['room'] is! String ||
            data['server'] != 'wss://sentinel-one-signaling.onrender.com') {
          throw const FormatException('QR non valido per SENTINEL ONE.');
        }
        final room = (data['room'] as String).toUpperCase();
        if (!RegExp(r'^[A-Z2-9]{6,10}$').hasMatch(room)) {
          throw const FormatException('Codice di associazione non valido.');
        }
        setState(() {
          _room.text = room;
          _scanning = false;
          _message = 'QR letto correttamente. Il collegamento video non è ancora stato avviato: serve il pairing autenticato sul server.';
        });
        return;
      } catch (_) {
        setState(() => _message = 'QR non riconosciuto. Inquadra quello mostrato da SENTINEL ONE.');
      }
    }
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
          Text(widget.isCamera ? 'Scansiona questo codice dall’altro telefono' : 'Inquadra il QR della telecamera',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(widget.isCamera
            ? 'Il codice contiene il server e una stanza casuale, non il segreto del server.'
            : 'L’app legge il codice senza farti copiare indirizzi o codici a mano.',
            textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.45)),
          const SizedBox(height: 22),
          if (widget.isCamera) ...[
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(data: _payload, version: QrVersions.auto, size: 230)),
            const SizedBox(height: 16),
            Text('Codice \${_room.text}', style: const TextStyle(color: _cyan, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => setState(() { _room.text = _newRoom(); _message = null; }),
              icon: const Icon(Icons.refresh_rounded), label: const Text('Genera nuovo codice')),
          ] else ...[
            if (_scanning)
              ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(height: 320, child: MobileScanner(onDetect: _onDetect)))
            else
              Container(height: 180, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF192435), borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.qr_code_scanner_rounded, color: _cyan, size: 76)),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: () => setState(() { _scanning = !_scanning; _message = null; }),
              icon: Icon(_scanning ? Icons.close_rounded : Icons.camera_alt_rounded),
              label: Text(_scanning ? 'Ferma scansione' : 'Scansiona QR code'),
              style: FilledButton.styleFrom(backgroundColor: _violet, minimumSize: const Size.fromHeight(50))),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: const TextStyle(color: _cyan, height: 1.45)),
            ],
          ],
        ]),
      ),
      const SizedBox(height: 16),
      const Text('Il QR è implementato, ma l’associazione automatica completa richiede credenziali temporanee emesse dal server. Il token amministrativo non viene inserito nel QR.',
        style: TextStyle(color: _muted, fontSize: 11, height: 1.5)),
    ]),
  );
}
