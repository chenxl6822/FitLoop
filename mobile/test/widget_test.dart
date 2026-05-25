import 'package:fitloop/api_client.dart';
import 'package:fitloop/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders login then dashboard shell', (tester) async {
    await tester.pumpWidget(
      FitLoopApp(
        api: _FakeApi.withTarget(),
        locationService: _FakeLocationService(),
      ),
    );

    expect(find.text('FitLoop'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('运动'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('社交'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('测试用户'), findsOneWidget);
    expect(find.textContaining('本周 运动次数：1 / 3'), findsOneWidget);

    await tester.tap(find.text('社交'));
    await tester.pumpAndSettle();

    expect(find.textContaining('120 积分 / Lv.2'), findsOneWidget);
    expect(find.textContaining('校园活力达人'), findsOneWidget);
    expect(find.textContaining('测试用户 / 5.2 km / 320.0 kcal'), findsOneWidget);

    await tester.tap(find.text('运动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始跑步'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已上传 1 个轨迹点'), findsOneWidget);
  });

  testWidgets('creates target from empty dashboard state', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('暂无进行中目标'), findsOneWidget);

    await tester.tap(find.text('创建目标'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存目标'));
    await tester.pumpAndSettle();

    expect(api.createdTargets, 1);
    expect(find.textContaining('本周 运动次数：0 / 3'), findsOneWidget);
  });

  testWidgets('submits health data from stats page', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      FitLoopApp(api: api, locationService: _FakeLocationService()),
    );

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('统计'));
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
          streamPositions: const [],
          currentPosition: _position(accuracy: 8),
        ),
      ),
    );

    await _openSportPage(tester);
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.stop));
    await tester.pumpAndSettle();

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
          streamPositions: const [],
          throwOnCurrentPosition: true,
        ),
      ),
    );

    await _openSportPage(tester);
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.stop));
    await tester.pumpAndSettle();

    expect(api.finishedSports, 1);
    expect(api.uploadedTrackPoints, 0);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}

Future<void> _openSportPage(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.login));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.directions_run_outlined));
  await tester.pumpAndSettle();
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

class _FakeApi implements FitLoopApi {
  _FakeApi({List<SportTarget> targets = const <SportTarget>[]})
      : _targets = List.of(targets);

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
  int uploadedTrackPoints = 0;
  int startedSports = 0;
  int finishedSports = 0;
  int createdTargets = 0;
  int createdHealthData = 0;

  @override
  Future<HealthData> addHealthData({
    required String token,
    double? weightKg,
    double? sleepHours,
    String? dietNote,
    required String dataDate,
  }) async {
    createdHealthData += 1;
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
    String scope = 'personal',
    String period = 'week',
    int page = 1,
    int size = 20,
  }) async {
    return const RankingResult(
      scope: 'personal',
      period: 'week',
      rows: [
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
      {required String account, required String password}) async {
    return const UserSession(token: 'token', userId: 1, nickname: '测试用户');
  }

  @override
  Future<void> register(
      {required String account,
      required String password,
      required String nickname}) async {}

  @override
  Future<SportRecord> finishSport({
    required String token,
    required String sessionId,
    required int durationSeconds,
    required double weightKg,
  }) async {
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
  Future<void> uploadTrackPoint({
    required String token,
    required TrackPoint point,
  }) async {
    uploadedTrackPoints += 1;
  }
}
