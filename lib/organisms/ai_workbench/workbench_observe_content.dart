//! observe tab 内容壳（2b.1，裁决 R1/R2/R3/R13）。
//!
//! - R1 单例跟随锁定连接：内容每次 build 从
//!   [effectiveWorkbenchContext] 派生 connectionId（连接快照不进 tab
//!   数据）；锁切换 = 段导航按新引擎重建 + 各段自动拉取一次（语义 =
//!   打开新观察对象），同一锁内刷新必须手动。
//! - R2 手动刷新 + 「最后更新于」时间戳恒显：零 Timer/零轮询；时间戳 =
//!   最近一次**成功**加载完成时刻（tab 级单值，各段 onLoaded 回调更新）；
//!   未加载过 = 「尚未加载」占位；加载失败时间戳不更新。
//! - R3 进程行尾 escalation「在经典中管理」：setAiPanelFullscreen(false)
//!   + switchToConnection + requestSidebarExpand('$id:performance') 三连
//!   （零 kill 进舞台）。
//! - R13 引擎分段：mysql → [进程列表 | 引擎状态]；redis → [内存分析]；
//!   其它引擎 → 「该引擎暂无观察段」空态。
//!
//! 布局 = 顶行（段标题 + refreshCw 手动刷新钮 + 时间戳恒显）+
//! Row[左段导航 | Expanded(右内容)]；左列语汇沿设置对话框左导航
//! （icon 14 + label 12，选中 accent-subtle 底 + 3px 左描边，宽 176）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart' show DatabaseType;
import '../../providers/app_provider.dart';
import '../../services/ai/workbench_context_resolver.dart';
import '../../theme/app_colors.dart';
import 'workbench_observe_engine_status_segment.dart';
import 'workbench_observe_process_list_segment.dart';
import 'workbench_observe_redis_segment.dart';

/// observe tab 内容壳（2b.1）。
class WorkbenchObserveContent extends StatefulWidget {
  const WorkbenchObserveContent({super.key, this.onManageInClassic});

  /// 进程行 escalation 出口（测试注入用；null = 内置 R3 三连实现）。
  /// 注入后测试可断言收到正确 connectionId 而不真执行切换。
  final void Function(String connectionId)? onManageInClassic;

  /// 手动刷新按钮探针。
  static const Key refreshButtonKey = ValueKey('workbench_observe_refresh');

  /// 时间戳文本探针。
  static const Key timestampKey = ValueKey('workbench_observe_timestamp');

  /// 未锁定连接空态探针。
  static const Key noConnectionKey = ValueKey(
    'workbench_observe_no_connection',
  );

  /// 引擎不支持空态探针。
  static const Key unsupportedKey = ValueKey('workbench_observe_unsupported');

  @override
  State<WorkbenchObserveContent> createState() =>
      _WorkbenchObserveContentState();
}

/// 段描述（左导航条目 + 内容槽路由）。
class _ObserveSegment {
  const _ObserveSegment({
    required this.id,
    required this.icon,
    required this.labelOf,
  });

  /// 段 id（内容槽 switch 路由 + 导航条目探针 key）。
  final String id;

  /// 左导航图标（子集内：server / database / chartPie）。
  final IconData icon;

  /// 段标题（l10n 解包后取文案）。
  final String Function(AppLocalizations l10n) labelOf;
}

class _WorkbenchObserveContentState extends State<WorkbenchObserveContent> {
  /// 激活段下标（锁切换归零）。
  int _activeSegment = 0;

  /// 手动刷新序号（R2：此后仅手动刷新——只有本值变化才触发段重载）。
  int _refreshTick = 0;

  /// 最近一次成功加载完成时刻（R2：tab 级单值；null = 尚未加载过）。
  DateTime? _lastUpdatedAt;

