// C15 · MySQL 侧边栏插件 —— 首个 per-type SidebarPlugin。
//
// 树装配：连接级全局节点（Server / Performance / Users，自
// builders/mysql_tree_builder.dart 整体迁入）；库级对象子树仍走
// sidebar_tree 通用 SQL 装配（generic 路径服务多类型，C19 统一收编），
// 故 buildDatabaseTree 恒空 = 宿主回退。
//
// 能力菜单（capabilityGroups）：与 core 插件同组 id 合并（'advanced'），
// 补 MySQL 专有入口——Kill Query（进程管理对话框）/ Engine Status。
// 能力位一律经 port 门控（engine.status / process.kill 均为 mysql 位），
// 本文件不写 DatabaseType 能力分支。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../molecules/context_menu.dart';
import '../../../models/database_models.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../builders/tree_utils.dart';
import '../capability/capability_menu_assembly.dart';
import '../capability/process_manager_dialog.dart';
import '../mysql_engine_status_dialog.dart';
import '../tree_item.dart';

class MysqlSidebarPlugin implements SidebarPlugin {
  const MysqlSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'mysql-sidebar',
        supportedTypes: {DatabaseType.mysql},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) {
    return [
      SidebarCapabilityGroup(
        id: 'advanced',
        label: (l10n) => l10n.sidebarCapGroupAdvanced,
        icon: LucideIcons.wrench,
        items: [
          SidebarCapabilityItem(
            id: 'process.kill',
            capabilityId: 'process.kill',
            label: (l10n) => l10n.processListKillQuery,
            icon: LucideIcons.circleStop,
            onActivate: () => _showProcessManager(context),
          ),
          SidebarCapabilityItem(
            id: 'engine.status',
            capabilityId: 'engine.status',
            label: (l10n) => l10n.engineStatusTitle,
            icon: LucideIcons.database,
            onActivate: () => _showEngineStatus(context),
          ),
        ],
      ),
    ];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    return _MysqlGlobalNodes(
      context: context,
      provider: tree.provider,
      connectionId: tree.connectionId,
      expandedItems: tree.expandedItems,
      onToggleExpand: tree.onToggleExpand,
    ).build();
  }

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) {
    // 库级子树未迁移：回退 sidebar_tree 通用 SQL 装配（C19 收编）。
    return const [];
  }

  // ── 能力项动作 ──────────────────────────────────────────────

  void _showProcessManager(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    final provider = context.read<AppProvider>();
    showDialog(
      context: context,
      builder: (_) => ProcessManagerDialog(
        connectionId: server.id,
        loader: (cid) => _loadProcesses(provider, cid),
        onKill: (cid, pid) => provider.killProcess(cid, pid),
      ),
    );
  }

  /// MySQL loader：经 provider 进程缓存（SHOW PROCESSLIST，与树内
  /// Performance 节点同一路径，加载后缓存通知重建）。
  Future<List<ProcessListEntry>> _loadProcesses(
    AppProvider provider,
    String connectionId,
  ) async {
    await provider.loadProcessList(connectionId);
    final rows = provider.getProcessList(connectionId) ?? const [];
    return [
      for (final p in rows)
        ProcessListEntry(
          id: int.tryParse(p['Id']?.toString() ?? '') ?? 0,
          user: p['User']?.toString() ?? '?',
          command: p['Command']?.toString() ?? '?',
          timeSeconds: _asSeconds(p['Time']),
          info: p['Info']?.toString(),
        ),
    ].where((e) => e.id > 0).toList();
  }

  static int _asSeconds(Object? raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  void _showEngineStatus(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    MysqlEngineStatusDialog.show(context, server.id);
  }
}

