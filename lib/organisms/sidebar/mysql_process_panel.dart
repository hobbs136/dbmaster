// T013 — MysqlProcessPanel: collapsible bottom panel for process list
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/context_menu.dart';
import '../../theme/app_colors.dart';

class MysqlProcessPanel extends StatefulWidget {
  final String connectionId;

  const MysqlProcessPanel({super.key, required this.connectionId});

  @override
  State<MysqlProcessPanel> createState() => _MysqlProcessPanelState();
}

class _MysqlProcessPanelState extends State<MysqlProcessPanel> {
  // plan §3.2：默认折叠——底部面板不默认挤压 Sidebar Tree 空间，用户按需展开
  bool _isExpanded = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final processes = provider.getProcessList(widget.connectionId);
        final count = processes?.length ?? 0;
        final currentInterval = provider.getProcessListAutoRefreshInterval(
          widget.connectionId,
        );

        return Container(
          // plan §3.2：固定最大高度 160px，避免展开时过度挤压上方 Tree
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            border: Border(
              top: BorderSide(color: AppDesignSystem.divider, width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              GestureDetector(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space2,
                    vertical: AppDesignSystem.space1,
                  ),
                  color: colors.bgSecondary,
                  child: Row(
                    children: [
                      Icon(
                        _isExpanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight,
                        size: 14,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: AppDesignSystem.space1),
                      Icon(
                        LucideIcons.chartLine,
                        size: 14,
                        color: context.themeColors.accentBlue,
                      ),
                      const SizedBox(width: AppDesignSystem.space1_5),
                      Text(
                        '${l10n.processListAutoRefresh}: $count',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: AppDesignSystem.fontWeightMedium,
                          color: colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Auto-refresh toggle buttons with active state
                      _RefreshIntervalButton(
                        label: '5s',
                        isActive: currentInterval == 5,
                        onTap: () => provider.startProcessListAutoRefresh(
                          widget.connectionId,
                          interval: const Duration(seconds: 5),
                        ),
                      ),
                      const SizedBox(width: 2),
                      _RefreshIntervalButton(
                        label: '10s',
                        isActive: currentInterval == 10,
                        onTap: () => provider.startProcessListAutoRefresh(
                          widget.connectionId,
                          interval: const Duration(seconds: 10),
                        ),
                      ),
                      const SizedBox(width: 2),
                      _RefreshIntervalButton(
                        label: '30s',
                        isActive: currentInterval == 30,
                        onTap: () => provider.startProcessListAutoRefresh(
                          widget.connectionId,
                          interval: const Duration(seconds: 30),
                        ),
                      ),
                      const SizedBox(width: 2),
                      _RefreshIntervalButton(
                        label: 'Off',
                        isActive: currentInterval == null,
                        onTap: () => provider.stopProcessListAutoRefresh(
                          widget.connectionId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Process table (scrollable)
              if (_isExpanded && processes != null && processes.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: processes.length,
                    itemBuilder: (context, index) {
                      final proc = processes[index];
                      return _ProcessRow(
                        proc: proc,
                        onKill: () => _killProcess(context, proc, provider),
                      );
                    },
                  ),
                )
              else if (_isExpanded && (processes == null || processes.isEmpty))
                Padding(
                  padding: const EdgeInsets.all(AppDesignSystem.space2),
                  child: Text(
                    processes == null
                        ? 'Loading...'
                        : l10n.processListNoProcesses,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _killProcess(
    BuildContext ctx,
    Map<String, dynamic> proc,
    AppProvider provider,
  ) {
    final l10n = AppLocalizations.of(ctx)!;
    final idStr = proc['Id']?.toString() ?? '?';
    final pid = int.tryParse(idStr) ?? 0;
    if (pid == 0) return;

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ctx.themeColors.bgSecondary,
        title: Text(l10n.processListKillConfirmTitle),
        content: Text(
          l10n.processListKillConfirm(
            idStr,
            proc['User']?.toString() ?? '?',
            proc['Host']?.toString() ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx);
              provider.killProcess(widget.connectionId, pid);
            },
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.processListKillQuery),
          ),
        ],
      ),
    );
  }
}

class _RefreshIntervalButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _RefreshIntervalButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: isActive
              ? context.themeColors.accentBlue.withValues(alpha: 0.15)
              : colors.textMuted.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: isActive
              ? Border.all(
                  color: context.themeColors.accentBlue.withValues(alpha: 0.5),
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive ? context.themeColors.accentBlue : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  final Map<String, dynamic> proc;
  final VoidCallback onKill;

  const _ProcessRow({required this.proc, required this.onKill});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final timeRaw = proc['Time'] ?? 0;
    final time = timeRaw is int
        ? timeRaw
        : int.tryParse(timeRaw.toString()) ?? 0;
    final isSlow = time > 5;
    final info = proc['Info']?.toString();

    // T016/T019/FR-004/FR-007 — right-click context menu on process row
    return ContextMenuUtils.gestureDetector(
      itemsBuilder: () => _buildProcessItems(context),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space0_5,
        ),
        color: isSlow
            ? context.themeColors.error.withValues(alpha: 0.06)
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                proc['Id']?.toString() ?? '?',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                proc['User']?.toString() ?? '?',
                style: AppTextStyles.caption.copyWith(
                  color: isSlow
                      ? context.themeColors.error
                      : colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                proc['Host']?.toString() ?? '',
                style: AppTextStyles.caption.copyWith(color: colors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                proc['db']?.toString() ?? '',
                style: AppTextStyles.caption.copyWith(color: colors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 55,
              child: Text(
                proc['Command']?.toString() ?? '?',
                style: AppTextStyles.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                _formatTime(time),
                style: AppTextStyles.caption.copyWith(
                  color: isSlow ? context.themeColors.error : colors.textMuted,
                  fontWeight: isSlow ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                proc['State']?.toString() ?? '',
                style: AppTextStyles.caption.copyWith(color: colors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(
                (info != null && info.isNotEmpty)
                    ? (info.length > 60 ? '${info.substring(0, 60)}...' : info)
                    : '',
                style: AppTextStyles.caption.copyWith(color: colors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onKill,
              child: Icon(
                LucideIcons.circleStop,
                size: 14,
                color: context.themeColors.error,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // T016/T019/FR-004/FR-007 — process row context menu items
  List<ContextMenuItem> _buildProcessItems(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final info = proc['Info']?.toString();
    final hasQuery = info != null && info.isNotEmpty;
    return [
      ContextMenuItem(
        id: 'copy_query',
        label: l10n.processListCopyQuery,
        icon: LucideIcons.copy,
        enabled: hasQuery,
        disabledReason: hasQuery ? null : l10n.processListNoQueryText,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: info ?? ''));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.sqlCopied),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'kill',
        label: l10n.processListKillQuery,
        icon: LucideIcons.circleStop,
        isDestructive: true,
        onTap: onKill,
      ),
    ];
  }

  String _formatTime(int seconds) {
    if (seconds > 60) return '${(seconds / 60).floor()}m ${seconds % 60}s';
    return '${seconds}s';
  }
}
