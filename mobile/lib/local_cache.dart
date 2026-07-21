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

  /// 缓存前缀，避免 key 冲突。
  static const _prefix = 'cache_';

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

  /// 清空所有非敏感业务缓存。认证令牌由安全存储独立管理。
  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    for (final key in p.getKeys()) {
      if (key.startsWith(_prefix)) {
        await p.remove(key);
      }
    }
  }
}
