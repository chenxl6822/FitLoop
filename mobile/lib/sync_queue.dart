import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'async_serial_executor.dart';
import 'secure_session_storage.dart';

// ──────── Data model for queued finish operations ────────

class PendingFinishRecord {
  PendingFinishRecord({
    required this.sessionId,
    required this.durationSeconds,
    required this.weightKg,
    this.trackPoints,
  });

  final String sessionId;
  final int durationSeconds;
  final double weightKg;
  final List<TrackPoint>? trackPoints;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'durationSeconds': durationSeconds,
        'weightKg': weightKg,
        if (trackPoints != null)
          'trackPoints': trackPoints!
              .map((tp) => {
                    'sessionId': tp.sessionId,
                    'lat': tp.lat,
                    'lng': tp.lng,
                    'accuracy': tp.accuracy,
                    'timestamp': tp.timestamp.toIso8601String(),
                  })
              .toList(),
      };

  factory PendingFinishRecord.fromJson(Map<String, dynamic> json) =>
      PendingFinishRecord(
        sessionId: json['sessionId'] as String,
        durationSeconds: json['durationSeconds'] as int,
        weightKg: (json['weightKg'] as num).toDouble(),
        trackPoints: json['trackPoints'] != null
            ? (json['trackPoints'] as List)
                .map((tp) => TrackPoint(
                      sessionId: tp['sessionId'] as String,
                      lat: (tp['lat'] as num).toDouble(),
                      lng: (tp['lng'] as num).toDouble(),
                      accuracy: (tp['accuracy'] as num).toDouble(),
                      timestamp: DateTime.parse(tp['timestamp'] as String),
                    ))
                .toList()
            : null,
      );
}

// ═══════════════════════════════════════════════════════════
//  Persistent offline sync queue
// ═══════════════════════════════════════════════════════════

class SyncQueue {
  SyncQueue._();

  static const _kQueueKey = 'fitloop.sync_queue.v1';
  static const _kLegacyQueueKey = 'sync_queue';
  static AsyncSerialExecutor _mutations = AsyncSerialExecutor();

  static Future<T> _withMutationLock<T>(Future<T> Function() action) =>
      _mutations.run(action);

  static void resetSerializersForTesting() {
    _mutations = AsyncSerialExecutor();
  }

  static Future<List<dynamic>> _readRawUnlocked() async {
    final protected = await TokenStorage.readProtectedValue(_kQueueKey);
    if (protected != null && protected.isNotEmpty) {
      await _removeLegacyQueue();
      try {
        return jsonDecode(protected) as List<dynamic>;
      } on FormatException {
        await TokenStorage.deleteProtectedValue(_kQueueKey);
        return <dynamic>[];
      }
    }

    final preferences = await SharedPreferences.getInstance();
    final legacy = preferences.getString(_kLegacyQueueKey);
    if (legacy == null || legacy.isEmpty) return <dynamic>[];
    late final List<dynamic> list;
    try {
      list = jsonDecode(legacy) as List<dynamic>;
    } on FormatException {
      await preferences.remove(_kLegacyQueueKey);
      return <dynamic>[];
    }
    await _writeRawUnlocked(list);
    await preferences.remove(_kLegacyQueueKey);
    return list;
  }

  static Future<void> _writeRawUnlocked(List<dynamic> list) async {
    final sanitized = list
        .map((item) => Map<String, dynamic>.from(item as Map)..remove('token'))
        .toList(growable: false);
    if (sanitized.isEmpty) {
      await TokenStorage.deleteProtectedValue(_kQueueKey);
    } else {
      await TokenStorage.writeProtectedValue(_kQueueKey, jsonEncode(sanitized));
    }
    await _removeLegacyQueue();
  }

