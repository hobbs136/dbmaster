import 'package:flutter/foundation.dart';
import '../models/dml_risk_models.dart';
import '../services/query_settings_service.dart';

/// 查询设置 Provider
/// 管理自动 LIMIT、安全配置等查询相关设置
class QuerySettingsProvider extends ChangeNotifier {
  final QuerySettingsService _service = QuerySettingsService();

  bool _autoLimitEnabled = QuerySettingsService.defaultAutoLimitEnabled;
  int _autoLimitValue = QuerySettingsService.defaultAutoLimitValue;
  SafetyConfig _safetyConfig = SafetyConfig.defaults;
  bool _isLoaded = false;

  bool get autoLimitEnabled => _autoLimitEnabled;
  int get autoLimitValue => _autoLimitValue;
  SafetyConfig get safetyConfig => _safetyConfig;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _autoLimitEnabled = await _service.getAutoLimitEnabled();
    _autoLimitValue = await _service.getAutoLimitValue();
    _safetyConfig = await _service.getSafetyConfig();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setAutoLimitEnabled(bool enabled) async {
    if (_autoLimitEnabled != enabled) {
      _autoLimitEnabled = enabled;
      notifyListeners();
      await _service.setAutoLimitEnabled(enabled);
    }
  }

  Future<void> setAutoLimitValue(int value) async {
    final clamped = value.clamp(
      QuerySettingsService.minAutoLimitValue,
      QuerySettingsService.maxAutoLimitValue,
    );
    if (_autoLimitValue != clamped) {
      _autoLimitValue = clamped;
      notifyListeners();
      await _service.setAutoLimitValue(clamped);
    }
  }

  // ──────────────── Safety Config ────────────────

  Future<void> setSafetyConfig(SafetyConfig config) async {
    if (_safetyConfig != config) {
      _safetyConfig = config;
      notifyListeners();
      await _service.setSafetyConfig(config);
    }
  }

  Future<void> setExplainPreflightEnabled(bool enabled) async {
    if (_safetyConfig.explainPreflightEnabled != enabled) {
      _safetyConfig = _safetyConfig.copyWith(explainPreflightEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setFullScanWarningThreshold(int threshold) async {
    if (_safetyConfig.fullScanWarningThreshold != threshold) {
      _safetyConfig =
          _safetyConfig.copyWith(fullScanWarningThreshold: threshold);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setPreflightTimeoutSeconds(int seconds) async {
    if (_safetyConfig.preflightTimeoutSeconds != seconds) {
      _safetyConfig =
          _safetyConfig.copyWith(preflightTimeoutSeconds: seconds);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setDmlCheckEnabled(bool enabled) async {
    if (_safetyConfig.dmlCheckEnabled != enabled) {
      _safetyConfig = _safetyConfig.copyWith(dmlCheckEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  // ──────────────── SafetyReviewService 规则开关（6 条）+ 统一阈值 ────────────────

  Future<void> setSchemaCompatEnabled(bool enabled) async {
    if (_safetyConfig.schemaCompatEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(schemaCompatEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setMissingLimitEnabled(bool enabled) async {
    if (_safetyConfig.missingLimitEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(missingLimitEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setFullTableScanEnabled(bool enabled) async {
    if (_safetyConfig.fullTableScanEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(fullTableScanEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setSqlInjectionEnabled(bool enabled) async {
    if (_safetyConfig.sqlInjectionEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(sqlInjectionEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setExplainFullScanEnabled(bool enabled) async {
    if (_safetyConfig.explainFullScanEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(explainFullScanEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setExplainEstimatedRowsEnabled(bool enabled) async {
    if (_safetyConfig.explainEstimatedRowsEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(explainEstimatedRowsEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  // ────────── B6 规则包开关（T14 收口，方案 §2.3 六条）──────────
  Future<void> setExecutableCommentEnabled(bool enabled) async {
    if (_safetyConfig.executableCommentEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(executableCommentEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setTautologyPredicateEnabled(bool enabled) async {
    if (_safetyConfig.tautologyPredicateEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(tautologyPredicateEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setComplementaryOrEnabled(bool enabled) async {
    if (_safetyConfig.complementaryOrEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(complementaryOrEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setWritableCteEnabled(bool enabled) async {
    if (_safetyConfig.writableCteEnabled != enabled) {
      _safetyConfig = _safetyConfig.copyWith(writableCteEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  Future<void> setFileWriteEnabled(bool enabled) async {
    if (_safetyConfig.fileWriteEnabled != enabled) {
      _safetyConfig = _safetyConfig.copyWith(fileWriteEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  /// 审查降级 fail-closed（T13）：同时约束引擎注入与编辑器执行门 catch。
  Future<void> setReviewFailClosedEnabled(bool enabled) async {
    if (_safetyConfig.reviewFailClosedEnabled != enabled) {
      _safetyConfig =
          _safetyConfig.copyWith(reviewFailClosedEnabled: enabled);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }

  /// 统一行数阈值（喂给 MissingLimit / ExplainFullScan / ExplainEstimatedRows）。
  /// 输入会被 clamp 到 [SafetyConfig.minFullScanRowThreshold,
  /// SafetyConfig.maxFullScanRowThreshold]。
  Future<void> setFullScanRowThreshold(int threshold) async {
    final clamped = threshold.clamp(
      SafetyConfig.minFullScanRowThreshold,
      SafetyConfig.maxFullScanRowThreshold,
    );
    if (_safetyConfig.fullScanRowThreshold != clamped) {
      _safetyConfig = _safetyConfig.copyWith(fullScanRowThreshold: clamped);
      notifyListeners();
      await _service.setSafetyConfig(_safetyConfig);
    }
  }
}
