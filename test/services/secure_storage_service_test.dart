import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageService - Password Storage Security', () {
    final secureStorage = <String, String>{};
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );

    setUp(() {
      secureStorage.clear();
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map<dynamic, dynamic>;
            final key = args['key'] as String?;
            switch (call.method) {
              case 'read':
                return secureStorage[key];
              case 'write':
                secureStorage[key!] = args['value'] as String;
                return null;
              case 'delete':
                secureStorage.remove(key);
                return null;
              case 'readAll':
                return secureStorage;
              case 'deleteAll':
                secureStorage.clear();
                return null;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    // =========================================================================
    // HIGH-001: savePassword 不应回退到 SharedPreferences
    // =========================================================================

    test(
      'savePassword should throw SecureStorageException when keychain unavailable',
      () async {
        // 模拟钥匙串不可用
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);

        expect(
          () => SecureStorageService.savePassword('conn_1', 'secret123'),
          throwsA(isA<SecureStorageException>()),
        );
      },
    );

    test(
      'savePassword should not write fallback_password_ to SharedPreferences',
      () async {
        await SecureStorageService.savePassword('conn_1', 'secret123');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('fallback_password_conn_1'), isNull);
      },
    );

    test('savePassword stores password in the credentials vault', () async {
      await SecureStorageService.savePassword('conn_1', 'secret123');

      final vaultJson = secureStorage['dbmaster_credentials_vault'];
      expect(vaultJson, isNotNull);
      expect(vaultJson, contains('"conn_1":"secret123"'));
    });

    // =========================================================================
    // HIGH-001: 向后兼容 — 清理旧 fallback 数据
    // =========================================================================

    test(
      'deletePassword should remove old fallback password if exists',
      () async {
        SharedPreferences.setMockInitialValues({
          'fallback_password_to_delete': 'old_secret',
        });

        await SecureStorageService.deletePassword('to_delete');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('fallback_password_to_delete'), isNull);
      },
    );

    test('clearAll should remove all old fallback passwords', () async {
      SharedPreferences.setMockInitialValues({
        'fallback_password_conn_1': 'secret1',
        'fallback_password_conn_2': 'secret2',
        'other_key': 'value',
      });

      await SecureStorageService.clearAll();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fallback_password_conn_1'), isNull);
      expect(prefs.getString('fallback_password_conn_2'), isNull);
      // clearAll 不应删除非 fallback key
      expect(prefs.getString('other_key'), equals('value'));
    });

    // =========================================================================
    // HIGH-001: migrateFallbackPasswords 清理旧 fallback
    // =========================================================================

    test(
      'migrateFallbackPasswords should migrate and clear fallback on success',
      () async {
        SharedPreferences.setMockInitialValues({
          'fallback_password_conn_a': 'secret_a',
          'other_unrelated_key': 'should_remain',
        });

        await SecureStorageService.migrateFallbackPasswords();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('fallback_password_conn_a'), isNull);
        expect(prefs.getString('other_unrelated_key'), equals('should_remain'));

        final vaultJson = secureStorage['dbmaster_credentials_vault'];
        expect(vaultJson, isNotNull);
        expect(vaultJson, contains('"conn_a":"secret_a"'));
      },
    );
  });
}
