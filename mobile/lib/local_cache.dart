import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ──────── 缓存辅助 ────────

class _CacheEntry {
  _CacheEntry(this.data, this.fetchedAt);

  final String data;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'data': data,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  static _CacheEntry? fromJson(dynamic json) {
    if (json is! Map) return null;
    final data = json['data'] as String?;
    final fetchedAt = json['fetchedAt'] as String?;
    if (data == null || fetchedAt == null) return null;
    return _CacheEntry(data, DateTime.parse(fetchedAt));
  }
}

// ═══════════════════════════════════════════════════════════
//  通用本地缓存
// ═══════════════════════════════════════════════════════════

class LocalCache {
  LocalCache._();

  static const _kToken = 'token';
  static const _kUid = 'uid';
  static const _kName = 'nickname';

  /// 缓存前缀，避免 key 冲突。
  static const _prefix = 'cache_';

  /// ── Token 持久化（兼容旧 TokenStorage 接口） ──

  static Future<void> saveToken(
      String token, int userId, String nickname) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setInt(_kUid, userId);
    await p.setString(_kName, nickname);
  }

  static Future<Map<String, Object>?> loadToken() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kToken);
    if (t == null || t.isEmpty) return null;
    return {
      'token': t,
      'userId': p.getInt(_kUid) ?? 0,
      'nickname': p.getString(_kName) ?? 'FitLoop 用户',
    };
  }

  static Future<void> clearToken() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUid);
    await p.remove(_kName);
    // 清除头像缓存
    for (final key in p.getKeys()) {
      if (key.startsWith('avatarUrl_')) {
        await p.remove(key);
      }
    }
  }

  static Future<void> save(String token, int userId, String nickname) =>
      saveToken(token, userId, nickname);

  static Future<Map<String, Object>?> load() => loadToken();

  static Future<void> clear() => clearToken();

  /// ── 通用数据缓存（JSON 序列化） ──

  /// 写入缓存，有效期为 [ttl]。
  static Future<void> put(String key, String value,
      {Duration ttl = const Duration(minutes: 5)}) async {
    final entry = _CacheEntry(value, DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('$_prefix$key', jsonEncode(entry.toJson()));
  }

  /// 读取缓存。过期或不存在返回 null。
  static Future<String?> get(String key,
      {Duration maxAge = const Duration(minutes: 5)}) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_prefix$key');
    if (raw == null) return null;
    final entry = _CacheEntry.fromJson(jsonDecode(raw));
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > maxAge) {
      await evict(key);
      return null;
    }
    return entry.data;
  }

  /// 是否存在缓存（不过期）。
  static Future<bool> has(String key,
      {Duration maxAge = const Duration(minutes: 5)}) async {
    final data = await get(key, maxAge: maxAge);
    return data != null;
  }

  /// 删除一条缓存。
  static Future<void> evict(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_prefix$key');
  }

  /// 清空所有缓存（保留 token）。
  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    // 保留 token 键
    for (final key in p.getKeys()) {
      if (key.startsWith(_prefix)) {
        await p.remove(key);
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  兼容层 — 旧代码仍用 TokenStorage 的地方直接重定向
// ═══════════════════════════════════════════════════════════

typedef TokenStorage = LocalCache;
