import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

const _bg = Color(0xFF080B12);
const _panel = Color(0xFF111824);
const _cyan = Color(0xFF48E5F2);
const _green = Color(0xFF47E0A0);
const _muted = Color(0xFF8D9AAF);

class CameraSenderScreen extends StatefulWidget {
  const CameraSenderScreen({super.key});
  @override
  State<CameraSenderScreen> createState() => _CameraSenderScreenState();
}

class _CameraSenderScreenState extends State<CameraSenderScreen>
    with WidgetsBindingObserver {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  MediaStream? _stream;
  bool _loading = true;
  bool _frontCamera = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPreview();
  }

  Future<void> _startPreview() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await _renderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': _frontCamera ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 24, 'max': 30},
        },
      });
      if (!mounted) {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
        return;
      }
      _stream = stream;
      _renderer.srcObject = stream;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Impossibile avviare la fotocamera. Controlla i permessi Android e riprova.\n\nDettaglio: $e';
      });
    }
  }

  Future<void> _stopPreview() async {
    final stream = _stream;
    _stream = null;
    _renderer.srcObject = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPreview();
    } else if (state == AppLifecycleState.resumed) {
      _startPreview();
    }
  }

  Future<void> _switchCamera() async {
    setState(() => _frontCamera = !_frontCamera);
    await _stopPreview();
    await _startPreview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPreview();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final previewHeight = (size.height * .48).clamp(320.0, 560.0);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Modalità telecamera'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            height: previewHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _cyan.withValues(alpha: .22)),
            ),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _cyan))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.no_photography_outlined,
                                  color: _muted, size: 44),
                              const SizedBox(height: 14),
                              Text(_error!, textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white)),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _startPreview,
                                child: const Text('Riprova'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          RTCVideoView(
                            _renderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .72),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, color: _green, size: 8),
                                  SizedBox(width: 7),
                                  Text('ANTEPRIMA LOCALE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      )),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: IconButton.filled(
                              tooltip: 'Cambia fotocamera',
                              onPressed: _switchCamera,
                              icon: const Icon(Icons.cameraswitch_rounded),
                            ),
                          ),
                        ],
                      ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Questo telefono diventa una telecamera',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'L’anteprima usa ora il motore multimediale WebRTC, la base tecnica per trasmettere il flusso a un secondo dispositivo.',
            style: TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: _cyan),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Il video resta su questo telefono: il pairing e lo scambio WebRTC con un ricevitore non sono ancora attivi. Non lasciare questa schermata aperta pensando che stia già trasmettendo.',
                    style: TextStyle(color: _muted, height: 1.45, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
