import 'package:fitloop/api_client.dart';
import 'package:fitloop/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders login then dashboard shell', (tester) async {
    await tester.pumpWidget(FitLoopApp(api: _FakeApi.withTarget()));

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

    await tester.tap(find.text('运动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始跑步'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已上传 1 个轨迹点'), findsOneWidget);
  });

  testWidgets('creates target from empty dashboard state', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(FitLoopApp(api: api));

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
  int createdTargets = 0;

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
