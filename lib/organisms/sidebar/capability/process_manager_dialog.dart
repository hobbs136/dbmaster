// C15 · 进程管理对话框 —— 能力菜单「Kill Query / Terminate」项的动作载体。
//
// MySQL 与 PG 的进程数据形状不同（SHOW PROCESSLIST vs pg_stat_activity），
// 但「列表 + 刷新 + 逐行终止（确认 + 结果反馈）」的交互一致——本对话框
// 只做归一化行的渲染与终止流程，数据获取经 loader 注入（插件各自闭包），
// 终止统一走 AppProvider.killProcess（MySQL KILL / PG pg_terminate_backend）。
// 深度进程管理（自动刷新间隔选择器等）仍在树内 Performance/Process List
// 节点，本对话框是能力菜单的直达入口。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';

/// 归一化进程行（loader 侧完成类型映射）。
@immutable
class ProcessListEntry {
  final int id;
  final String user;

  /// MySQL Command / PG state。
  final String command;
  final int timeSeconds;

  /// 完整查询文本（Tooltip 展示；无则 null）。
  final String? info;

  const ProcessListEntry({
    required this.id,
    required this.user,
    required this.command,
    required this.timeSeconds,
    this.info,
  });
}

class ProcessManagerDialog extends StatefulWidget {
  final String connectionId;

  /// 进程列表加载器（插件注入的类型专有查询）。
  final Future<List<ProcessListEntry>> Function(String connectionId) loader;

  /// 终止动作（与树内终止同一路径：AppProvider.killProcess → adapter）。
  final Future<bool> Function(String connectionId, int pid) onKill;

  const ProcessManagerDialog({
    super.key,
    required this.connectionId,
    required this.loader,
    required this.onKill,
  });

  @override
  State<ProcessManagerDialog> createState() => _ProcessManagerDialogState();
}

class _ProcessManagerDialogState extends State<ProcessManagerDialog> {
  List<ProcessListEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.loader(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndKill(ProcessListEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(l10n.processListKillConfirmTitle),
        content: Text(
          l10n.processListKillConfirm(
            '${entry.id}',
            entry.user,
            '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.processListKillQuery),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // killProcess 由插件经 provider 传入（与树内终止同一路径）；此处仅
    // 反馈结果并刷新列表。
    final ok = await widget.onKill(widget.connectionId, entry.id);
    if (!mounted) return;
    final colors = context.themeColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? l10n.commonSuccess : l10n.commonFailed),
        backgroundColor: ok ? colors.accentGreen : colors.error,
      ),
    );
    if (ok) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(
            LucideIcons.list,
            color: context.themeColors.accentBlue,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.processManagerTitle),
          const Spacer(),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 420,
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: context.themeColors.accentBlue,
                ),
              )
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  child: Text(
                    _error!,
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ),
              )
            : (_entries?.isEmpty ?? true)
            ? Center(child: Text(l10n.processListNoProcesses))
            : ListView.builder(
                itemCount: _entries!.length,
                itemBuilder: (_, i) {
                  final e = _entries![i];
                  final isSlow = e.timeSeconds > 5;
                  final timeStr = e.timeSeconds > 60
                      ? '${(e.timeSeconds / 60).floor()}m ${e.timeSeconds % 60}s'
                      : '${e.timeSeconds}s';
                  final label = '[${e.id}] ${e.user} • ${e.command} • $timeStr';
                  return Tooltip(
                    message:
                        (e.info != null && e.info!.isNotEmpty) ? e.info! : label,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Container(
                      color: isSlow
                          ? colors.error.withValues(alpha: 0.08)
                          : null,
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          e.command == 'Sleep' || e.command == 'idle'
                              ? LucideIcons.moon
                              : LucideIcons.chartLine,
                          size: 16,
                          color: isSlow
                              ? colors.error
                              : colors.textSecondary,
                        ),
                        title: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textPrimary,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () => _confirmAndKill(e),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.error,
                          ),
                          child: Text(l10n.processListKillQuery),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
