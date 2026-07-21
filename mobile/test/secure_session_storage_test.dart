import 'package:fitloop/secure_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _MemorySecureStore secureStore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore = _MemorySecureStore();
    TokenStorage.useSecureStoreForTesting(secureStore);
  });

  test('stores the whole authenticated session outside shared preferences',
      () async {
    SharedPreferences.setMockInitialValues({
      'token': 'legacy-token',
      'uid': 1,
      'nickname': 'Legacy',
      'role': 'USER',
    });

    await TokenStorage.save('signed-admin-jwt', 7, 'Admin', 'ADMIN');
    final session = await TokenStorage.load();
    final preferences = await SharedPreferences.getInstance();

    expect(session, {
      'token': 'signed-admin-jwt',
      'userId': 7,
      'nickname': 'Admin',
      'role': 'ADMIN',
    });
    expect(secureStore.values, hasLength(1));
    expect(preferences.getString('token'), isNull);
    expect(preferences.getInt('uid'), isNull);
    expect(preferences.getString('nickname'), isNull);
    expect(preferences.getString('role'), isNull);
  });

  test('migrates a legacy plaintext session once and removes it', () async {
    SharedPreferences.setMockInitialValues({
      'token': 'legacy-admin-jwt',
      'uid': 9,
      'nickname': 'Admin',
      'role': 'ADMIN',
    });

    final session = await TokenStorage.load();
    final preferences = await SharedPreferences.getInstance();

    expect(session?['token'], 'legacy-admin-jwt');
    expect(session?['role'], 'ADMIN');
    expect(secureStore.values, hasLength(1));
    expect(preferences.getString('token'), isNull);
  });

  test('fails closed when the secure session is damaged', () async {
    secureStore.fallbackReadValue = '{not-json';
    SharedPreferences.setMockInitialValues({
      'token': 'stale-plaintext-token',
      'uid': 10,
    });

    expect(await TokenStorage.load(), isNull);
    expect(secureStore.deletedKeys, hasLength(1));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('token'), isNull);
  });

  test('clear removes secure and legacy session data', () async {
    await TokenStorage.save('jwt', 11, 'User', 'USER');

    await TokenStorage.clear();

    expect(await TokenStorage.load(), isNull);
    expect(secureStore.values, isEmpty);
    expect(secureStore.deletedKeys, isNotEmpty);
  });

  test('rejects an invalid authenticated session', () async {
    await expectLater(
      TokenStorage.save(' ', 0, 'User', 'USER'),
      throwsArgumentError,
    );
    expect(secureStore.values, isEmpty);
  });
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};
  final List<String> deletedKeys = [];
  String? fallbackReadValue;

  @override
  Future<String?> read({required String key}) async =>
      values[key] ?? fallbackReadValue;

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
    fallbackReadValue = null;
  }

  @override
  Future<void> delete({required String key}) async {
    deletedKeys.add(key);
    values.remove(key);
    fallbackReadValue = null;
  }
}
