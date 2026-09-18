// C18 · Doris 侧边栏插件 —— 全局树迁入（自 builders/doris_tree_builder.dart）。
//
// 树装配：连接级全局节点（Server / Performance，行为逐行保持）；
// 库级对象子树仍走 sidebar_tree 通用 SQL 装配（Tables/Views/Materialized
// Views 分类，generic 路径服务多类型，C19 统一收编），故
// buildDatabaseTree 恒空 = 宿主回退。Users 节点有意省略（Doris mysql.user
// 列不匹配、SHOW ALL GRANTS 需 GRANT 权限——旧 builder 注释保留）。
//
// 能力菜单（capabilityGroups）：与 core 插件同组 id 合并（'advanced'），
// 补 Doris 专有入口 Kill Query（进程管理对话框；Doris 复用 MySQL 协议，
// loader 与 MySQL 同路径经 provider 进程缓存）。能力位经 port 门控
// （process.kill 含 doris），本文件不写 DatabaseType 能力分支。
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
import '../tree_item.dart';

class DorisSidebarPlugin implements SidebarPlugin {
  const DorisSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'doris-sidebar',
        supportedTypes: {DatabaseType.doris},
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
        ],
      ),
    ];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    return _DorisGlobalNodes(
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

  /// Doris loader：与 MySQL 同路径（MySQL 协议复用 mysql_base_adapter，
  /// SHOW PROCESSLIST 经 provider 进程缓存，与树内 Performance 节点一致）。
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
}

/// Doris 连接级全局节点装配（自 builders/doris_tree_builder.dart 迁入，
/// 行为逐行保持：Server 合并 version_comment + enable_feature_binlog、
/// Performance 进程列表带自动刷新间隔与 Kill Query）。
class _DorisGlobalNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;
  final Function(String) onToggleExpand;

  _DorisGlobalNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
  });

  List<Widget> build() {
    final globalNodes = <Widget>[];
    final l10n = AppLocalizations.of(context)!;

    // ── Server ──────────────────────────────────────────────────────────
    final serverExpandKey = '$connectionId:doris_server';
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

      if (status == null && variables == null) {
        globalNodes.add(buildLoadingLeaf(context));
      } else if (status != null && status.isNotEmpty) {
        // Doris version from SHOW VARIABLES (version_comment) or SELECT VERSION()
        final versionComment = variables?['version_comment']?.toString();
        final displayVersion =
            versionComment ?? status['Version']?.toString() ?? 'N/A';
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.info,
            l10n.serverInfoVersion(displayVersion),
          ),
        );

        // Key Doris FE configuration (no MySQL-specific vars)
        if (variables != null && variables.isNotEmpty) {
          final keyVars = {'enable_feature_binlog': 'enable_feature_binlog'};
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
        // Loaded but empty — server status not available
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.info,
            l10n.serverStatusUnavailable,
          ),
        );
      }
    }

    // ── Performance ─────────────────────────────────────────────────────
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
      final processes = provider.getProcessList(connectionId);
      if (processes == null) {
        provider.loadProcessList(connectionId);
      }

      globalNodes.add(_buildRefreshIntervalSelector(l10n));

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
                  message: (info != null && info.isNotEmpty) ? info : label,
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

    // NOTE: Users node intentionally omitted — not applicable to Doris.
    // mysql.user lacks password_expired/account_locked columns; SHOW ALL GRANTS
    // requires GRANT privilege unavailable to ordinary users.

    return globalNodes;
  }

  Widget _buildRefreshIntervalSelector(AppLocalizations l10n) {
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
            final isActive = entry.value == null
                ? currentInterval == null
                : currentInterval == entry.value!.inSeconds;
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
