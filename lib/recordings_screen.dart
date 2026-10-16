import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

const _recordingsBg = Color(0xFF080B12);
const _recordingsPanel = Color(0xFF111824);
const _recordingsCyan = Color(0xFF48E5F2);
const _recordingsMuted = Color(0xFF8D9AAF);

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  late Future<List<File>> _files = _loadFiles();

  Future<List<File>> _loadFiles() async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/recordings');
    if (!await folder.exists()) return <File>[];
    final entries = await folder.list().toList();
    final files = entries.whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  void _refresh() => setState(() => _files = _loadFiles());

  Future<void> _delete(File file) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la registrazione?'),
        content: Text(file.uri.pathSegments.last),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await file.delete();
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registrazione eliminata dal dispositivo.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eliminazione non riuscita: $e')));
    }
  }

  String _size(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    } catch (_) {
      return 'Dimensione non disponibile';
    }
  }

  String _date(File file) {
    try {
      return file.lastModifiedSync().toLocal().toString().split('.').first;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _recordingsBg,
    appBar: AppBar(
      backgroundColor: _recordingsBg,
      title: const Text('Registrazioni locali'),
      actions: [IconButton(onPressed: _refresh, tooltip: 'Aggiorna', icon: const Icon(Icons.refresh_rounded))],
    ),
    body: FutureBuilder<List<File>>(
      future: _files,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Impossibile leggere le registrazioni: ${snapshot.error}', textAlign: TextAlign.center)));
        }
        final files = snapshot.data ?? <File>[];
        if (files.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.video_library_outlined, size: 58, color: _recordingsCyan),
              SizedBox(height: 16),
              Text('Nessuna registrazione', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
              Text('Avvia la telecamera su questo telefono e usa “Avvia registrazione locale”. I file restano nell’area privata dell’app.', textAlign: TextAlign.center, style: TextStyle(color: _recordingsMuted, height: 1.5)),
            ]),
          ));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: files.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final file = files[index];
            return Container(
              decoration: BoxDecoration(color: _recordingsPanel, borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecordingPlaybackScreen(file: file))),
                leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: _recordingsCyan.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.play_circle_outline_rounded, color: _recordingsCyan)),
                title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                subtitle: Text('${_size(file)} · ${_date(file)}', style: const TextStyle(color: _recordingsMuted, fontSize: 10)),
                trailing: IconButton(onPressed: () => _delete(file), tooltip: 'Elimina', icon: const Icon(Icons.delete_outline_rounded, color: _recordingsMuted)),
              ),
            );
          },
        );
      },
    ),
  );
}

class RecordingPlaybackScreen extends StatefulWidget {
  const RecordingPlaybackScreen({super.key, required this.file});
  final File file;

  @override
  State<RecordingPlaybackScreen> createState() => _RecordingPlaybackScreenState();
}

class _RecordingPlaybackScreenState extends State<RecordingPlaybackScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(widget.file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Il file non può essere riprodotto su questo dispositivo: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _recordingsBg,
    appBar: AppBar(backgroundColor: _recordingsBg, title: const Text('Riproduci registrazione')),
    body: Center(
      child: _error != null
        ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))
        : _controller == null
          ? const CircularProgressIndicator()
          : Column(mainAxisSize: MainAxisSize.min, children: [
              AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)),
              const SizedBox(height: 16),
              IconButton.filled(
                onPressed: () => setState(() {
                  if (_controller!.value.isPlaying) {
                    _controller!.pause();
                  } else {
                    _controller!.play();
                  }
                }),
                icon: Icon(_controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              VideoProgressIndicator(_controller!, allowScrubbing: true),
            ]),
    ),
  );
}
