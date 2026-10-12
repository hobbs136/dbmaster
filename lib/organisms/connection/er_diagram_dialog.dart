import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/er_diagram_service.dart';
import 'object_tabs/er_diagram_content.dart';

/// ER 图 dialog 薄壳（T16 J4：body 已提取为 [ErDiagramContent]，本类仅为
/// 保留既有 dialog 公开构造面的兼容壳；主入口已迁主标签栏对象 tab）。
///
/// [erDiagramService] 沿既有构造面保留（历史上未被使用，行为零变化）。
class ERDiagramDialog extends StatelessWidget {
  final ERDiagramService? erDiagramService;
  final String? initialConnectionId;
  final String? initialDatabase;

  const ERDiagramDialog({
    super.key,
    this.erDiagramService,
    this.initialConnectionId,
    this.initialDatabase,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.themeColors.bgPrimary,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 1200,
          minHeight: 800,
          maxWidth: 1600,
          maxHeight: 900,
        ),
        child: ErDiagramContent(
          initialConnectionId: initialConnectionId,
          initialDatabase: initialDatabase,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
