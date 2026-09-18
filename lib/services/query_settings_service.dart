import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dml_risk_models.dart';

/// 查询设置服务
/// 管理自动 LIMIT、安全配置等查询相关设置
class QuerySettingsService {
  static const String _autoLimitEnabledKey = 'query_auto_limit_enabled';
  static const String _autoLimitValueKey = 'query_auto_limit_value';
  static const String _safetyConfigKey = 'safety_config';

  static const bool defaultAutoLimitEnabled = true;
  static const int defaultAutoLimitValue = 3000;
  static const int minAutoLimitValue = 100;
  static const int maxAutoLimitValue = 100000;

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
}
