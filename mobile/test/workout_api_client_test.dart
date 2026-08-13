import 'dart:convert';
import 'dart:io';

import 'package:fitloop/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads the signed-in users private workout track', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      expect(request.uri.path, '/api/v1/workouts/42/track-points');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer signed-user-jwt',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'recordId': 42,
        'coordinateSystem': 'WGS84',
        'points': [
          {
            'sequenceNo': 1,
            'lat': 39.908823,
            'lng': 116.397470,
            'accuracy': 7.5,
            'timestamp': '2026-08-13T06:00:00Z',
          },
        ],
      }));
      await request.response.close();
    });
    final api = HttpFitLoopApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );

    final track = await api.workoutTrack(
      token: 'signed-user-jwt',
      recordId: 42,
    );

    expect(track.recordId, 42);
    expect(track.coordinateSystem, 'WGS84');
    expect(track.points.single.lat, 39.908823);
    await handled;
    await server.close(force: true);
  });
}