  /// 上次 build 派生的 connectionId（锁切换检测锚）。
  String? _lastConnectionId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    // R1：每次 build 从生效上下文派生（锁定快照优先，否则跟随解析）。
    final ctx = effectiveWorkbenchContext(
      provider.aiPanel.sessionManager.currentSession,
      provider,
    );
    final String? connectionId = ctx.connectionId;

    // 锁切换 = 打开新观察对象（R1）：激活段归零 + 时间戳回到「尚未加载」
    //（新对象未加载过；各段 didUpdateWidget 见 connectionId 变化自动拉取
    // 一次）。build 内直改状态字段（本帧即生效，无需 setState 触发本轮）。
    if (connectionId != _lastConnectionId) {
      _lastConnectionId = connectionId;
      _activeSegment = 0;
      _lastUpdatedAt = null;
    }

    if (connectionId == null) {
      return _buildEmptyState(
        key: WorkbenchObserveContent.noConnectionKey,
        icon: LucideIcons.activity,
        title: l10n.workbenchObserveNoConnection,
        hint: l10n.workbenchObserveNoConnectionHint,
        colors: colors,
      );
    }

    final segments = _segmentsFor(_engineOf(provider, connectionId));
    if (segments.isEmpty) {
      return _buildEmptyState(
        key: WorkbenchObserveContent.unsupportedKey,
        icon: LucideIcons.activity,
        title: l10n.workbenchObserveUnsupportedEngine,
        hint: null,
        colors: colors,
      );
    }

