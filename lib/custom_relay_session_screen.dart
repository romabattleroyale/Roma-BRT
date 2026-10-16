import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'custom_stream_transport.dart';
import 'pairing_payload.dart';
import 'signaling_config.dart';

class CustomRelaySessionScreen extends StatefulWidget {
  const CustomRelaySessionScreen({super.key, required this.cameraRole, this.remote = false});
  final bool cameraRole;
  final bool remote;
  @override State<CustomRelaySessionScreen> createState() => _CustomRelaySessionScreenState();
}

class _CustomRelaySessionScreenState extends State<CustomRelaySessionScreen> {
  static const bg = Color(0xFF080B12), panel = Color(0xFF111824), cyan = Color(0xFF48E5F2), violet = Color(0xFF9B7BFF), muted = Color(0xFF8D9AAF);
  final server = TextEditingController(text: defaultSignalingServerUrl);
  final room = TextEditingController(text: _newRoomCode());
  final token = TextEditingController();
  CameraController? camera;
  SentinelStreamTransport? transport;
  Uint8List? frame;
  String status = 'Non collegato';
  String? error;
  bool busy = false, encoding = false;
  DateTime lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  static String _newRoomCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = math.Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  Future<void> connect() async {
    if (busy || transport != null) return;
    setState(() { busy = true; error = null; });
    try {
      final base = PairingPayload.parseServer(server.text.trim());
      if (widget.remote && base.scheme != 'wss') {
        throw const FormatException('Per la modalità Internet è obbligatorio WSS/TLS');
      }
      final client = SentinelStreamTransport(server: base, room: room.text.trim().toUpperCase(), role: widget.cameraRole ? SentinelStreamRole.camera : SentinelStreamRole.viewer, token: token.text,
        onStatus: (s) { if (mounted) setState(() => status = s); },
        onError: (e) { if (mounted) setState(() => error = e.toString()); },
        onFrame: (bytes) { if (mounted && !widget.cameraRole) setState(() => frame = bytes); });
      await client.connect();
      transport = client;
      if (widget.cameraRole) await _startCamera();
      if (mounted) setState(() { busy = false; });
    } catch (e) {
      await _stopCamera();
      final old = transport; transport = null; await old?.close();
      if (mounted) setState(() { busy = false; error = e.toString(); status = 'Non collegato'; });
    }
  }

  Future<void> _startCamera() async {
    final devices = await availableCameras();
    if (devices.isEmpty) throw StateError('Fotocamera non disponibile');
    final device = devices.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => devices.first);
    final controller = CameraController(device, ResolutionPreset.low, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    camera = controller;
    await controller.initialize();
    await controller.startImageStream((image) {
      if (encoding || transport?.isConnected != true || DateTime.now().difference(lastFrame).inMilliseconds < 250) return;
      encoding = true; lastFrame = DateTime.now();
      unawaited(Future<void>(() async {
        try { final bytes = _jpeg(image); if (bytes != null && transport?.isConnected == true) transport!.sendJpeg(bytes); }
        catch (e) { if (mounted) setState(() => error = 'Codifica JPEG: $e'); }
        finally { encoding = false; }
      }));
    });
  }

  Uint8List? _jpeg(CameraImage src) {
    if (src.format.group != ImageFormatGroup.yuv420 || src.planes.length < 3) throw StateError('Formato camera non supportato');
    final out = img.Image(width: src.width, height: src.height);
    final yp = src.planes[0], up = src.planes[1], vp = src.planes[2];
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final yIndex = y * yp.bytesPerRow + x * (yp.bytesPerPixel ?? 1);
        final uIndex = (y >> 1) * up.bytesPerRow + (x >> 1) * (up.bytesPerPixel ?? 1);
        final vIndex = (y >> 1) * vp.bytesPerRow + (x >> 1) * (vp.bytesPerPixel ?? 1);
        if (yIndex >= yp.bytes.length || uIndex >= up.bytes.length || vIndex >= vp.bytes.length) {
          throw StateError('Buffer YUV incompleto');
        }
        final yy = yp.bytes[yIndex];
        final u = up.bytes[uIndex] - 128;
        final v = vp.bytes[vIndex] - 128;
        final c = (yy - 16).clamp(0, 255);
        out.setPixelRgb(x, y, (1.164*c + 1.596*v).round().clamp(0,255), (1.164*c - .392*u - .813*v).round().clamp(0,255), (1.164*c + 2.017*u).round().clamp(0,255));
      }
    }
    final scaled = img.copyResize(out, width: 480);
    final bytes = img.encodeJpg(scaled, quality: 45);
    if (bytes.length > 1024 * 1024) throw StateError('JPEG oltre 1 MiB');
    if (mounted && widget.cameraRole && frame == null) setState(() => frame = Uint8List.fromList(bytes));
    return Uint8List.fromList(bytes);
  }

  Future<void> _stopCamera() async { final c = camera; camera = null; if (c == null) return; try { if (c.value.isStreamingImages) await c.stopImageStream(); } catch (_) {} try { await c.dispose(); } catch (_) {} }
  Future<void> disconnect() async { if (busy) return; setState(() => busy = true); await _stopCamera(); final old = transport; transport = null; await old?.close(); if (mounted) setState(() { busy = false; frame = null; status = 'Sessione terminata'; }); }
  @override void dispose() { final t = transport; if (t != null) unawaited(t.close()); final c = camera; if (c != null) unawaited(c.dispose()); server.dispose(); room.dispose(); token.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(backgroundColor: bg, appBar: AppBar(backgroundColor: bg, title: Text(widget.cameraRole ? 'Telecamera · relay JPEG' : 'Monitor · relay JPEG')), body: ListView(padding: const EdgeInsets.all(16), children: [
    Container(height: 230, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18)), child: frame == null ? const Center(child: Text('In attesa dei fotogrammi', style: TextStyle(color: muted))) : Image.memory(frame!, fit: BoxFit.contain, gaplessPlayback: true)),
    const SizedBox(height: 12), Text(status, style: const TextStyle(color: cyan, fontWeight: FontWeight.bold)),
    if (error != null) Text(error!, style: const TextStyle(color: Color(0xFFFFA6B5))),
    TextField(controller: server, enabled: transport == null && !busy, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Server ws:// o wss://')),
    TextField(controller: room, enabled: transport == null && !busy, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Codice stanza (6–10 caratteri)')),
    TextField(controller: token, enabled: transport == null && !busy, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Token facoltativo')),
    if (widget.cameraRole) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(color: Colors.white, padding: const EdgeInsets.all(8), child: AnimatedBuilder(animation: Listenable.merge([server, room]), builder: (context, _) => QrImageView(data: jsonEncode({'server': server.text.trim(), 'room': room.text.trim().toUpperCase()}), size: 150)))),
    const SizedBox(height: 12), FilledButton(onPressed: busy ? null : (transport == null ? connect : disconnect), style: FilledButton.styleFrom(backgroundColor: violet), child: Text(busy ? 'Attendi…' : (transport == null ? 'Avvia relay personalizzato' : 'Termina sessione'))),
    const Text('Trasporto JPEG binario su WebSocket; non usa WebRTC. Solo video, senza audio. Per Internet serve WSS/TLS e il server /stream/<CODICE>.', style: TextStyle(color: muted, fontSize: 11)),
  ]));
}