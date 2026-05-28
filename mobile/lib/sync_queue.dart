import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

// ──────── Data model for queued finish operations ────────

class PendingFinishRecord {
  PendingFinishRecord({
    required this.token,
    required this.sessionId,
    required this.durationSeconds,
    required this.weightKg,
    this.trackPoints,
  });

  final String token;
  final String sessionId;
  final int durationSeconds;
  final double weightKg;
  final List<TrackPoint>? trackPoints;

  Map<String, dynamic> toJson() => {
        'token': token,
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
        token: json['token'] as String,
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

  static const _kQueueKey = 'sync_queue';

  /// 将一次 finishSport 操作加入队列（断网时调用）。
  static Future<void> enqueueFinish(PendingFinishRecord record) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kQueueKey);
    final list = raw != null ? (jsonDecode(raw) as List) : <dynamic>[];
    list.add(record.toJson());
    await p.setString(_kQueueKey, jsonEncode(list));
  }

  /// 返回所有待同步的记录。
  static Future<List<PendingFinishRecord>> pending() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kQueueKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => PendingFinishRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 清空整条队列（全部同步成功后调用）。
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kQueueKey);
  }

  /// 移除队列中第 [index] 项（单条同步成功后调用）。
  static Future<void> removeAt(int index) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kQueueKey);
    if (raw == null) return;
    final list = jsonDecode(raw) as List;
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) {
      await p.remove(_kQueueKey);
    } else {
      await p.setString(_kQueueKey, jsonEncode(list));
    }
  }

  /// 队列长度。
  static Future<int> length() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kQueueKey);
    if (raw == null) return 0;
    return (jsonDecode(raw) as List).length;
  }

  /// 是否有待同步项。
  static Future<bool> get hasPending => length().then((l) => l > 0);
}

// ═══════════════════════════════════════════════════════════
//  Sync processor — call when coming back online
// ═══════════════════════════════════════════════════════════

class SyncProcessor {
  SyncProcessor(this.api);

  final FitLoopApi api;

  /// 尝试同步所有待处理打卡记录。
  ///
  /// 逐条重放 finishSport。成功则移除，失败则保留。
  /// 返回 { synced: 成功数, failed: 失败数 }。
  Future<({int synced, int failed})> processAll() async {
    final items = await SyncQueue.pending();
    if (items.isEmpty) return (synced: 0, failed: 0);

    int synced = 0;
    int failed = 0;

    for (int i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      try {
        // 先尝试补传未上传的轨迹点
        if (item.trackPoints != null && item.trackPoints!.isNotEmpty) {
          for (final tp in item.trackPoints!) {
            try {
              await api.uploadTrackPoint(
                token: item.token,
                point: tp,
              );
            } catch (_) {
              // 轨迹点上传失败不影响主记录
            }
          }
        }

        await api.finishSport(
          token: item.token,
          sessionId: item.sessionId,
          durationSeconds: item.durationSeconds,
          weightKg: item.weightKg,
        );
        await SyncQueue.removeAt(i);
        synced++;
      } catch (_) {
        failed++;
      }
    }

    return (synced: synced, failed: failed);
  }
}
