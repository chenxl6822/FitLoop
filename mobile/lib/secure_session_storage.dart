import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class PlatformSecureKeyValueStore implements SecureKeyValueStore {
  const PlatformSecureKeyValueStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class TokenStorage {
  static const _secureSessionKey = 'fitloop.session.v1';
  static const _legacyTokenKey = 'token';
  static const _legacyUserIdKey = 'uid';
  static const _legacyNicknameKey = 'nickname';
  static const _legacyRoleKey = 'role';

  static SecureKeyValueStore _secureStore = const PlatformSecureKeyValueStore();

  @visibleForTesting
  static void useSecureStoreForTesting(SecureKeyValueStore store) {
    _secureStore = store;
  }

  static Future<void> save(
    String token,
    int userId,
    String nickname,
    String role,
  ) async {
    if (token.trim().isEmpty || userId <= 0) {
      throw ArgumentError('A valid authenticated session is required');
    }
    final session = jsonEncode({
      'token': token,
      'userId': userId,
      'nickname': nickname,
      'role': _normalizeRole(role),
    });
    await _secureStore.write(key: _secureSessionKey, value: session);
    await _clearLegacyStorage();
  }

  static Future<Map<String, Object>?> load() async {
    final secureSession = await _secureStore.read(key: _secureSessionKey);
    if (secureSession != null) {
      final decoded = _decodeSession(secureSession);
      if (decoded != null) return decoded;

      // Fail closed: a damaged secure record must not resurrect a stale
      // plaintext token left by an interrupted migration.
      await _secureStore.delete(key: _secureSessionKey);
      await _clearLegacyStorage();
      return null;
    }

    return _migrateLegacySession();
  }

  static Future<void> clear() async {
    await _secureStore.delete(key: _secureSessionKey);
    await _clearLegacyStorage();
  }

  static Map<String, Object>? _decodeSession(String value) {
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic>) return null;
      final token = data['token'];
      final userId = data['userId'];
      final nickname = data['nickname'];
      if (token is! String || token.isEmpty || userId is! int || userId <= 0) {
        return null;
      }
      return {
        'token': token,
        'userId': userId,
        'nickname':
            nickname is String && nickname.isNotEmpty ? nickname : 'FitLoop 用户',
        'role': _normalizeRole(data['role']),
      };
    } on FormatException {
      return null;
    }
  }

  static Future<Map<String, Object>?> _migrateLegacySession() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_legacyTokenKey);
    final userId = preferences.getInt(_legacyUserIdKey);
    if (token == null || token.isEmpty || userId == null || userId <= 0) {
      await _clearLegacyStorage(preferences);
      return null;
    }

    final nickname = preferences.getString(_legacyNicknameKey) ?? 'FitLoop 用户';
    final role = _normalizeRole(preferences.getString(_legacyRoleKey));
    await save(token, userId, nickname, role);
    return {
      'token': token,
      'userId': userId,
      'nickname': nickname,
      'role': role,
    };
  }

  static String _normalizeRole(Object? role) =>
      role == 'ADMIN' ? 'ADMIN' : 'USER';

  static Future<void> _clearLegacyStorage(
      [SharedPreferences? preferences]) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    await prefs.remove(_legacyTokenKey);
    await prefs.remove(_legacyUserIdKey);
    await prefs.remove(_legacyNicknameKey);
    await prefs.remove(_legacyRoleKey);
  }
}
