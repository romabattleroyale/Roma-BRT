import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bg = Color(0xFF080B12);
const _panel = Color(0xFF111824);
const _cyan = Color(0xFF48E5F2);
const _violet = Color(0xFF9B7BFF);
const _muted = Color(0xFF8D9AAF);

class HousePlanScreen extends StatefulWidget {
  const HousePlanScreen({super.key});
  @override
  State<HousePlanScreen> createState() => _HousePlanScreenState();
}

class _HousePlanScreenState extends State<HousePlanScreen> {
  static const _storageKey = 'sentinel_house_plan_camera_markers_v1';
  final List<Map<String, dynamic>> _markers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _markers
            ..clear()
            ..addAll(decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_markers));
  }

  Future<void> _addAt(Offset point, Size size) async {
    var markerName = 'Telecamera ${_markers.length + 1}';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Aggiungi punto telecamera'),
        content: TextFormField(
          initialValue: markerName,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'Nome / posizione'),
          onChanged: (value) => markerName = value,
          onFieldSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, markerName.trim()), child: const Text('Aggiungi')),
        ],
      ),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() {
      _markers.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'name': name.trim(),
        'x': (point.dx / size.width).clamp(0.04, 0.96),
        'y': (point.dy / size.height).clamp(0.04, 0.96),
      });
    });
    await _save();
  }

  Future<void> _markerActions(Map<String, dynamic> marker) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_rounded, color: _cyan),
              title: Text(marker['name']?.toString() ?? 'Telecamera'),
              subtitle: const Text('Punto planimetria salvato localmente'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rinomina punto'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Rimuovi punto'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      setState(() => _markers.removeWhere((item) => item['id'] == marker['id']));
      await _save();
    } else if (action == 'rename') {
      var renamed = marker['name']?.toString() ?? '';
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _panel,
          title: const Text('Rinomina punto'),
          content: TextFormField(
            initialValue: renamed,
            autofocus: true,
            maxLength: 32,
            onChanged: (value) => renamed = value,
            onFieldSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, renamed.trim()), child: const Text('Salva')),
          ],
        ),
      );
      if (name != null && name.isNotEmpty && mounted) {
        setState(() => marker['name'] = name);
        await _save();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Planimetria di casa'),
        actions: [
          IconButton(
            tooltip: 'Rimuovi tutti i punti',
            onPressed: _markers.isEmpty ? null : () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: _panel,
                  title: const Text('Cancellare i punti?'),
                  content: const Text('Saranno rimossi i punti telecamera salvati su questo telefono.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annulla')),
                    FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancella')),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                setState(_markers.clear);
                await _save();
              }
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _violet.withValues(alpha: .25)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EDITOR PLANIMETRIA', style: TextStyle(color: _cyan, fontWeight: FontWeight.w800, letterSpacing: 1.3, fontSize: 10)),
                      SizedBox(height: 8),
                      Text('Tocca la pianta per aggiungere un punto telecamera. Premi un punto per rinominarlo o rimuoverlo.', style: TextStyle(color: _muted, height: 1.45, fontSize: 12)),
                      SizedBox(height: 8),
                      Text('I punti sono salvati sul telefono. La pianta è una base manuale, non una ricostruzione 3D/AR automatica.', style: TextStyle(color: _muted, height: 1.45, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AspectRatio(
                  aspectRatio: 0.82,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _addAt(details.localPosition, size),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1420),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _cyan.withValues(alpha: .35)),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(child: CustomPaint(painter: _PlanPainter())),
                              const Positioned(left: 14, top: 12, child: Text('CASA · PIANTA MANUALE', style: TextStyle(color: _muted, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.bold))),
                              Positioned.fill(
                                child: Stack(
                                  children: _markers.map((marker) {
                                    final x = (marker['x'] as num).toDouble().clamp(0.0, 1.0);
                                    final y = (marker['y'] as num).toDouble().clamp(0.0, 1.0);
                                    return Positioned(
                                      left: (size.width - 42) * x,
                                      top: (size.height - 42) * y,
                                      child: GestureDetector(
                                        onTap: () => _markerActions(marker),
                                        child: Container(
                                          constraints: const BoxConstraints(maxWidth: 150),
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF102630),
                                            borderRadius: BorderRadius.circular(13),
                                            border: Border.all(color: _cyan, width: 1.2),
                                            boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .15), blurRadius: 12)],
                                          ),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            const Icon(Icons.videocam_rounded, color: _cyan, size: 15),
                                            const SizedBox(width: 5),
                                            Flexible(child: Text(marker['name']?.toString() ?? 'Telecamera', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                                          ]),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _summary('PUNTI SALVATI', _markers.length.toString(), _cyan)),
                    const SizedBox(width: 10),
                    Expanded(child: _summary('SALVATAGGIO', 'LOCALE', _violet)),
                  ],
                ),
                const SizedBox(height: 14),
                if (_markers.isEmpty)
                  const Text('Nessun punto inserito. Tocca un punto della pianta per cominciare.', style: TextStyle(color: _muted, fontSize: 12))
                else
                  ..._markers.map((marker) => Card(
                    color: _panel,
                    child: ListTile(
                      leading: const Icon(Icons.videocam_outlined, color: _cyan),
                      title: Text(marker['name']?.toString() ?? 'Telecamera'),
                      subtitle: const Text('Posizione personalizzata'),
                      trailing: IconButton(icon: const Icon(Icons.more_horiz), onPressed: () => _markerActions(marker)),
                    ),
                  )),
              ],
            ),
    );
  }

  Widget _summary(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 9, letterSpacing: .7)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
    ]),
  );
}

class _PlanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = _cyan.withValues(alpha: .055)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final wall = Paint()..color = const Color(0xFF26364A)..style = PaintingStyle.fill;
    final outline = Paint()..color = _cyan.withValues(alpha: .85)..style = PaintingStyle.stroke..strokeWidth = 4;
    final left = size.width * .12;
    final top = size.height * .17;
    final right = size.width * .88;
    final bottom = size.height * .88;
    final outer = Path()
      ..moveTo(left, top)
      ..lineTo(right, top)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();
    canvas.drawPath(outer, wall);
    canvas.drawPath(outer, outline);
    final inner = Paint()..color = _cyan.withValues(alpha: .72)..strokeWidth = 3;
    canvas.drawLine(Offset(size.width * .52, top), Offset(size.width * .52, size.height * .52), inner);
    canvas.drawLine(Offset(left, size.height * .48), Offset(right, size.height * .48), inner);
    canvas.drawLine(Offset(size.width * .52, size.height * .69), Offset(size.width * .52, bottom), inner);
    final labels = [
      ('SOGGIORNO', Offset(size.width * .20, size.height * .30)),
      ('CUCINA', Offset(size.width * .62, size.height * .30)),
      ('CAMERA 1', Offset(size.width * .20, size.height * .59)),
      ('CAMERA 2', Offset(size.width * .62, size.height * .59)),
      ('BAGNO', Offset(size.width * .62, size.height * .75)),
    ];
    for (final item in labels) {
      final painter = TextPainter(
        text: TextSpan(text: item.$1, style: TextStyle(color: Colors.white.withValues(alpha: .45), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: .5)),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, item.$2);
    }
  }
  @override
  bool shouldRepaint(covariant _PlanPainter oldDelegate) => false;
}