/// MySQL 连接级全局节点装配（自 builders/mysql_tree_builder.dart 迁入，
/// 行为逐行保持：Server 合并状态/关键变量、Performance 进程列表带自动
/// 刷新间隔、Users 用户列表）。
class _MysqlGlobalNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;
  final Function(String) onToggleExpand;

  _MysqlGlobalNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
  });

  List<Widget> build() {
    final globalNodes = <Widget>[];
    final l10n = AppLocalizations.of(context)!; // 全局节点文本本地化

    // Server (merged: Status + key Variables)
    final serverExpandKey = '$connectionId:mysql_server';
    final isServerExpanded = expandedItems.contains(serverExpandKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: TreeIcons.server,
        iconColor: context.themeColors.accentBlue,
        label: l10n.sidebarServerGlobal,
        isExpanded: isServerExpanded,
        onTap: () {
          onToggleExpand(serverExpandKey);
          if (!isServerExpanded) {
            provider.loadServerStatus(connectionId);
            provider.loadGlobalVariables(connectionId);
          }
        },
      ),
    );
    if (isServerExpanded) {
      final status = provider.getServerStatus(connectionId);
      final variables = provider.getGlobalVariables(connectionId);

      final isStatusLoaded = status != null;
      final isVariablesLoaded = variables != null;

      // Still loading — neither has come back yet
      if (!isStatusLoaded && !isVariablesLoaded) {
        globalNodes.add(buildLoadingLeaf(context));
      } else if (status != null && status.isNotEmpty) {
        final version = status['Version'] ?? 'N/A';
        final uptime = status['Uptime'];
        final threadsConn =
            int.tryParse(status['Threads_connected']?.toString() ?? '') ?? 0;
        final threadsRun =
            int.tryParse(status['Threads_running']?.toString() ?? '') ?? 0;
        final queries = int.tryParse(status['Queries']?.toString() ?? '') ?? 0;
        final slowQueries =
            int.tryParse(status['Slow_queries']?.toString() ?? '') ?? 0;

        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.info,
            l10n.serverInfoVersion(version),
          ),
        );
        if (uptime != null) {
          globalNodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.timer,
              l10n.serverInfoUptime(formatUptime(uptime)),
            ),
          );
        }
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.users,
            l10n.serverInfoThreads('$threadsConn', '$threadsRun'),
          ),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.chartLine,
            l10n.serverInfoQueries(formatNumber(queries)),
          ),
        );
        if (slowQueries > 0) {
          globalNodes.add(
            TreeItem(
              level: 3,
              icon: LucideIcons.triangleAlert,
              iconColor: context.themeColors.warning,
              label: l10n.serverInfoSlowQueries(formatNumber(slowQueries)),
              showArrow: false,
              onTap: () {},
            ),
          );
        }

        // Key variables
        if (variables != null && variables.isNotEmpty) {
          final keyVars = {
            'max_connections': l10n.serverVarMaxConnections,
            'innodb_buffer_pool_size': l10n.serverVarBufferPool,
            'character_set_server': l10n.serverVarCharset,
          };
          for (final entry in keyVars.entries) {
            if (variables.containsKey(entry.key)) {
              globalNodes.add(
                buildInfoLeaf(
                  context,
                  LucideIcons.slidersHorizontal,
                  '${entry.value}: ${variables[entry.key]}',
                ),
              );
            }
          }
        }
      } else {
        // Loaded but empty — server status not available for this connection type
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.info,
            l10n.serverStatusUnavailable,
          ),
        );
      }
    }

    // T011 — Enhanced Performance (Process List) with auto-refresh
    final perfExpandKey = '$connectionId:performance';
    final isPerfExpanded = expandedItems.contains(perfExpandKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: TreeIcons.performance,
        iconColor: context.themeColors.accentBlue,
        label: l10n.sidebarPerformance,
        isExpanded: isPerfExpanded,
        onTap: () {
          onToggleExpand(perfExpandKey);
          if (!isPerfExpanded) {
            provider.startProcessListAutoRefresh(
              connectionId,
              interval: const Duration(seconds: 10),
            );
          } else {
            provider.stopProcessListAutoRefresh(connectionId);
          }
        },
      ),
    );
    if (isPerfExpanded) {
      // Load on demand: if data is null, trigger async fetch.
      // When load completes, notifyListeners → context.watch rebuilds.
      final processes = provider.getProcessList(connectionId);
      if (processes == null) {
        provider.loadProcessList(connectionId);
      }

      // Auto-refresh interval selector
      globalNodes.add(_buildRefreshIntervalSelector());

      if (processes != null) {
        if (processes.isNotEmpty) {
          for (final proc in processes.take(20)) {
            final timeRaw = proc['Time'] ?? 0;
            final time = timeRaw is int
                ? timeRaw
                : int.tryParse(timeRaw.toString()) ?? 0;
            final timeStr = time > 60
                ? '${(time / 60).floor()}m ${time % 60}s'
                : '${time}s';
            final id = proc['Id']?.toString() ?? '?';
            final user = proc['User']?.toString() ?? '?';
            final command = proc['Command']?.toString() ?? '?';
            final info = proc['Info']?.toString();
            final isSlow = time > 5;

            // 行瘦身——可见标签只保留 [Id] User · Cmd · Time；完整 SQL 移到 Tooltip
            final label = '[$id] $user • $command • $timeStr';

            final IconData cmdIcon = command == 'Sleep'
                ? LucideIcons.moon
                : (command == 'Query'
                      ? LucideIcons.chartLine
                      : LucideIcons.memoryStick);

            globalNodes.add(
              Container(
                color: isSlow
                    ? context.themeColors.error.withValues(alpha: 0.08)
                    : null,
                child: Tooltip(
                  message:
                      (info != null && info.isNotEmpty) ? info : label,
                  waitDuration: const Duration(milliseconds: 400),
                  child: TreeItem(
                    level: 3,
                    icon: cmdIcon,
                    iconColor: isSlow
                        ? context.themeColors.error
                        : context.themeColors.textSecondary,
                    label: label,
                    showArrow: false,
                    onTap: () {},
                    onContextMenu: (pos) =>
                        _showProcessContextMenu(context, pos, proc),
                  ),
                ),
              ),
            );
          }
          if (processes.length > 20) {
            globalNodes.add(
              TreeItem(
                level: 3,
                icon: LucideIcons.ellipsis,
                iconColor: context.themeColors.textMuted,
                label: l10n.processListMore(processes.length - 20),
                showArrow: false,
                onTap: () {},
              ),
            );
          }
        } else {
          globalNodes.add(
            TreeItem(
              level: 3,
              icon: LucideIcons.ban,
              iconColor: context.themeColors.textMuted,
              label: l10n.processListNoProcesses,
              showArrow: false,
              onTap: () {},
            ),
          );
        }
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // Users
    final usersExpandKey = '$connectionId:users';
    final isUsersExpanded = expandedItems.contains(usersExpandKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: TreeIcons.users,
        iconColor: context.themeColors.accentBlue,
        label: l10n.sidebarUsers,
        isExpanded: isUsersExpanded,
        onTap: () {
          onToggleExpand(usersExpandKey);
          if (!isUsersExpanded) {
            provider.loadServerUsers(connectionId);
          }
        },
      ),
    );
    if (isUsersExpanded) {
      final users = provider.getServerUsers(connectionId);
      if (users != null) {
        if (users.isNotEmpty) {
          for (final user in users) {
            globalNodes.add(
              TreeItem(
                level: 3,
                icon: LucideIcons.user,
                iconColor: context.themeColors.textSecondary,
                label: "${user['User']}@${user['Host']}",
                badge: user['AccountLocked'] == true ? l10n.usersLocked : null,
                showArrow: false,
                onTap: () {},
                // T028/FR-011 — right-click menu (was menu-less).
                onContextMenu: (pos) => _showUserMenu(context, pos, user),
              ),
            );
          }
        } else {
          globalNodes.add(
            TreeItem(
              level: 3,
              icon: LucideIcons.ban,
              iconColor: context.themeColors.textMuted,
              label: l10n.usersNoUsers,
              showArrow: false,
              onTap: () {},
            ),
          );
        }
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    return globalNodes;
  }

  // T011 — Auto-refresh interval selector widget
  Widget _buildRefreshIntervalSelector() {
    final l10n = AppLocalizations.of(context)!; // 刷新控件文本本地化
    final intervals = {
      '5s': const Duration(seconds: 5),
      '10s': const Duration(seconds: 10),
      '30s': const Duration(seconds: 30),
      l10n.processListRefreshOff: null,
    };

    final colors = context.themeColors;
    final currentInterval = provider.getProcessListAutoRefreshInterval(
      connectionId,
    );

    return Padding(
      padding: const EdgeInsets.only(left: 48, bottom: 4),
      child: Row(
        children: [
          Text(
            l10n.processListRefreshLabel,
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          const SizedBox(width: 4),
          ...intervals.entries.map((entry) {
            // Active when: Off selected (both null) OR duration seconds match
            final isActive = entry.value == null
                ? currentInterval == null
                : currentInterval == entry.value!.inSeconds;
            // chip 放大（34×24）、间距 space1、激活态更强（0.18 + radiusXs）
            return Padding(
              padding: const EdgeInsets.only(right: AppDesignSystem.space1),
              child: SizedBox(
                width: 34,
                height: 24,
                child: Material(
                  color: isActive
                      ? context.themeColors.accentBlue.withValues(alpha: 0.18)
                      : colors.textMuted.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    onTap: () {
                      if (entry.value != null) {
                        provider.startProcessListAutoRefresh(
                          connectionId,
                          interval: entry.value!,
                        );
                      } else {
                        provider.stopProcessListAutoRefresh(connectionId);
                      }
                    },
                    child: Center(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isActive
                              ? context.themeColors.accentBlue
                              : colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // T012 — Process context menu (Kill Query + Copy Query)
  // T019/FR-004/FR-007/FR-023 — migrated from raw showMenu to the shared
  // ContextMenuUtils renderer (visual consistency + keyboard nav). Copy Query is
  // now disabled with a reason when the process has no query text (was a silent
  // no-op); Kill Query is destructive and grouped at the bottom.
  Future<void> _showProcessContextMenu(
    BuildContext outerContext,
    Offset position,
    Map<String, dynamic> proc,
  ) async {
    final l10n = AppLocalizations.of(outerContext)!;
    final idStr = proc['Id']?.toString() ?? '?';
    final user = proc['User']?.toString() ?? '?';
    final host = proc['Host']?.toString() ?? '?';
    final info = proc['Info']?.toString();
    final hasQuery = info != null && info.isNotEmpty;

    await ContextMenuUtils.show(
      context: outerContext,
      position: position,
      items: [
        ContextMenuItem(
          id: 'copy_query',
          label: l10n.processListCopyQuery,
          icon: LucideIcons.copy,
          enabled: hasQuery,
          disabledReason: hasQuery ? null : l10n.processListNoQueryText,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: info ?? ''));
            if (!outerContext.mounted) return;
            ScaffoldMessenger.of(outerContext).showSnackBar(
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
          onTap: () => _confirmAndKill(idStr, user, host),
        ),
      ],
    );
  }

  // T028/FR-011 — User leaf context menu (previously a dead node).
  // Copy Name copies 'User@Host' (MySQL identity is always both tokens).
  // Refresh re-fetches the user list. Drop User omitted: no provider/adapter
  // dropUser exists yet (would need DROP USER plumbing + cache invalidation).
  Future<void> _showUserMenu(
    BuildContext outerContext,
    Offset position,
    Map<String, dynamic> user,
  ) async {
    final l10n = AppLocalizations.of(outerContext)!;
    final userName = user['User']?.toString() ?? '?';
    final host = user['Host']?.toString() ?? '?';
    final identity = '$userName@$host';

    await ContextMenuUtils.show(
      context: outerContext,
      position: position,
      items: [
        ContextMenuItem(
          id: 'copyName',
          label: l10n.sidebarCopyName,
          icon: LucideIcons.copy,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: identity));
            if (!outerContext.mounted) return;
            ScaffoldMessenger.of(outerContext).showSnackBar(
              SnackBar(
                content: Text(l10n.sqlCopied),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        ContextMenuItem(
          id: 'refresh',
          label: l10n.commonRefresh,
          icon: LucideIcons.refreshCw,
          onTap: () => provider.loadServerUsers(connectionId),
        ),
      ],
    );
  }

  void _confirmAndKill(String idStr, String user, String host) {
    final pid = int.tryParse(idStr) ?? 0;
    if (pid == 0) return;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(l10n.processListKillConfirmTitle),
        content: Text(l10n.processListKillConfirm(idStr, user, host)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.killProcess(connectionId, pid);
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
