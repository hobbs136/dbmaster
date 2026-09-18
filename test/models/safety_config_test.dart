// SafetyConfig 模型测试（B1：可配置规则引擎 UI）。
//
// 覆盖：defaults / round-trip（toJson→fromJson）/ copyWith / 向后兼容
// （老配置无新增字段时落默认值）。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/dml_risk_models.dart';

void main() {
  group('SafetyConfig', () {
    // =====================================================================
    // defaults
    // =====================================================================

    test('defaults has all rule toggles enabled and threshold 100000', () {
      const config = SafetyConfig.defaults;
      // 既有字段（回归保护）。
      expect(config.explainPreflightEnabled, isTrue);
      expect(config.dmlCheckEnabled, isTrue);
      expect(config.fullScanWarningThreshold, equals(10000));
      expect(config.preflightTimeoutSeconds, equals(3));
      // 新增规则开关——默认全开，保持既有「硬编码全开」行为。
      expect(config.schemaCompatEnabled, isTrue);
      expect(config.missingLimitEnabled, isTrue);
      expect(config.fullTableScanEnabled, isTrue);
      expect(config.sqlInjectionEnabled, isTrue);
      expect(config.explainFullScanEnabled, isTrue);
      expect(config.explainEstimatedRowsEnabled, isTrue);
      // B6 规则包开关（T14 收口，方案 §2.3 六条全默认开）。
      expect(config.executableCommentEnabled, isTrue);
      expect(config.tautologyPredicateEnabled, isTrue);
      expect(config.complementaryOrEnabled, isTrue);
      expect(config.writableCteEnabled, isTrue);
      expect(config.fileWriteEnabled, isTrue);
      expect(config.reviewFailClosedEnabled, isTrue);
      // 统一行数阈值。
      expect(config.fullScanRowThreshold, equals(100000));
    });

    test('threshold range constants are defined', () {
      expect(SafetyConfig.minFullScanRowThreshold, equals(1000));
      expect(SafetyConfig.maxFullScanRowThreshold, equals(1000000));
    });

    // =====================================================================
    // round-trip: toJson → fromJson
    // =====================================================================

    test('toJson/fromJson round-trip preserves all fields', () {
      const original = SafetyConfig(
        explainPreflightEnabled: false,
        fullScanWarningThreshold: 5000,
        preflightTimeoutSeconds: 5,
        dmlCheckEnabled: false,
        schemaCompatEnabled: false,
        missingLimitEnabled: true,
        fullTableScanEnabled: false,
        sqlInjectionEnabled: true,
        explainFullScanEnabled: false,
        explainEstimatedRowsEnabled: true,
        fullScanRowThreshold: 50000,
        executableCommentEnabled: false,
        tautologyPredicateEnabled: true,
        complementaryOrEnabled: false,
        writableCteEnabled: true,
        fileWriteEnabled: false,
        reviewFailClosedEnabled: true,
      );
      final restored = SafetyConfig.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test('round-trip with defaults produces no drift', () {
      const original = SafetyConfig.defaults;
      final restored = SafetyConfig.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    // =====================================================================
    // 向后兼容：老配置（无新增字段）反序列化
    // =====================================================================

    test('fromJson falls back to defaults for missing rule-toggle fields', () {
      // 模拟老版本持久化的配置——只有既有 4 个字段，无规则开关。
      final legacyJson = <String, dynamic>{
        'explainPreflightEnabled': false,
        'fullScanWarningThreshold': 20000,
        'preflightTimeoutSeconds': 2,
        'dmlCheckEnabled': true,
      };
      final config = SafetyConfig.fromJson(legacyJson);
      // 既有字段按老配置读。
      expect(config.explainPreflightEnabled, isFalse);
      expect(config.fullScanWarningThreshold, equals(20000));
      expect(config.preflightTimeoutSeconds, equals(2));
      expect(config.dmlCheckEnabled, isTrue);
      // 新增字段落默认值（不崩、保持全开行为）。
      expect(config.schemaCompatEnabled, isTrue);
      expect(config.missingLimitEnabled, isTrue);
      expect(config.fullTableScanEnabled, isTrue);
      expect(config.sqlInjectionEnabled, isTrue);
      expect(config.explainFullScanEnabled, isTrue);
      expect(config.explainEstimatedRowsEnabled, isTrue);
      expect(config.fullScanRowThreshold, equals(100000));
      // B6 开关同样落默认开（老配置升级无感知）。
      expect(config.executableCommentEnabled, isTrue);
      expect(config.tautologyPredicateEnabled, isTrue);
      expect(config.complementaryOrEnabled, isTrue);
      expect(config.writableCteEnabled, isTrue);
      expect(config.fileWriteEnabled, isTrue);
      expect(config.reviewFailClosedEnabled, isTrue);
    });

    test('fromJson on empty map returns defaults', () {
      final config = SafetyConfig.fromJson({});
      expect(config, equals(SafetyConfig.defaults));
    });

    // =====================================================================
    // copyWith
    // =====================================================================

    test('copyWith updates only specified rule-toggle fields', () {
      const base = SafetyConfig.defaults;
      final updated = base.copyWith(
        schemaCompatEnabled: false,
        fullScanRowThreshold: 25000,
      );
      expect(updated.schemaCompatEnabled, isFalse);
      expect(updated.fullScanRowThreshold, equals(25000));
      // 未指定的字段保持原值。
      expect(updated.missingLimitEnabled, equals(base.missingLimitEnabled));
      expect(updated.explainEstimatedRowsEnabled,
          equals(base.explainEstimatedRowsEnabled));
      expect(updated.dmlCheckEnabled, equals(base.dmlCheckEnabled));
    });

    test('copyWith with no args returns equal config', () {
      const base = SafetyConfig.defaults;
      expect(base.copyWith(), equals(base));
    });

    // =====================================================================
    // equality
    // =====================================================================

    test('equality considers all rule-toggle fields', () {
      const a = SafetyConfig(schemaCompatEnabled: false);
      const b = SafetyConfig(schemaCompatEnabled: false);
      const c = SafetyConfig(schemaCompatEnabled: true);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equality considers fullScanRowThreshold', () {
      const a = SafetyConfig(fullScanRowThreshold: 50000);
      const b = SafetyConfig(fullScanRowThreshold: 50000);
      const c = SafetyConfig(fullScanRowThreshold: 100000);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
