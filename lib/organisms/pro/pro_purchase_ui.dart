// 全免费客户端——ProPurchaseUi 降级为 NoOp 桩，所有方法为 no-op。
// 原购买对话框/订阅 UI/升级提示已移除。保留 SPI 接口以维持 main.dart 中
// Provider<ProPurchaseUi>.value() 注入链编译兼容。
import 'package:flutter/widgets.dart';

/// Pro 购买 UI 扩展点（全免费客户端——所有方法为 no-op）。
///
/// 该 SPI 保留以维持 AppProvider / DbmasterApp 构造函数的编译兼容性，
/// 但所有 UI 触发点（showUpgradeDialog、buildSubscriptionSection 等）均无操作。
abstract class ProPurchaseUi {
  const ProPurchaseUi();

  /// 显示升级至 Pro 的对话框——全免费客户端为 no-op。
  void showUpgradeDialog(BuildContext context) {}

  /// 构建订阅区块——全免费客户端返回 null（不显示）。
  Widget? buildSubscriptionSection(BuildContext context) => null;
}

/// 全免费客户端的默认 [ProPurchaseUi] 实现——所有方法均为 no-op。
class NoOpProPurchaseUi extends ProPurchaseUi {
  const NoOpProPurchaseUi();
}
