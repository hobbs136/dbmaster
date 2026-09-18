import 'package:flutter/material.dart';

/// 数据同步（Data Sync）对话框接入点（open-core Phase B.2 UI SPI，ADR 0001）。
///
/// OSS 仓不持有 [DataSyncDialog] / [DataSyncService]（Pro 专属，待 Phase B.3
/// 迁出 `lib/`）。侧栏「Data Sync」右键菜单经此 SPI 委托——OSS 注入
/// [NoOpProSyncUi]（no-op），Pro 仓注入真实实现打开 [DataSyncDialog]。
///
/// 放 UI 层（非 Provider 层）：接收 [BuildContext]，故 import material；
/// 不进 `lib/services/pro_module.dart`（后者须保持 foundation-pure）。
/// 镜像 [ProPurchaseUi] 的注入模式（DbmasterApp ctor + Provider.value）。
abstract class ProSyncUi {
  const ProSyncUi();

  /// 打开数据同步对话框。OSS NoOp 不做任何事（用户操作入口已由
  /// `tryDataSync` 门禁先行拦截，NoOp 仅作兜底）。
  Future<void> openDataSyncDialog(
    BuildContext context, {
    required String connectionId,
    required String database,
    required String table,
  });
}

/// OSS 默认实现：数据同步对话框 no-op（Pro 专属功能不在 OSS 渲染）。
class NoOpProSyncUi extends ProSyncUi {
  const NoOpProSyncUi();

  @override
  Future<void> openDataSyncDialog(
    BuildContext context, {
    required String connectionId,
    required String database,
    required String table,
  }) async {
    // OSS 无 Data Sync UI——静默 no-op。
  }
}