  static Future<void> _removeLegacyQueue() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_kLegacyQueueKey);
  }

  /// 将一次 finishSport 操作加入队列（断网时调用）。
  static Future<void> enqueueFinish(PendingFinishRecord record) async {
    await _withMutationLock(() async {
      final list = await _readRawUnlocked();
      list.removeWhere((item) =>
          (item as Map<String, dynamic>)['sessionId'] == record.sessionId);
      list.add(record.toJson());
      await _writeRawUnlocked(list);
    });
  }

  /// 返回所有待同步的记录。
  static Future<List<PendingFinishRecord>> pending() async {
    return _withMutationLock(() async {
      final list = await _readRawUnlocked();
      return List<PendingFinishRecord>.unmodifiable(list.map(
        (item) => PendingFinishRecord.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
      ));
    });
  }

  /// 清空整条队列（全部同步成功后调用）。
  static Future<void> clear() async {
    await _withMutationLock(() => _writeRawUnlocked(<dynamic>[]));
  }

  /// 按稳定的 sessionId 移除成功项，避免并发入队导致索引漂移。
  static Future<void> removeSession(String sessionId) async {
    await _withMutationLock(() async {
      final list = await _readRawUnlocked();
      list.removeWhere(
          (item) => (item as Map<String, dynamic>)['sessionId'] == sessionId);
      await _writeRawUnlocked(list);
    });
  }

  /// 队列长度。
  static Future<int> length() async {
    return (await pending()).length;
  }

  /// 是否有待同步项。
  static Future<bool> get hasPending => length().then((l) => l > 0);
}

// ═══════════════════════════════════════════════════════════
//  Sync processor — call when coming back online
// ═══════════════════════════════════════════════════════════

class SyncProcessor {
  SyncProcessor(this.api, {required this.token});

  final FitLoopApi api;
  final String token;

  /// 尝试同步所有待处理打卡记录。
  ///
  /// 逐条重放 finishSport。成功则移除，失败则保留。
  /// 返回 { synced: 成功数, failed: 失败数 }。
  Future<({int synced, int failed})> processAll() async {
    final items = await SyncQueue.pending();
    if (items.isEmpty) return (synced: 0, failed: 0);

    int synced = 0;
    int failed = 0;

    for (final item in items) {
      try {
        // 先尝试补传未上传的轨迹点
        if (item.trackPoints != null && item.trackPoints!.isNotEmpty) {
          for (final tp in item.trackPoints!) {
            try {
              await api.uploadTrackPoint(
                token: token,
                point: tp,
              );
            } catch (_) {
              // 轨迹点上传失败不影响主记录
            }
          }
        }

        await api.finishSport(
          token: token,
          sessionId: item.sessionId,
          durationSeconds: item.durationSeconds,
          weightKg: item.weightKg,
        );
        await SyncQueue.removeSession(item.sessionId);
        synced++;
      } catch (_) {
        failed++;
      }
    }

    return (synced: synced, failed: failed);
  }
}

class WorkoutFinishResult {
  const WorkoutFinishResult.saved(this.record)
      : queued = false,
        error = null;

  const WorkoutFinishResult.queued(this.error)
      : queued = true,
        record = null;

  final bool queued;
  final SportRecord? record;
  final Object? error;
}

class ReliableWorkoutFinisher {
  const ReliableWorkoutFinisher(this.api);

  final FitLoopApi api;

  Future<WorkoutFinishResult> finish({
    required String token,
    required String sessionId,
    required int durationSeconds,
    required double weightKg,
    double? distanceKm,
  }) async {
    try {
      final record = await api.finishSport(
        token: token,
        sessionId: sessionId,
        durationSeconds: durationSeconds,
        weightKg: weightKg,
        distanceKm: distanceKm,
      );
      return WorkoutFinishResult.saved(record);
    } catch (error) {
      await SyncQueue.enqueueFinish(PendingFinishRecord(
        sessionId: sessionId,
        durationSeconds: durationSeconds,
        weightKg: weightKg,
      ));
      return WorkoutFinishResult.queued(error);
    }
  }
}
