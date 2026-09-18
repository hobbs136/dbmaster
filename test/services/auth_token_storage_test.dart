import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/services/auth_token_storage.dart';

// ============================================================================
// AuthTokenStorage Tests
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthTokenStorage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('load 应从 SharedPreferences legacy key 读取', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'legacy_token',
        'refresh_token': 'legacy_refresh',
      });

      final result = await AuthTokenStorage.load();

      expect(result['token'], equals('legacy_token'));
      expect(result['refreshToken'], equals('legacy_refresh'));
    });

    test('load 应返回 null 当无存储值时', () async {
      SharedPreferences.setMockInitialValues({});

      final result = await AuthTokenStorage.load();

      expect(result['token'], isNull);
      expect(result['refreshToken'], isNull);
    });

    test('clear 应清除 legacy SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'token',
        'refresh_token': 'refresh',
      });

      await AuthTokenStorage.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('migrateIfNeeded 在 secure storage 不可用时保留 legacy 数据', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'old_token',
        'refresh_token': 'old_refresh',
      });

      // In test environment, FlutterSecureStorage fails (no platform channel),
      // so migration aborts and legacy keys are preserved.
      await AuthTokenStorage.migrateIfNeeded();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), equals('old_token'));
      expect(prefs.getString('refresh_token'), equals('old_refresh'));
    });

    test('migrateIfNeeded 无 legacy 数据时不应报错', () async {
      SharedPreferences.setMockInitialValues({});

      // Should not throw
      await AuthTokenStorage.migrateIfNeeded();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
    });
  });
}
