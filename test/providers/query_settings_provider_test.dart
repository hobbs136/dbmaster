import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/providers/query_settings_provider.dart';

void main() {
  group('QuerySettingsProvider', () {
    late QuerySettingsProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = QuerySettingsProvider();
    });

    tearDown(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        await prefs.remove(key);
      }
    });

    // =====================================================================
    // 初始状态
    // =====================================================================

    test('initial state uses defaults before load', () {
      expect(provider.autoLimitEnabled, equals(true));
      expect(provider.autoLimitValue, equals(3000));
      expect(provider.isLoaded, equals(false));
    });

    // =====================================================================
    // load() 测试
    // =====================================================================

    test('load reads persisted values and sets isLoaded', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('query_auto_limit_enabled', false);
      await prefs.setInt('query_auto_limit_value', 5000);

      await provider.load();

      expect(provider.autoLimitEnabled, equals(false));
      expect(provider.autoLimitValue, equals(5000));
      expect(provider.isLoaded, equals(true));
    });

    test('load notifies listeners', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.load();

      expect(notified, equals(true));
    });

    // =====================================================================
    // setAutoLimitEnabled 测试
    // =====================================================================

    test('setAutoLimitEnabled updates state and persists', () async {
      await provider.setAutoLimitEnabled(false);

      expect(provider.autoLimitEnabled, equals(false));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('query_auto_limit_enabled'), equals(false));
    });

    test('setAutoLimitEnabled notifies listeners when value changes', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setAutoLimitEnabled(false);

      expect(notified, equals(true));
    });

    test('setAutoLimitEnabled does not notify when value unchanged', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setAutoLimitEnabled(true); // same as default

      expect(notified, equals(false));
    });

    // =====================================================================
    // setAutoLimitValue 测试
    // =====================================================================

    test('setAutoLimitValue updates state and persists', () async {
      await provider.setAutoLimitValue(5000);

      expect(provider.autoLimitValue, equals(5000));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('query_auto_limit_value'), equals(5000));
    });

    test('setAutoLimitValue clamps below minimum', () async {
      await provider.setAutoLimitValue(50);
      expect(provider.autoLimitValue, equals(100));
    });

    test('setAutoLimitValue clamps above maximum', () async {
      await provider.setAutoLimitValue(200000);
      expect(provider.autoLimitValue, equals(100000));
    });

    test('setAutoLimitValue notifies listeners when value changes', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setAutoLimitValue(5000);

      expect(notified, equals(true));
    });

    test('setAutoLimitValue does not notify when value unchanged', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setAutoLimitValue(3000); // same as default

      expect(notified, equals(false));
    });

    test(
      'setAutoLimitValue does not notify when clamped result equals current',
      () async {
        // Set current to minimum boundary
        await provider.setAutoLimitValue(100);

        var notified = false;
        provider.addListener(() => notified = true);

        // 50 is below min, clamped to 100, which equals current -> no notify
        await provider.setAutoLimitValue(50);

        expect(notified, equals(false));
      },
    );

    // =====================================================================
    // SafetyConfig 规则开关 setter（B1）—— 6 开关 + 统一阈值
    // =====================================================================

    test('rule-toggle setters default to enabled before load', () {
      final config = provider.safetyConfig;
      expect(config.schemaCompatEnabled, isTrue);
      expect(config.missingLimitEnabled, isTrue);
      expect(config.fullTableScanEnabled, isTrue);
      expect(config.sqlInjectionEnabled, isTrue);
      expect(config.explainFullScanEnabled, isTrue);
      expect(config.explainEstimatedRowsEnabled, isTrue);
      expect(config.fullScanRowThreshold, equals(100000));
    });

    test('setSchemaCompatEnabled updates state, persists, notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setSchemaCompatEnabled(false);

      expect(provider.safetyConfig.schemaCompatEnabled, isFalse);
      expect(notified, isTrue);
      // 持久化校验：重建 config 看落盘值。
      final prefs = await SharedPreferences.getInstance();
      final persisted = SafetyConfig.fromJson(
        jsonDecode(prefs.getString('safety_config')!) as Map<String, dynamic>,
      );
      expect(persisted.schemaCompatEnabled, isFalse);
    });

    test('remaining rule toggles update state and persist', () async {
      await provider.setMissingLimitEnabled(false);
      await provider.setFullTableScanEnabled(false);
      await provider.setSqlInjectionEnabled(false);
      await provider.setExplainFullScanEnabled(false);
      await provider.setExplainEstimatedRowsEnabled(false);

      final config = provider.safetyConfig;
      expect(config.missingLimitEnabled, isFalse);
      expect(config.fullTableScanEnabled, isFalse);
      expect(config.sqlInjectionEnabled, isFalse);
      expect(config.explainFullScanEnabled, isFalse);
      expect(config.explainEstimatedRowsEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      final persisted = SafetyConfig.fromJson(
        jsonDecode(prefs.getString('safety_config')!) as Map<String, dynamic>,
      );
      expect(persisted, equals(config));
    });

    test('rule-toggle setter does not notify when value unchanged', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setSqlInjectionEnabled(true); // same as default

      expect(notified, isFalse);
    });

    // ── fullScanRowThreshold（带 clamp）──

    test('setFullScanRowThreshold updates state and persists', () async {
      await provider.setFullScanRowThreshold(50000);

      expect(provider.safetyConfig.fullScanRowThreshold, equals(50000));

      final prefs = await SharedPreferences.getInstance();
      final persisted = SafetyConfig.fromJson(
        jsonDecode(prefs.getString('safety_config')!) as Map<String, dynamic>,
      );
      expect(persisted.fullScanRowThreshold, equals(50000));
    });

    test('setFullScanRowThreshold clamps below minimum', () async {
      await provider.setFullScanRowThreshold(100); // below min 1000
      expect(
        provider.safetyConfig.fullScanRowThreshold,
        equals(SafetyConfig.minFullScanRowThreshold),
      );
    });

    test('setFullScanRowThreshold clamps above maximum', () async {
      await provider.setFullScanRowThreshold(9999999); // above max 1000000
      expect(
        provider.safetyConfig.fullScanRowThreshold,
        equals(SafetyConfig.maxFullScanRowThreshold),
      );
    });

    test('setFullScanRowThreshold does not notify when clamped == current',
        () async {
      await provider.setFullScanRowThreshold(1000); // set to min boundary

      var notified = false;
      provider.addListener(() => notified = true);

      // 500 below min, clamped to 1000 == current -> no notify
      await provider.setFullScanRowThreshold(500);

      expect(notified, isFalse);
    });
  });
}
