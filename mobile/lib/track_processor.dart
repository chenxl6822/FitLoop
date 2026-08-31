import 'dart:math';

/// Filters noisy GPS samples before distance accumulation.
class TrackProcessor {
  TrackProcessor({
    this.maxAccuracyMeters = 50,
    this.minSegmentMeters = 4,
    this.maxSegmentSpeedMs = 6,
    this.stationarySpeedMs = 0.6,
  });

  final double maxAccuracyMeters;
  final double minSegmentMeters;
  final double maxSegmentSpeedMs;
  final double stationarySpeedMs;

  double _totalDistanceKm = 0;
  double? _lastLat;
  double? _lastLng;
  DateTime? _lastTimestamp;
  int _acceptedPoints = 0;
  int _rejectedPoints = 0;

  double get totalDistanceKm => _totalDistanceKm;

  int get acceptedPoints => _acceptedPoints;

  int get rejectedPoints => _rejectedPoints;

  void reset() {
    _totalDistanceKm = 0;
    _lastLat = null;
    _lastLng = null;
    _lastTimestamp = null;
    _acceptedPoints = 0;
    _rejectedPoints = 0;
  }

  /// Returns segment distance added in kilometers (0 when rejected).
  double ingest({
    required double lat,
    required double lng,
    required double accuracyMeters,
    required DateTime timestamp,
    double? speedMs,
  }) {
    if (!_hasUsableAccuracy(accuracyMeters)) {
      _rejectedPoints++;
      return 0;
    }

    if (_lastLat == null || _lastLng == null || _lastTimestamp == null) {
      _acceptAnchor(lat, lng, timestamp);
      return 0;
    }

    final segmentMeters = haversineMeters(_lastLat!, _lastLng!, lat, lng);
    if (segmentMeters < minSegmentMeters) {
      _rejectedPoints++;
      return 0;
    }

    final elapsedSeconds =
        max(timestamp.difference(_lastTimestamp!).inMilliseconds / 1000, 0.001);
    final impliedSpeedMs = segmentMeters / elapsedSeconds;
    if (impliedSpeedMs > maxSegmentSpeedMs) {
      _rejectedPoints++;
      return 0;
    }

    final reportedSpeed = speedMs;
    if (reportedSpeed != null &&
        reportedSpeed.isFinite &&
        reportedSpeed >= 0 &&
        reportedSpeed < stationarySpeedMs) {
      _rejectedPoints++;
      return 0;
    }

    final segmentKm = segmentMeters / 1000;
    _totalDistanceKm += segmentKm;
    _acceptAnchor(lat, lng, timestamp);
    return segmentKm;
  }

  double averageSpeedKmh(int activeSeconds) {
    if (activeSeconds <= 0 || _totalDistanceKm <= 0) return 0;
    return _totalDistanceKm / (activeSeconds / 3600);
  }

  void _acceptAnchor(double lat, double lng, DateTime timestamp) {
    _lastLat = lat;
    _lastLng = lng;
    _lastTimestamp = timestamp;
    _acceptedPoints++;
  }

  bool _hasUsableAccuracy(double accuracyMeters) {
    return accuracyMeters.isFinite &&
        accuracyMeters >= 0 &&
        accuracyMeters <= maxAccuracyMeters;
  }
}

double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_degToRad(lat1)) *
          cos(_degToRad(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _degToRad(double deg) => deg * pi / 180.0;
