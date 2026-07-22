import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';

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
  static const _secureSessionKey = 'fitloop.session.v2';
  static const _obsoleteSecureSessionKey = 'fitloop.session.v1';
  static const _legacyTokenKey = 'token';
  static const _legacyUserIdKey = 'uid';
  static const _legacyNicknameKey = 'nickname';
  static const _legacyRoleKey = 'role';

  static SecureKeyValueStore _secureStore = const PlatformSecureKeyValueStore();

  @visibleForTesting
  static void useSecureStoreForTesting(SecureKeyValueStore store) {
    _secureStore = store;
  }

  static Future<void> save(UserSession value) async {
    if (value.token.trim().isEmpty ||
        value.refreshToken.trim().isEmpty ||
        value.userId <= 0) {
      throw ArgumentError('A valid authenticated session is required');
    }
    final session = jsonEncode({
      'version': 2,
      'token': value.token,
      'refreshToken': value.refreshToken,
      'expiresAt': value.expiresAt.toUtc().toIso8601String(),
      'userId': value.userId,
      'nickname': value.nickname,
      'avatarUrl': value.avatarUrl,
      'role': _normalizeRole(value.role),
    });
    await _secureStore.write(key: _secureSessionKey, value: session);
    await _secureStore.delete(key: _obsoleteSecureSessionKey);
    await _clearLegacyStorage();
  }

  static Future<UserSession?> load() async {
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

    // Version 1 and SharedPreferences sessions contain only an access token.
    // They cannot be refreshed safely, so require a new login instead of
    // resurrecting an authentication state that is about to expire.
    await _secureStore.delete(key: _obsoleteSecureSessionKey);
    await _clearLegacyStorage();
    return null;
  }

  static Future<void> clear() async {
    await _secureStore.delete(key: _secureSessionKey);
    await _secureStore.delete(key: _obsoleteSecureSessionKey);
    await _clearLegacyStorage();
  }

  static UserSession? _decodeSession(String value) {
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic>) return null;
      final token = data['token'];
      final refreshToken = data['refreshToken'];
      final expiresAtValue = data['expiresAt'];
      final userId = data['userId'];
      final nickname = data['nickname'];
      final expiresAt = expiresAtValue is String
          ? DateTime.tryParse(expiresAtValue)?.toUtc()
          : null;
      if (data['version'] != 2 ||
          token is! String ||
          token.isEmpty ||
          refreshToken is! String ||
          refreshToken.isEmpty ||
          expiresAt == null ||
          userId is! int ||
          userId <= 0) {
        return null;
      }
      return UserSession(
        token: token,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        userId: userId,
        nickname:
            nickname is String && nickname.isNotEmpty ? nickname : 'FitLoop 用户',
        avatarUrl:
            data['avatarUrl'] is String ? data['avatarUrl'] as String : null,
        role: _normalizeRole(data['role']),
      );
    } on FormatException {
      return null;
    }
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

class SecureSessionStore implements SessionStore {
  const SecureSessionStore();

  @override
  Future<UserSession?> load() => TokenStorage.load();

  @override
  Future<void> save(UserSession session) => TokenStorage.save(session);

  @override
  Future<void> clear() => TokenStorage.clear();
}
