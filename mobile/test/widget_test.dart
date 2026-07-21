import 'dart:io';

import 'package:fitloop/api_client.dart';
import 'package:fitloop/main.dart';
import 'package:fitloop/reminder_scheduler.dart';
import 'package:fitloop/secure_session_storage.dart';
import 'package:fitloop/sync_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TokenStorage.useSecureStoreForTesting(_WidgetTestSecureStore());
  });

  testWidgets('renders login then dashboard shell', (tester) async {
    await tester.pumpWidget(
      FitLoopApp(
        api: _FakeApi.withTarget(),
        locationService: _FakeLocationService(),
      ),
    );
    await _enterApp(tester);

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('运动'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('社交'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('测试用户'), findsOneWidget);
    // Dashboard now has more content, scroll to find the target card
    await tester.scrollUntilVisible(
      find.textContaining('本周 运动次数：1 / 3'),
      200.0,
    );
    expect(find.textContaining('本周 运动次数：1 / 3'), findsOneWidget);

    await tester.tap(find.text('社交'));
    await tester.pumpAndSettle();

    expect(find.textContaining('120 积分 / Lv.2'), findsOneWidget);
    expect(find.textContaining('校园活力达人'), findsOneWidget);
    expect(find.textContaining('测试用户 / 5.2 km / 320.0 kcal'), findsOneWidget);

    await tester.tap(find.text('运动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始打卡'));
    await tester.pumpAndSettle();
    await _selectGpsCheckinMode(tester);

    expect(find.textContaining('已上传 1 个轨迹点'), findsOneWidget);
  });

  testWidgets('refreshes ranking on tab entry and switches scope',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );
    await _enterApp(tester);
    final initialCalls = api.rankingCalls;

    await tester.tap(find.text('社交'));
    await tester.pumpAndSettle();

    expect(api.rankingCalls, initialCalls + 1);
    expect(api.lastRankingScope, 'friends');

    final globalScope = find.byKey(const Key('ranking-scope-global'));
    tester.widget<ChoiceChip>(globalScope).onSelected!(true);
    await tester.pumpAndSettle();

    expect(api.lastRankingScope, 'global');
  });

  testWidgets('registers with email verification code', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );
    await _openAuthPage(tester);

    await tester.tap(find.text('没有账号，创建账号'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'student@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'pass1234');
    await tester.enterText(find.byType(TextField).at(2), 'pass1234');
    await tester.enterText(find.byType(TextField).at(3), '邮箱用户');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(api.lastVerificationChannel, 'email');
    expect(api.lastVerificationTarget, 'student@example.com');
    expect(api.lastVerificationPurpose, 'register');

    await tester.enterText(find.byType(TextField).at(4), '123456');
    await tester.tap(find.text('注册并进入'));
    await tester.pump();

    expect(api.lastRegisterCode, '123456');
  });

  testWidgets('logs in with email verification code', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );
    await _openAuthPage(tester);

    await tester.tap(find.text('验证码登录'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'student@example.com');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.text('登录'));
    await tester.pump();

    expect(api.lastVerificationChannel, 'email');
    expect(api.lastVerificationPurpose, 'login');
    expect(api.lastLoginCode, '123456');
    expect(api.lastLoginType, 'code');
  });

  testWidgets('resets password with verification code', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );
    await _openAuthPage(tester);

    await tester.tap(find.text('忘记密码'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'student@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'newpass123');
    await tester.enterText(find.byType(TextField).at(2), 'newpass123');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField).at(3), '123456');
    await tester.tap(find.text('重置密码'));
    await tester.pump();

    expect(api.lastVerificationPurpose, 'reset_password');
    expect(api.lastResetAccount, 'student@example.com');
    expect(api.lastResetCode, '123456');
    expect(api.lastResetPassword, 'newpass123');
    expect(find.text('密码已重置，请使用新密码登录'), findsOneWidget);
  });

  testWidgets('creates target from empty dashboard state', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );
    await _enterApp(tester);

    // Dashboard now has more content, scroll to find the target card
    await tester.scrollUntilVisible(
      find.text('暂无进行中目标'),
      200.0,
    );
    expect(find.text('暂无进行中目标'), findsOneWidget);

    // Scroll to the create target button
    await tester.scrollUntilVisible(
      find.byKey(const Key('target-create-button')),
      200.0,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('target-create-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('target-save-button')));
    await tester.pumpAndSettle();

    expect(api.createdTargets, 1);
    // After creating target, scroll back to find the target card
    await tester.scrollUntilVisible(
      find.textContaining('本周 运动次数：0 / 3'),
      200.0,
    );
    expect(find.textContaining('本周 运动次数：0 / 3'), findsOneWidget);
  });

  testWidgets('submits health data from stats page', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );
    await _enterApp(tester);
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();

    expect(find.text('本周运动次数'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('里程 / 热量趋势'), 300);
    await tester.pumpAndSettle();
    expect(find.text('里程 / 热量趋势'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('体重趋势'), 300);
    await tester.pumpAndSettle();
    expect(find.text('体重趋势'), findsOneWidget);
    expect(find.textContaining('暂无数据'), findsNWidgets(2));

    await tester.scrollUntilVisible(find.text('记录健康数据'), -300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录健康数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存健康数据'));
    await tester.pumpAndSettle();

    expect(find.text('请至少填写一项健康数据'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '体重 kg'), '62.5');
    await tester.enterText(find.widgetWithText(TextField, '睡眠小时'), '7.5');
    await tester.enterText(find.widgetWithText(TextField, '饮食备注'), '清淡饮食');
    await tester.tap(find.text('保存健康数据'));
    await tester.pumpAndSettle();

    expect(api.createdHealthData, 1);
    expect(find.textContaining('体重 62.5 kg'), findsOneWidget);
    expect(find.textContaining('睡眠 7.5 小时'), findsOneWidget);
    expect(find.textContaining('饮食 清淡饮食'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('体重趋势'), 300);
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无数据'), findsOneWidget);
  });

  testWidgets('does not start GPS session when permission is denied forever',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(
          initialPermission: LocationPermission.denied,
          requestedPermission: LocationPermission.deniedForever,
        ),
      ),
    );

    await _openSportPage(tester);
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    await _selectGpsCheckinMode(tester);

    expect(api.startedSports, 0);
    expect(find.textContaining('需要位置权限'), findsOneWidget);
  });

  testWidgets('ignores inaccurate GPS stream positions', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(
          streamPositions: [_position(accuracy: 80)],
        ),
      ),
    );

    await _openSportPage(tester);
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    await _selectGpsCheckinMode(tester);

    expect(api.startedSports, 1);
    expect(api.uploadedTrackPoints, 0);
    expect(find.textContaining('GPS精度不足'), findsOneWidget);
  });

  testWidgets('counts final GPS point when finishing session', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(
          streamPositions: [_position(accuracy: 80)],
          currentPosition: _position(accuracy: 8),
        ),
      ),
    );

    await _openSportPage(tester);
    await _startSportSession(tester, api);
    await _finishSportSession(tester, api);

    expect(api.finishedSports, 1);
    expect(api.uploadedTrackPoints, 1);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('keeps session active when GPS stream reports an error',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(
          streamError: Exception('stream unavailable'),
        ),
      ),
    );

    await _openSportPage(tester);
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    await _selectGpsCheckinMode(tester);

    expect(api.startedSports, 1);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.textContaining('GPS定位失败'), findsOneWidget);
  });

  testWidgets('finishes session when final GPS lookup fails', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(
          streamPositions: [_position(accuracy: 80)],
          throwOnCurrentPosition: true,
        ),
      ),
    );

    await _openSportPage(tester);
    await _startSportSession(tester, api);
    await _finishSportSession(tester, api);

    expect(api.finishedSports, 1);
    expect(api.uploadedTrackPoints, 0);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('queues finish request when session finish fails',
      (tester) async {
    final api = _FakeApi(finishError: const SocketException('offline'));
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(
          currentPosition: _position(accuracy: 8),
        ),
      ),
    );

    await _openSportPage(tester);
    await _startSportSession(tester, api);
    await tester.tap(find.byKey(const Key('sport-session-toggle')));
    await tester.pumpAndSettle();

    final pending = await SyncQueue.pending();
    expect(pending, hasLength(1));
    expect(pending.single.sessionId, 'session-1');
    expect(find.textContaining('已加入离线同步队列'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('submits an appeal from a historical abnormal workout',
      (tester) async {
    final api = _FakeApi(
      sportRecords: const [
        SportRecord(
          recordId: 42,
          status: 2,
          durationSeconds: 1800,
          distanceKm: 5.2,
          calorie: 320,
          sportType: 'running',
          abnormalReason: 'GPS speed jump',
        ),
      ],
    );
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );

    await _openSportPage(tester);
    final appealButton = find.byKey(const Key('appeal-record-42'));
    await tester.scrollUntilVisible(appealButton, 200);
    expect(appealButton, findsOneWidget);

    tester.widget<TextButton>(appealButton).onPressed!();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'GPS signal drift');
    await tester.tap(find.byKey(const Key('submit-appeal')));
    await tester.pumpAndSettle();

    expect(api.createdAppeals, 1);
    expect(find.byKey(const Key('appeal-record-42')), findsNothing);
    expect(find.byKey(const Key('my-appeals-card')), findsOneWidget);
  });

  testWidgets('saves reminder and refreshes profile without reopening it',
      (tester) async {
    final api = _FakeApi(
      reminders: const [
        ReminderConfig(
          id: 1,
          type: 'sport',
          time: '08:00:00',
          cycle: 'daily',
          enabled: false,
        ),
      ],
    );
    final scheduler = _FakeReminderScheduler();
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(),
        reminderScheduler: scheduler,
      ),
    );

    await _openSportReminderSettings(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, '启用提醒'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(api.reminderUpsertCalls, 1);
    expect(scheduler.calls, contains('daily:sport'));
    expect(find.text('提醒设置已保存'), findsOneWidget);
    expect(find.text('已开启 · 08:00'), findsOneWidget);
    expect(find.text('运动 提醒'), findsNothing);
  });

  testWidgets('does not update server when local reminder scheduling fails',
      (tester) async {
    final api = _FakeApi(
      reminders: const [
        ReminderConfig(
          id: 1,
          type: 'sport',
          time: '08:00:00',
          cycle: 'daily',
          enabled: false,
        ),
      ],
    );
    final scheduler = _FakeReminderScheduler(
      scheduleError: Exception('local notification failed'),
    );
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(),
        reminderScheduler: scheduler,
      ),
    );

    await _openSportReminderSettings(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, '启用提醒'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(api.reminderUpsertCalls, 0);
    expect(api.reminders.single.enabled, isFalse);
    expect(scheduler.calls, ['daily:sport', 'cancel:sport']);
    expect(find.textContaining('local notification failed'), findsOneWidget);
    expect(find.text('运动 提醒'), findsOneWidget);
  });

  testWidgets('restores local reminder when server save fails', (tester) async {
    final api = _FakeApi(
      reminders: const [
        ReminderConfig(
          id: 1,
          type: 'sport',
          time: '08:00:00',
          cycle: 'daily',
          enabled: false,
        ),
      ],
      reminderUpsertError: Exception('server save failed'),
    );
    final scheduler = _FakeReminderScheduler();
    await tester.pumpWidget(
      FitLoopApp(
        api: api,
        locationService: _FakeLocationService(),
        reminderScheduler: scheduler,
      ),
    );

    await _openSportReminderSettings(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, '启用提醒'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(api.reminderUpsertCalls, 1);
    expect(api.reminders.single.enabled, isFalse);
    expect(scheduler.calls, ['daily:sport', 'cancel:sport']);
    expect(find.textContaining('server save failed'), findsOneWidget);
    expect(find.text('运动 提醒'), findsOneWidget);
  });

  _adminDashboardTests();
}

