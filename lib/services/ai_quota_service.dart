import 'package:shared_preferences/shared_preferences.dart';

/// AI 月度配额服务
///
/// 由于 AI 请求直接使用用户自配的 API Key 从本机发出，DbMaster 服务端不参与，
/// 因此配额控制为客户端商业限制，非技术防破解手段。
/// Free 用户每月可使用 30 次 AI 助手，Pro 无限制。
class AiQuotaService {
  static const int _freeMonthlyQuota = 30;
  static const String _lastRecordedMonthKey = 'dbmaster_ai_quota_last_month';
  static const String _usageCountKey = 'dbmaster_ai_quota_usage_count';

  final Future<bool> Function() _isPro;

  AiQuotaService({required Future<bool> Function() isPro}) : _isPro = isPro;

  /// Free 用户每月 AI 调用配额
  static int get freeMonthlyQuota => _freeMonthlyQuota;

  /// 当前配额周期内已使用次数
  Future<int> getUsedCount() async {
    await _ensureMonthReset();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_usageCountKey) ?? 0;
  }

  /// 当前配额周期内剩余次数
  Future<int> getRemainingCount() async {
    if (await _isPro()) return -1; // Pro 无限制
    final used = await getUsedCount();
    return (_freeMonthlyQuota - used).clamp(0, _freeMonthlyQuota);
  }

  /// 是否还有可用配额
  Future<bool> hasQuota() async {
    if (await _isPro()) return true;
    final used = await getUsedCount();
    return used < _freeMonthlyQuota;
  }

  /// 记录一次 AI 调用
  Future<void> recordUsage() async {
    if (await _isPro()) return;
    await _ensureMonthReset();
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_usageCountKey) ?? 0;
    await prefs.setInt(_usageCountKey, current + 1);
  }

  /// 检查跨月并重置计数
  Future<void> _ensureMonthReset() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final currentMonthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final storedMonth = prefs.getString(_lastRecordedMonthKey);

    if (storedMonth != currentMonthKey) {
      await prefs.setString(_lastRecordedMonthKey, currentMonthKey);
      await prefs.setInt(_usageCountKey, 0);
    }
  }

  /// 仅用于测试：重置配额
  Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRecordedMonthKey);
    await prefs.remove(_usageCountKey);
  }
}
