import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../atoms/app_loading.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// 危险确认对话框的语气（决定图标/影响容器/确认钮的语义色）。
enum DestructiveTone { error, warning }

/// 危险确认对话框（契约 C3）——所有破坏性操作确认的唯一外壳。
///
/// 结构：语义色图标 + 标题 → 影响说明容器（语义色 10% 底）→ 按钮区
/// （Cancel 左 / 语义色确认钮右，确认钮为 [LoadingButton]）。
///
/// 纯 UI 组件，不负责任何数据查询：执行前影响（行数、依赖数）由调用方
/// 查好后经 [impactDescription] / [extraContent] 传入。
class DestructiveConfirmDialog extends StatefulWidget {
  /// 标题左侧的语义色图标。
  final IconData icon;

  /// 对话框标题。
  final String title;

  /// 影响说明容器上方的补充说明文案（可选）。
  final String? body;

  /// 影响说明文案；为 null 时不渲染影响说明容器。
  final String? impactDescription;

  /// 语气：决定图标、影响容器与确认钮使用 error 还是 warning 语义色。
  final DestructiveTone impactTone;

  /// 确认钮文案。
  final String confirmLabel;

  /// 确认回调（通常负责 pop 并携带结果）。
  final VoidCallback onConfirm;

  /// 要求用户输入匹配的文本后才解禁确认钮（大小写不敏感）；null 表示不需要。
  final String? requireTypedConfirmation;

  /// 影响说明容器下方的自定义内容插槽（如依赖警告、SQL 预览）。
  final Widget? extraContent;

  /// 内容区固定宽度（可选，用于宽内容如 SQL 预览）。
  final double? contentWidth;

  const DestructiveConfirmDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.impactTone,
    required this.confirmLabel,
    required this.onConfirm,
    this.body,
    this.impactDescription,
    this.requireTypedConfirmation,
    this.extraContent,
    this.contentWidth,
  });

  @override
  State<DestructiveConfirmDialog> createState() =>
      _DestructiveConfirmDialogState();
}

class _DestructiveConfirmDialogState extends State<DestructiveConfirmDialog> {
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Color _toneColor(BuildContext context) {
    return widget.impactTone == DestructiveTone.error
        ? context.themeColors.error
        : context.themeColors.warning;
  }

  bool get _typedConfirmed {
    final expected = widget.requireTypedConfirmation;
    if (expected == null) return true;
    return _confirmController.text.trim().toLowerCase() ==
        expected.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tone = _toneColor(context);

    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(widget.icon, color: tone),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: widget.contentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.body != null) ...[
                Text(
                  widget.body ?? '',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
              ],
              if (widget.impactDescription != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.info, size: 16, color: tone),
                      const SizedBox(width: AppDesignSystem.space2),
                      Expanded(
                        child: SelectableText(
                          widget.impactDescription ?? '',
                          style: TextStyle(
                            color: tone.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.extraContent != null) ...[
                const SizedBox(height: AppDesignSystem.space3),
                widget.extraContent ?? const SizedBox.shrink(),
              ],
              if (widget.requireTypedConfirmation != null) ...[
                const SizedBox(height: AppDesignSystem.space3),
                Text(
                  l10n?.ddlTypeToConfirmDestructive(
                        widget.requireTypedConfirmation ?? '',
                      ) ??
                      'Type "${widget.requireTypedConfirmation}" to confirm',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                TextField(
                  controller: _confirmController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: widget.requireTypedConfirmation,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n?.commonCancel ?? 'Cancel'),
        ),
        LoadingButton(
          label: widget.confirmLabel,
          onPressed: _typedConfirmed ? widget.onConfirm : null,
          backgroundColor: tone,
        ),
      ],
    );
  }
}
