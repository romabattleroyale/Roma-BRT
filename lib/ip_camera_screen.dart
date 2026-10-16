import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'event_store.dart';
import 'notification_service.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

const _ipBg = Color(0xFF080B12);
const _ipPanel = Color(0xFF111824);
const _ipCyan = Color(0xFF48E5F2);
const _ipViolet = Color(0xFF9B7BFF);
const _ipMuted = Color(0xFF8D9AAF);

class IpCameraScreen extends StatefulWidget {
  const IpCameraScreen({super.key});

  @override
  State<IpCameraScreen> createState() => _IpCameraScreenState();
}

class _IpCameraScreenState extends State<IpCameraScreen> {
  final _url = TextEditingController();
  VlcPlayerController? _player;
  String? _error;
  bool _connecting = false;
  bool _motionDetection = false;
  bool _samplingMotion = false;
  Timer? _motionTimer;
  List<int>? _motionBaseline;
  DateTime? _lastMotionAlert;
  double? _lastMotionScore;

  Future<void> _connect() async {
    final raw = _url.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !const {'rtsp', 'rtsps', 'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => _error = 'Inserisci un URL RTSP/RTSPS valido della tua telecamera.');
      return;
    }
    _motionTimer?.cancel();
    _motionTimer = null;
    _motionDetection = false;
    _motionBaseline = null;
    setState(() { _connecting = true; _error = null; });
    final old = _player;
    _player = null;
    if (old != null) {
      try { await old.stopRendererScanning(); } catch (_) {}
      try { await old.dispose(); } catch (_) {}
    }
    try {
      final controller = VlcPlayerController.network(
        raw,
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(),
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() { _player = controller; _connecting = false; });
    } catch (e) {
      if (mounted) setState(() { _connecting = false; _error = 'Impossibile avviare il lettore: $e'; });
    }
  }

