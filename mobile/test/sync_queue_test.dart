import 'dart:convert';

import 'package:fitloop/api_client.dart';
import 'package:fitloop/secure_session_storage.dart';
import 'package:fitloop/sync_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _MemorySecureStore secureStore;

  setUp(() async {
    SyncQueue.resetSerializersForTesting();
    SharedPreferences.setMockInitialValues({});
    secureStore = _MemorySecureStore();
    TokenStorage.useSecureStoreForTesting(secureStore);
    await SyncQueue.clear();
  });

  test('concurrent enqueues do not overwrite another workout', () async {
    await Future.wait(List.generate(
      40,
      (index) => SyncQueue.enqueueFinish(_record('session-$index', index + 1)),
    ));

    final pending = await SyncQueue.pending();

    expect(pending, hasLength(40));
    expect(
      pending.map((record) => record.sessionId).toSet(),
      hasLength(40),
    );
  });

  test('re-enqueueing a session updates instead of duplicating it', () async {
    await SyncQueue.enqueueFinish(_record('same-session', 10));
    await SyncQueue.enqueueFinish(_record('same-session', 20));

    final pending = await SyncQueue.pending();

    expect(pending, hasLength(1));
    expect(pending.single.durationSeconds, 20);
  });

  test('migrates legacy queue without retaining plaintext access token',
      () async {
    SharedPreferences.setMockInitialValues({
      'sync_queue': jsonEncode([
        {
          'token': 'legacy-sensitive-token',
          'sessionId': 'legacy-session',
          'durationSeconds': 60,
          'weightKg': 60.0,
        },
      ]),
    });

    final pending = await SyncQueue.pending();

    expect(pending.single.sessionId, 'legacy-session');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('sync_queue'), isNull);
    expect(secureStore.values.values.join(),
        isNot(contains('legacy-sensitive-token')));
  });

  test('removes by stable session id while another workout is enqueued',
      () async {
    await SyncQueue.enqueueFinish(_record('completed-session', 10));

    await Future.wait([
      SyncQueue.enqueueFinish(_record('new-session', 20)),
      SyncQueue.removeSession('completed-session'),
    ]);

    final pending = await SyncQueue.pending();
    expect(pending.map((record) => record.sessionId), ['new-session']);
  });

  test('replays a queued workout with the current signed-in token', () async {
    await SyncQueue.enqueueFinish(_record('queued-session', 300));
    final api = _SyncFakeApi();

    final result = await SyncProcessor(
      api,
      token: 'current-signed-in-token',
    ).processAll();

    expect(result, (synced: 1, failed: 0));
    expect(api.receivedToken, 'current-signed-in-token');
    expect(api.receivedSessionId, 'queued-session');
    expect(await SyncQueue.pending(), isEmpty);
  });

  test('queues the workout when the finish API fails', () async {
    final api = _SyncFakeApi(finishError: StateError('offline'));

    final result = await ReliableWorkoutFinisher(api).finish(
      token: 'current-signed-in-token',
      sessionId: 'failed-session',
      durationSeconds: 420,
      weightKg: 60,
      distanceKm: 1.2,
    );

    expect(result.queued, isTrue);
    expect(result.error, isA<StateError>());
    final pending = await SyncQueue.pending();
    expect(pending.single.sessionId, 'failed-session');
    expect(pending.single.durationSeconds, 420);
    expect(pending.single.toJson().containsKey('token'), isFalse);
  });
}

PendingFinishRecord _record(String sessionId, int durationSeconds) {
  return PendingFinishRecord(
    sessionId: sessionId,
    durationSeconds: durationSeconds,
    weightKg: 60,
  );
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

class _SyncFakeApi implements FitLoopApi {
  _SyncFakeApi({this.finishError});

  final Object? finishError;
  String? receivedToken;
  String? receivedSessionId;

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
    if (error != null) throw error;
    receivedToken = token;
    receivedSessionId = sessionId;
    return SportRecord(
      recordId: 1,
      status: 1,
      durationSeconds: durationSeconds,
      distanceKm: 0,
      calorie: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
