import 'dart:convert';
import 'dart:io';

import 'package:fitloop/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login response preserves administrator role', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      expect(request.uri.path, '/api/auth/login');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'code': 0,
        'message': 'ok',
        'data': {
          'token': 'admin-jwt',
          'role': 'ADMIN',
          'userProfile': {
            'userId': 9,
            'nickname': 'Administrator',
            'avatarUrl': null,
          },
        },
      }));
      await request.response.close();
    });
    final api = HttpFitLoopApi(baseUrl: 'http://127.0.0.1:${server.port}');

    final session =
        await api.login(account: 'admin@example.com', password: 'secret');

    expect(session.role, 'ADMIN');
    expect(session.isAdmin, isTrue);
    await handled;
    await server.close(force: true);
  });

  test('admin calls use bearer JWT and never send legacy admin key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      expect(request.uri.path, '/api/admin/stats');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer signed-admin-jwt');
      expect(request.headers.value('X-Admin-Key'), isNull);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'code': 0,
        'message': 'ok',
        'data': {
          'totalUsers': 10,
          'todayNewUsers': 1,
          'totalSportRecords': 20,
          'todayCheckins': 2,
          'pendingFeedbackCount': 3,
        },
      }));
      await request.response.close();
    });
    final api = HttpFitLoopApi(baseUrl: 'http://127.0.0.1:${server.port}');

    final stats = await api.adminGetStats(token: 'signed-admin-jwt');

    expect(stats.totalUsers, 10);
    await handled;
    await server.close(force: true);
  });
}
