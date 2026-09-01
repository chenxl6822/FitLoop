import 'package:fitloop/coord_transform.dart';
import 'package:fitloop/map_config.dart';
import 'package:fitloop/track_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackProcessor', () {
    test('rejects GPS drift jumps and stationary noise', () {
      final processor = TrackProcessor(
        minSegmentMeters: 4,
        maxSegmentSpeedMs: 6,
      );
      final base = DateTime.utc(2026, 8, 31, 10);

      processor.ingest(
        lat: 27.8820,
        lng: 112.9090,
        accuracyMeters: 8,
        timestamp: base,
      );
      processor.ingest(
        lat: 27.88201,
        lng: 112.90901,
        accuracyMeters: 8,
        timestamp: base.add(const Duration(seconds: 1)),
      );
      expect(processor.totalDistanceKm, 0);

      processor.ingest(
        lat: 27.88208,
        lng: 112.90908,
        accuracyMeters: 8,
        timestamp: base.add(const Duration(seconds: 8)),
        speedMs: 1.2,
      );
      expect(processor.totalDistanceKm, greaterThan(0));
      expect(processor.totalDistanceKm, lessThan(0.02));

      processor.ingest(
        lat: 27.8900,
        lng: 112.9200,
        accuracyMeters: 8,
        timestamp: base.add(const Duration(seconds: 10)),
      );
      expect(processor.totalDistanceKm, lessThan(0.02));
    });

    test('average speed matches distance and active time', () {
      final processor = TrackProcessor();
      final base = DateTime.utc(2026, 8, 31, 11);

      processor.ingest(
        lat: 27.8820,
        lng: 112.9090,
        accuracyMeters: 5,
        timestamp: base,
      );
      processor.ingest(
        lat: 27.8830,
        lng: 112.9100,
        accuracyMeters: 5,
        timestamp: base.add(const Duration(minutes: 5)),
        speedMs: 1.4,
      );

      final avg = processor.averageSpeedKmh(300);
      expect(avg, closeTo(processor.totalDistanceKm / (300 / 3600), 0.5));
    });
  });

  group('CoordTransform', () {
    test('converts XTU campus WGS84 to GCJ-02 offset', () {
      final gcj = CoordTransform.wgs84ToGcj02(xtuCampusCenterLat, xtuCampusCenterLng);
      expect(gcj.lat, isNot(xtuCampusCenterLat));
      expect(gcj.lng, isNot(xtuCampusCenterLng));
      expect((gcj.lat - xtuCampusCenterLat).abs(), lessThan(0.01));
    });
  });
}
