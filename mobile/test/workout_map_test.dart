import 'package:fitloop/api_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses private workout track points without changing WGS84 data', () {
    final track = WorkoutTrack.fromJson({
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
        {
          'sequenceNo': 2,
          'lat': 39.909100,
          'lng': 116.398000,
          'accuracy': 6.0,
          'timestamp': '2026-08-13T06:00:05Z',
        },
      ],
    });

    expect(track.recordId, 42);
    expect(track.coordinateSystem, 'WGS84');
    expect(track.points.map((point) => point.sequenceNo), [1, 2]);
    expect(track.points.first.lat, 39.908823);
    expect(track.points.first.lng, 116.397470);
  });
}
