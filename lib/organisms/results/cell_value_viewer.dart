import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// 只读单元格查看器（双击数据单元格打开）。
///
/// 网格写回已按用户拍板下线（2026-08-24，恢复 U07 语义），但长文本需要
/// 一个查看入口——本对话框提供完整内容查看（可选择/滚动）+ 复制，
/// 不产生任何「假保存」错觉（只读，无编辑态）。
void showCellValueViewer(
  BuildContext context, {
  required String columnName,
  required dynamic value,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => CellValueViewer(columnName: columnName, value: value),
  );
}

class CellValueViewer extends StatelessWidget {
  final String columnName;
  final dynamic value;

  const CellValueViewer({
    super.key,
    required this.columnName,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final isNull = value == null;
    final text = isNull ? '' : value.toString();

    return Dialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        side: BorderSide(color: colors.borderColor),
      ),
      child: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部：列名 + 字符计数 + 关闭 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesignSystem.space3,
                AppDesignSystem.space2,
                AppDesignSystem.space2,
                AppDesignSystem.space2,
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.textCursorInput,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Flexible(
                    child: Text(
                      columnName,
                      style: AppTextStyles.h3.copyWith(
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isNull) ...[
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      l10n.cellViewerChars(text.length),
                      style: AppTextStyles.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.borderColor),

            // ── 内容：完整值（可选择/滚动）；NULL 占位 ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppDesignSystem.space3),
                child: isNull
                    ? Center(
                        child: Text(
                          'NULL',
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: colors.textMuted,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: SizedBox(
                          width: double.infinity,
                          child: SelectableText(
                            text,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              fontFamily: AppDesignSystem.monoFontFamily,
                              fontFamilyFallback:
                                  AppDesignSystem.monoFontFamilyFallback,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
              ),
            ),

            // ── footer：复制 + 关闭 ──
            Divider(height: 1, color: colors.borderColor),
            Padding(
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: isNull
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.copiedToClipboard),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                    icon: const Icon(LucideIcons.copy, size: 14),
                    label: Text(l10n.cellViewerCopy),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
