// C17 · Redis 侧边栏插件 —— per-type SidebarPlugin（怪类型基准）。
//
// 拆法裁定（同 C16 SQLite）：Redis 无 SQL 意义的数据库层——逻辑库 db0-15
// 列表来自 keyspace 的连接级事实，库节点与全局节点（Server/Replication/
// Memory/Stats/Clients/Config/Slow Log + 9 面板入口）在连接卡展开区一次
// 渲染，故整树走 buildGlobalTree（宿主经 SidebarTreeContext.databases 透传
// 搜索过滤后的库列表），buildDatabaseTree 恒空（C19 删旧路径无需反转）。
// 树装配体 _RedisConnectionTree 自 builders/redis_tree_builder.dart 逐行
// 迁入；6 个内嵌对话框拆至 redis_dialogs/（树右键与能力菜单双入口共享）。
//
// 能力菜单（capabilityGroups）：键空间组「新建键」（树 db 右键同流程双轨）
// + advanced 组 9 面板入口（Workbench/Pub-Sub/Lua/Pipeline/Transaction/
// Memory Analysis/Keyspace Notifications/ACL/Edit Config——与树内全局节点
// 同一 showDialog 路径，能力位经 port 门控）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../molecules/context_menu.dart';
import '../../../models/database_models.dart' hide QueryTab;
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart' show QueryTab;
import '../../../theme/app_theme.dart';
import '../../connection/error_boundary.dart';
import '../../redis_functions/redis_functions_panel.dart';
import '../../redis_pubsub/redis_pubsub_panel.dart';
import '../../redis_workbench/redis_workbench_panel.dart';
import '../../redis_lua/redis_lua_panel.dart';
import '../../redis_pipeline/redis_pipeline_panel.dart';
import '../../redis_transaction/redis_transaction_panel.dart';
import '../../redis_memory_analysis/redis_memory_analysis_panel.dart';
import '../../redis_keyspace/redis_keyspace_panel.dart';
import '../../redis_acl/redis_acl_panel.dart';
import '../../redis_key_editor/redis_key_editor_dialog.dart';
import '../capability/capability_menu_assembly.dart';
import '../redis_dialogs/redis_confirm_dialogs.dart';
import '../redis_dialogs/redis_edit_config_dialog.dart';
import '../redis_dialogs/redis_new_key_dialog.dart';
import '../redis_dialogs/redis_rename_key_dialog.dart';
import '../redis_dialogs/redis_set_ttl_dialog.dart';
import '../tree_item.dart';
import '../builders/tree_utils.dart';
import '../../../molecules/compact_popup_menu_item.dart';

