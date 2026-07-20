import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

abstract class ReminderScheduler {
  Future<void> scheduleOnce({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  });

  Future<void> scheduleDaily({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  });

  Future<void> scheduleWeekly({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
    required int timesPerWeek,
  });

  Future<void> cancel(String type);
}

class ReminderPermissionDeniedException implements Exception {
  const ReminderPermissionDeniedException();

  @override
  String toString() => '通知权限未开启，请在系统设置中允许 FitLoop 发送通知';
}

class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  @override
  Future<void> scheduleOnce({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    await _ensureInitialized();
    await _requestPermission();
    await _cancelScheduledType(type);
    await _plugin.zonedSchedule(
      _notificationId(type),
      title,
      body,
      _nextInstanceOf(time),
      _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _notificationPayload(type),
    );
  }

  @override
  Future<void> scheduleDaily({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    await _ensureInitialized();
    await _requestPermission();
    await _cancelScheduledType(type);
    await _plugin.zonedSchedule(
      _notificationId(type),
      title,
      body,
      _nextInstanceOf(time),
      _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: _notificationPayload(type),
    );
  }

  @override
  Future<void> scheduleWeekly({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
    required int timesPerWeek,
  }) async {
    await _ensureInitialized();
    await _requestPermission();
    await _cancelScheduledType(type);
    final count = timesPerWeek.clamp(1, 7).toInt();
    final now = tz.TZDateTime.now(tz.local);
    for (var index = 0; index < count; index += 1) {
      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      ).add(Duration(days: index));
      if (!scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 7));
      }
      await _plugin.zonedSchedule(
        _notificationId(type) + index,
        title,
        body,
        scheduled,
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: _notificationPayload(type),
      );
    }
  }

  @override
  Future<void> cancel(String type) async {
    await _ensureInitialized();
    await _cancelScheduledType(type);
  }

  Future<void> _requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await androidPlugin?.requestNotificationsPermission();
    if (granted == false) {
      throw const ReminderPermissionDeniedException();
    }
  }

  Future<void> _cancelScheduledType(String type) async {
    final ids = <int>{
      for (var index = 0; index < 7; index += 1) _notificationId(type) + index,
    };

    // Versions before the ID layout migration used overlapping ranges
    // (1001..1010). Only remove legacy entries that can be attributed to this
    // reminder, otherwise editing one reminder can accidentally cancel another.
    final pending = await _plugin.pendingNotificationRequests();
    ids.addAll(
      pending
          .where((request) => _isLegacyRequestForType(request, type))
          .map((request) => request.id),
    );

    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }

  bool _isLegacyRequestForType(
    PendingNotificationRequest request,
    String type,
  ) {
    if (request.id < 1001 || request.id > 1010) return false;
    if (request.payload == _notificationPayload(type)) return true;
    final titlePrefix = _legacyTitlePrefix(type);
    return titlePrefix != null &&
        request.title?.startsWith(titlePrefix) == true;
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'fitloop_daily_reminders',
      'FitLoop reminders',
      channelDescription: 'Daily health and activity reminders',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

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
        return 2000;
      case 'sit':
        return 2010;
      case 'drink':
        return 2020;
      case 'sleep':
        return 2030;
      default:
        return 2090;
    }
  }

  String _notificationPayload(String type) => 'fitloop_reminder:$type';

  String? _legacyTitlePrefix(String type) {
    switch (type) {
      case 'sport':
        return '运动 提醒';
      case 'sit':
        return '久坐 提醒';
      case 'drink':
        return '喝水 提醒';
      case 'sleep':
        return '睡眠 提醒';
      default:
        return null;
    }
  }
}
