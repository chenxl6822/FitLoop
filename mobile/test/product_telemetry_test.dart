import 'package:flutter_test/flutter_test.dart';

import 'package:fitloop/api_services.dart';
import 'package:fitloop/product_telemetry.dart';

class _RecordingApi implements FitLoopApi {
  final List<List<Map<String, Object?>>> batches = [];

  @override
  Future<void> ingestTelemetryEvents({
    required String token,
    required List<Map<String, Object?>> events,
  }) async {
    batches.add(events);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('ProductTelemetry posts allowlisted event without coordinates', () async {
    final api = _RecordingApi();
    final telemetry = ProductTelemetry(api, token: () => 'tok');

    await telemetry.track('workout_finish', props: {
      'result': 'saved',
      'checkin_mode': 'gps',
      'nested': {'bad': true},
    });

    expect(api.batches, hasLength(1));
    final event = api.batches.single.single;
    expect(event['eventName'], 'workout_finish');
    final props = event['props'] as Map<String, Object?>;
    expect(props['result'], 'saved');
    expect(props.containsKey('nested'), isFalse);
    expect(props.keys, isNot(contains('lat')));
    expect(props.keys, isNot(contains('lng')));
  });

  test('ProductTelemetry swallows API failures', () async {
    final telemetry = ProductTelemetry(
      _ThrowingApi(),
      token: () => 'tok',
    );
    await telemetry.track('map_consent', props: {'granted': true});
  });
}

class _ThrowingApi implements FitLoopApi {
  @override
  Future<void> ingestTelemetryEvents({
    required String token,
    required List<Map<String, Object?>> events,
  }) async {
    throw StateError('offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