class RedisSidebarPlugin implements SidebarPlugin {
  const RedisSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'redis-sidebar',
        supportedTypes: {DatabaseType.redis},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) {
    return [
      SidebarCapabilityGroup(
        id: 'keyspace',
        label: (l10n) => l10n.redisCapGroupKeyspace,
        icon: LucideIcons.keyRound,
        items: [
          SidebarCapabilityItem(
            id: 'redis.key.new',
            label: (l10n) => l10n.sidebarNewKey,
            icon: LucideIcons.plus,
            onActivate: () => _activateNewKey(context),
          ),
        ],
      ),
      SidebarCapabilityGroup(
        id: 'advanced',
        label: (l10n) => l10n.sidebarCapGroupAdvanced,
        icon: LucideIcons.wrench,
        items: [
          SidebarCapabilityItem(
            id: 'redis.cli',
            capabilityId: 'redis.cli',
            label: (l10n) => l10n.redisCapWorkbench,
            icon: LucideIcons.terminal,
            onActivate: () => _activateWorkbench(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.pubsub',
            capabilityId: 'redis.pubsub',
            label: (l10n) => l10n.redisCapPubsub,
            icon: LucideIcons.wifi,
            onActivate: () => _activatePubsub(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.lua',
            capabilityId: 'redis.lua',
            label: (l10n) => l10n.redisCapLua,
            icon: LucideIcons.code,
            onActivate: () => _activateLua(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.pipeline',
            label: (l10n) => l10n.redisCapPipeline,
            icon: LucideIcons.fastForward,
            onActivate: () => _activatePipeline(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.transaction',
            label: (l10n) => l10n.redisCapTransaction,
            icon: LucideIcons.lock,
            onActivate: () => _activateTransaction(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.memory',
            label: (l10n) => l10n.redisCapMemoryAnalysis,
            icon: LucideIcons.chartPie,
            onActivate: () => _activateMemoryAnalysis(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.keyspace.notifications',
            label: (l10n) => l10n.redisCapKeyspaceNotifications,
            icon: LucideIcons.bellRing,
            onActivate: () => _activateKeyspaceNotifications(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.acl',
            label: (l10n) => l10n.redisCapAcl,
            icon: LucideIcons.shieldCheck,
            onActivate: () => _activateAcl(context),
          ),
          SidebarCapabilityItem(
            id: 'redis.config',
            capabilityId: 'redis.config',
            label: (l10n) => l10n.redisCapConfig,
            icon: LucideIcons.settings,
            onActivate: () => _activateEditConfig(context),
          ),
        ],
      ),
    ];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    return _RedisConnectionTree(
      context: context,
      provider: tree.provider,
      connectionId: tree.connectionId,
      searchQuery: tree.searchQuery,
      expandedItems: tree.expandedItems,
      expandedDatabases: tree.expandedDatabases,
      onToggleExpand: tree.onToggleExpand,
      onToggleDatabase: tree.onToggleDatabase,
      onSelectNode: tree.onSelectNode,
      selectedNodeKey: tree.selectedNodeKey,
    ).buildConnectionNodes(tree.databases);
  }

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) {
    // 拆法裁定：Redis 整树连接级，无库级分缝（C19 删旧路径无需反转）。
    return const [];
  }

  // ── 能力项动作（与树内全局节点同一 showDialog 路径） ─────────────

  /// 能力菜单动作的目标 db：侧栏选中库（限本连接）→ '0' 兜底
  /// （树内 Workbench/Pub/Sub 入口即用 '0'，Pub/Sub 为 server 级）。
  String _actionDb(AppProvider provider, String connectionId) {
    if (provider.sidebar.selectedConnectionId == connectionId &&
        provider.sidebar.selectedDatabaseName != null) {
      return provider.sidebar.selectedDatabaseName!;
    }
    return '0';
  }

  void _activateNewKey(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    final provider = context.read<AppProvider>();
    showDialog(
      context: context,
      builder: (ctx) => RedisNewKeyDialog(
        provider: provider,
        connectionId: server.id,
        dbName: _actionDb(provider, server.id),
      ),
    );
  }

  void _activateWorkbench(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisWorkbenchPanel(
          connectionId: server.id,
          databaseName: '0',
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activatePubsub(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisPubSubPanel(
          connectionId: server.id,
          // Pub/Sub 为 server 级,与 db 无关,占位即可
          databaseName: '0',
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activateLua(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisLuaPanel(
          connectionId: server.id,
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activatePipeline(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisPipelinePanel(
          connectionId: server.id,
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activateTransaction(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisTransactionPanel(
          connectionId: server.id,
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activateMemoryAnalysis(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisMemoryAnalysisPanel(
          connectionId: server.id,
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activateKeyspaceNotifications(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisKeyspacePanel(
          connectionId: server.id,
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activateAcl(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.themeColors.bgSecondary,
        child: RedisAclPanel(
          connectionId: server.id,
          provider: context.read<AppProvider>(),
        ),
      ),
    );
  }

  void _activateEditConfig(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    showDialog(
      context: context,
      builder: (ctx) => RedisEditConfigDialog(
        provider: context.read<AppProvider>(),
        connectionId: server.id,
      ),
    );
  }
}

/// Redis 连接级整树装配（自 builders/redis_tree_builder.dart 逐行迁入，
/// 行为保持：库列表 + 空 db 显隐开关 + 全局信息节点 + 9 面板入口）。
class _RedisConnectionTree {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final String searchQuery;
  final Set<String> expandedItems;
  final Set<String> expandedDatabases;
  final Function(String) onToggleExpand;
  final Function(String) onToggleDatabase;
  final ValueChanged<String>? onSelectNode;
  final String? selectedNodeKey;

  _RedisConnectionTree({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.searchQuery,
    required this.expandedItems,
    required this.expandedDatabases,
    required this.onToggleExpand,
    required this.onToggleDatabase,
    this.onSelectNode,
    this.selectedNodeKey,
  });

  /// 构建 Redis 连接下的所有节点（数据库列表 + 全局信息）
  List<Widget> buildConnectionNodes(List<String> connectionDatabases) {
    final nodes = <Widget>[];

    // Show toggle for empty databases if there are many
    if (provider.getTotalDatabaseCount(connectionId) > 16) {
      nodes.add(_buildShowEmptyDbToggle());
      if (connectionDatabases.isEmpty) {
        nodes.add(
          TreeItem(
            level: 2,
            icon: LucideIcons.info,
            iconColor: context.themeColors.textMuted,
            label: 'No databases with data',
            showArrow: false,
            onTap: () {},
          ),
        );
      }
    }

    // Database nodes
    for (final database in connectionDatabases) {
      nodes.add(_buildDatabaseNode(database));
    }

    // Divider + Global nodes
    nodes.add(buildDivider(context));
    nodes.addAll(_buildGlobalNodes());

    return nodes;
  }

  Widget _buildShowEmptyDbToggle() {
    final isShowingEmpty = provider.isShowingEmptyDatabases(connectionId);
    final totalCount = provider.getTotalDatabaseCount(connectionId);
    final nonEmptyCount = provider.getNonEmptyDatabaseCount(connectionId);

    return InkWell(
      onTap: () => provider.toggleShowEmptyDatabases(connectionId),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Container(
        height: 28,
        padding: const EdgeInsets.only(
          left: AppDesignSystem.space3 * 2 + 16 + AppDesignSystem.space2,
          right: AppDesignSystem.space2,
        ),
        child: Row(
          children: [
            Icon(
              isShowingEmpty ? LucideIcons.squareCheckBig : LucideIcons.square,
              size: 14,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              'Show empty ($nonEmptyCount / $totalCount)',
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: context.themeColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseNode(String databaseName) {
    final key = '$connectionId:$databaseName';
    final isExpanded = expandedDatabases.contains(key);
    final isSelected =
        provider.sidebar.selectedConnectionId == connectionId &&
        provider.sidebar.selectedDatabaseName == databaseName;

    final keyspace = provider.getRedisKeyspaceInfo(connectionId);
    final dbKeyCount = keyspace?[databaseName]?['keys'] as int?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: TreeIcons.database,
          iconColor: isSelected
              ? AppDesignSystem.dbRedis
              : context.themeColors.textSecondary,
          iconSize: 16,
          label: databaseName,
          badge: dbKeyCount != null && dbKeyCount > 0
              ? formatNumber(dbKeyCount)
              : null,
          isExpanded: isExpanded,
          isSelected: isSelected,
          // #hotfix-redis — 对齐 SQL db 节点：tap 切换展开 + 选择。
          // 原先只 _selectDatabase 不 toggle，导致 db 节点永不展开、子节点不渲染。
          onTap: () {
            onToggleDatabase(key);
            _selectDatabase(databaseName);
          },
          onDoubleTap: () async {
            _selectDatabase(databaseName);
            await provider.openQueryTab(connectionId, databaseName);
          },
          onContextMenu: (position) =>
              _showDatabaseContextMenu(databaseName, position),
        ),
        if (isExpanded)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: AppDesignSystem.curveDefault,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildDatabaseChildren(databaseName),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildDatabaseChildren(String databaseName) {
    final nodes = <Widget>[];
    final keyInfo = provider.getRedisDatabaseKeyInfo(
      connectionId,
      databaseName,
    );

    // Keys
    final keysKey = '$connectionId:$databaseName:keys';
    final isKeysExpanded = expandedItems.contains(keysKey);
    final typeCount = keyInfo?['typeCount'] as Map? ?? {};
    final totalKeys = typeCount.values.fold(0, (sum, v) => sum + (v as int));
    nodes.add(
      TreeItem(
        level: 3,
        icon: LucideIcons.keyRound,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Keys',
        badge: totalKeys > 0 ? formatNumber(totalKeys) : null,
        isExpanded: isKeysExpanded,
        onTap: () {
          onToggleExpand(keysKey);
          if (!isKeysExpanded) {
            provider.loadRedisDatabaseKeyInfo(connectionId, databaseName);
          }
        },
      ),
    );
    if (isKeysExpanded) {
      if (keyInfo != null) {
        final typeSamples = keyInfo['typeSamples'] as Map? ?? {};
        final totalScanned = keyInfo['totalScanned'] as int? ?? 0;
        final hasMore = keyInfo['hasMore'] as bool? ?? false;

        if (typeCount.isNotEmpty) {
          final typeDisplayNames = {
            'string': 'String',
            'hash': 'Hash',
            'list': 'List',
            'set': 'Set',
            'zset': 'Sorted Set',
            'stream': 'Stream',
          };
          final typeIcons = {
            'string': LucideIcons.type,
            'hash': LucideIcons.rows3,
            'list': LucideIcons.list,
            'set': LucideIcons.users,
            'zset': LucideIcons.arrowUpDown,
            'stream': LucideIcons.waves,
          };

          for (final entry in typeCount.entries) {
            final typeName = entry.key.toString();
            final displayName = typeDisplayNames[typeName] ?? typeName;
            final samples = typeSamples[typeName] as List? ?? [];

            nodes.add(
              TreeItem(
                level: 4,
                icon: typeIcons[typeName] ?? LucideIcons.circleHelp,
                iconColor: context.themeColors.textSecondary,
                label: '$displayName (${formatNumber(entry.value as int)})',
                showArrow: samples.isNotEmpty,
                onTap: () {},
              ),
            );
            if (samples.isNotEmpty) {
              for (final sample in samples.take(3)) {
                nodes.add(
                  TreeItem(
                    level: 5,
                    icon: LucideIcons.keyRound,
                    iconColor: context.themeColors.textMuted,
                    label: sample.toString(),
                    showArrow: false,
                    isSelected:
                        selectedNodeKey ==
                        '$connectionId:$databaseName:key:$sample',
                    onTap: () => onSelectNode?.call(
                      '$connectionId:$databaseName:key:$sample',
                    ),
                    onContextMenu: (position) => _showKeyContextMenu(
                      dbName: databaseName,
                      key: sample.toString(),
                      type: typeName,
                      position: position,
                    ),
                    onDoubleTap: () => _handleKeyAction(
                      dbName: databaseName,
                      key: sample.toString(),
                      type: typeName,
                      action: 'view',
                    ),
                  ),
                );
              }
            }
          }

          if (hasMore) {
            nodes.add(
              TreeItem(
                level: 4,
                icon: LucideIcons.info,
                iconColor: context.themeColors.textMuted,
                label: 'Scanned ${formatNumber(totalScanned)} keys (sampling)',
                showArrow: false,
                onTap: () {},
              ),
            );
          }
        } else {
          nodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.ban,
              'No keys found',
              iconColor: context.themeColors.textMuted,
            ),
          );
        }
      } else {
        nodes.add(buildLoadingLeaf(context));
      }
    }

    // Namespaces
    final nsKey = '$connectionId:$databaseName:namespaces';
    final isNsExpanded = expandedItems.contains(nsKey);
    final namespaceCount = keyInfo?['namespaceCount'] as Map? ?? {};
    nodes.add(
      TreeItem(
        level: 3,
        icon: LucideIcons.folder,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Namespaces',
        badge: namespaceCount.isNotEmpty ? '${namespaceCount.length}' : null,
        isExpanded: isNsExpanded,
        onTap: () {
          onToggleExpand(nsKey);
          if (!isNsExpanded) {
            provider.loadRedisDatabaseKeyInfo(connectionId, databaseName);
          }
        },
      ),
    );
    if (isNsExpanded) {
      if (keyInfo != null) {
        final namespaceSamples = keyInfo['namespaceSamples'] as Map? ?? {};
        final totalScanned = keyInfo['totalScanned'] as int? ?? 0;

        if (namespaceCount.isNotEmpty) {
          // 碎片化检测：命名空间基数 ≈ 样本量 → key 名无主导前缀（如
          // UUID 主键），聚合视图只会是 count=1 噪音——如实告知并导向
          // 搜索，不渲染清单。
          final fragmented =
              totalScanned >= 50 &&
              namespaceCount.length >= totalScanned * 0.9;
          if (fragmented) {
            nodes.add(
              buildInfoLeaf(
                context,
                LucideIcons.shuffle,
                'Names look fragmented (no dominant prefix) — '
                'use search to find specific keys',
                iconColor: context.themeColors.textMuted,
              ),
            );
          } else {
            final sortedNs = namespaceCount.entries.toList()
              ..sort((a, b) => (b.value as int).compareTo(a.value as int));

            for (final entry in sortedNs.take(20)) {
              final nsName = entry.key.toString();
              final samples = namespaceSamples[nsName] as List? ?? [];

              nodes.add(
                TreeItem(
                  level: 4,
                  icon: LucideIcons.tag,
                  iconColor: context.themeColors.textSecondary,
                  label: '$nsName (${formatNumber(entry.value as int)})',
                  showArrow: samples.isNotEmpty,
                  onTap: () {},
                ),
              );
              if (samples.isNotEmpty) {
                for (final sample in samples.take(3)) {
                  nodes.add(
                    TreeItem(
                      level: 5,
                      icon: LucideIcons.keyRound,
                      iconColor: context.themeColors.textMuted,
                      label: sample.toString(),
                      showArrow: false,
                      onTap: () {},
                    ),
                  );
                }
              }
            }
            if (namespaceCount.length > 20) {
              nodes.add(
                TreeItem(
                  level: 4,
                  icon: LucideIcons.ellipsis,
                  iconColor: context.themeColors.textMuted,
                  label: '... and ${namespaceCount.length - 20} more',
                  showArrow: false,
                  onTap: () {},
                ),
              );
            }
          }
        } else {
          nodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.ban,
              'No namespaces found',
              iconColor: context.themeColors.textMuted,
            ),
          );
        }
      } else {
        nodes.add(buildLoadingLeaf(context));
      }
    }

    // Expiring Soon
    final ttlKey = '$connectionId:$databaseName:ttl_monitor';
    final isTtlExpanded = expandedItems.contains(ttlKey);
    nodes.add(
      TreeItem(
        level: 3,
        icon: LucideIcons.timer,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Expiring Soon',
        isExpanded: isTtlExpanded,
        onTap: () {
          onToggleExpand(ttlKey);
          if (!isTtlExpanded) {
            provider.loadRedisTTLKeys(connectionId, databaseName);
          }
        },
      ),
    );
    if (isTtlExpanded) {
      final ttlResult = provider.getRedisTTLKeys(connectionId, databaseName);
      if (ttlResult != null) {
        // 头部精确口径（INFO keyspace，O(1) 零枚举）——Redis 对「多少
        // key 带过期、平均活多久」的原生答案；明细列表只承诺样本内。
        final totalKeys = ttlResult['totalKeys'] as int? ?? 0;
        final expires = ttlResult['expires'] as int? ?? 0;
        final avgTtlMs = ttlResult['avgTtlMs'] as int? ?? 0;
        final sampled = ttlResult['sampled'] as int? ?? 0;
        final keys = ttlResult['keys'] as List? ?? const [];
        nodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.chartColumn,
            'Keys ${formatNumber(totalKeys)} · With TTL ${formatNumber(expires)}'
            '${avgTtlMs > 0 ? ' · Avg ${formatTTL(avgTtlMs ~/ 1000)}' : ''}',
            iconColor: context.themeColors.textMuted,
          ),
        );
        nodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.filter,
            'Sampled ${formatNumber(sampled)} keys (sampling)',
            iconColor: context.themeColors.textMuted,
          ),
        );
        if (keys.isNotEmpty) {
          for (final entry in keys.take(20)) {
            final ttl = entry['ttl'] as int;
            final ttlColor = ttl < 60
                ? context.themeColors.error
                : (ttl < 300
                      ? context.themeColors.warning
                      : context.themeColors.textSecondary);
            nodes.add(
              TreeItem(
                level: 4,
                icon: LucideIcons.clock,
                iconColor: ttlColor,
                label: '${entry['key']} (${formatTTL(ttl)})',
                showArrow: false,
                onTap: () {},
              ),
            );
          }
          if (keys.length > 20) {
            nodes.add(
              TreeItem(
                level: 4,
                icon: LucideIcons.ellipsis,
                iconColor: context.themeColors.textMuted,
                label: '... and ${keys.length - 20} more (in sample)',
                showArrow: false,
                onTap: () {},
              ),
            );
          }
        } else {
          nodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.circleCheckBig,
              'No keys expiring soon',
              iconColor: context.themeColors.success,
            ),
          );
        }
      } else {
        nodes.add(buildLoadingLeaf(context));
      }
    }

    // DB Info
    final dbStatsKey = '$connectionId:$databaseName:db_stats';
    final isDbStatsExpanded = expandedItems.contains(dbStatsKey);
    nodes.add(
      TreeItem(
        level: 3,
        icon: LucideIcons.chartColumn,
        iconColor: AppDesignSystem.dbRedis,
        label: 'DB Info',
        isExpanded: isDbStatsExpanded,
        onTap: () {
          onToggleExpand(dbStatsKey);
          if (!isDbStatsExpanded) {
            provider.loadRedisDBStats(connectionId, databaseName);
          }
        },
      ),
    );
    if (isDbStatsExpanded) {
      final stats = provider.getRedisDBStats(connectionId, databaseName);
      if (stats != null && stats.isNotEmpty) {
        final keyCount = stats['keyCount'] ?? 0;
        final expires = stats['expires'] as int? ?? 0;
        final avgTtlMs = stats['avgTtlMs'] as int? ?? 0;
        nodes.add(
          TreeItem(
            level: 4,
            icon: LucideIcons.keyRound,
            iconColor: context.themeColors.textSecondary,
            label: 'Keys: ${formatNumber(keyCount)}',
            showArrow: false,
            onTap: () {},
          ),
        );
        nodes.add(
          TreeItem(
            level: 4,
            icon: LucideIcons.timer,
            iconColor: context.themeColors.textSecondary,
            label: 'With TTL: ${formatNumber(expires)}',
            showArrow: false,
            onTap: () {},
          ),
        );
        if (avgTtlMs > 0) {
          nodes.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.clock,
              iconColor: context.themeColors.textSecondary,
              label: 'Avg TTL: ${formatTTL(avgTtlMs ~/ 1000)}',
              showArrow: false,
              onTap: () {},
            ),
          );
        }
      } else {
        nodes.add(buildLoadingLeaf(context));
      }
    }

    return nodes;
  }

  List<Widget> _buildGlobalNodes() {
    final globalNodes = <Widget>[];

    // Server Info (merged with Keyspace)
    final serverInfoKey = '$connectionId:redis_server_info';
    final isServerInfoExpanded = expandedItems.contains(serverInfoKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.monitor,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Server',
        isExpanded: isServerInfoExpanded,
        onTap: () {
          onToggleExpand(serverInfoKey);
          if (!isServerInfoExpanded) {
            provider.loadRedisServerInfo(connectionId);
            provider.loadRedisKeyspaceInfo(connectionId);
          }
        },
      ),
    );
    if (isServerInfoExpanded) {
      final info = provider.getRedisServerInfo(connectionId);
      final keyspace = provider.getRedisKeyspaceInfo(connectionId);

      if (info != null && info.isNotEmpty) {
        final version = info['redis_version'] ?? 'N/A';
        final mode = info['redis_mode'] ?? 'N/A';
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.info, 'Redis $version'),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.network,
            '${mode.substring(0, 1).toUpperCase()}${mode.substring(1)} Mode',
          ),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.timer,
            'Uptime: ${formatUptime(info['uptime_in_seconds'])}',
          ),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.users,
            'Connected Clients: ${info['connected_clients'] ?? 0}',
          ),
        );

        if (keyspace != null && keyspace.isNotEmpty) {
          for (final entry in keyspace.entries) {
            final keys = entry.value['keys'] ?? 0;
            final expires = entry.value['expires'] ?? 0;
            globalNodes.add(
              buildInfoLeaf(
                context,
                LucideIcons.database,
                '${entry.key}: ${formatNumber(keys)} keys, $expires expiring',
              ),
            );
          }
        }
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // D1 — Replication
    final replicationKey = '$connectionId:redis_replication';
    final isReplicationExpanded = expandedItems.contains(replicationKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.arrowRightLeft,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Replication',
        isExpanded: isReplicationExpanded,
        onTap: () {
          onToggleExpand(replicationKey);
          if (!isReplicationExpanded) {
            provider.loadRedisReplication(connectionId);
          }
        },
      ),
    );
    if (isReplicationExpanded) {
      final repl = provider.getRedisReplicationInfo(connectionId);
      if (repl != null && repl.isNotEmpty) {
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.shieldCheck,
            'Role: ${repl['role'] ?? '-'}',
          ),
        );
        if (repl['role'] == 'slave') {
          globalNodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.cloud,
              'Master: ${repl['master_host'] ?? '-'}:${repl['master_port'] ?? '-'}',
            ),
          );
          globalNodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.link,
              'Link: ${repl['master_link_status'] ?? '-'}',
            ),
          );
        }
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.users,
            'Connected slaves: ${repl['connected_slaves'] ?? '0'}',
          ),
        );
        // D1 — 动态 slave0/slave1...
        for (final entry in repl.entries) {
          if (entry.key.startsWith('slave')) {
            globalNodes.add(
              buildInfoLeaf(
                context,
                LucideIcons.monitor,
                '${entry.key}: ${entry.value}',
              ),
            );
          }
        }
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // Memory
    final memoryKey = '$connectionId:redis_memory';
    final isMemoryExpanded = expandedItems.contains(memoryKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.memoryStick,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Memory',
        isExpanded: isMemoryExpanded,
        onTap: () {
          onToggleExpand(memoryKey);
          if (!isMemoryExpanded) {
            provider.loadRedisMemoryInfo(connectionId);
          }
        },
      ),
    );
    if (isMemoryExpanded) {
      final memory = provider.getRedisMemoryInfo(connectionId);
      if (memory != null && memory.isNotEmpty) {
        final used = memory['used_memory_human'] ?? 'N/A';
        final peak = memory['used_memory_peak_human'] ?? 'N/A';
        final frag = memory['mem_fragmentation_ratio'] ?? 'N/A';
        final maxMem = memory['maxmemory_human'] ?? '0';
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.chartPie, 'Used: $used'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.trendingUp, 'Peak: $peak'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.chartPie, 'Fragmentation: $frag'),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.memoryStick,
            'Max Memory: ${maxMem == '0' ? 'No Limit' : maxMem}',
          ),
        );
        // D2 — 内存深度分析入口(Top-N / Doctor / Stats)
        globalNodes.add(
          TreeItem(
            level: 3,
            icon: LucideIcons.chartColumn,
            iconColor: context.themeColors.accentBlue,
            label: 'Memory Analysis...',
            showArrow: false,
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => Dialog(
                backgroundColor: context.themeColors.bgSecondary,
                child: RedisMemoryAnalysisPanel(
                  connectionId: connectionId,
                  provider: provider,
                ),
              ),
            ),
          ),
        );
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // Stats
    final statsKey = '$connectionId:redis_stats';
    final isStatsExpanded = expandedItems.contains(statsKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.chartLine,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Stats',
        isExpanded: isStatsExpanded,
        onTap: () {
          onToggleExpand(statsKey);
          if (!isStatsExpanded) {
            provider.loadRedisStats(connectionId);
          }
        },
      ),
    );
    if (isStatsExpanded) {
      final stats = provider.getRedisStats(connectionId);
      if (stats != null && stats.isNotEmpty) {
        final totalCmds = formatNumber(
          int.tryParse(stats['total_commands_processed'] ?? '0') ?? 0,
        );
        final opsPerSec = stats['instantaneous_ops_per_sec'] ?? '0';
        final hits = int.tryParse(stats['keyspace_hits'] ?? '0') ?? 0;
        final misses = int.tryParse(stats['keyspace_misses'] ?? '0') ?? 0;
        final hitRate = hits + misses > 0
            ? '${((hits / (hits + misses)) * 100).toStringAsFixed(1)}%'
            : 'N/A';
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.hash, 'Commands: $totalCmds'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.gauge, 'Ops/sec: $opsPerSec'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.thumbsUp, 'Hit Rate: $hitRate'),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.trash2,
            'Expired: ${formatNumber(int.tryParse(stats['expired_keys'] ?? '0') ?? 0)}',
          ),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.zapOff,
            'Evicted: ${formatNumber(int.tryParse(stats['evicted_keys'] ?? '0') ?? 0)}',
          ),
        );
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // Clients
    final clientsKey = '$connectionId:redis_clients';
    final isClientsExpanded = expandedItems.contains(clientsKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.users,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Clients',
        isExpanded: isClientsExpanded,
        onTap: () {
          onToggleExpand(clientsKey);
          if (!isClientsExpanded) {
            provider.loadRedisClientInfo(connectionId);
          }
        },
      ),
    );
    if (isClientsExpanded) {
      final clients = provider.getRedisClientInfo(connectionId);
      if (clients != null) {
        final info = clients['info'] as Map?;
        final clientList = clients['clients'] as List?;
        if (info != null) {
          globalNodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.user,
              'Connected: ${info['connected_clients'] ?? 0}',
            ),
          );
          globalNodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.ban,
              'Blocked: ${info['blocked_clients'] ?? 0}',
            ),
          );
        }
        if (clientList != null && clientList.isNotEmpty) {
          for (final client in clientList.take(10)) {
            globalNodes.add(
              buildInfoLeaf(
                context,
                LucideIcons.user,
                '${client['name'] ?? client['addr'] ?? 'Unknown'}',
              ),
            );
          }
          if (clientList.length > 10) {
            globalNodes.add(
              buildInfoLeaf(
                context,
                LucideIcons.ellipsis,
                '... and ${clientList.length - 10} more',
              ),
            );
          }
        }
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // Config
    final configKey = '$connectionId:redis_config';
    final isConfigExpanded = expandedItems.contains(configKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.settings,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Config',
        isExpanded: isConfigExpanded,
        onTap: () {
          onToggleExpand(configKey);
          if (!isConfigExpanded) {
            provider.loadRedisConfig(connectionId);
          }
        },
      ),
    );
    if (isConfigExpanded) {
      final config = provider.getRedisConfig(connectionId);
      if (config != null && config.isNotEmpty) {
        final dbCount = config['databases'] ?? '16';
        final maxClients = formatNumber(
          int.tryParse(config['maxclients'] ?? '0') ?? 0,
        );
        final timeout = config['timeout'] ?? '0';
        final logLevel = config['loglevel'] ?? 'notice';
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.database, 'Databases: $dbCount'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.users, 'Max Clients: $maxClients'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.timer, 'Timeout: ${timeout}s'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.fileText, 'Log Level: $logLevel'),
        );
        // B4 — Edit Config 入口
        globalNodes.add(
          TreeItem(
            level: 3,
            icon: LucideIcons.pencil,
            iconColor: context.themeColors.accentBlue,
            label: 'Edit Config...',
            showArrow: false,
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => RedisEditConfigDialog(
                provider: provider,
                connectionId: connectionId,
              ),
            ),
          ),
        );
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // Slow Log
    final slowlogKey = '$connectionId:redis_slowlog';
    final isSlowlogExpanded = expandedItems.contains(slowlogKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.gauge,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Slow Log',
        isExpanded: isSlowlogExpanded,
        onTap: () {
          onToggleExpand(slowlogKey);
          if (!isSlowlogExpanded) {
            provider.loadRedisSlowLog(connectionId);
          }
        },
      ),
    );
    if (isSlowlogExpanded) {
      final logs = provider.getRedisSlowLog(connectionId);
      if (logs != null) {
        if (logs.isNotEmpty) {
          for (final log in logs.take(10)) {
            globalNodes.add(
              buildInfoLeaf(
                context,
                LucideIcons.terminal,
                '${log['command']} (${log['duration']}μs)',
              ),
            );
          }
          if (logs.length > 10) {
            globalNodes.add(
              buildInfoLeaf(
                context,
                LucideIcons.ellipsis,
                '... and ${logs.length - 10} more',
              ),
            );
          }
        } else {
          globalNodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.circleCheckBig,
              'No slow queries',
              iconColor: context.themeColors.success,
            ),
          );
        }
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // 阶段3 - Functions 节点
    globalNodes.add(
      RedisFunctionsPanel(
        connectionId: connectionId,
        provider: provider,
        onToggleExpand: (key) => onToggleExpand(key),
      ),
    );

    // 第三波 C2 — 命令行 Workbench
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.terminal,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Workbench',
        showArrow: false,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              child: RedisWorkbenchPanel(
                connectionId: connectionId,
                databaseName: '0',
                provider: provider,
              ),
            ),
          );
        },
      ),
    );

    // 第三波 C3 — Lua 脚本工作台
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.code,
        iconColor: AppDesignSystem.accentPrimary,
        label: 'Lua Scripts',
        showArrow: false,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              child: RedisLuaPanel(
                connectionId: connectionId,
                provider: provider,
              ),
            ),
          );
        },
      ),
    );

    // 第三波 C4 — Pipeline 执行器
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.fastForward,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Pipeline',
        showArrow: false,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              child: RedisPipelinePanel(
                connectionId: connectionId,
                provider: provider,
              ),
            ),
          );
        },
      ),
    );

    // 第三波 C5 — MULTI-EXEC 事务执行器
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.lock,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Transaction',
        showArrow: false,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              child: RedisTransactionPanel(
                connectionId: connectionId,
                provider: provider,
              ),
            ),
          );
        },
      ),
    );

    // 第四波 D3 — 键空间通知
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.bellRing,
        iconColor: context.themeColors.accentOrange,
        label: 'Keyspace Notifications',
        showArrow: false,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              child: RedisKeyspacePanel(
                connectionId: connectionId,
                provider: provider,
              ),
            ),
          );
        },
      ),
    );

    // 第四波 D4 — ACL 管理(Redis 6.0+)
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.shieldCheck,
        iconColor: AppDesignSystem.dbRedis,
        label: 'ACL',
        showArrow: false,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              child: RedisAclPanel(
                connectionId: connectionId,
                provider: provider,
              ),
            ),
          );
        },
      ),
    );

    // Pub/Sub - 阶段4 - 集成 Pub/Sub Studio
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.wifi,
        iconColor: AppDesignSystem.dbRedis.withValues(alpha: 0.5),
        label: 'Pub/Sub',
        showArrow: false,
        onTap: () {
          // TODO: 打开 Pub/Sub Studio 面板
          // 当前简化:显示对话框
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              child: RedisPubSubPanel(
                connectionId: connectionId,
                databaseName: '0', // Pub/Sub 为 server 级,与 db 无关,占位即可
                provider: provider,
              ),
            ),
          );
        },
      ),
    );

    return globalNodes;
  }

  void _selectDatabase(String databaseName) {
    provider.switchToConnection(connectionId);
    provider.changeDatabase(databaseName);
  }

  void _showDatabaseContextMenu(String dbName, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'select_db',
          child: Row(
            children: [
              Icon(
                LucideIcons.circleCheckBig,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Select DB'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.commonRefresh),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'new_key',
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sidebarNewKey),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'flush_db',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.sidebarFlushDB,
                style: TextStyle(color: context.themeColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      _handleDatabaseAction(dbName, value);
    });
  }

  Future<void> _handleDatabaseAction(String dbName, String action) async {
    switch (action) {
      case 'select_db':
        await provider.switchToConnection(connectionId);
        await provider.changeDatabase(dbName);
        break;
      case 'refresh':
        provider.loadRedisDatabaseKeyInfo(connectionId, dbName);
        provider.loadRedisTTLKeys(connectionId, dbName);
        provider.loadRedisDBStats(connectionId, dbName);
        break;
      case 'new_key':
        _showNewKeyDialog(dbName);
        break;
      case 'flush_db':
        _showFlushDBDialog(dbName);
        break;
    }
  }

  void _showNewKeyDialog(String dbName) {
    showDialog(
      context: context,
      builder: (ctx) => RedisNewKeyDialog(
        provider: provider,
        connectionId: connectionId,
        dbName: dbName,
      ),
    );
  }

  // 全功能 Redis GUI — 阶段1: Keys 右键菜单
  void _showKeyContextMenu({
    required String dbName,
    required String key,
    required String type,
    required Offset position,
  }) {
    final l10n = AppLocalizations.of(context)!;

    ContextMenuUtils.show(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          id: 'view',
          label: l10n.browseData,
          icon: LucideIcons.eye,
          onTap: () => _handleKeyAction(
            dbName: dbName,
            key: key,
            type: type,
            action: 'view',
          ),
        ),
        ContextMenuItem(
          id: 'copy_name',
          label: l10n.sidebarCopyColumnName,
          icon: LucideIcons.copy,
          onTap: () => _handleKeyAction(
            dbName: dbName,
            key: key,
            type: type,
            action: 'copy_name',
          ),
        ),
        if (type != 'none')
          ContextMenuItem(
            id: 'copy_value',
            label: 'Copy Value',
            icon: LucideIcons.copy,
            onTap: () => _handleKeyAction(
              dbName: dbName,
              key: key,
              type: type,
              action: 'copy_value',
            ),
          ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'set_ttl',
          label: 'Set TTL',
          icon: LucideIcons.timer,
          onTap: () => _handleKeyAction(
            dbName: dbName,
            key: key,
            type: type,
            action: 'set_ttl',
          ),
        ),
        if (type != 'none')
          ContextMenuItem(
            id: 'persist',
            label: 'Remove TTL',
            icon: LucideIcons.infinity,
            onTap: () => _handleKeyAction(
              dbName: dbName,
              key: key,
              type: type,
              action: 'persist',
            ),
          ),
        ContextMenuItem(
          id: 'rename',
          label: l10n.rename,
          icon: LucideIcons.pencilLine,
          onTap: () => _handleKeyAction(
            dbName: dbName,
            key: key,
            type: type,
            action: 'rename',
          ),
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'delete',
          label: l10n.commonDelete,
          icon: LucideIcons.trash2,
          isDestructive: true,
          onTap: () => _handleKeyAction(
            dbName: dbName,
            key: key,
            type: type,
            action: 'delete',
          ),
        ),
      ],
    );
  }

  Future<void> _handleKeyAction({
    required String dbName,
    required String key,
    required String type,
    required String action,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    switch (action) {
      case 'view':
        // 阶段2 - 打开键值编辑器对话框
        showDialog(
          context: context,
          builder: (ctx) => RedisKeyEditorDialog(
            keyName: key,
            type: type,
            connectionId: connectionId,
            databaseName: dbName,
            provider: provider,
          ),
        );
        break;

      case 'copy_name':
        await Clipboard.setData(ClipboardData(text: key));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.messageCopied),
              backgroundColor: context.themeColors.accentGreen,
            ),
          );
        }
        break;

      case 'copy_value':
        // 执行 GET 命令获取值
        try {
          final tab = QueryTab(
            id: '${DateTime.now().millisecondsSinceEpoch}',
            title: 'GET $key',
            sql: 'GET $key',
            connectionId: connectionId,
            databaseName: dbName,
            isAutoTitle: false,
          );
          await provider.addTab(tab);
        } catch (e) {
          if (context.mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              'Failed to copy value: $e',
            );
          }
        }
        break;

      case 'set_ttl':
        // TODO: 在后续实现 set_ttl_dialog
        _showSetTtlDialog(dbName, key);
        break;

      case 'persist':
        try {
          final tab = QueryTab(
            id: '${DateTime.now().millisecondsSinceEpoch}',
            title: 'PERSIST',
            sql: 'PERSIST \'$key\'',
            connectionId: connectionId,
            databaseName: dbName,
            isAutoTitle: false,
          );
          await provider.addTab(tab);
          provider.loadRedisTTLKeys(connectionId, dbName);
        } catch (e) {
          if (context.mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              'Failed to remove TTL: $e',
            );
          }
        }
        break;

      case 'rename':
        _showRenameKeyDialog(dbName, key);
        break;

      case 'delete':
        _confirmDeleteKey(dbName, key);
        break;
    }
  }

  void _showSetTtlDialog(String dbName, String key) {
    showDialog(
      context: context,
      builder: (ctx) => RedisSetTtlDialog(
        provider: provider,
        connectionId: connectionId,
        dbName: dbName,
        redisKey: key,
      ),
    );
  }

  void _showRenameKeyDialog(String dbName, String key) {
    showDialog(
      context: context,
      builder: (ctx) => RedisRenameKeyDialog(
        provider: provider,
        connectionId: connectionId,
        dbName: dbName,
        redisKey: key,
      ),
    );
  }

  void _confirmDeleteKey(String dbName, String key) {
    showDialog(
      context: context,
      builder: (ctx) => RedisDeleteKeyDialog(
        provider: provider,
        connectionId: connectionId,
        dbName: dbName,
        redisKey: key,
      ),
    );
  }

  void _showFlushDBDialog(String dbName) {
    showDialog(
      context: context,
      builder: (ctx) => RedisFlushDbDialog(
        provider: provider,
        connectionId: connectionId,
        dbName: dbName,
      ),
    );
  }
}
