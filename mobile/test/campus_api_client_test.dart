import 'dart:convert';
import 'dart:io';

import 'package:fitloop/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 8);

  test('unlinkCampus accepts HTTP 204 No Content', () async {
    final store = _MemorySessionStore(_session());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      expect(request.method, 'DELETE');
      expect(request.uri.path, '/api/v1/campus/link');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer access-token-1');
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();

    await api.unlinkCampus(token: 'access-token-1');

    await handled;
    await server.close(force: true);
  });

  test('retries campus sync after Spring Security 403 without detail', () async {
    final store = _MemorySessionStore(_session());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var syncCalls = 0;
    server.listen((request) async {
      if (request.uri.path == '/api/v1/auth/refresh') {
        await _writeJson(request.response, _authPayload(2));
        return;
      }
      expect(request.uri.path, '/api/v1/campus/sync-schedule');
      final authorization =
          request.headers.value(HttpHeaders.authorizationHeader);
      if (authorization == 'Bearer access-token-1') {
        request.response.statusCode = HttpStatus.forbidden;
        await _writeJson(request.response, {'error': 'Forbidden'});
        return;
      }
      expect(authorization, 'Bearer access-token-2');
      syncCalls += 1;
      await _writeJson(request.response, _scheduleEnvelope());
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();

    final schedule = await api.syncCampusSchedule(
      token: 'access-token-1',
      studentId: '20230001',
      password: 'secret',
    );

    expect(syncCalls, 1);
    expect(schedule.courses, isEmpty);
    expect(store.session?.token, 'access-token-2');
    await server.close(force: true);
  });

  test('does not retry campus sync for business 403 detail', () async {
    final store = _MemorySessionStore(_session());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var refreshCalls = 0;
    server.listen((request) async {
      if (request.uri.path == '/api/v1/auth/refresh') {
        refreshCalls += 1;
        await _writeJson(request.response, _authPayload(2));
        return;
      }
      request.response.statusCode = HttpStatus.forbidden;
      await _writeJson(request.response, {
        'type': 'about:blank',
        'title': 'Forbidden',
        'status': 403,
        'detail': 'Campus identity required',
      });
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();

    await expectLater(
      api.syncCampusSchedule(
        token: 'access-token-1',
        studentId: '20230001',
        password: 'secret',
      ),
      throwsA(
        predicate<ApiException>(
          (error) =>
              error.message == '请先完成湘大校园认证后再同步课表',
        ),
      ),
    );

    expect(refreshCalls, 0);
    await server.close(force: true);
  });
}

UserSession _session() => UserSession(
      token: 'access-token-1',
      refreshToken: 'refresh-token-1',
      expiresAt: DateTime.utc(2026, 9, 1, 9),
      userId: 7,
      nickname: 'Tester',
      role: 'USER',
    );

Map<String, dynamic> _authPayload(int generation) => {
      'token': 'access-token-$generation',
      'refreshToken': 'refresh-token-$generation',
      'tokenType': 'Bearer',
      'expiresIn': 900,
      'role': 'USER',
      'userProfile': {
        'userId': 7,
        'nickname': 'Tester',
        'avatarUrl': null,
      },
    };

Map<String, dynamic> _scheduleEnvelope() => {
      'code': 0,
      'message': 'ok',
      'data': {
        'termYear': '2025',
        'termCode': '1',
        'syncedAt': '2026-09-01T08:00:00Z',
        'courses': <Map<String, dynamic>>[],
        'exams': <Map<String, dynamic>>[],
        'workoutWindows': <Map<String, dynamic>>[],
      },
    };

Future<void> _writeJson(
    HttpResponse response, Map<String, dynamic> body) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

class _MemorySessionStore implements SessionStore {
  _MemorySessionStore(this.session);

  UserSession? session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<UserSession?> load() async => session;

  @override
  Future<void> save(UserSession value) async => session = value;
}
