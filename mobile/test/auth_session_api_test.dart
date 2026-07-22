import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitloop/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 22, 8);

  test('proactively refreshes an expiring session and persists rotation',
      () async {
    final store = _MemorySessionStore(_session(
      expiresAt: now.subtract(const Duration(seconds: 1)),
    ));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var refreshCalls = 0;
    final done = Completer<void>();
    server.listen((request) async {
      if (request.uri.path == '/api/v1/auth/refresh') {
        refreshCalls += 1;
        expect(await _requestJson(request), {
          'refreshToken': 'refresh-token-1',
        });
        await _writeJson(request.response, _authPayload(2));
        return;
      }
      expect(request.uri.path, '/api/admin/stats');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer access-token-2');
      await _writeJson(request.response, _statsEnvelope());
      done.complete();
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();

    final stats = await api.adminGetStats(token: 'access-token-1');

    expect(stats.totalUsers, 10);
    expect(refreshCalls, 1);
    expect(store.session?.token, 'access-token-2');
    expect(store.session?.refreshToken, 'refresh-token-2');
    await done.future;
    await server.close(force: true);
  });

  test('deduplicates concurrent refresh after unauthorized responses',
      () async {
    final store = _MemorySessionStore(_session(
      expiresAt: now.add(const Duration(minutes: 10)),
    ));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var refreshCalls = 0;
    var successfulCalls = 0;
    server.listen((request) async {
      if (request.uri.path == '/api/v1/auth/refresh') {
        refreshCalls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await _writeJson(request.response, _authPayload(2));
        return;
      }
      final authorization =
          request.headers.value(HttpHeaders.authorizationHeader);
      if (authorization == 'Bearer access-token-1') {
        request.response.statusCode = HttpStatus.unauthorized;
        await _writeJson(request.response, {'message': 'expired'});
        return;
      }
      expect(authorization, 'Bearer access-token-2');
      successfulCalls += 1;
      await _writeJson(request.response, _statsEnvelope());
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();

    await Future.wait([
      api.adminGetStats(token: 'access-token-1'),
      api.adminGetStats(token: 'access-token-1'),
    ]);

    expect(refreshCalls, 1);
    expect(successfulCalls, 2);
    await server.close(force: true);
  });

  test('clears session when the refresh token is rejected', () async {
    final store = _MemorySessionStore(_session(
      expiresAt: now.subtract(const Duration(seconds: 1)),
    ));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/api/v1/auth/refresh');
      request.response.statusCode = HttpStatus.unauthorized;
      await _writeJson(request.response, {'message': 'refresh revoked'});
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();
    final invalidated = api.sessionChanges.first;

    await expectLater(
      api.adminGetStats(token: 'access-token-1'),
      throwsA(isA<ApiException>()),
    );

    expect(await invalidated, isNull);
    expect(store.session, isNull);
    await server.close(force: true);
  });

  test('logout revokes the refresh token and always clears local state',
      () async {
    final store = _MemorySessionStore(_session(
      expiresAt: now.add(const Duration(minutes: 10)),
    ));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      expect(request.uri.path, '/api/v1/auth/logout');
      expect(await _requestJson(request), {
        'refreshToken': 'refresh-token-1',
      });
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();

    await api.logoutSession();

    expect(store.session, isNull);
    await handled;
    await server.close(force: true);
  });

  test('offline refresh failure preserves the refreshable session', () async {
    final store = _MemorySessionStore(_session(
      expiresAt: now.subtract(const Duration(seconds: 1)),
    ));
    final unavailable = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = unavailable.port;
    await unavailable.close(force: true);
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:$port',
      sessionStore: store,
      now: () => now,
    );
    await api.restoreSession();

    await expectLater(
      api.adminGetStats(token: 'access-token-1'),
      throwsA(isA<ApiException>()),
    );

    expect(store.session?.refreshToken, 'refresh-token-1');
  });
}

UserSession _session({required DateTime expiresAt}) => UserSession(
      token: 'access-token-1',
      refreshToken: 'refresh-token-1',
      expiresAt: expiresAt,
      userId: 7,
      nickname: 'Admin',
      role: 'ADMIN',
    );

Map<String, dynamic> _authPayload(int generation) => {
      'token': 'access-token-$generation',
      'refreshToken': 'refresh-token-$generation',
      'tokenType': 'Bearer',
      'expiresIn': 900,
      'role': 'ADMIN',
      'userProfile': {
        'userId': 7,
        'nickname': 'Admin',
        'avatarUrl': null,
      },
    };

Map<String, dynamic> _statsEnvelope() => {
      'code': 0,
      'message': 'ok',
      'data': {
        'totalUsers': 10,
        'todayNewUsers': 1,
        'totalSportRecords': 20,
        'todayCheckins': 2,
        'pendingFeedbackCount': 3,
      },
    };

Future<Map<String, dynamic>> _requestJson(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return jsonDecode(body) as Map<String, dynamic>;
}

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
