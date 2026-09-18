// C01a · UI 插件注册框架 —— 侧边栏插件接口（C4 消费）。
//
// 对应原型「侧边栏能力菜单」：对象树 + 按分组组织的能力菜单。
// C14-C20 将把 sidebar_tree.dart 分发巨石与 7 个 tree builder 迁移为
// 注册表分发的侧边栏插件；能力项是否展示/可用由宿主按 port 能力位裁决。
//
// 铁律 2 落点：[SidebarCapabilityItem.capabilityId] 只是 port 能力位的
// 查询键（纯 UI 元数据），能力的真值永远来自 DbCapabilityPort——宿主渲染
// 前查询，查不到 = 不渲染，插件无权自带能力开关。
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/database_models.dart';
import '../providers/app_provider.dart';
import 'plugin_descriptor.dart';

/// 连接级全局树上下文。字段对齐现有 `XxxTreeBuilder` 构造参数
/// （context / provider / connectionId / expandedItems / onToggleExpand），
/// 使 C15-C18 的 builder 迁移保持机械化。
///
/// [provider] 在 port（C01）落地后由 C14 演进为经 port 的数据访问；
/// 接口形状（展开集合 + 切换回调）预计保持稳定。
///
/// C16 增补三字段（SQLite 整树是连接级的：无数据库层、ATTACH alias 列表
/// 来自 PRAGMA database_list 的连接级事实，故搜索过滤与表级展开也在连接级）：
/// MySQL/PG 全局树不消费，均有默认值，向后兼容。
///
/// C17 增补五字段（Redis 整树同为连接级：逻辑库 db0-15 列表来自 keyspace
/// 的连接级事实，库节点在连接卡片展开区直接渲染，且 key 样本有选中态）：
/// [databases]（宿主搜索过滤后的库列表）、[expandedDatabases] /
/// [onToggleDatabase]（库级展开与分类展开分轨，同宿主 expandedTables 模式）、
/// [selectedNodeKey] / [onSelectNode]（key 样本叶子的选中/右键态）。
/// MySQL/PG/SQLite 不消费，均有默认值，向后兼容。
@immutable
class SidebarTreeContext {
  final AppProvider provider;
  final String connectionId;

  /// 展开节点的 key 集合。沿用 SidebarController 的 immutable Set
  /// replacement 模式：每次变更由宿主新建 Set。
  final Set<String> expandedItems;
  final void Function(String key) onToggleExpand;

  /// 对象过滤词（连接卡搜索框透传；空 = 不过滤）。
  final String searchQuery;

  /// 表级展开 key 集合 + 切换回调（表展开与分类展开分轨）。
  final Set<String> expandedTables;
  final void Function(String key) onToggleTable;

  /// 库级展开 key 集合 + 切换回调（Redis 逻辑库节点展开；C17）。
  final Set<String> expandedDatabases;
  final void Function(String key) onToggleDatabase;

  /// 宿主搜索过滤后的库列表（Redis 整树在连接级直接渲染库节点；C17）。
  final List<String> databases;

  /// 选中/右键节点 key 与选中回调（Redis key 样本叶子消费；C17）。
  final String? selectedNodeKey;
  final ValueChanged<String>? onSelectNode;

  const SidebarTreeContext({
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
    this.searchQuery = '',
    this.expandedTables = const {},
    this.onToggleTable = _noopToggle,
    this.expandedDatabases = const {},
    this.onToggleDatabase = _noopToggle,
    this.databases = const [],
    this.selectedNodeKey,
    this.onSelectNode,
  });

  static void _noopToggle(String key) {}
}

/// 库级对象树上下文（C15 增补）。字段对齐原
/// `PostgresqlTreeBuilder.buildDatabaseNode` 的全量参数——宿主（sidebar_tree）
/// 在树分缝处一次性装配，插件按需消费；C16-C18 的 builder 迁移复用同一
/// 载荷（SQLite/Mongo/Redis builder 的构造参数是其子集）。
///
/// 菜单路由回调（onShowTableMenu 等）是宿主私有装配（关闭于宿主状态），
/// 经此透传给插件树叶子——插件不感知宿主实现，只按签名调用。
@immutable
class SidebarDatabaseTreeContext {
  final AppProvider provider;
  final String connectionId;
  final DbServer server;

  /// 当前正在装配子树的数据库（每个库节点各调用一次 buildDatabaseTree）。
  final String databaseName;
  final Database db;
  final String searchQuery;

  // ── 展开状态（连接级 + 表级）──
  final Set<String> expandedItems;
  final void Function(String key) onToggleExpand;
  final Set<String> expandedTables;
  final void Function(String key) onToggleTable;

  // ── 表 schema 懒加载状态 ──
  final Map<String, DbTable> loadedTableSchemas;
  final Map<String, List<ForeignKey>> loadedTableForeignKeys;
  final Set<String> loadingTableSchemas;
  final Map<String, int> tableRowCounts;
  final Future<void> Function(String connectionId, String databaseName)?
  onLoadTableRowCounts;
  final Future<void> Function(String connectionId)? onLoadTableSchema;

  // ── 选中/右键态 ──
  final String? rightClickedNodeKey;
  final void Function(String? key)? onRightClickTargetChanged;
  final String? selectedNodeKey;
  final ValueChanged<String>? onSelectNode;

