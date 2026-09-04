import 'api_services.dart';

/// Fire-and-forget product telemetry. Never blocks UX; never sends coordinates
/// or credentials. Server also rejects forbidden prop keys.
class ProductTelemetry {
  ProductTelemetry(this._api, {required this.token});

  final FitLoopApi _api;
  final String Function() token;

  Future<void> track(
    String eventName, {
    Map<String, Object?> props = const {},
  }) async {
    try {
      final clean = <String, Object?>{};
      for (final entry in props.entries) {
        final value = entry.value;
        if (value == null || value is bool || value is num || value is String) {
          clean[entry.key] = value;
        }
      }
      await _api.ingestTelemetryEvents(
        token: token(),
        events: [
          {
            'eventName': eventName,
            'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
            'props': clean,
          },
        ],
      );
    } catch (_) {
      // Telemetry must never break workout / account flows.
    }
  }
}