    final activeIndex = _activeSegment.clamp(0, segments.length - 1);
    final active = segments[activeIndex];
    final timestamp = _lastUpdatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(l10n, colors, active, timestamp),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 176,
                child: _buildNav(context, segments, activeIndex),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colors.dividerColor,
              ),
              Expanded(
                child: IndexedStack(
                  index: activeIndex,
                  children: [
                    for (final segment in segments)
                      _buildSegmentContent(context, segment, connectionId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 锁定连接引擎类型（savedConnections 解析；未登记 = null → 空态）。
  DatabaseType? _engineOf(AppProvider provider, String connectionId) {
    for (final server in provider.savedConnections) {
      if (server.id == connectionId) return server.type;
    }
    return null;
  }

  /// 段派生（R13）：mysql → 进程列表/引擎状态；redis → 内存分析；
  /// 其它 → 空态（3.1 扩展位）。
  List<_ObserveSegment> _segmentsFor(DatabaseType? type) {
    switch (type) {
      case DatabaseType.mysql:
        return [
          _ObserveSegment(
            id: 'processList',
            icon: LucideIcons.server,
            labelOf: (l10n) => l10n.workbenchObserveSegmentProcessList,
          ),
          _ObserveSegment(
            id: 'engineStatus',
            icon: LucideIcons.database,
            labelOf: (l10n) => l10n.workbenchObserveSegmentEngineStatus,
          ),
        ];
      case DatabaseType.redis:
        return [
          _ObserveSegment(
            id: 'memory',
            icon: LucideIcons.chartPie,
            labelOf: (l10n) => l10n.workbenchObserveSegmentMemory,
          ),
        ];
      default:
        return const <_ObserveSegment>[];
    }
  }

  /// 顶行：段图标 + 段标题 + 手动刷新钮 + 时间戳恒显。
  Widget _buildHeader(
    AppLocalizations l10n,
    ThemeColors colors,
    _ObserveSegment active,
    DateTime? timestamp,
  ) {
    return Row(
      children: [
        Icon(active.icon, size: 14, color: colors.textSecondary),
        const SizedBox(width: AppDesignSystem.space1_5),
        Expanded(
          child: Text(
            active.labelOf(l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              fontWeight: AppDesignSystem.fontWeightMedium,
              color: colors.textPrimary,
            ),
          ),
        ),
        IconButton(
          key: WorkbenchObserveContent.refreshButtonKey,
          icon: const Icon(LucideIcons.refreshCw, size: 14),
          tooltip: l10n.workbenchObserveRefresh,
          color: colors.textSecondary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          onPressed: _refresh,
        ),
        const SizedBox(width: AppDesignSystem.space1),
        Text(
          timestamp != null
              ? l10n.workbenchObserveLastUpdated(_formatTime(timestamp))
              : l10n.workbenchObserveNotLoaded,
          key: WorkbenchObserveContent.timestampKey,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeXs,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  /// 左段导航（语汇沿设置对话框左导航：icon 14 + label 12、选中
  /// accent-subtle 底 + 3px 左描边）。
  Widget _buildNav(
    BuildContext context,
    List<_ObserveSegment> segments,
    int activeIndex,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < segments.length; i++)
            _buildNavItem(
              l10n,
              segments[i],
              selected: i == activeIndex,
              onTap: () => setState(() => _activeSegment = i),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    AppLocalizations l10n,
    _ObserveSegment segment, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.themeColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        key: ValueKey('workbench_observe_segment_${segment.id}'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentBlue.withValues(alpha: 0.10) : null,
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected ? colors.accentBlue : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              segment.icon,
              size: 14,
              color: selected ? colors.accentBlue : colors.textSecondary,
            ),
            const SizedBox(width: AppDesignSystem.space2_5),
            Expanded(
              child: Text(
                segment.labelOf(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  fontWeight: selected
                      ? AppDesignSystem.fontWeightMedium
                      : FontWeight.w400,
                  color: selected ? colors.accentBlue : colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 段内容槽（各段独立加载生命周期；refreshTick 变化 = 手动刷新重载）。
  Widget _buildSegmentContent(
    BuildContext context,
    _ObserveSegment segment,
    String connectionId,
  ) {
    switch (segment.id) {
      case 'processList':
        return WorkbenchObserveProcessListSegment(
          connectionId: connectionId,
          refreshTick: _refreshTick,
          onLoaded: _onSegmentLoaded,
          onManageInClassic: widget.onManageInClassic ?? _handleManageInClassic,
        );
      case 'engineStatus':
        return WorkbenchObserveEngineStatusSegment(
          connectionId: connectionId,
          refreshTick: _refreshTick,
          onLoaded: _onSegmentLoaded,
        );
      case 'memory':
        return WorkbenchObserveRedisSegment(
          connectionId: connectionId,
          refreshTick: _refreshTick,
          onLoaded: _onSegmentLoaded,
        );
      default:
        // 防御：段表新增 id 未接槽时显示空态而非崩溃（本文件与段表同源
        // 维护，理论上不可达）。
        return const SizedBox.shrink();
    }
  }

  /// 空态（未锁 / 不支持两态共用）：图标 + 标题 + 可选 hint，**无按钮**
  /// （零写手势，引导入口在上下文芯片/picker 既有位置）。
  Widget _buildEmptyState({
    required Key key,
    required IconData icon,
    required String title,
    required String? hint,
    required ThemeColors colors,
  }) {
    return Center(
      key: key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textSecondary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 手动刷新（R2：此后仅手动刷新——本值只经按钮变化）。
  void _refresh() {
    setState(() => _refreshTick++);
  }

  /// 任一段成功加载完成 → 更新时间戳（R2：失败不更新，锁定）。
  void _onSegmentLoaded() {
    setState(() => _lastUpdatedAt = DateTime.now());
  }

  /// 内置 escalation（R3 三连）：退出工作台回经典 → 锚定连接 →
  /// 请求展开经典进程面板挂载键（`'$id:performance'`）。回调体内
  /// [context.read] 一次，异步 switchToConnection 以 unawaited 包装。
  void _handleManageInClassic(String connectionId) {
    final provider = context.read<AppProvider>();
    provider.aiPanel.setAiPanelFullscreen(false);
    final Future<bool> anchored = provider.switchToConnection(connectionId);
    provider.sidebar.requestSidebarExpand('$connectionId:performance');
    unawaited(anchored);
  }

  /// 时间戳显示格式（HH:mm:ss 本地时，R2 语义不变）。
  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
