import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bulk_close_controller.dart';
import '../providers/tab_provider.dart' show QueryTab;
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// 批量关闭对话框的返回结果。
class BulkCloseResult {
  /// 用户是否确认了操作（false 表示取消）。
  final bool confirmed;

  /// tabId -> 决定。仅在 [confirmed] 为 true 时有效。
  final Map<String, BulkCloseDecision> decisions;

  const BulkCloseResult({required this.confirmed, this.decisions = const {}});

  static const BulkCloseResult cancelled = BulkCloseResult(confirmed: false);
}

/// 当存在未保存的查询标签页时，用于一次性确认多个标签页关闭的汇总对话框。
///
/// 调用方通过 [showBulkCloseDialog] 显示，并根据返回的 [BulkCloseResult]
/// 执行实际的保存/关闭操作。
class BulkCloseDialog extends StatelessWidget {
  final List<QueryTab> tabs;

  const BulkCloseDialog({super.key, required this.tabs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;

    return ChangeNotifierProvider(
      create: (_) => BulkCloseController(tabs),
      child: AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Text(
          l10n?.bulkCloseDialogTitle ?? 'Unsaved Changes',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.bulkCloseDialogMessage ??
                    'Some tabs have unsaved changes.',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Consumer<BulkCloseController>(
                  builder: (context, controller, _) {
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: controller.items.length * 2 - 1,
                      itemBuilder: (context, index) {
                        if (index.isOdd) return const Divider(height: 1);
                        final item = controller.items[index ~/ 2];
                        return _TabListItem(item: item);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, BulkCloseResult.cancelled),
            child: Text(l10n?.commonCancel ?? 'Cancel'),
          ),
          Consumer<BulkCloseController>(
            builder: (context, controller, _) {
              return TextButton(
                onPressed: () {
                  controller.discardAllPending();
                  Navigator.pop(
                    context,
                    _buildResult(controller, BulkCloseDecision.discard),
                  );
                },
                child: Text(
                  l10n?.bulkCloseDiscardAll ?? 'Discard All',
                  style: TextStyle(color: context.themeColors.error),
                ),
              );
            },
          ),
          Consumer<BulkCloseController>(
            builder: (context, controller, _) {
              return TextButton(
                onPressed: () {
                  controller.saveAllPending();
                  Navigator.pop(
                    context,
                    _buildResult(controller, BulkCloseDecision.save),
                  );
                },
                child: Text(l10n?.bulkCloseSaveAll ?? 'Save All'),
              );
            },
          ),
        ],
      ),
    );
  }

  BulkCloseResult _buildResult(
    BulkCloseController controller,
    BulkCloseDecision defaultDecision,
  ) {
    final decisions = <String, BulkCloseDecision>{};
    for (final item in controller.items) {
      decisions[item.tab.id] =
          item.isPending ? defaultDecision : item.decision;
    }
    return BulkCloseResult(confirmed: true, decisions: decisions);
  }
}

class _TabListItem extends StatelessWidget {
  final BulkCloseItem item;

  const _TabListItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;
    final snippet = _buildSnippet(item.tab.sql);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        item.tab.title,
        style: TextStyle(color: colors.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: snippet.isNotEmpty
          ? Text(
              snippet,
              style: TextStyle(color: colors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DecisionChip(
            label: l10n?.bulkCloseDecisionSave ?? 'Save',
            isSelected: item.isSave,
            onTap: () {
              context.read<BulkCloseController>().setDecision(
                    item.tab,
                    BulkCloseDecision.save,
                  );
            },
          ),
          const SizedBox(width: 8),
          _DecisionChip(
            label: l10n?.bulkCloseDecisionDiscard ?? 'Discard',
            isSelected: item.isDiscard,
            onTap: () {
              context.read<BulkCloseController>().setDecision(
                    item.tab,
                    BulkCloseDecision.discard,
                  );
            },
          ),
        ],
      ),
    );
  }

  String _buildSnippet(String sql) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return '';
    const maxLength = 60;
    return trimmed.length > maxLength
        ? '${trimmed.substring(0, maxLength)}...'
        : trimmed;
  }
}

class _DecisionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DecisionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Material(
      color: isSelected ? colors.accentBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// 显示批量关闭确认对话框。
///
/// 返回 [BulkCloseResult]；调用方应根据其中的决定执行实际的保存/关闭操作。
Future<BulkCloseResult> showBulkCloseDialog(
  BuildContext context, {
  required List<QueryTab> tabs,
}) async {
  return await showDialog<BulkCloseResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BulkCloseDialog(tabs: tabs),
      ) ??
      BulkCloseResult.cancelled;
}
