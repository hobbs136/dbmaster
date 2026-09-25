import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
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

    // =====================================================================
    // Agent 运行族配置（T02：agent_max_steps / agent_l05_row_threshold）
    // =====================================================================

    group('agent keys', () {
      test('getAgentMaxSteps returns default 25 when prefs empty', () async {
        expect(await service.getAgentMaxSteps(), equals(25));
      });

      test(
        'getAgentL05RowThreshold returns default 10000 when prefs empty',
        () async {
          expect(await service.getAgentL05RowThreshold(), equals(10000));
        },
      );

      test('setAgentMaxSteps persists and can be read back', () async {
        await service.setAgentMaxSteps(40);
        expect(await service.getAgentMaxSteps(), equals(40));
      });

      test('setAgentL05RowThreshold persists and can be read back', () async {
        await service.setAgentL05RowThreshold(50000);
        expect(await service.getAgentL05RowThreshold(), equals(50000));
      });

      test('setAgentMaxSteps clamps below minimum to 1', () async {
        await service.setAgentMaxSteps(0);
        expect(await service.getAgentMaxSteps(), equals(1));

        await service.setAgentMaxSteps(-5);
        expect(await service.getAgentMaxSteps(), equals(1));
      });

      test('setAgentMaxSteps clamps above maximum to 100', () async {
        await service.setAgentMaxSteps(101);
        expect(await service.getAgentMaxSteps(), equals(100));

        await service.setAgentMaxSteps(1000000);
        expect(await service.getAgentMaxSteps(), equals(100));
      });

      test('setAgentMaxSteps allows exact bounds', () async {
        await service.setAgentMaxSteps(1);
        expect(await service.getAgentMaxSteps(), equals(1));

        await service.setAgentMaxSteps(100);
        expect(await service.getAgentMaxSteps(), equals(100));
      });

      test('setAgentL05RowThreshold clamps below minimum to 1000', () async {
        await service.setAgentL05RowThreshold(999);
        expect(await service.getAgentL05RowThreshold(), equals(1000));

        await service.setAgentL05RowThreshold(0);
        expect(await service.getAgentL05RowThreshold(), equals(1000));
      });

      test('setAgentL05RowThreshold clamps above maximum to 1000000', () async {
        await service.setAgentL05RowThreshold(1000001);
        expect(await service.getAgentL05RowThreshold(), equals(1000000));
      });

      test('setAgentL05RowThreshold allows exact bounds', () async {
        await service.setAgentL05RowThreshold(1000);
        expect(await service.getAgentL05RowThreshold(), equals(1000));

        await service.setAgentL05RowThreshold(1000000);
        expect(await service.getAgentL05RowThreshold(), equals(1000000));
      });

      test('agent keys do not interfere with each other', () async {
        await service.setAgentMaxSteps(50);
        await service.setAgentL05RowThreshold(20000);

        await service.setAgentMaxSteps(1);
        expect(await service.getAgentL05RowThreshold(), equals(20000));

        await service.setAgentL05RowThreshold(999000);
        expect(await service.getAgentMaxSteps(), equals(1));
      });

      test(
        'agent keys and safety_config blob do not affect each other',
        () async {
          // 写 agent 两 key 不影响 safety_config blob（D6 分立）
          await service.setAgentMaxSteps(40);
          await service.setAgentL05RowThreshold(50000);
          expect(
            (await service.getSafetyConfig()).fullScanRowThreshold,
            equals(SafetyConfig.defaults.fullScanRowThreshold),
          );

          // 写 safety_config 不影响 agent 两 key
          await service.setSafetyConfig(
            SafetyConfig.defaults.copyWith(fullScanRowThreshold: 123456),
          );
          expect(await service.getAgentMaxSteps(), equals(40));
          expect(await service.getAgentL05RowThreshold(), equals(50000));
          expect(
            (await service.getSafetyConfig()).fullScanRowThreshold,
            equals(123456),
          );
        },
      );
    });
  });
}
