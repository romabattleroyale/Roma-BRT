import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize({bool requestPermission = false}) async {
    if (!_initialized) {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_sentinel'),
        ),
      );
      _initialized = true;
    }
    if (requestPermission) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> showSecurityAlert({
    required String title,
    required String body,
  }) async {
    try {
      await initialize();
      final id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'sentinel_one_security_alerts',
            'SENTINEL ONE · Avvisi',
            channelDescription: 'Avvisi di sicurezza rilevati da SENTINEL ONE',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
    } catch (_) {
      // Notification delivery must not interrupt live video.
    }
  }
}