Future<void> _openAuthPage(WidgetTester tester) async {
  await tester.pumpAndSettle();
  if (find.text('跳过').evaluate().isNotEmpty) {
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
  }
}

Future<void> _enterApp(WidgetTester tester) async {
  // 等待启动页动画完成（AnimationController 1200ms）
  await _openAuthPage(tester);
  // 登录 — 输入账号密码（预填值已移除）
  await tester.enterText(find.byType(TextField).first, '13800000001');
  // 密码字段：password 登录模式下第二个输入框
  final textFields = find.byType(TextField).evaluate().toList();
  if (textFields.length >= 2) {
    await tester.enterText(find.byWidget(textFields[1].widget), 'pass1234');
  }
  await tester.tap(find.text('登录'));
  await tester.pumpAndSettle();
}

Future<void> _openSportPage(WidgetTester tester) async {
  await _enterApp(tester);
  await tester.tap(find.byIcon(Icons.directions_run_outlined));
  await tester.pumpAndSettle();
}

Future<void> _openSportReminderSettings(WidgetTester tester) async {
  await _enterApp(tester);
  await tester.tap(find.text('我的'));
  await tester.pumpAndSettle();
  final sportReminderTile = find.widgetWithText(ListTile, '运动');
  await tester.scrollUntilVisible(sportReminderTile, 200);
  await tester.tap(sportReminderTile);
  await tester.pumpAndSettle();
  expect(find.text('运动 提醒'), findsOneWidget);
}

