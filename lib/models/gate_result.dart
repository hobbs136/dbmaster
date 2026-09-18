import 'pro_feature.dart';

/// 统一门禁结果——subsumes 旧 `bool` 返回、`_pendingUpgradeFeature` 副通道（research.md R6）。
sealed class GateResult {
  const GateResult();
}

/// Pro 用户，或已成功消费试用额度——放行。
class Allowed extends GateResult {
  const Allowed();
}

/// 该功能不配置试用（仅 Pro 可用）。
class ProOnly extends GateResult {
  const ProOnly(this.feature);
  final ProFeature feature;
}

/// Free 用户可试用，[remaining] 为剩余次数。
class TrialAvailable extends GateResult {
  const TrialAvailable(this.feature, this.remaining);
  final ProFeature feature;
  final int remaining;
}

/// 试用额度用尽——触发升级提示。
class QuotaExhausted extends GateResult {
  const QuotaExhausted(this.feature);
  final ProFeature feature;
}

/// 连接 / Tab 等硬性上限（保留旧 `bool` 语义）。
class HardCap extends GateResult {
  const HardCap(this.capName);
  final String capName;
}
