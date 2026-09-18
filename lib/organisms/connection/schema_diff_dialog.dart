import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';
import 'schema_diff/schema_diff_page.dart';

/// Schema Diff & Sync 主对话框（入口已重构为三栏工作台）
/// 保留静态 show() 方法作为向后兼容的入口点
class SchemaDiffDialog extends StatelessWidget {
  final String? initialConnectionId;
  final String? initialDatabaseName;

  const SchemaDiffDialog({
    super.key,
    this.initialConnectionId,
    this.initialDatabaseName,
  });

  static Future<void> show({
    required BuildContext context,
    String? initialConnectionId,
    String? initialDatabaseName,
  }) {
    AppLogger.d(
      'SchemaDiffDialog',
      'SchemaDiffDialog.show called with connectionId=$initialConnectionId, db=$initialDatabaseName',
    );
    return showDialog(
      context: context,
      builder: (dialogContext) => SchemaDiffDialog(
        initialConnectionId: initialConnectionId,
        initialDatabaseName: initialDatabaseName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      child: Container(
        width: size.width * 0.9,
        height: size.height * 0.9,
        constraints: const BoxConstraints(
          minWidth: 900,
          minHeight: 600,
          maxWidth: 1600,
          maxHeight: 1000,
        ),
        child: SchemaDiffPage(
          initialConnectionId: initialConnectionId,
          initialDatabaseName: initialDatabaseName,
        ),
      ),
    );
  }
}