Future<void> _selectGpsCheckinMode(WidgetTester tester) async {
  await tester.tap(find.text('GPS 定位打卡'));
  await tester.pumpAndSettle();
}

void _adminDashboardTests() {
  testWidgets('admin dashboard is visible only to admin sessions',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        session: const UserSession(
          token: 'user-token',
          userId: 1,
          nickname: 'User',
        ),
        api: api,
      ),
    ));
    expect(find.text('0.1.5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('管理后台'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        session: const UserSession(
          token: 'admin-token',
          userId: 2,
          nickname: 'Admin',
          role: 'ADMIN',
        ),
        api: api,
      ),
    ));
    expect(find.text('管理后台'), findsOneWidget);

    await tester.tap(find.text('管理后台'));
    await tester.pumpAndSettle();
    expect(find.text('申诉'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
  });
}

Future<void> _startSportSession(WidgetTester tester, _FakeApi api) async {
  await tester.tap(find.byKey(const Key('sport-session-toggle')));
  await tester.pumpAndSettle();
  await _selectGpsCheckinMode(tester);

  expect(api.startedSports, 1);
  _expectEnabledSportButton(tester);
}

Future<void> _finishSportSession(WidgetTester tester, _FakeApi api) async {
  _expectEnabledSportButton(tester);
  await tester.tap(find.byKey(const Key('sport-session-toggle')));

  for (var i = 0; i < 10 && api.finishedSports == 0; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void _expectEnabledSportButton(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.byKey(const Key('sport-session-toggle')),
  );
  expect(button.onPressed, isNotNull);
}

class _FakeLocationService implements LocationService {
  _FakeLocationService({
    this.initialPermission = LocationPermission.always,
    this.requestedPermission = LocationPermission.always,
    List<Position>? streamPositions,
    Position? currentPosition,
    this.throwOnCurrentPosition = false,
    this.streamError,
  })  : streamPositions = streamPositions ?? [_position()],
        currentPosition = currentPosition ?? _position();

  final LocationPermission initialPermission;
  final LocationPermission requestedPermission;
  final List<Position> streamPositions;
  final Position currentPosition;
  final bool throwOnCurrentPosition;
  final Object? streamError;

  @override
  Future<LocationPermission> checkPermission() async {
    return initialPermission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    if (throwOnCurrentPosition) {
      throw Exception('location unavailable');
    }
    return currentPosition;
  }

  @override
  Stream<Position> getPositionStream({required LocationSettings settings}) {
    final error = streamError;
    if (error != null) {
      return Stream<Position>.error(error);
    }
    return Stream.fromIterable(streamPositions);
  }

  @override
  Future<LocationPermission> requestPermission() async {
    return requestedPermission;
  }
}

class _FakeReminderScheduler implements ReminderScheduler {
  _FakeReminderScheduler({this.scheduleError});

  final Object? scheduleError;
  final List<String> calls = [];

  Future<void> _schedule(String cycle, String type) async {
    calls.add('$cycle:$type');
    final error = scheduleError;
    if (error != null) throw error;
  }

  @override
  Future<void> cancel(String type) async {
    calls.add('cancel:$type');
  }

  @override
  Future<void> scheduleDaily({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  }) =>
      _schedule('daily', type);

  @override
  Future<void> scheduleOnce({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
  }) =>
      _schedule('once', type);

  @override
  Future<void> scheduleWeekly({
    required String type,
    required String title,
    required String body,
    required TimeOfDay time,
    required int timesPerWeek,
  }) =>
      _schedule('weekly:$timesPerWeek', type);
}

Position _position({double accuracy = 10}) {
  return Position(
    longitude: 121.4737,
    latitude: 31.2304,
    timestamp: DateTime(2026, 5, 26),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _WidgetTestSecureStore implements SecureKeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}

class _FakeApi implements FitLoopApi {
  _FakeApi({
    List<SportTarget> targets = const <SportTarget>[],
    List<ReminderConfig> reminders = const <ReminderConfig>[],
    List<SportRecord> sportRecords = const <SportRecord>[],
    List<AppealResponse> appeals = const <AppealResponse>[],
    this.finishError,
    this.reminderUpsertError,
  })  : _targets = List.of(targets),
        _reminders = List.of(reminders),
        _sportRecords = List.of(sportRecords),
        _appeals = List.of(appeals);

  factory _FakeApi.withTarget() {
    return _FakeApi(
      targets: const [
        SportTarget(
          targetId: 1,
          periodType: 'week',
          metric: 'count',
          targetValue: 3,
          completedValue: 1,
          progress: 33.3,
          startDate: '2026-05-25',
          endDate: '2026-05-31',
          status: 'active',
        ),
      ],
    );
  }

  final List<SportTarget> _targets;
  final List<ReminderConfig> _reminders;
  final List<SportRecord> _sportRecords;
  final List<AppealResponse> _appeals;
  final Object? finishError;
  final Object? reminderUpsertError;
  int uploadedTrackPoints = 0;
  int startedSports = 0;
  int finishedSports = 0;
  int createdTargets = 0;
  int createdHealthData = 0;
  int reminderUpsertCalls = 0;
  int createdAppeals = 0;
  int rankingCalls = 0;
  String? lastRankingScope;
  double? _lastWeight;
  String? lastLoginPassword;
  String? lastLoginCode;
  String? lastLoginType;
  String? lastRegisterCode;
  String? lastVerificationChannel;
  String? lastVerificationTarget;
  String? lastVerificationPurpose;
  String? lastResetAccount;
  String? lastResetCode;
  String? lastResetPassword;

  List<ReminderConfig> get reminders => List.unmodifiable(_reminders);

  @override
  Future<HealthData> addHealthData({
    required String token,
    double? weightKg,
    double? sleepHours,
    String? dietNote,
    required String dataDate,
  }) async {
    createdHealthData += 1;
    _lastWeight = weightKg;
    return HealthData(
      healthId: createdHealthData,
      weightKg: weightKg,
      sleepHours: sleepHours,
      dietNote: dietNote,
      dataDate: dataDate,
    );
  }

  @override
  Future<SportTarget> createTarget({
    required String token,
    required String periodType,
    required String metric,
    required double targetValue,
  }) async {
    createdTargets += 1;
    final target = SportTarget(
      targetId: createdTargets,
      periodType: periodType,
      metric: metric,
      targetValue: targetValue,
      completedValue: 0,
      progress: 0,
      startDate: '2026-05-25',
      endDate: '2026-05-31',
      status: 'active',
    );
    _targets
      ..clear()
      ..add(target);
    return target;
  }

  @override
  Future<void> deleteTarget({
    required String token,
    required int targetId,
  }) async {
    _targets.removeWhere((t) => t.targetId == targetId);
  }

  @override
  Future<List<SportTarget>> currentTargets({required String token}) async {
    return List.of(_targets);
  }

  @override
  Future<MedalSummary> medalSummary({required String token}) async {
    return const MedalSummary(
      points: 120,
      level: 2,
      medals: ['初次启程', '校园活力达人'],
    );
  }

  @override
  Future<RankingResult> ranking({
    required String token,
    String scope = 'friends',
    String period = 'week',
    int page = 1,
    int size = 20,
  }) async {
    rankingCalls += 1;
    lastRankingScope = scope;
    return RankingResult(
      scope: scope,
      period: 'week',
      rows: const [
        RankingRow(
          rank: 1,
          userId: 1,
          nickname: '测试用户',
          distanceKm: 5.2,
          calorie: 320,
        ),
      ],
    );
  }

  @override
  Future<UserSession> login(
      {required String account,
      String? password,
      String? code,
      String loginType = 'password'}) async {
    lastLoginPassword = password;
    lastLoginCode = code;
    lastLoginType = loginType;
    return const UserSession(token: 'token', userId: 1, nickname: '测试用户');
  }

  @override
  Future<void> register(
      {required String account,
      required String password,
      required String nickname,
      String? code}) async {
    lastRegisterCode = code;
  }

  @override
  Future<SportRecord> finishSport({
    required String token,
    required String sessionId,
    required int durationSeconds,
    required double weightKg,
    double? distanceKm,
    double? calorie,
    String? note,
    String? photoUrl,
  }) async {
    final error = finishError;
    if (error != null) {
      throw error;
    }
    finishedSports += 1;
    return const SportRecord(
      recordId: 1,
      status: 1,
      durationSeconds: 1800,
      distanceKm: 0,
      calorie: 240,
    );
  }

  @override
  Future<SportStart> startSport({
    required String token,
    required String sportType,
    required String checkinMode,
  }) async {
    startedSports += 1;
    return const SportStart(
        sessionId: 'session-1', startTime: '2026-05-25T00:00:00Z');
  }

  @override
  Future<SportStats> sportStats({required String token}) async {
    return const SportStats(
        checkinCount: 1, durationSeconds: 1800, distanceKm: 0, calorie: 240);
  }

  @override
  Future<List<SportRecord>> listSportRecords({required String token}) async {
    return List.of(_sportRecords);
  }

  @override
  Future<void> uploadTrackPoint({
    required String token,
    required TrackPoint point,
  }) async {
    uploadedTrackPoints += 1;
  }

  @override
  Future<TargetReminderListResponse> targetReminders(
      {required String token}) async {
    return const TargetReminderListResponse(targets: []);
  }

  @override
  Future<void> acknowledgeTargetReminder(
      {required String token, required int targetId}) async {}

  @override
  Future<ReminderListResponse> listReminders({required String token}) async {
    return ReminderListResponse(reminders: List.of(_reminders));
  }

  @override
  Future<ReminderConfig> upsertReminder(
      {required String token,
      required int remindId,
      required String type,
      String? time,
      String? cycle,
      bool? enabled}) async {
    reminderUpsertCalls += 1;
    final error = reminderUpsertError;
    if (error != null) throw error;
    final saved = ReminderConfig(
      id: remindId == 0 ? 1 : remindId,
      type: type,
      time: time,
      cycle: cycle ?? 'daily',
      enabled: enabled ?? true,
    );
    _reminders.removeWhere((reminder) => reminder.type == type);
    _reminders.add(saved);
    return saved;
  }

  @override
  Future<FriendListResponse> listFriends({required String token}) async {
    return const FriendListResponse(friends: []);
  }

  @override
  Future<UserSearchResponse> searchUsers(
      {required String token, required String query}) async {
    return const UserSearchResponse(users: []);
  }

  @override
  Future<void> addFriend(
      {required String token, required int friendUserId}) async {}

  @override
  Future<AppealListResponse> listAppeals({required String token}) async {
    return AppealListResponse(appeals: List.of(_appeals));
  }

  @override
  Future<void> createAppeal(
      {required String token,
      required int recordId,
      required String reason}) async {
    createdAppeals += 1;
    _appeals.add(AppealResponse(
      appealId: createdAppeals,
      recordId: recordId,
      reason: reason,
      status: 'pending',
      createdAt: '2026-07-21T00:00:00Z',
    ));
    final index =
        _sportRecords.indexWhere((record) => record.recordId == recordId);
    if (index >= 0) {
      final record = _sportRecords[index];
      _sportRecords[index] = SportRecord(
        recordId: record.recordId,
        status: 3,
        durationSeconds: record.durationSeconds,
        distanceKm: record.distanceKm,
        calorie: record.calorie,
        sportType: record.sportType,
        abnormalReason: record.abnormalReason,
        startedAt: record.startedAt,
      );
    }
  }

  @override
  Future<SportHistoryResponse> sportHistory({
    required String token,
    String period = 'week',
    String metric = 'all',
  }) async {
    return const SportHistoryResponse(
      period: 'week',
      metric: 'all',
      points: [
        SportHistoryPoint(
            date: '2026-05-25',
            count: 1,
            durationSeconds: 0,
            distanceKm: 0,
            calorie: 0),
        SportHistoryPoint(
            date: '2026-05-26',
            count: 0,
            durationSeconds: 0,
            distanceKm: 0,
            calorie: 0),
        SportHistoryPoint(
            date: '2026-05-27',
            count: 0,
            durationSeconds: 0,
            distanceKm: 0,
            calorie: 0),
        SportHistoryPoint(
            date: '2026-05-28',
            count: 0,
            durationSeconds: 0,
            distanceKm: 0,
            calorie: 0),
        SportHistoryPoint(
            date: '2026-05-29',
            count: 0,
            durationSeconds: 0,
            distanceKm: 0,
            calorie: 0),
        SportHistoryPoint(
            date: '2026-05-30',
            count: 0,
            durationSeconds: 0,
            distanceKm: 0,
            calorie: 0),
        SportHistoryPoint(
            date: '2026-05-31',
            count: 0,
            durationSeconds: 0,
            distanceKm: 0,
            calorie: 0),
      ],
    );
  }

  @override
  Future<String> uploadAvatar({
    required String token,
    required String imagePath,
  }) async {
    return 'https://example.com/avatar.png';
  }

  @override
  Future<UserProfileResponse> getUserProfile({required String token}) async {
    return const UserProfileResponse(
      userId: 1,
      nickname: '测试用户',
      avatarUrl: 'https://example.com/avatar.png',
    );
  }

  @override
  Future<WeightHistoryResponse> weightHistory({
    required String token,
    int days = 30,
  }) async {
    if (_lastWeight != null) {
      return WeightHistoryResponse(points: [
        WeightHistoryPoint(date: '2026-05-27', weightKg: _lastWeight),
      ]);
    }
    return const WeightHistoryResponse(points: []);
  }

  @override
  Future<Map<String, String>> sendSmsCode({required String phone}) async {
    return {'message': '验证码已发送', 'debugCode': '123456'};
  }

  @override
  Future<Map<String, String>> sendVerificationCode({
    required String channel,
    required String target,
    required String purpose,
  }) async {
    lastVerificationChannel = channel;
    lastVerificationTarget = target;
    lastVerificationPurpose = purpose;
    return {'message': '验证码已发送', 'debugCode': '123456'};
  }

  @override
  Future<void> resetPassword({
    required String account,
    required String code,
    required String newPassword,
  }) async {
    lastResetAccount = account;
    lastResetCode = code;
    lastResetPassword = newPassword;
  }

  @override
  Future<String> uploadSportPhoto({
    required String token,
    required String imagePath,
  }) async {
    return '/uploads/photos/test.jpg';
  }

  @override
  Future<FeatureFlags> fetchFeatureFlags() async {
    return const FeatureFlags(smsEnabled: false);
  }

  @override
  Future<FeedbackItem> submitFeedback({
    required String token,
    required String type,
    required String content,
    String? contact,
  }) async {
    return FeedbackItem(
      feedbackId: 1,
      type: type,
      content: content,
      contact: contact,
      status: 'pending',
      adminNote: null,
      createdAt: '2026-06-04',
    );
  }

  @override
  Future<FeedbackListResponse> listFeedback({required String token}) async {
    return const FeedbackListResponse(feedbacks: []);
  }

  @override
  Future<AdminStats> adminGetStats({required String token}) async {
    return const AdminStats(
      totalUsers: 0,
      todayNewUsers: 0,
      totalSportRecords: 0,
      todayCheckins: 0,
      pendingFeedbackCount: 0,
    );
  }

  @override
  Future<AdminUserListResponse> adminListUsers({
    required String token,
    int page = 0,
    int size = 20,
  }) async {
    return const AdminUserListResponse(users: [], total: 0);
  }

  @override
  Future<AdminUserDetail> adminGetUserDetail({
    required String token,
    required int userId,
  }) async {
    return AdminUserDetail(
      userId: userId,
      nickname: 'test',
      sportRecordCount: 0,
      targetCount: 0,
      totalDurationSeconds: 0,
      totalDistanceKm: 0,
    );
  }

  @override
  Future<FeedbackListResponse> adminListFeedback(
      {required String token}) async {
    return const FeedbackListResponse(feedbacks: []);
  }

  @override
  Future<void> adminUpdateFeedback({
    required String token,
    required int feedbackId,
    required String status,
    String? adminNote,
  }) async {}

  @override
  Future<AdminAppealPage> adminListAppeals({
    required String token,
    String? status,
    int page = 0,
    int size = 20,
  }) async {
    return const AdminAppealPage(items: [], totalElements: 0);
  }

  @override
  Future<void> adminReviewAppeal({
    required String token,
    required int appealId,
    required String status,
    String? reviewNote,
  }) async {}

  @override
  Future<String> adminStartAppealAgentReview({
    required String token,
    required int appealId,
  }) async {
    return 'run-1';
  }

  @override
  Future<AdminAgentRunPage> adminListAgentRuns({
    required String token,
    String? type,
    String? status,
    int page = 0,
    int size = 20,
  }) async {
    return const AdminAgentRunPage(items: [], totalElements: 0);
  }

  @override
  Future<AgentRunAudit> adminGetAgentRunAudit({
    required String token,
    required String runId,
  }) async {
    return AgentRunAudit(
      runId: runId,
      status: 'SUCCEEDED',
      proposals: const [],
      toolCalls: const [],
    );
  }

  @override
  Future<void> adminConfirmAgentProposal({
    required String token,
    required int proposalId,
  }) async {}

  @override
  Future<void> adminRejectAgentProposal({
    required String token,
    required int proposalId,
    String? reason,
  }) async {}

  @override
  Future<AdminAuditPage> adminListAuditLogs({
    required String token,
    String? resourceType,
    String? resourceId,
    int page = 0,
    int size = 20,
  }) async {
    return const AdminAuditPage(items: [], totalElements: 0);
  }

  @override
  Future<SportTarget> editTarget({
    required String token,
    required int targetId,
    required String periodType,
    required String metric,
    required double targetValue,
  }) async {
    return SportTarget(
      targetId: targetId,
      periodType: periodType,
      metric: metric,
      targetValue: targetValue,
      completedValue: 0,
      progress: 0,
      startDate: '2026-06-01',
      endDate: '2026-06-07',
      status: 'active',
    );
  }
}
