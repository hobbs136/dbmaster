import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dml_risk_models.dart';

/// 查询设置服务
/// 管理自动 LIMIT、安全配置等查询相关设置
class QuerySettingsService {
  static const String _autoLimitEnabledKey = 'query_auto_limit_enabled';
  static const String _autoLimitValueKey = 'query_auto_limit_value';
  static const String _safetyConfigKey = 'safety_config';
  static const String _agentMaxStepsKey = 'agent_max_steps';
  static const String _agentL05RowThresholdKey = 'agent_l05_row_threshold';

  static const bool defaultAutoLimitEnabled = true;
  static const int defaultAutoLimitValue = 3000;
  static const int minAutoLimitValue = 100;
  static const int maxAutoLimitValue = 100000;

  // Agent 运行族配置（D16/D6）：与编辑器 SafetyConfig 分立，互不影响。
  static const int defaultAgentMaxSteps = 25;
  static const int minAgentMaxSteps = 1;
  static const int maxAgentMaxSteps = 100;

  // L0.5 读前分析行数阈值（D6）：独立于编辑器
  // SafetyConfig.fullScanRowThreshold（100000），分立是有意设计。
  static const int defaultAgentL05RowThreshold = 10000;
  static const int minAgentL05RowThreshold = 1000;
  static const int maxAgentL05RowThreshold = 1000000;

  Future<bool> getAutoLimitEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLimitEnabledKey) ?? defaultAutoLimitEnabled;
  }

  Future<void> setAutoLimitEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLimitEnabledKey, enabled);
  }

  Future<int> getAutoLimitValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoLimitValueKey) ?? defaultAutoLimitValue;
  }

  Future<void> setAutoLimitValue(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = value.clamp(minAutoLimitValue, maxAutoLimitValue);
    await prefs.setInt(_autoLimitValueKey, clamped);
  }

  // ──────────────── Safety Config ────────────────

  Future<SafetyConfig> getSafetyConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_safetyConfigKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return SafetyConfig.defaults;
    }
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SafetyConfig.fromJson(map);
    } catch (_) {
      return SafetyConfig.defaults;
    }
  }

  Future<void> setSafetyConfig(SafetyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(config.toJson());
    await prefs.setString(_safetyConfigKey, jsonStr);
  }

  // ──────────────── Agent（AI 工作台智能体，D16/D6）────────────────

  /// Agent 单次运行步数上限（D16）。
  Future<int> getAgentMaxSteps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_agentMaxStepsKey) ?? defaultAgentMaxSteps;
  }

  Future<void> setAgentMaxSteps(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = value.clamp(minAgentMaxSteps, maxAgentMaxSteps);
    await prefs.setInt(_agentMaxStepsKey, clamped);
  }

  /// Agent L0.5 读前分析的行数阈值（D6）。
  Future<int> getAgentL05RowThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_agentL05RowThresholdKey) ??
        defaultAgentL05RowThreshold;
  }

  Future<void> setAgentL05RowThreshold(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = value.clamp(
      minAgentL05RowThreshold,
      maxAgentL05RowThreshold,
    );
    await prefs.setInt(_agentL05RowThresholdKey, clamped);
  }
}
