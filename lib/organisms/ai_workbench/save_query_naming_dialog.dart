//! 保存查询命名对话框（工作台「保存为查询」链路的命名步骤）。
//!
//! 单行命名 + 确认/取消；确认钮空输入禁用（U17 先例
//! `query_editor_widget.dart` `_showSaveQueryNamingDialog` 的组件化提取——
//! 经典实现零改动，本组件为工作台卡动作专用入口）。确认返回去除首尾
//! 空白的名称；取消 / 关闭返回 null，由调用方决定中止。
//!
//! l10n 复用经典侧既有 key（saveQueryTitle / queryName / enterQueryName /
//! saveQueryHint / commonCancel / commonSave），不新增第二套文案。

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

/// 弹出保存查询命名对话框；确认返回去除首尾空白的名称，取消返回 null。
Future<String?> showSaveQueryNamingDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => SaveQueryNamingDialog(initialName: initialName),
  );
}

/// 保存查询命名对话框：标题 + 单行输入（预填 [initialName]）+ 取消/保存。
class SaveQueryNamingDialog extends StatefulWidget {
  const SaveQueryNamingDialog({super.key, required this.initialName});

  /// 输入框预填名（调用方建议的默认名，如 SQL 首行截断）。
  final String initialName;

  /// 名称输入框（测试定位点）。
  static const Key fieldKey = ValueKey('save_query_naming_field');

  /// 确认（保存）按钮。
  static const Key confirmButtonKey = ValueKey('save_query_naming_confirm');

  /// 取消按钮。
  static const Key cancelButtonKey = ValueKey('save_query_naming_cancel');

  @override
  State<SaveQueryNamingDialog> createState() => _SaveQueryNamingDialogState();
}

class _SaveQueryNamingDialogState extends State<SaveQueryNamingDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Text(
        l10n.saveQueryTitle,
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: SaveQueryNamingDialog.fieldKey,
            controller: _nameController,
            autofocus: true,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: l10n.queryName,
              labelStyle: TextStyle(color: colors.textSecondary),
              hintText: l10n.enterQueryName,
              hintStyle: TextStyle(color: colors.textMuted),
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            l10n.saveQueryHint,
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: SaveQueryNamingDialog.cancelButtonKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        // U17 先例：空标题禁用保存——防「点保存对话框直接关闭、保存静默
        // 中止，表现为按钮没反应」。
        ListenableBuilder(
          listenable: _nameController,
          builder: (context, _) {
            final canSave = _nameController.text.trim().isNotEmpty;
            return ElevatedButton(
              key: SaveQueryNamingDialog.confirmButtonKey,
              onPressed: canSave ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentBlue,
              ),
              child: Text(l10n.commonSave),
            );
          },
        ),
      ],
    );
  }
}