  // ── 宿主菜单路由（sidebar_tree 私有装配的透传）──
  final Future<void> Function(
    BuildContext context,
    String tableName,
    Offset position,
  )
  onShowTableMenu;
  final void Function(
    BuildContext context,
    DbTable schema,
    DbColumn col,
    Offset position,
  )?
  onShowColumnMenu;
  final void Function(
    DbIndex idx,
    String schema,
    String tableName,
    List<DbColumn> columns,
    Offset pos,
  )?
  onShowIndexMenu;
  final void Function(ForeignKey fk, Offset pos)? onShowFkMenu;

  /// 视图叶子右键菜单。[isMaterializedView] = 物化视图叶子（DROP 语句与
  /// 确认文案不同；泛 SQL 共享树 MV 分类消费 true，PG/SS 视图叶子 false）。
  final void Function(
    String qualifiedName,
    Offset pos,
    bool isMaterializedView,
  )?
  onShowViewMenu;

  /// 过程/函数叶子右键菜单。[isFunction] = 函数叶子（MySQL/Doris 把函数
  /// 折进 procedures 列表；调用语句 SELECT 而非 CALL）。
  final void Function(
    String qualifiedName,
    Offset pos,
    bool isFunction,
  )?
  onShowProcedureMenu;

  /// 分类头右键菜单（C19 扩参）：[offerCreateTable] = tables 分类头提供
  /// Create Table（泛 SQL 共享树 = true；PG/SS schema 树 = false——
  /// Create Table 对话框非 schema-aware）；[categoryType] = 'view' /
  /// 'materialized_view' 时提供对应对话框项，null = 仅 Refresh。
  final void Function(
    Offset pos,
    bool offerCreateTable,
    String? categoryType,
  )?
  onShowCategoryMenu;
  final void Function(String name) onInsertName;

  const SidebarDatabaseTreeContext({
    required this.provider,
    required this.connectionId,
    required this.server,
    required this.databaseName,
    required this.db,
    required this.searchQuery,
    required this.expandedItems,
    required this.onToggleExpand,
    required this.expandedTables,
    required this.onToggleTable,
    required this.loadedTableSchemas,
    required this.loadedTableForeignKeys,
    required this.loadingTableSchemas,
    required this.tableRowCounts,
    this.onLoadTableRowCounts,
    this.onLoadTableSchema,
    this.rightClickedNodeKey,
    this.onRightClickTargetChanged,
    this.selectedNodeKey,
    this.onSelectNode,
    required this.onShowTableMenu,
    this.onShowColumnMenu,
    this.onShowIndexMenu,
    this.onShowFkMenu,
    this.onShowViewMenu,
    this.onShowProcedureMenu,
    this.onShowCategoryMenu,
    required this.onInsertName,
  });
}

/// 侧边栏能力分组（原型分组示例：Redis 的「键空间 / 数据结构 / 高级」、
/// ClickHouse 的「数据库对象 / 数据操作 / 高级」等）。
@immutable
class SidebarCapabilityGroup {
  final String id;
  final String Function(AppLocalizations l10n) label;
  final IconData icon;
  final List<SidebarCapabilityItem> items;

  const SidebarCapabilityGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.items,
  });
}

/// 能力菜单单项。纯 UI 元数据 + 激活回调；是否展示由宿主按
/// [capabilityId] 查 port 决定（null = 无条件展示的纯导航项）。
@immutable
class SidebarCapabilityItem {
  final String id;
  final String Function(AppLocalizations l10n) label;
  final IconData icon;

  /// port 能力位键（如 `redis.pubsub`、`mysql.killQuery`）。键空间由
  /// C01 与 T27 联合定稿；宿主查询不到该能力时隐藏本项。
  final String? capabilityId;

  /// 激活动作（打开面板 / 对话框 / 视图）。运行时上下文由插件在
  /// capabilityGroups 构造时闭包捕获；null = 仅展示。
  final VoidCallback? onActivate;

  /// 品牌色高亮（原型「AI 助手」项形态：brand-subtle 底 + 主色文字，
  /// sidebar-capability-menu.html）。C14 增补，默认 false。
  final bool highlight;

  const SidebarCapabilityItem({
    required this.id,
    required this.label,
    required this.icon,
    this.capabilityId,
    this.onActivate,
    this.highlight = false,
  });
}

/// 侧边栏插件（C4 消费；实现见 C14 起新框架与 C15-C20 各类型迁移）。
///
/// 树装配分两级（C15 拆分，原单一 `buildObjectTree` 演进）：
/// 连接级全局节点（`buildGlobalTree`）与库级对象子树（`buildDatabaseTree`），
/// 分别对应宿主 sidebar_tree 的两处分缝。任一级返回空列表 = 该插件不
/// 接管该级，宿主回退旧装配（C19 删除旧路径时分缝反转）。
abstract interface class SidebarPlugin {
  PluginDescriptor get descriptor;

  /// 能力分组目录（侧边栏能力菜单数据源）。按当前连接的运行时上下文
  /// 提供；能力项的展示/可用性裁决归宿主 + port。
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context);

  /// 连接级全局节点（数据库列表与分隔线之后的类型专有区：
  /// Server / Performance / Users 等）。空 = 未迁移 → 宿主回退旧 dispatch。
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree);

  /// 库级对象子树（接管 `_buildDatabaseObjectsOrSchemaAware` 的整个装配，
  /// 含 schema 层；搜索过滤责任随迁移移交插件树）。
  /// 空树 = 未迁移，宿主回退旧装配。
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  );
}
