import 'package:flutter/material.dart';

import '../../services/ai/ai_client.dart';
import '../../services/database_abstract.dart';

/// 数据导入向导（Smart Import）接入点（open-core Phase B.2 UI SPI，ADR 0001）。
///
/// OSS 仓不持有 [ImportWizardDialog] / [SmartImportService]（Pro 专属，待
/// Phase B.3 迁出 `lib/`）。侧栏表节点「Smart Import」与查询编辑器
/// 「Import」入口经此 SPI 委托——OSS 注入 [NoOpProImportUi]（no-op），
/// Pro 仓注入真实实现弹出 [ImportWizardDialog]。
///
/// 放 UI 层（非 Provider 层）：接收 [BuildContext]，故 import material；
/// 不进 `lib/services/pro_module.dart`（后者须保持 foundation-pure）。
/// 镜像 [ProPurchaseUi] 的注入模式（DbmasterApp ctor + Provider.value）。
abstract class ProImportUi {
  const ProImportUi();

  /// 打开智能导入向导。参数镜像 [ImportWizardDialog] 构造函数——
  /// `connectionId` / `initialDatabase` 沿用可空签名（调用方可能无活动 tab）。
  /// OSS NoOp 不做任何事（用户操作入口已由 `tryDataImport` 门禁先行拦截）。
  Future<void> openImportWizard(
    BuildContext context, {
    String? connectionId,
    String? initialDatabase,
    required DatabaseAdapter adapter,
    required AiClient aiClient,
  });
}

/// OSS 默认实现：导入向导 no-op（Pro 专属功能不在 OSS 渲染）。
class NoOpProImportUi extends ProImportUi {
  const NoOpProImportUi();

  @override
  Future<void> openImportWizard(
    BuildContext context, {
    String? connectionId,
    String? initialDatabase,
    required DatabaseAdapter adapter,
    required AiClient aiClient,
  }) async {
    // OSS 无 Import Wizard UI——静默 no-op。
  }
}
