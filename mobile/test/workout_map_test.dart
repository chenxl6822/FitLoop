import 'package:fitloop/api_models.dart';
import 'package:fitloop/map_config.dart';
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

  test('keeps WGS84 coordinates aligned with WGS84 map tiles', () {
    final display = MapConfig.displayCoordinateForSystem(
      27.882,
      112.909,
      'WGS84',
    );

    expect(display.lat, 27.882);
    expect(display.lng, 112.909);
  });

  test('only shifts coordinates when a GCJ02 tile source is explicit', () {
    final display = MapConfig.displayCoordinateForSystem(
      27.882,
      112.909,
      'GCJ02',
    );

    expect(display.lat, isNot(27.882));
    expect(display.lng, isNot(112.909));
  });
}
