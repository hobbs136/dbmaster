import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/query_settings_service.dart';

void main() {
  group('QuerySettingsService', () {
    late QuerySettingsService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = QuerySettingsService();
    });

    tearDown(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        await prefs.remove(key);
      }
    });

    // =====================================================================
    // 默认值测试
    // =====================================================================

    test('getAutoLimitEnabled returns default when prefs empty', () async {
      expect(await service.getAutoLimitEnabled(), equals(true));
    });

    test('getAutoLimitValue returns default when prefs empty', () async {
      expect(await service.getAutoLimitValue(), equals(3000));
    });

    // =====================================================================
    // 读写测试
    // =====================================================================

    test('setAutoLimitEnabled persists and can be read back', () async {
      await service.setAutoLimitEnabled(false);
      expect(await service.getAutoLimitEnabled(), equals(false));

      await service.setAutoLimitEnabled(true);
      expect(await service.getAutoLimitEnabled(), equals(true));
    });

    test('setAutoLimitValue persists and can be read back', () async {
      await service.setAutoLimitValue(5000);
      expect(await service.getAutoLimitValue(), equals(5000));
    });

    // =====================================================================
    // 边界 clamp 测试
    // =====================================================================

    test('setAutoLimitValue clamps below minimum to 100', () async {
      await service.setAutoLimitValue(50);
      expect(await service.getAutoLimitValue(), equals(100));
    });

    test('setAutoLimitValue clamps above maximum to 100000', () async {
      await service.setAutoLimitValue(200000);
      expect(await service.getAutoLimitValue(), equals(100000));
    });

    test('setAutoLimitValue clamps negative value to 100', () async {
      await service.setAutoLimitValue(-1);
      expect(await service.getAutoLimitValue(), equals(100));
    });

    test('setAutoLimitValue allows exact minimum', () async {
      await service.setAutoLimitValue(100);
      expect(await service.getAutoLimitValue(), equals(100));
    });

    test('setAutoLimitValue allows exact maximum', () async {
      await service.setAutoLimitValue(100000);
      expect(await service.getAutoLimitValue(), equals(100000));
    });

    // =====================================================================
    // 隔离测试：多次实例共享同一存储
    // =====================================================================

    test('new service instance reads previously persisted values', () async {
      await service.setAutoLimitEnabled(false);
      await service.setAutoLimitValue(9999);

      final newService = QuerySettingsService();
      expect(await newService.getAutoLimitEnabled(), equals(false));
      expect(await newService.getAutoLimitValue(), equals(9999));
    });
  });
}
