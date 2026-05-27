import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

abstract class ReminderScheduler {
  Future<void> scheduleDaily({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  });

  Future<void> cancel(String type);
}

class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  @override
  Future<void> scheduleDaily({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    await _ensureInitialized();
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await _plugin.zonedSchedule(
      _notificationId(type),
      title,
      body,
      _nextInstanceOf(time),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'fitloop_daily_reminders',
          'FitLoop reminders',
          channelDescription: 'Daily health and activity reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel(String type) async {
    await _ensureInitialized();
    await _plugin.cancel(_notificationId(type));
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _initialized = true;
  }

  tz.TZDateTime _nextInstanceOf(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  int _notificationId(String type) {
    switch (type) {
      case 'sport':
        return 1001;
      case 'sit':
        return 1002;
      case 'drink':
        return 1003;
      case 'sleep':
        return 1004;
      default:
        return 1099;
    }
  }
}
