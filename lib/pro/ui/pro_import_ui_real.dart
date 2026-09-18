import 'package:flutter/material.dart';

import 'package:dbmaster/organisms/pro/pro_import_ui.dart';
import 'package:dbmaster/pro/data_import/import_wizard_dialog.dart';
import 'package:dbmaster/services/ai/ai_client.dart';
import 'package:dbmaster/services/database_abstract.dart';

/// [ProImportUi] 的 Pro 实现（open-core B.2）。
///
/// 直接转发到 [ImportWizardDialog]——`lib/pro/data_import/` 全部依赖
/// （[SmartImportService] / [FileAnalyzer] / [DataGenerationService]）
/// 已在 B.1 阶段随导入功能迁入 Pro 仓，故此处仅是 showDialog 胶合。
class RealProImportUi extends ProImportUi {
  const RealProImportUi();

  @override
  Future<void> openImportWizard(
    BuildContext context, {
    String? connectionId,
    String? initialDatabase,
    required DatabaseAdapter adapter,
    required AiClient aiClient,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ImportWizardDialog(
        initialConnectionId: connectionId,
        initialDatabase: initialDatabase,
        adapter: adapter,
        aiClient: aiClient,
      ),
    );
  }
}
