// C17 · MongoDB 侧边栏插件 —— per-type SidebarPlugin。
//
// 拆法裁定（同 C15 PG 两级树）：连接级全局节点（Server / Replication /
// Sharding）走 buildGlobalTree；库级子树（Collections / Views / GridFS，
// 含集合展开的 Document Schema 与 Indexes）走 buildDatabaseTree，消费
// SidebarDatabaseTreeContext 载荷子集。树装配体自 builders/
// mongodb_tree_builder.dart 逐行迁入。
//
// 铁律 3 落点：原 builder 三处直连 adapter（insertOne / dropTable /
// dropIndex 经 cast）收编为 provider 级调用（provider.insertMongoDocument
// 新增；dropTable/dropIndex 走既有 facade），本文件零 adapter import。
//
// C03 发现 #3 处置：原 _showValidationRulesDialog 为「未实现」占位弹窗，
// 本迁移实做为真验证规则查看器（listCollections options 的 validator /
// validationLevel / validationAction 只读展示，无规则与加载失败状态区分）。
//
// capabilityGroups：Mongo 专有能力（集合/索引/视图浏览）即树本体，连接级
// 无真实独立入口（聚合构建器/KillOp 为 C03 backlog），故恒空——能力菜单
// 由 core 项 + port 门控自然裁决。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart' hide QueryTab;
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_logger.dart';
import '../builders/tree_utils.dart';
import '../tree_item.dart';
import '../../../molecules/compact_popup_menu_item.dart';

class MongodbSidebarPlugin implements SidebarPlugin {
  const MongodbSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'mongodb-sidebar',
        supportedTypes: {DatabaseType.mongodb},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) {
    // 见文件头：连接级无真实独立入口，恒空（core 项 + port 门控裁决）。
    return const [];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    return _MongoGlobalNodes(
      context: context,
      provider: tree.provider,
      connectionId: tree.connectionId,
      expandedItems: tree.expandedItems,
      onToggleExpand: tree.onToggleExpand,
    ).buildGlobalNodes();
  }

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) {
    return _MongoDatabaseTree(
      context: context,
      provider: db.provider,
      connectionId: db.connectionId,
      databaseName: db.databaseName,
      searchQuery: db.searchQuery,
      expandedItems: db.expandedItems,
      expandedCollections: db.expandedTables,
      onToggleExpand: db.onToggleExpand,
      onToggleCollection: db.onToggleTable,
    ).build(db.db);
  }
}

