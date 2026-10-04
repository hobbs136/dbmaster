//! observe 进程列表段（2b.1，MySQL；R2 刷新语义 + R3 零 kill）。
//!
//! 数据源 = `provider.connection.loadProcessList(connectionId)` 拉取 +
//! `getProcessList` 读缓存（connection_provider 既有 facade）；行布局沿
//! 经典面板八列（Id/User/Host/db/Command/Time/State/Info，无表头行）。
//! 差异（对照 mysql_process_panel.dart）：
//! - 行尾 kill 图标列**删除**，改「在经典中管理」escalation 文本按钮
//!   （R3 三连出口，零 kill 进舞台）；
//! - 慢行（Time>5s）语义保留，但只作 error 弱化底色、正文恒
//!   textPrimary/textSecondary（v1 §3.6）。
//!
//! 状态三态：缓存 null = 加载中（首载）/ 空列表 = commonNoData /
//! 加载失败 = workbenchObserveLoadFailed + 重试（重试 = 手动刷新同义）。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';

/// observe 进程列表段（MySQL）。
class WorkbenchObserveProcessListSegment extends StatefulWidget {
  const WorkbenchObserveProcessListSegment({
    super.key,
    required this.connectionId,
    required this.refreshTick,
    required this.onLoaded,
    required this.onManageInClassic,
  });

  /// 锁定连接 id（数据键；变化 = 锁切换，自动拉取一次）。
  final String connectionId;

  /// 手动刷新序号（变化 = 手动刷新，重载一次）。
  final int refreshTick;

  /// 成功加载完成回调（内容壳更新时间戳；失败不回调——R2 锁定）。
  final VoidCallback onLoaded;

  /// 行尾 escalation（R3：内容壳注入「在经典中管理」三连实现）。
  final void Function(String connectionId) onManageInClassic;

  /// 进程表探针。
  static const Key tableKey = ValueKey('workbench_observe_process_list');

  /// 加载失败态探针。
  static const Key errorKey = ValueKey('workbench_observe_process_list_error');

  @override
  State<WorkbenchObserveProcessListSegment> createState() =>
      _WorkbenchObserveProcessListSegmentState();
}

class _WorkbenchObserveProcessListSegmentState
    extends State<WorkbenchObserveProcessListSegment> {
  bool _failed = false;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    // R2：mount 首载自动拉取一次。
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkbenchObserveProcessListSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionId != widget.connectionId) {
      // R1：锁切换 = 打开新观察对象 → 自动拉取一次。
      _load();
    } else if (oldWidget.refreshTick != widget.refreshTick) {
      // R2：此后仅手动刷新。
      _load();
    }
  }

  /// 拉取一次：facade 成功后缓存必非 null（含空列表）——仍为 null 说明
  /// 加载未落缓存（失败兜底）；异常同样记失败（R2：失败不更新时间戳）。
  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() => _failed = false);
    final provider = context.read<AppProvider>();
    var ok = false;
    try {
      await provider.connection.loadProcessList(widget.connectionId);
      final data = provider.connection.getProcessList(widget.connectionId);
      ok = data != null;
    } catch (_) {
      ok = false;
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() => _failed = !ok);
    if (ok) widget.onLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<AppProvider>();
    final data = provider.connection.getProcessList(widget.connectionId);
    if (data == null) {
      // null 缓存 = 加载中（首载）；加载完成后仍 null = 失败。
      return _failed
          ? _buildError(context, l10n)
          : const Center(child: CircularProgressIndicator());
    }
    if (data.isEmpty) {
      return Center(
        child: Text(
          l10n.commonNoData,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeXs,
            color: context.themeColors.textMuted,
          ),
        ),
      );
    }
    return ListView.builder(
      key: WorkbenchObserveProcessListSegment.tableKey,
      itemCount: data.length,
      itemBuilder: (context, index) => _ProcessRow(
        proc: data[index],
        onManageInClassic: () => widget.onManageInClassic(widget.connectionId),
      ),
    );
  }

  Widget _buildError(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Center(
      key: WorkbenchObserveProcessListSegment.errorKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleAlert, size: 24, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space1_5),
          Text(
            l10n.workbenchObserveLoadFailed,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          TextButton(onPressed: _load, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}

/// 进程行：八列（Id/User/Host/db/Command/Time/State/Info）+ escalation
/// 文本按钮；慢行 error 弱化底（v1 §3.6：红只作底色不作正文色）。
class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.proc, required this.onManageInClassic});

  final Map<String, dynamic> proc;
  final VoidCallback onManageInClassic;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final timeRaw = proc['Time'] ?? 0;
    final time = timeRaw is int
        ? timeRaw
        : int.tryParse(timeRaw.toString()) ?? 0;
    final isSlow = time > 5;
    final info = proc['Info']?.toString() ?? '';
    final captionStyle = TextStyle(fontSize: AppDesignSystem.fontSizeXs);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space0_5,
      ),
      color: isSlow ? colors.error.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              proc['Id']?.toString() ?? '?',
              style: captionStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              proc['User']?.toString() ?? '?',
              style: captionStyle.copyWith(color: colors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              proc['Host']?.toString() ?? '',
              style: captionStyle.copyWith(color: colors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              proc['db']?.toString() ?? '',
              style: captionStyle.copyWith(color: colors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 55,
            child: Text(
              proc['Command']?.toString() ?? '?',
              style: captionStyle.copyWith(color: colors.textSecondary),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              _formatTime(time),
              style: captionStyle.copyWith(
                color: colors.textMuted,
                fontWeight: isSlow ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              proc['State']?.toString() ?? '',
              style: captionStyle.copyWith(color: colors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              info.length > 60 ? '${info.substring(0, 60)}...' : info,
              style: captionStyle.copyWith(color: colors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Tooltip(
            message: l10n.workbenchObserveManageInClassic,
            child: TextButton(
              onPressed: onManageInClassic,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.workbenchObserveManageInClassic,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeSm,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    LucideIcons.externalLink,
                    size: 12,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    if (seconds > 60) {
      return '${(seconds / 60).floor()}m ${seconds % 60}s';
    }
    return '${seconds}s';
  }
}
