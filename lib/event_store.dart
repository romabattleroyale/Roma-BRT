import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local event history. It deliberately stores no video or credentials.
class EventStore {
  static const _storageKey = 'sentinel_one_security_events_v1';
  static const _maxEvents = 100;

  static Future<void> record(String title, String detail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final events = prefs.getStringList(_storageKey) ?? <String>[];
      events.insert(0, jsonEncode(<String, String>{
        'title': title,
        'detail': detail,
        'time': DateTime.now().toIso8601String(),
      }));
      if (events.length > _maxEvents) {
        events.removeRange(_maxEvents, events.length);
      }
      await prefs.setStringList(_storageKey, events);
    } catch (_) {
      // Event logging must never interrupt camera or monitor operation.
    }
  }

  static Future<List<Map<String, String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_storageKey) ?? <String>[];
      final events = <Map<String, String>>[];
      for (final raw in stored) {
        try {
          final value = jsonDecode(raw);
          if (value is! Map) continue;
          final event = <String, String>{
            'title': value['title']?.toString() ?? 'Evento',
            'detail': value['detail']?.toString() ?? '',
            'time': value['time']?.toString() ?? '',
          };
          if (event['title']!.isNotEmpty) events.add(event);
        } catch (_) {
          // Skip one malformed entry without hiding the rest of the history.
          continue;
        }
      }
      return events;
    } catch (_) {
      return <Map<String, String>>[];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}