/// MongoDB 连接级全局节点装配（自 builders/mongodb_tree_builder.dart 迁入，
/// 行为逐行保持：Server 合并状态、Replication 副本集、Sharding 分片状态）。
class _MongoGlobalNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;
  final Function(String) onToggleExpand;

  _MongoGlobalNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
  });

  /// 构建 MongoDB 全局节点（连接级别）
  List<Widget> buildGlobalNodes() {
    final globalNodes = <Widget>[];

    // Server node
    final serverInfoKey = '$connectionId:mongodb_server_info';
    final isServerInfoExpanded = expandedItems.contains(serverInfoKey);
    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.monitor,
        iconColor: AppDesignSystem.dbMongodb,
        label: 'Server',
        isExpanded: isServerInfoExpanded,
        onTap: () {
          onToggleExpand(serverInfoKey);
          if (!isServerInfoExpanded) {
            provider.loadMongoDBServerInfo(connectionId);
          }
        },
      ),
    );
    if (isServerInfoExpanded) {
      final info = provider.getMongoDBServerInfo(connectionId);

      if (info != null && info.isNotEmpty) {
        final version = info['version'] ?? 'N/A';
        final host = info['host'] ?? 'N/A';
        final uptime = info['uptime'] ?? 0;
        final storageEngine = info['storageEngine'] ?? 'unknown';
        final connections = info['connections'] as Map<String, dynamic>?;
        final currentConn = connections?['current'] ?? 0;
        final availableConn = connections?['available'] ?? 0;

        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.info, 'MongoDB $version'),
        );
        globalNodes.add(
          buildInfoLeaf(context, LucideIcons.server, 'Host: $host'),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.timer,
            'Uptime: ${formatUptime(uptime)}',
          ),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.database,
            'Storage: $storageEngine',
          ),
        );
        globalNodes.add(
          buildInfoLeaf(
            context,
            LucideIcons.users,
            '$currentConn active / $availableConn available',
          ),
        );

        final memory = info['memory'] as Map<String, dynamic>?;
        if (memory != null) {
          final resident = memory['resident'] ?? 0;
          final virtual = memory['virtual'] ?? 0;
          globalNodes.add(
            buildInfoLeaf(
              context,
              LucideIcons.memoryStick,
              'Memory: ${resident}MB resident, ${virtual}MB virtual',
            ),
          );
        }
      } else {
        globalNodes.add(buildLoadingLeaf(context));
      }
    }

    // Replication node
    final replicationKey = '$connectionId:mongodb_replication';
    final isReplicationExpanded = expandedItems.contains(replicationKey);
    final l10n = AppLocalizations.of(context)!;

    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.refreshCw,
        iconColor: AppDesignSystem.dbMongodb,
        label: l10n.mongoNodeReplication,
        isExpanded: isReplicationExpanded,
        onTap: () {
          onToggleExpand(replicationKey);
          if (!isReplicationExpanded) {
            _loadReplicationStatus();
          }
        },
      ),
    );

    if (isReplicationExpanded) {
      globalNodes.add(_buildReplicationContent());
    }

    // Sharding node
    final shardingKey = '$connectionId:mongodb_sharding';
    final isShardingExpanded = expandedItems.contains(shardingKey);

    globalNodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.gitFork,
        iconColor: AppDesignSystem.dbMongodb,
        label: l10n.mongoNodeSharding,
        isExpanded: isShardingExpanded,
        onTap: () {
          onToggleExpand(shardingKey);
          if (!isShardingExpanded) {
            _loadShardingStatus();
          }
        },
      ),
    );

    if (isShardingExpanded) {
      globalNodes.add(_buildShardingContent());
    }

    return globalNodes;
  }

  /// Load sharding status from adapter (#7 — wire to provider cache)
  void _loadShardingStatus() {
    provider.loadMongoDBShardingStatus(connectionId);
  }

  /// Build sharding status content (#7 — render real data from provider cache)
  Widget _buildShardingContent() {
    final l10n = AppLocalizations.of(context)!;

    // 加载中
    if (provider.isLoadingMongoDBSharding(connectionId)) {
      return Padding(
        padding: const EdgeInsets.only(left: 48, top: 8),
        child: buildLoadingLeaf(context),
      );
    }

    final status = provider.getMongoDBShardingStatus(connectionId);
    // 未加载过：触发拉取并显示 loading
    if (status == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.loadMongoDBShardingStatus(connectionId);
      });
      return Padding(
        padding: const EdgeInsets.only(left: 48, top: 8),
        child: buildLoadingLeaf(context),
      );
    }

    // 拉取出错
    if (status['error'] != null) {
      return _buildStatusLeaf(
        icon: LucideIcons.circleAlert,
        iconColor: context.themeColors.error,
        text: 'Failed to load: ${status['error']}',
      );
    }

    // 不是分片集群（哨兵 __loaded=true, isShardedCluster=false）
    if (status['__loaded'] == true && status['isShardedCluster'] == false) {
      return _buildStatusLeaf(
        icon: LucideIcons.info,
        iconColor: context.themeColors.textSecondary,
        text: l10n.mongoShardingNotSharded,
      );
    }

    final shards = (status['shards'] as List<dynamic>?) ?? [];
    final totalShards = status['totalShards'] ?? shards.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusLeaf(
          icon: LucideIcons.gitFork,
          iconColor: AppDesignSystem.dbMongodb,
          text: '$totalShards shards',
        ),
        for (final s in shards)
          _buildStatusLeaf(
            icon: LucideIcons.database,
            iconColor: context.themeColors.textSecondary,
            text: _formatShard(s as Map<String, dynamic>),
            indent: 60,
          ),
      ],
    );
  }

  /// Load replication status from adapter (#7 — wire to provider cache)
  void _loadReplicationStatus() {
    provider.loadMongoDBReplicaSetStatus(connectionId);
  }

  /// Build replication status content (#7 — render real data from provider cache)
  Widget _buildReplicationContent() {
    // 加载中
    if (provider.isLoadingMongoDBReplicaSet(connectionId)) {
      return Padding(
        padding: const EdgeInsets.only(left: 48, top: 8),
        child: buildLoadingLeaf(context),
      );
    }

    final status = provider.getMongoDBReplicaSetStatus(connectionId);
    if (status == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.loadMongoDBReplicaSetStatus(connectionId);
      });
      return Padding(
        padding: const EdgeInsets.only(left: 48, top: 8),
        child: buildLoadingLeaf(context),
      );
    }

    if (status['error'] != null) {
      return _buildStatusLeaf(
        icon: LucideIcons.circleAlert,
        iconColor: context.themeColors.error,
        text: 'Failed to load: ${status['error']}',
      );
    }

    // 不是副本集（哨兵 __loaded=true, isReplicaSet=false）
    if (status['__loaded'] == true && status['isReplicaSet'] == false) {
      return _buildStatusLeaf(
        icon: LucideIcons.info,
        iconColor: context.themeColors.textSecondary,
        text: 'Not a replica set',
      );
    }

    final setName = status['setName'] ?? 'unknown';
    final myState = status['myState'];
    final members = (status['members'] as List<dynamic>?) ?? [];
    // myState 1 = PRIMARY（MongoDB 文档）
    final roleStr = (myState == 1) ? 'PRIMARY' : 'SECONDARY';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusLeaf(
          icon: LucideIcons.tag,
          iconColor: AppDesignSystem.dbMongodb,
          text: 'Set: $setName',
        ),
        _buildStatusLeaf(
          icon: LucideIcons.star,
          iconColor: context.themeColors.warning,
          text: 'This node: $roleStr',
        ),
        for (final m in members)
          _buildStatusLeaf(
            icon: _replicationIcon(m as Map<String, dynamic>),
            iconColor: _replicationColor(context, m),
            text: _formatMember(m),
            indent: 60,
          ),
      ],
    );
  }

  /// 渲染一行带图标的状态叶子节点（替代 placeholder Text）。
  Widget _buildStatusLeaf({
    required IconData icon,
    required Color iconColor,
    required String text,
    double indent = 48,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: indent, top: 4, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatShard(Map<String, dynamic> shard) {
    final id = shard['id'] ?? 'unknown';
    final host = shard['host'] ?? '';
    return '$id — $host';
  }

  String _formatMember(Map<String, dynamic> m) {
    final name = m['name'] ?? 'unknown';
    final state = m['state'] ?? 'UNKNOWN';
    final ping = m['pingMs'];
    final pingStr = (ping != null) ? ' (${ping}ms)' : '';
    return '$name ($state$pingStr)';
  }

  IconData _replicationIcon(Map<String, dynamic> m) {
    final state = (m['state'] as String?) ?? '';
    if (state == 'PRIMARY') return LucideIcons.star;
    if (state == 'SECONDARY') return LucideIcons.cloud;
    if (state == 'ARBITER') return LucideIcons.gavel;
    return LucideIcons.circleHelp;
  }

  Color _replicationColor(BuildContext context, Map<String, dynamic> m) {
    final state = (m['state'] as String?) ?? '';
    final health = m['health'];
    final colors = context.themeColors;
    if (health == 0) return colors.error; // down
    if (state == 'PRIMARY') return colors.warning;
    if (state == 'SECONDARY') return colors.success;
    return colors.textMuted;
  }
}

/// MongoDB 库级子树装配（自 builders/mongodb_tree_builder.dart 迁入，行为
/// 逐行保持；adapter 直连三处收编 provider，验证规则弹窗实做）。
class _MongoDatabaseTree {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final String databaseName;
  final String searchQuery;
  final Set<String> expandedItems;
  final Set<String> expandedCollections;
  final Function(String) onToggleExpand;
  final Function(String) onToggleCollection;

  _MongoDatabaseTree({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.databaseName,
    required this.searchQuery,
    required this.expandedItems,
    required this.expandedCollections,
    required this.onToggleExpand,
    required this.onToggleCollection,
  });

  List<Widget> build(Database db) {
    final nodes = <Widget>[];

    // Collections 节点（替代 Tables）
    nodes.add(_buildCollectionsNode(db));

    // Views 节点
    if (db.views.isNotEmpty) {
      nodes.add(_buildViewsNode(db));
    }

    // GridFS Buckets 节点
    final gridfsBuckets = _getGridFSBuckets(db);
    if (gridfsBuckets.isNotEmpty) {
      nodes.add(_buildGridFSNode(gridfsBuckets));
    }

    return nodes;
  }

  // 大数据集阈值，超过此数量使用虚拟列表优化
  static const int _virtualListThreshold = 50;

  Widget _buildCollectionsNode(Database db) {
    final expandKey = '${db.name}_collections';
    final isExpanded = expandedItems.contains(expandKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 3,
          icon: TreeIcons.collections,
          iconColor: context.themeColors.accentBlue,
          label: 'Collections',
          badge: db.tables.isEmpty ? null : _formatNumber(db.tables.length),
          isExpanded: isExpanded,
          onTap: () => onToggleExpand(expandKey),
        ),
        if (isExpanded) ...[
          Builder(
            builder: (context) {
              final filteredCollections = db.tables
                  .where(
                    (t) =>
                        searchQuery.isEmpty ||
                        t.name.toLowerCase().contains(searchQuery),
                  )
                  .toList();

              // 大数据集优化：超过阈值使用 ListView.builder
              if (filteredCollections.length > _virtualListThreshold) {
                return _buildVirtualCollectionsList(filteredCollections);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: filteredCollections.map((table) {
                  final collectionKey =
                      '$connectionId:$databaseName:${table.name}';
                  final isCollectionExpanded = expandedCollections.contains(
                    collectionKey,
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCollectionItem(
                        table,
                        collectionKey,
                        isCollectionExpanded,
                      ),
                      if (isCollectionExpanded)
                        _buildCollectionDetails(table, collectionKey),
                    ],
                  );
                }).toList(),
              );
            },
          ),
        ],
      ],
    );
  }

  /// 大数据集虚拟列表实现
  Widget _buildVirtualCollectionsList(List<DbTable> collections) {
    return SizedBox(
      height: collections.length * 28.0, // 估算每项高度
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: collections.length,
        itemBuilder: (context, index) {
          final table = collections[index];
          final collectionKey = '$connectionId:$databaseName:${table.name}';
          final isCollectionExpanded = expandedCollections.contains(
            collectionKey,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCollectionItem(table, collectionKey, isCollectionExpanded),
              if (isCollectionExpanded)
                _buildCollectionDetails(table, collectionKey),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCollectionItem(
    DbTable table,
    String collectionKey,
    bool isExpanded,
  ) {
    // 获取集合统计信息
    final stats = provider.getMongoDBCollectionStats(connectionId, table.name);
    final docCount = stats?['documentCount'] as int?;

    String? badge;
    if (docCount != null) {
      badge = _formatNumber(docCount);
    }

    final treeItem = TreeItem(
      level: 4,
      icon: LucideIcons.database,
      iconColor: context.themeColors.accentBlue,
      label: table.name,
      badge: badge,
      isExpanded: isExpanded,
      showArrow: true,
      onTap: () {
        onToggleCollection(collectionKey);
        if (!isExpanded && stats == null) {
          // 懒加载统计信息
          provider.loadMongoDBCollectionStats(
            connectionId,
            databaseName,
            table.name,
          );
        }
      },
      onDoubleTap: () {
        // 打开查询标签页浏览文档
        _browseCollection(table.name);
      },
      onContextMenu: (position) => _showCollectionContextMenu(table, position),
    );

    // 拖拽支持
    return Draggable<MongoCollectionDragData>(
      data: MongoCollectionDragData(
        collectionName: table.name,
        databaseName: databaseName,
        connectionId: connectionId,
      ),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.database,
                size: 14,
                color: AppDesignSystem.dbMongodb,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                table.name,
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: treeItem),
      child: treeItem,
    );
  }

  Widget _buildCollectionDetails(DbTable table, String collectionKey) {
    final schema = provider.getMongoDBSchema(connectionId, table.name);
    final isLoadingSchema = provider.isLoadingMongoDBSchema(
      connectionId,
      table.name,
    );

    // 如果还没有加载 Schema，自动加载（post-frame：load 首行同步
    // notifyListeners，build 期内直调会触发 markNeedsBuild 断言——同
    // Sharding/Replication 懒加载模式，C17 迁移时修复的存量时序缺陷）
    if (schema == null && !isLoadingSchema) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.loadMongoDBSchema(connectionId, databaseName, table.name);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Document Schema
        if (schema != null && schema['fields'] != null) ...[
          _buildSchemaNode(schema['fields'] as Map<String, dynamic>),
        ] else if (isLoadingSchema) ...[
          TreeItem(
            level: 5,
            icon: LucideIcons.hourglass,
            iconColor: context.themeColors.textMuted,
            label: 'Loading schema...',
            showArrow: false,
            onTap: () {},
          ),
        ],
        // Indexes
        TreeItem(
          level: 5,
          icon: LucideIcons.keyRound,
          iconColor: context.themeColors.accentYellow,
          label: 'Indexes (${table.indexes.length})',
          showArrow: false,
          onTap: () {},
          onContextMenu: (position) => _showIndexesContextMenu(table, position),
        ),
        if (table.indexes.isNotEmpty)
          ...table.indexes.map((index) {
            final (idxIcon, idxColor) = _getMongoDBIndexIconInfo(
              index.name,
              index.isUnique,
            );
            final indexProps = _getIndexProperties(index.name);

            return TreeItem(
              level: 6,
              icon: idxIcon,
              iconColor: idxColor,
              label: index.name,
              badge: index.columns.isEmpty ? null : index.columns.join(', '),
              showArrow: false,
              trailing: indexProps.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: indexProps
                          .map(
                            (prop) => Container(
                              margin: const EdgeInsets.only(left: 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: prop.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                  AppDesignSystem.radiusSm,
                                ),
                              ),
                              child: Text(
                                prop.label,
                                style: TextStyle(
                                  // 徽章例外（契约 C4）：角标类 supplementary 文本允许 10px，
                                  // 见 AppDesignSystem.fontSizeXs 注释。
                                  fontSize: 10,
                                  color: prop.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    )
                  : null,
              onTap: () {},
              onContextMenu: (position) =>
                  _showIndexContextMenu(table, index, position),
            );
          }),
      ],
    );
  }

  Widget _buildSchemaNode(Map<String, dynamic> fields, {int level = 5}) {
    final nodes = <Widget>[];

    for (final entry in fields.entries) {
      final fieldName = entry.key;
      final fieldInfo = entry.value as Map<String, dynamic>;
      final bsonType = fieldInfo['type'] as String? ?? 'Unknown';
      final occurrence = fieldInfo['occurrence'] as int? ?? 1;
      final hasSubFields = fieldInfo['subFields'] != null;

      final (fieldIcon, fieldColor) = _getBsonTypeIconInfo(bsonType);

      // 递归展示子字段
      List<Widget>? children;
      if (hasSubFields) {
        final subFields = fieldInfo['subFields'] as Map<String, dynamic>;
        children = [_buildSchemaNode(subFields, level: level + 1)];
      }

      nodes.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TreeItem(
              level: level,
              icon: fieldIcon,
              iconColor: fieldColor,
              label: '$fieldName: $bsonType',
              badge: occurrence < 100 ? '$occurrence%' : null,
              showArrow: hasSubFields,
              onTap: () {},
            ),
            if (children != null) ...children,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes,
    );
  }

  Widget _buildViewsNode(Database db) {
    final expandKey = '${db.name}_views';
    final isExpanded = expandedItems.contains(expandKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 3,
          icon: LucideIcons.eye,
          iconColor: context.themeColors.accentPurple,
          label: 'Views',
          badge: db.views.isEmpty ? null : _formatNumber(db.views.length),
          isExpanded: isExpanded,
          onTap: () => onToggleExpand(expandKey),
        ),
        if (isExpanded)
          ...db.views
              .where(
                (v) =>
                    searchQuery.isEmpty ||
                    v.toLowerCase().contains(searchQuery),
              )
              .map(
                (view) => TreeItem(
                  level: 4,
                  icon: LucideIcons.eye,
                  iconColor: context.themeColors.accentPurple,
                  label: view,
                  onTap: () {},
                  // 视图可操作 —— 双击用 db.<view>.find() 浏览（与集合同查询方式）
                  onDoubleTap: () => _browseCollection(view),
                ),
              ),
      ],
    );
  }

  void _browseCollection(String collectionName) {
    try {
      AppLogger.d('MongoSidebar', 'Browse collection: $collectionName');
      // 生成 MongoDB find 查询语句
      final query = 'db.$collectionName.find().limit(100)';
      final newTab = QueryTab(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '$collectionName.find()',
        sql: query,
        connectionId: connectionId,
        databaseName: databaseName,
        isAutoTitle: true,
      );
      provider.addTab(newTab);
    } catch (e, stackTrace) {
      AppLogger.e(
        'MongoSidebar',
        'Failed to browse collection: $e',
        stackTrace,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.loadFailed(e.toString()),
            ),
          ),
        );
      }
    }
  }

  void _showCollectionContextMenu(DbTable table, Offset position) {
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
          value: 'browse',
          child: Row(
            children: [
              Icon(
                LucideIcons.table2,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              const Text('Browse Documents'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'insert',
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.accentGreen,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarInsertDocument),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'stats',
          child: Row(
            children: [
              Icon(
                LucideIcons.chartColumn,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarViewStats),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'indexes',
          child: Row(
            children: [
              Icon(
                LucideIcons.keyRound,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Indexes (${table.indexes.length})'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'validate',
          child: Row(
            children: [
              Icon(
                LucideIcons.listChecks,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              const Text('Validation Rules'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'drop',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                AppLocalizations.of(context)!.sidebarDropCollectionTitle,
                style: TextStyle(color: context.themeColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'browse':
          // spec 041 US2 同款数据浏览入口（对齐 SQL 系右键「浏览数据」）：
          // 隐 editor + 自动执行 find → C12 文档卡片直出。此前塞未执行的
          // find 进查询编辑器（走查反馈：应直接看到数据）。
          provider.openBrowseDataTab(connectionId, databaseName, table.name);
          break;
        case 'insert':
          // 打开插入文档对话框
          _showInsertDocumentDialog(table.name);
          break;
        case 'stats':
          _showCollectionStatsDialog(table.name);
          break;
        case 'indexes':
          // 展开索引节点
          final idxKey = '$connectionId:$databaseName:${table.name}';
          if (!expandedCollections.contains(idxKey)) {
            onToggleCollection(idxKey);
          }
          break;
        case 'validate':
          _showValidationRulesDialog(table.name);
          break;
        case 'drop':
          _showDropCollectionDialog(table.name);
          break;
      }
    });
  }

  void _showIndexesContextMenu(DbTable table, Offset position) {
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
          value: 'create',
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.accentGreen,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarCreateNewIndex),
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
              const Text('Refresh'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'create':
          _showCreateIndexDialog(table);
          break;
        case 'refresh':
          _refreshCollectionIndexes(table.name);
          break;
      }
    });
  }

  void _showIndexContextMenu(DbTable table, DbIndex index, Offset position) {
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
          value: 'drop',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                AppLocalizations.of(context)!.dropIndex,
                style: TextStyle(color: context.themeColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'drop':
          _showDropIndexDialog(table.name, index.name);
          break;
      }
    });
  }

  void _showCreateIndexDialog(DbTable table) {
    final indexNameController = TextEditingController();
    final columnsController = TextEditingController();
    bool isUnique = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.themeColors.bgSecondary,
          title: Text(
            AppLocalizations.of(context)!.sidebarCreateIndexTitle(table.name),
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: 14,
            ),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: indexNameController,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.sidebarIndexName,
                    labelStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space2,
                      vertical: AppDesignSystem.space1,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                TextField(
                  controller: columnsController,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.sidebarIndexColumns,
                    labelStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                    hintText: AppLocalizations.of(
                      context,
                    )!.sidebarIndexFieldsHint,
                    hintStyle: TextStyle(
                      color: context.themeColors.textMuted.withValues(
                        alpha: 0.5,
                      ),
                      fontSize: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space2,
                      vertical: AppDesignSystem.space1,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                Row(
                  children: [
                    SizedBox(
                      height: 32,
                      child: Switch(
                        value: isUnique,
                        onChanged: (value) => setState(() => isUnique = value),
                        activeThumbColor: context.themeColors.accentBlue,
                      ),
                    ),
                    Text(
                      'Unique',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.commonCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final indexName = indexNameController.text.trim();
                final columnsText = columnsController.text.trim();

                if (indexName.isEmpty || columnsText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.sidebarIndexFieldsRequired,
                      ),
                      backgroundColor: context.themeColors.accentRed,
                    ),
                  );
                  return;
                }

                final columns = columnsText
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();

                Navigator.pop(ctx);
                await _createIndex(table.name, indexName, columns, isUnique);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
                foregroundColor: Colors.white,
              ),
              child: Text(AppLocalizations.of(context)!.sidebarCreate),
            ),
          ],
        ),
      ),
    ).then((_) {
      indexNameController.dispose();
      columnsController.dispose();
    });
  }

  Future<void> _createIndex(
    String collectionName,
    String indexName,
    List<String> columns,
    bool unique,
  ) async {
    try {
      final success = await provider.createIndex(
        databaseName,
        collectionName,
        indexName,
        columns,
        unique: unique,
      );

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.sidebarIndexCreated(indexName, collectionName),
            ),
          ),
        );
        // Refresh the collection to show new index
        await _refreshCollectionIndexes(collectionName);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.createIndexFailed(e.toString()),
            ),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _refreshCollectionIndexes(String collectionName) async {
    try {
      // Reload database info to refresh indexes
      await provider.loadDatabaseInfo(
        connectionId,
        databaseName,
        forceRefresh: true,
      );
      if (context.mounted) {
        // Trigger rebuild by toggling collection expansion
        final key = '$connectionId:$databaseName:$collectionName';
        if (expandedCollections.contains(key)) {
          onToggleCollection(key);
          await Future.delayed(const Duration(milliseconds: 50));
          onToggleCollection(key);
        }
      }
    } catch (e) {
      AppLogger.e('MongoSidebar', 'Failed to refresh indexes: $e');
    }
  }

  void _showDropIndexDialog(String collectionName, String indexName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          AppLocalizations.of(context)!.dropIndexTitle,
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontSize: 14,
          ),
        ),
        content: Text(
          'Are you sure you want to drop index "$indexName" from "$collectionName"?\n\nThis action cannot be undone.',
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _dropIndex(collectionName, indexName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentRed,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context)!.sidebarDrop),
          ),
        ],
      ),
    );
  }

  Future<void> _dropIndex(String collectionName, String indexName) async {
    try {
      // C17：收编 provider facade（原直连 adapter.dropIndex）
      final success = await provider.dropIndex(
        databaseName,
        collectionName,
        indexName,
      );
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.sidebarIndexDropped(indexName),
            ),
          ),
        );
        await _refreshCollectionIndexes(collectionName);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.dropIndexFailed(e.toString()),
            ),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  void _showInsertDocumentDialog(String collectionName) {
    final controller = TextEditingController(text: '{\n  \n}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(AppLocalizations.of(context)!.sidebarInsertDocument),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              hintText: '{\n  "field": "value"\n}',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: 13,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final jsonStr = controller.text.trim();
                if (jsonStr.isEmpty) return;
                final document = jsonDecode(jsonStr) as Map<String, dynamic>;

                // C17：收编 provider（原直连 adapter cast insertOne）
                final success = await provider.insertMongoDocument(
                  connectionId,
                  databaseName,
                  collectionName,
                  document,
                );
                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.sidebarDocumentInserted(
                          collectionName,
                        ),
                      ),
                    ),
                  );
                  provider.loadMongoDBCollectionStats(
                    connectionId,
                    databaseName,
                    collectionName,
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.insertDocumentFailed,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.sidebarFailedInsert(e.toString()),
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context)!.sidebarInsertDocument),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showDropCollectionDialog(String collectionName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(AppLocalizations.of(context)!.sidebarDropCollectionTitle),
        content: Text(
          'Are you sure you want to drop collection "$collectionName"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // C17：收编 provider facade（原直连 adapter.dropTable）
                final success = await provider.dropTable(
                  databaseName,
                  collectionName,
                );
                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.sidebarCollectionDroppedSnack(collectionName),
                      ),
                    ),
                  );
                  await provider.loadDatabaseInfo(connectionId, databaseName);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.sidebarDropCollectionFailed,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.sidebarDropCollectionFailed,
                      ),
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(AppLocalizations.of(context)!.sidebarDrop),
          ),
        ],
      ),
    );
  }

  void _showCollectionStatsDialog(String collectionName) {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder(
        future: provider.loadMongoDBCollectionStats(
          connectionId,
          databaseName,
          collectionName,
        ),
        builder: (context, snapshot) {
          final stats = provider.getMongoDBCollectionStats(
            connectionId,
            collectionName,
          );
          return AlertDialog(
            backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
            title: Text('Stats: $collectionName'),
            content: stats != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatRow(
                        'Document Count',
                        '${stats['documentCount'] ?? 'N/A'}',
                      ),
                      _buildStatRow(
                        'Storage Size',
                        _formatBytes(stats['storageSize'] ?? 0),
                      ),
                      _buildStatRow(
                        AppLocalizations.of(context)!.sidebarIndexSize,
                        _formatBytes(stats['totalIndexSize'] ?? 0),
                      ),
                      _buildStatRow(
                        'Avg Doc Size',
                        _formatBytes(stats['avgObjSize'] ?? 0),
                      ),
                    ],
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'N/A';
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '$bytes B';
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.themeColors.textSecondary,
            ),
          ),
          Text(value, style: TextStyle(color: context.themeColors.textPrimary)),
        ],
      ),
    );
  }

  /// C03 发现 #3 处置：原「未实现」占位弹窗实做为真验证规则查看器——
  /// listCollections options 的 validator（$jsonSchema/查询形状）+
  /// validationLevel / validationAction 只读展示；无规则与加载失败分态。
  void _showValidationRulesDialog(String collectionName) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<Map<String, dynamic>?>(
        future: provider.getMongoCollectionOptions(
          connectionId,
          databaseName,
          collectionName,
        ),
        builder: (context, snapshot) {
          final Widget content;
          if (snapshot.connectionState != ConnectionState.done) {
            content = const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            content = Text(
              l10n.mongoValidationLoadFailed(snapshot.error.toString()),
              style: TextStyle(
                color: context.themeColors.error,
                fontSize: 13,
              ),
            );
          } else {
            final options =
                (snapshot.data?['options'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            final validator = options['validator'];
            final validationLevel = options['validationLevel'];
            final validationAction = options['validationAction'];

            if (validator == null) {
              content = Text(
                l10n.mongoValidationNoValidator,
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: 13,
                ),
              );
            } else {
              const encoder = JsonEncoder.withIndent('  ');
              content = SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatRow(
                      l10n.mongoValidationLevel,
                      validationLevel?.toString() ?? 'strict',
                    ),
                    _buildStatRow(
                      l10n.mongoValidationAction,
                      validationAction?.toString() ?? 'error',
                    ),
                    const SizedBox(height: AppDesignSystem.space2),
                    SelectableText(
                      encoder.convert(validator),
                      style: TextStyle(
                        fontFamily: AppDesignSystem.monoFontFamily,
                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                        fontSize: 12,
                        color: context.themeColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }
          }

          return AlertDialog(
            backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
            title: Text('${l10n.mongoValidationTitle}: $collectionName'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
              child: content,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonClose),
              ),
            ],
          );
        },
      ),
    );
  }

  (IconData, Color) _getBsonTypeIconInfo(String type) {
    switch (type) {
      case 'ObjectId':
        return (LucideIcons.fingerprint, AppDesignSystem.schemaGreen);
      case 'String':
        return (LucideIcons.type, AppDesignSystem.schemaBlue);
      case 'Number':
        return (LucideIcons.hash, AppDesignSystem.schemaPink);
      case 'Date':
        return (LucideIcons.calendar, AppDesignSystem.schemaAmber);
      case 'Boolean':
        return (LucideIcons.toggleRight, AppDesignSystem.schemaGreen);
      case 'Array':
        return (LucideIcons.brackets, AppDesignSystem.schemaPurple);
      case 'Document':
        return (LucideIcons.folderOpen, AppDesignSystem.schemaOrange);
      case 'Binary':
        return (LucideIcons.code, AppDesignSystem.schemaGray);
      case 'Null':
        return (LucideIcons.circleMinus, const Color(0xFF9CA3AF));
      default:
        return (LucideIcons.circleHelp, AppDesignSystem.schemaGray);
    }
  }

  /// 获取索引属性标签
  List<_IndexProperty> _getIndexProperties(String name) {
    final props = <_IndexProperty>[];
    final n = name.toUpperCase();

    if (n.contains('SPARSE')) {
      props.add(_IndexProperty('Sparse', AppDesignSystem.schemaGreen));
    }
    if (n.contains('PARTIAL')) {
      props.add(_IndexProperty('Partial', AppDesignSystem.schemaBlue));
    }
    if (n.contains('HIDDEN')) {
      props.add(_IndexProperty('Hidden', AppDesignSystem.schemaGray));
    }
    if (n.contains('TTL')) {
      props.add(_IndexProperty('TTL', AppDesignSystem.schemaYellow));
    }

    return props;
  }

  (IconData, Color) _getMongoDBIndexIconInfo(String name, bool isUnique) {
    final n = name.toUpperCase();
    if (n == '_ID_' || n.contains('PRIMARY')) {
      return (LucideIcons.keyRound, AppDesignSystem.schemaRed);
    }
    if (isUnique || n.contains('UNIQUE')) {
      return (LucideIcons.lock, AppDesignSystem.schemaAmber);
    }
    if (n.contains('TEXT')) {
      return (LucideIcons.search, AppDesignSystem.schemaBlue);
    }
    if (n.contains('2DSPHERE') || n.contains('GEO')) {
      return (LucideIcons.map, AppDesignSystem.schemaLime);
    }
    if (n.contains('HASHED')) {
      return (LucideIcons.tag, AppDesignSystem.schemaPurple);
    }
    if (n.contains('TTL')) {
      return (LucideIcons.timer, AppDesignSystem.schemaYellow);
    }
    return (LucideIcons.list, AppDesignSystem.schemaGray);
  }

  // ========== GridFS 支持 ==========

  /// 从数据库表中识别 GridFS Buckets
  List<String> _getGridFSBuckets(Database db) {
    final buckets = <String>{};
    final collectionNames = db.tables.map((t) => t.name).toList();

    for (final name in collectionNames) {
      if (name.endsWith('.files')) {
        final bucket = name.substring(0, name.length - 6);
        if (collectionNames.contains('$bucket.chunks')) {
          buckets.add(bucket);
        }
      }
    }

    return buckets.toList();
  }

  /// 构建 GridFS 节点
  Widget _buildGridFSNode(List<String> buckets) {
    final expandKey = '${databaseName}_gridfs';
    final isExpanded = expandedItems.contains(expandKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 3,
          icon: LucideIcons.folderBookmark,
          iconColor: context.themeColors.accentPurple,
          label: 'GridFS Buckets',
          badge: buckets.length.toString(),
          isExpanded: isExpanded,
          onTap: () => onToggleExpand(expandKey),
        ),
        if (isExpanded)
          ...buckets.map(
            (bucket) => TreeItem(
              level: 4,
              icon: LucideIcons.database,
              iconColor: context.themeColors.accentPurple,
              label: bucket,
              badge: '2 collections',
              showArrow: false,
              onTap: () {},
            ),
          ),
      ],
    );
  }

  String _formatNumber(int num) {
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toString();
  }
}

/// 索引属性标签
class _IndexProperty {
  final String label;
  final Color color;

  const _IndexProperty(this.label, this.color);
}

/// MongoDB Collection 拖拽数据
class MongoCollectionDragData {
  final String collectionName;
  final String databaseName;
  final String connectionId;

  const MongoCollectionDragData({
    required this.collectionName,
    required this.databaseName,
    required this.connectionId,
  });

  /// 生成 find 查询语句
  String get findStatement => 'db.$collectionName.find().limit(100)';

  /// 生成 count 查询语句
  String get countStatement => 'db.$collectionName.countDocuments()';

  /// 生成聚合查询框架
  String get aggregateStatement => '''db.$collectionName.aggregate([
  { \$match: { } },
  { \$group: { _id: null, count: { \$sum: 1 } } }
])''';

  @override
  String toString() => 'MongoCollectionDragData($collectionName)';
}