  Future<void> _toggleMotionDetection() async {
    if (_motionDetection) {
      _motionTimer?.cancel();
      _motionTimer = null;
      _motionBaseline = null;
      setState(() { _motionDetection = false; });
      unawaited(EventStore.record('Rilevamento movimento disattivato', 'Analisi locale dello stream RTSP arrestata'));
      return;
    }
    if (_player == null) return;
    try {
      await NotificationService.initialize(requestPermission: true);
    } catch (_) {}
    if (!mounted || _player == null) return;
    setState(() { _motionDetection = true; _motionBaseline = null; _lastMotionScore = null; });
    unawaited(EventStore.record('Rilevamento movimento attivato', 'Analisi immagini locale sul telefono'));
    _motionTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_sampleMotion());
    });
  }

  Future<void> _sampleMotion() async {
    if (!_motionDetection || _samplingMotion || _player == null) return;
    _samplingMotion = true;
    try {
      final bytes = await _player!.takeSnapshot();
      if (bytes == null || bytes.isEmpty) return;
      final frame = img.decodeImage(bytes);
      if (frame == null || frame.width < 2 || frame.height < 2) return;
      final sample = <int>[];
      const columns = 24;
      const rows = 14;
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < columns; x++) {
          final px = frame.getPixel((x * frame.width / columns).floor(), (y * frame.height / rows).floor());
          sample
            ..add(px.r.toInt())
            ..add(px.g.toInt())
            ..add(px.b.toInt());
        }
      }
      final previous = _motionBaseline;
      if (previous != null && previous.length == sample.length) {
        var total = 0;
        for (var i = 0; i < sample.length; i++) {
          total += (sample[i] - previous[i]).abs();
        }
        final score = total / sample.length;
        final now = DateTime.now();
        if (mounted) setState(() => _lastMotionScore = score);
        final last = _lastMotionAlert;
        // Debounce alerts and require a meaningful average pixel change.
        if (score >= 22 && (last == null || now.difference(last) >= const Duration(seconds: 12))) {
          _lastMotionAlert = now;
          unawaited(EventStore.record('Movimento rilevato', 'Variazione visiva nello stream RTSP (indice ${score.toStringAsFixed(1)})'));
          unawaited(NotificationService.showSecurityAlert(
            title: 'Movimento rilevato',
            body: 'SENTINEL ONE ha rilevato una variazione visiva nella telecamera IP.',
          ));
        }
      }
      _motionBaseline = sample;
    } catch (_) {
      // Snapshot failures are ignored; they must never interrupt live playback.
    } finally {
      _samplingMotion = false;
    }
  }

  Future<void> _disconnect() async {
    _motionTimer?.cancel();
    _motionTimer = null;
    _motionBaseline = null;
    final old = _player;
    setState(() { _player = null; _connecting = false; _motionDetection = false; });
    if (old != null) {
      try { await old.stopRendererScanning(); } catch (_) {}
      try { await old.dispose(); } catch (_) {}
    }
  }

  @override
  void dispose() {
    _motionTimer?.cancel();
    _url.dispose();
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _ipBg,
    appBar: AppBar(backgroundColor: _ipBg, title: const Text('Telecamera IP · RTSP')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _ipPanel, borderRadius: BorderRadius.circular(18), border: Border.all(color: _ipCyan.withValues(alpha: .2))),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tapo · EZVIZ · RTSP/ONVIF compatibili', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          SizedBox(height: 8),
          Text('Il lettore supporta flussi RTSP/RTSPS e URL HTTP(S) compatibili. Tapo ed EZVIZ funzionano solo se il modello/firmware espone uno stream locale e la funzione è stata abilitata. Non è una connessione al cloud proprietario del produttore.', style: TextStyle(color: _ipMuted, height: 1.5, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        height: 220,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18), border: Border.all(color: _ipViolet.withValues(alpha: .25))),
        child: _player == null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.videocam_off_outlined, color: _ipMuted, size: 42),
              const SizedBox(height: 10),
              Text(_connecting ? 'Connessione…' : 'Nessuno stream aperto', style: const TextStyle(color: _ipMuted)),
            ]))
          : VlcPlayer(controller: _player!, aspectRatio: 16 / 9, placeholder: const Center(child: CircularProgressIndicator())),
      ),
      const SizedBox(height: 18),
      const Text('URL dello stream', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      TextField(
        controller: _url,
        autocorrect: false,
        keyboardType: TextInputType.url,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'rtsp://indirizzo-locale:554/percorso',
          filled: true,
          fillColor: _ipPanel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => setState(() => _url.text = 'rtsp://utente:password@192.168.1.50:554/stream1'),
        icon: const Icon(Icons.content_paste_go_rounded),
        label: const Text('Inserisci un esempio modificabile'),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _connecting ? null : _connect,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Apri stream'),
        style: FilledButton.styleFrom(backgroundColor: _ipViolet, padding: const EdgeInsets.symmetric(vertical: 15)),
      ),
      if (_player != null) OutlinedButton.icon(
        onPressed: _disconnect,
        icon: const Icon(Icons.stop_rounded),
        label: const Text('Interrompi stream'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _player == null ? null : _toggleMotionDetection,
        icon: Icon(_motionDetection ? Icons.motion_photos_off_rounded : Icons.motion_photos_on_rounded),
        label: Text(_motionDetection ? 'Disattiva rilevamento movimento' : 'Attiva rilevamento movimento'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _motionDetection ? const Color(0xFFFFC66D) : _ipCyan,
          side: BorderSide(color: _motionDetection ? const Color(0xFFFFC66D) : _ipCyan),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      if (_motionDetection) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _lastMotionScore == null
            ? 'Analisi immagini attiva sul telefono…'
            : 'Analisi locale attiva · variazione immagine ${_lastMotionScore!.toStringAsFixed(1)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _ipCyan, fontSize: 11),
        ),
      ),

      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8C9D))),
      ),
      const SizedBox(height: 12),
      const Text('Privacy e accesso remoto: non inserire le credenziali in link o chat pubbliche e non esporre RTSP direttamente su Internet. Questo lettore apre lo stream raggiungibile dal telefono sulla rete corrente; il gateway sicuro per vedere queste telecamere da fuori casa non è ancora integrato.', style: TextStyle(color: _ipMuted, height: 1.5, fontSize: 11)),
    ]),
  );
}
