import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 用户对关闭单个未保存 Tab 的决定。
enum TabCloseDecision {
  /// 保存后关闭。
  save,

  /// 不保存直接关闭。
  discard,
}

/// 关闭单个未保存查询标签页时的确认对话框。
///
/// 只用于单 Tab 关闭场景；批量关闭（关闭所有/其他/右侧、退出应用）
/// 走 `BulkCloseDialog`，两者文案语义不同，避免「全部保存/全部不保存」
/// 出现在单 Tab 语境中引起误解。
class TabCloseConfirmDialog extends StatelessWidget {
  final String tabTitle;

  const TabCloseConfirmDialog({super.key, required this.tabTitle});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Text(
        l10n?.unsavedChangesTitle ?? 'Unsaved Changes',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Text(
        l10n?.tabCloseConfirmMessage(tabTitle) ??
            'Do you want to save the changes made to "$tabTitle" before closing?',
        style: TextStyle(color: colors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n?.commonCancel ?? 'Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, TabCloseDecision.discard),
          child: Text(
            l10n?.discardChanges ?? 'Discard',
            style: TextStyle(color: colors.error),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, TabCloseDecision.save),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accentBlue,
          ),
          child: Text(l10n?.commonSave ?? 'Save'),
        ),
      ],
    );
  }
}

/// 显示单 Tab 关闭确认对话框。
///
/// 返回用户决定；取消（取消按钮、遮罩点击、Esc）返回 null，调用方应保持 Tab 打开。
Future<TabCloseDecision?> showTabCloseConfirmDialog(
  BuildContext context, {
  required String tabTitle,
}) {
  return showDialog<TabCloseDecision>(
    context: context,
    builder: (_) => TabCloseConfirmDialog(tabTitle: tabTitle),
  );
}
