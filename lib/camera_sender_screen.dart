import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  CameraController? _controller;
  bool _loading = true;
  String? _error;
  List<CameraDescription> _cameras = const [];
  int _selectedCamera = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('no-camera', 'Nessuna fotocamera disponibile.');
      }
      _selectedCamera = _selectedCamera.clamp(0, _cameras.length - 1);
      final controller = CameraController(
        _cameras[_selectedCamera], ResolutionPreset.high, enableAudio: false);
      _controller = controller;
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      setState(() => _loading = false);
    } on CameraException catch (e) {
      if (mounted) setState(() { _loading = false; _error = _cameraError(e); });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Impossibile avviare la fotocamera: ' + e.toString();
      });
    }
  }

  String _cameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        return 'Permesso fotocamera negato. Consenti l’accesso nelle impostazioni Android.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Accesso fotocamera bloccato. Abilitalo dalle impostazioni Android.';
      case 'no-camera':
        return e.description ?? 'Nessuna fotocamera disponibile.';
      default:
        return e.description ?? 'Errore fotocamera (' + e.code + ').';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    await _controller?.dispose();
    _controller = null;
    _selectedCamera = (_selectedCamera + 1) % _cameras.length;
    await _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Modalità telecamera')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Container(
          height: 390, clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _panel, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _cyan.withValues(alpha: .22))),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _cyan))
              : _error != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.no_photography_outlined, color: _muted, size: 44),
                        const SizedBox(height: 14),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _initializeCamera, child: const Text('Riprova')),
                      ])))
                  : controller != null && controller.value.isInitialized
                      ? Stack(fit: StackFit.expand, children: [
                          CameraPreview(controller),
                          Positioned(top: 14, left: 14, child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .65),
                              borderRadius: BorderRadius.circular(20)),
                            child: const Row(children: [
                              Icon(Icons.circle, color: _green, size: 8),
                              SizedBox(width: 7),
                              Text('ANTEPRIMA LOCALE', style: TextStyle(
                                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ]))),
                          if (_cameras.length > 1)
                            Positioned(right: 12, bottom: 12, child: IconButton.filled(
                              onPressed: _switchCamera, icon: const Icon(Icons.cameraswitch_rounded))),
                        ])
                      : const Center(child: Text('Fotocamera non disponibile')),
        ),
        const SizedBox(height: 18),
        const Text('Questo telefono diventa una telecamera',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Questa prima fase verifica la fotocamera e mostra l’anteprima sul dispositivo. Il video non viene ancora trasmesso all’altro telefono.',
          style: TextStyle(color: _muted, height: 1.5)),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(18)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline_rounded, color: _cyan),
            SizedBox(width: 12),
            Expanded(child: Text(
              'Privacy: l’anteprima resta su questo telefono. La condivisione locale e l’accesso remoto verranno attivati dopo aver implementato associazione sicura e trasporto video.',
              style: TextStyle(color: _muted, height: 1.45, fontSize: 12))),
          ])),
      ]),
    );
  }
}
