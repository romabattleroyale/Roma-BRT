import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'event_store.dart';
import 'notification_service.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  static const _profilesKey = 'sentinel_one_ip_camera_profiles_v1';
  static const _secureStorage = FlutterSecureStorage();
  final List<Map<String, String>> _profiles = [];
  bool _profilesLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfiles());
  }

  Future<void> _loadProfiles() async {
    try {
      final raw = await _secureStorage.read(key: _profilesKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _profiles
            ..clear()
            ..addAll(decoded.whereType<Map>().map((item) => {
              'id': item['id']?.toString() ?? '',
              'name': item['name']?.toString() ?? 'Telecamera',
              'url': item['url']?.toString() ?? '',
            }).where((item) => item['id']!.isNotEmpty && item['url']!.isNotEmpty));
        }
      }
    } catch (_) {
      // Keep the camera screen usable if secure storage is unavailable.
    }
    if (mounted) setState(() => _profilesLoading = false);
  }

  Future<void> _persistProfiles() async {
    await _secureStorage.write(key: _profilesKey, value: jsonEncode(_profiles));
  }

  Future<void> _saveCurrentProfile() async {
    final streamUrl = _url.text.trim();
    final uri = Uri.tryParse(streamUrl);
    if (uri == null || !const {'rtsp', 'rtsps', 'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => _error = 'Inserisci prima un URL valido della telecamera.');
      return;
    }
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _ipPanel,
        title: const Text('Salva telecamera'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome (es. Ingresso)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, nameController.text.trim()), child: const Text('Salva')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final existing = _profiles.indexWhere((profile) => profile['name']!.toLowerCase() == name.toLowerCase());
    final profile = <String, String>{
      'id': existing >= 0 ? _profiles[existing]['id']! : DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name,
      'url': streamUrl,
    };
    setState(() {
      if (existing >= 0) {
        _profiles[existing] = profile;
      } else {
        _profiles.insert(0, profile);
      }
      _error = null;
    });
    try {
      await _persistProfiles();
      unawaited(EventStore.record('Telecamera IP salvata', 'Profilo "$name" memorizzato in archivio protetto sul dispositivo'));
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossibile salvare il profilo in archivio protetto: $e');
    }
  }

  Future<void> _deleteProfile(String id) async {
    final previous = List<Map<String, String>>.from(_profiles);
    setState(() => _profiles.removeWhere((profile) => profile['id'] == id));
    try {
      await _persistProfiles();
    } catch (e) {
      if (mounted) setState(() {
        _profiles
          ..clear()
          ..addAll(previous);
        _error = 'Impossibile eliminare il profilo: $e';
      });
    }
  }

  Future<void> _openProfile(Map<String, String> profile) async {
    _url.text = profile['url'] ?? '';
    await _connect();
  }
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
      Row(
        children: [
          const Expanded(child: Text('Le mie telecamere', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          TextButton.icon(
            onPressed: _saveCurrentProfile,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Salva'),
          ),
        ],
      ),
      if (_profilesLoading)
        const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
      else if (_profiles.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Nessun profilo salvato. Inserisci l’URL e premi Salva per riutilizzarlo in seguito.', style: TextStyle(color: _ipMuted, height: 1.4, fontSize: 12)),
        )
      else
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: _ipPanel, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: _profiles.map((profile) => ListTile(
              leading: const Icon(Icons.videocam_outlined, color: _ipCyan),
              title: Text(profile['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                Uri.tryParse(profile['url'] ?? '')?.host ?? 'URL salvato',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _ipMuted, fontSize: 11),
              ),
              onTap: () => _openProfile(profile),
              trailing: IconButton(
                tooltip: 'Elimina profilo',
                icon: const Icon(Icons.delete_outline, color: Color(0xFFFF8C9D)),
                onPressed: () => _deleteProfile(profile['id']!),
              ),
            )).toList(),
          ),
        ),
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
