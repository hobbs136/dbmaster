import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../models/database_models.dart';
import '../tree_item.dart';

// 图标体系已全面切 Lucide（D9，C07；跨平台一致、可主题着色、可对齐网格）
class TreeIcons {
  static const IconData tables = LucideIcons.table2;
  static const IconData views = LucideIcons.eye;
  static const IconData procedures = LucideIcons.network;
  static const IconData functions = LucideIcons.functionSquare;
  static const IconData triggers = LucideIcons.zap;
  static const IconData indexes = LucideIcons.keyRound;
  static const IconData columns = LucideIcons.columns2;
  static const IconData server = LucideIcons.server;
  static const IconData users = LucideIcons.users;
  static const IconData performance = LucideIcons.chartLine;
  static const IconData table = LucideIcons.table2;
  static const IconData view = LucideIcons.eye;
  static const IconData procedure = LucideIcons.network;
  static const IconData trigger = LucideIcons.zap;
  static const IconData database = LucideIcons.database;
  static const IconData info = LucideIcons.info;
  static const IconData folder = LucideIcons.folder;
  static const IconData collections = LucideIcons.package;
  static const IconData collection = LucideIcons.package;
  static const IconData document = LucideIcons.fileText;
  static const IconData gridfs = LucideIcons.package;
  static const IconData schema = LucideIcons.folderOpen;
  static const IconData materializedView = LucideIcons.eye;
  static const IconData sequence = LucideIcons.listOrdered;
}

/// 构建信息叶子节点
Widget buildInfoLeaf(
  BuildContext context,
  IconData icon,
  String label, {
  Color? iconColor,
}) {
  return TreeItem(
    level: 3,
    icon: icon,
    iconColor: iconColor ?? context.themeColors.textSecondary,
    label: label,
    showArrow: false,
    onTap: () {},
  );
}

// buildEmojiInfoLeaf 已移除（emoji 退场后无调用方；信息叶子统一用 buildInfoLeaf）

/// 构建加载中叶子节点
Widget buildLoadingLeaf(BuildContext context) {
  return buildInfoLeaf(
    context,
    LucideIcons.hourglass,
    'Loading...',
    iconColor: context.themeColors.textMuted,
  );
}

// 提取自 postgresql_tree_builder —— 可折叠简单对象分类（Views/Procedures/Functions 等），
// 供 PG 与 SQL Server 共享（copy-on-write：默认共享，仅在需要分歧时各自 fork）。
// T039b — 新增 onItemContextMenu（叶子右键）与 onHeaderContextMenu（分类头右键），
// 让 PG/SQL Server 的 Views/Procedures/Functions 等叶子继承上下文菜单（FR-008/009/014）。
List<Widget> buildSimpleObjectCategory({
  required BuildContext context,
  required Set<String> expandedItems,
  required void Function(String key) onToggleExpand,
  required bool Function(String key) isSelected,
  required String categoryKey,
  required IconData icon,
  required String label,
  required List<String> items,
  required int totalCount,
  required String sq,
  required int level,
  void Function(String name)? onDoubleTap,
  void Function(String name, Offset position)? onItemContextMenu,
  void Function(Offset position)? onHeaderContextMenu,
}) {
  final widgets = <Widget>[];
  final expanded = sq.isNotEmpty || expandedItems.contains(categoryKey);
  widgets.add(
    TreeItem(
      level: level,
      icon: icon,
      iconColor: context.themeColors.accentBlue,
      label:
          '$label (${items.length}${sq.isNotEmpty && items.length != totalCount ? "/$totalCount" : ""})',
      isExpanded: expanded,
      isSelected: isSelected('cat:$categoryKey'),
      showArrow: true,
      onTap: () => onToggleExpand(categoryKey),
      onContextMenu: onHeaderContextMenu, // T039b — 分类头右键
    ),
  );
  if (expanded) {
    for (final item in items) {
      widgets.add(
        TreeItem(
          level: level + 1,
          icon: icon,
          iconColor: context.themeColors.textSecondary,
          iconSize: 12,
          label: item,
          showArrow: false,
          onTap: () {},
          onDoubleTap: onDoubleTap != null ? () => onDoubleTap(item) : null,
          // T039b — 叶子右键（对象名由调用方决定是否 schema-qualified）
          onContextMenu: onItemContextMenu == null
              ? null
              : (pos) => onItemContextMenu(item, pos),
        ),
      );
    }
  }
  return widgets;
}

/// 骨架屏占位节点（数据库加载中）
Widget buildSkeletonLeaf(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.only(left: 84, top: 2, bottom: 2),
    child: Container(
      height: 14,
      width: 120,
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
    ),
  );
}

/// 构建骨架屏占位列表（N 条闪烁占位）
List<Widget> buildSkeletonPlaceholders(BuildContext context, {int count = 4}) {
  return List.generate(count, (_) => buildSkeletonLeaf(context));
}

/// 构建分隔线
Widget buildDivider(BuildContext context) {
  return Container(
    height: 1,
    margin: const EdgeInsets.symmetric(
      vertical: AppDesignSystem.space2,
      horizontal: AppDesignSystem.space3,
    ),
    color: context.themeColors.borderSubtle,
  );
}

/// 格式化数字（添加 K/M 后缀）
String formatNumber(int num) {
  if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
  if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
  return num.toString();
}

/// 格式化 TTL（秒转人类可读）
String formatTTL(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  if (seconds < 86400) return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  return '${seconds ~/ 86400}d ${(seconds % 86400) ~/ 3600}h';
}

/// 格式化运行时间
String formatUptime(Object? seconds) {
  if (seconds == null) return 'N/A';
  final s = seconds is int ? seconds : int.tryParse(seconds.toString()) ?? 0;
  final days = s ~/ 86400;
  final hours = (s % 86400) ~/ 3600;
  final mins = (s % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h ${mins}m';
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}

/// 根据列类型获取图标和颜色
// 硬编码 hex 全部替换为 AppDesignSystem.schema* 语义色 token
(IconData, Color) getColumnIconInfo(String type) {
  final t = type.toUpperCase();
  if (t.contains('INT') ||
      t.contains('BIGINT') ||
      t.contains('SMALLINT') ||
      t.contains('TINYINT')) {
    return (LucideIcons.pin, AppDesignSystem.schemaBlue);
  }
  if (t.contains('VARCHAR') || t.contains('TEXT') || t.contains('CHAR')) {
    return (LucideIcons.type, AppDesignSystem.schemaIndigo);
  }
  if (t.contains('DATE') || t.contains('TIME')) {
    return (LucideIcons.calendar, AppDesignSystem.schemaAmber);
  }
  if (t.contains('BOOL') || t.contains('BIT')) {
    return (LucideIcons.toggleRight, AppDesignSystem.schemaGreen);
  }
  if (t.contains('DECIMAL') ||
      t.contains('FLOAT') ||
      t.contains('DOUBLE') ||
      t.contains('NUMERIC')) {
    return (LucideIcons.dollarSign, AppDesignSystem.schemaPink);
  }
  if (t.contains('BLOB') || t.contains('BINARY')) {
    return (LucideIcons.archive, AppDesignSystem.schemaPurple);
  }
  if (t.contains('JSON')) {
    return (LucideIcons.code, AppDesignSystem.schemaCyan);
  }
  if (t.contains('ENUM') || t.contains('SET')) {
    return (LucideIcons.list, AppDesignSystem.schemaOrange);
  }
  if (t.contains('TIMESTAMP')) {
    return (LucideIcons.timer, AppDesignSystem.schemaYellow);
  }
  if (t.contains('POINT') || t.contains('GEOMETRY') || t.contains('SPATIAL')) {
    return (LucideIcons.map, AppDesignSystem.schemaLime);
  }
  return (LucideIcons.list, AppDesignSystem.schemaGray);
}

/// 根据列类型获取标签颜色
// 硬编码 hex 全部替换为 AppDesignSystem.schema* 语义色 token
Color getTagTypeColor(String type) {
  final t = type.toUpperCase();
  if (t.contains('INT') || t.contains('BIGINT')) {
    return AppDesignSystem.schemaBlue;
  }
  if (t.contains('FLOAT') || t.contains('DOUBLE')) {
    return AppDesignSystem.schemaPink;
  }
  if (t.contains('BINARY') || t.contains('NCHAR') || t.contains('VARCHAR')) {
    return AppDesignSystem.schemaGreen;
  }
  if (t.contains('BOOL')) {
    return AppDesignSystem.schemaAmber;
  }
  if (t.contains('TIMESTAMP')) {
    return AppDesignSystem.schemaYellow;
  }
  if (t.contains('JSON')) {
    return AppDesignSystem.schemaCyan;
  }
  return AppDesignSystem.schemaPurple;
}

/// 根据索引名称获取图标和颜色
// 硬编码 hex 全部替换为 AppDesignSystem.schema* 语义色 token
(IconData, Color) getIndexIconInfo(
  String name,
  bool isUnique, {
  bool isForeignKey = false,
}) {
  final n = name.toUpperCase();
  if (n.contains('PRIMARY') || n == 'PRIMARY') {
    return (LucideIcons.keyRound, AppDesignSystem.schemaRed);
  }
  if (isForeignKey || n.contains('FOREIGN') || n.contains('FK_')) {
    return (LucideIcons.link, AppDesignSystem.schemaPurple);
  }
  if (isUnique || n.contains('UNIQUE')) {
    return (LucideIcons.lock, AppDesignSystem.schemaAmber);
  }
  if (n.contains('FULLTEXT')) {
    return (LucideIcons.search, AppDesignSystem.schemaBlue);
  }
  if (n.contains('COMPOSITE') || n.contains('MULTI')) {
    return (LucideIcons.puzzle, AppDesignSystem.schemaGreen);
  }
  return (LucideIcons.list, AppDesignSystem.schemaGray);
}

// ============================================================================
// 树形详情节点辅助函数（供 SidebarTree / PostgresqlTreeBuilder 等复用）
// ============================================================================

/// Calculate the left indent for non-TreeItem schema detail nodes
/// (group headers, columns, indexes, foreign keys) at a given [level].
///
/// Produces the same label-start position as [TreeItem] would at that level,
/// matching: leftPadding + connectors + arrowSection + iconSize + iconGap.
double schemaNodeIndent(int level) {
  const leftPad = AppDesignSystem.space3; // TreeItem uses space3 for level≥3
  const arrowSection = 14.0 + AppDesignSystem.space1; // arrow width + gap
  const iconSize = 14.0; // TreeItem icon size for level≥3
  const iconGap = AppDesignSystem.space2;
  final connectors = (level - 1) * AppDesignSystem.treeNodeIndent;
  return leftPad + connectors + arrowSection + iconSize + iconGap;
}

/// 构建列分组标题（Columns / Indexes / Foreign Keys）
Widget buildTreeGroupHeader(
  BuildContext context,
  IconData icon,
  String label,
  String count,
) {
  final c = context.themeColors;
  return Padding(
    padding: EdgeInsets.only(left: schemaNodeIndent(5)),
    child: Row(
      children: [
        // 分组头字号下限（label 9→11、count 8→9、icon 10→12）
        Icon(icon, size: 12, color: c.textMuted),
        const SizedBox(width: AppDesignSystem.space1),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
          ),
        ),
        const SizedBox(width: AppDesignSystem.space1),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: c.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Text(
            count,
            style: TextStyle(fontSize: 11, color: c.textMuted),
          ),
        ),
      ],
    ),
  );
}

/// 构建加载中占位节点
Widget buildTreeLoadingNode(BuildContext context) {
  return Padding(
    padding: EdgeInsets.only(left: schemaNodeIndent(5)),
    child: const SizedBox(
      height: AppDesignSystem.space5,
      child: Center(
        child: SizedBox(
          width: AppDesignSystem.space3,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
    ),
  );
}

// ============================================================================
// 交互式 schema 叶子节点（列扁平 / 索引 / 外键）—— MySQL/Doris + PostgreSQL 共用
// ============================================================================

/// 构建一个交互式 schema 叶子 [TreeItem]：复用 TreeItem 的悬停/选中/单击/双击/右键
/// 脚手架，视觉由 [labelWidget] 决定（保留原有"图标+名+类型+徽章"布局）。
Widget _interactiveSchemaLeaf({
  required BuildContext context,
  required String key,
  required IconData iconData,
  required Color iconColor,
  required bool Function(String key) isSelected,
  required void Function(String key) onSelect,
  required VoidCallback onInsert,
  required void Function(Offset position)? onMenu,
  required Widget labelWidget,
}) {
  return TreeItem(
    level: 6,
    icon: iconData,
    iconColor: iconColor,
    iconSize: 10,
    showArrow: false,
    isSelected: isSelected(key),
    onTap: () => onSelect(key),
    onDoubleTap: onInsert,
    onContextMenu: onMenu,
    labelWidget: labelWidget,
  );
}

/// 区段分隔线（字段↔索引、索引↔外键），与分组头同缩进。
// 区段分割线（需求：扁平化后字段/索引区段间增加分隔）
class SchemaSectionDivider extends StatelessWidget {
  const SchemaSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: schemaNodeIndent(5),
        right: AppDesignSystem.space3,
        top: AppDesignSystem.space1,
        bottom: AppDesignSystem.space1,
      ),
      child: Container(
        height: 1,
        color: context.themeColors.borderSubtle,
      ),
    );
  }
}

Widget _columnLabelWidget(BuildContext context, DbColumn col) {
  final c = context.themeColors;
  final badges = <String>[];
  if (col.isPrimaryKey) badges.add('PK');
  if (!col.isNullable) badges.add('NN');
  if (col.defaultValue != null && col.defaultValue!.isNotEmpty) {
    badges.add(
      '= ${col.defaultValue!.length > 12 ? "${col.defaultValue!.substring(0, 11)}…" : col.defaultValue!}',
    );
  }
  return Row(
    children: [
      Flexible(
        child: Text(
          col.name,
          style: TextStyle(fontSize: 11, color: c.textSecondary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: AppDesignSystem.space1),
      // 类型字号 9→10，避免 Windows 下模糊
      Text(col.type, style: TextStyle(fontSize: 11, color: c.textMuted)),
      ...badges.map(
        (b) => Container(
          margin: const EdgeInsets.only(left: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space0_5,
          ),
          decoration: BoxDecoration(
            color: c.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          // 徽章字号 7→9（原低于可读下限），色值改用主题 token
          child: Text(b, style: TextStyle(fontSize: 11, color: c.textMuted)),
        ),
      ),
    ],
  );
}

Widget _indexLabelWidget(BuildContext context, DbIndex idx) {
  final c = context.themeColors;
  return Row(
    children: [
      Flexible(
        child: Text(
          '${idx.name}  (${idx.columns.join(', ')})',
          style: TextStyle(fontSize: 11, color: c.textSecondary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

Widget _fkLabelWidget(BuildContext context, ForeignKey fk) {
  final c = context.themeColors;
  return Row(
    children: [
      Flexible(
        child: Text(
          '${fk.name}  (${fk.column} → ${fk.referencedTable}.${fk.referencedColumn})',
          style: TextStyle(fontSize: 11, color: c.textSecondary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// 构建某张已展开表的交互式 schema 叶子列表：
/// - 列**扁平**渲染（无 "Columns" 组头），每个列为交互式 [TreeItem]；
/// - 随后 "Indexes (N)" 组头 + 交互式索引叶子；
/// - "Foreign Keys (N)" 组头 + 交互式外键叶子。
///
/// 列/索引/外键的节点 key 由 [colKeyOf]/[idxKeyOf]/[fkKeyOf] 生成（PG 含 schema 段）。
/// [onSelect] 单击选中、[onInsert] 双击/Enter 插入活动编辑器、菜单回调可选。
/// 供 MySQL/Doris（[SidebarTree._buildDatabaseObjects]）与 PostgreSQL
/// （[PostgresqlTreeBuilder._buildTableNode]）共用。
List<Widget> buildInteractiveTableSchemaLeaves({
  required BuildContext context,
  required DbTable schema,
  required List<ForeignKey> foreignKeys,
  required String indexesLabel,
  required String foreignKeysLabel,
  required String Function(DbColumn) colKeyOf,
  required String Function(DbIndex) idxKeyOf,
  required String Function(ForeignKey) fkKeyOf,
  required bool Function(String key) isSelected,
  required void Function(String key) onSelect,
  required void Function(String name) onInsert,
  void Function(Offset position, DbColumn col)? onColumnMenu,
  void Function(Offset position, DbIndex idx)? onIndexMenu,
  void Function(Offset position, ForeignKey fk)? onFkMenu,
}) {
  final widgets = <Widget>[];
  // 列扁平（去掉 Columns 组头）
  for (final col in schema.columns) {
    final (icon, color) = getColumnIconInfo(col.type);
    widgets.add(
      _interactiveSchemaLeaf(
        context: context,
        key: colKeyOf(col),
        iconData: icon,
        iconColor: color,
        isSelected: isSelected,
        onSelect: onSelect,
        onInsert: () => onInsert(col.name),
        onMenu: onColumnMenu == null ? null : (pos) => onColumnMenu(pos, col),
        labelWidget: _columnLabelWidget(context, col),
      ),
    );
  }
  if (schema.indexes.isNotEmpty) {
    if (schema.columns.isNotEmpty) {
      widgets.add(const SchemaSectionDivider()); // 字段↔索引 分割线
    }
    widgets.add(
      buildTreeGroupHeader(
        context,
        LucideIcons.list,
        indexesLabel,
        '${schema.indexes.length}',
      ),
    );
    for (final idx in schema.indexes) {
      final (icon, color) = getIndexIconInfo(
        idx.name,
        idx.isUnique,
        isForeignKey: idx.isForeignKey,
      );
      widgets.add(
        _interactiveSchemaLeaf(
          context: context,
          key: idxKeyOf(idx),
          iconData: icon,
          iconColor: color,
          isSelected: isSelected,
          onSelect: onSelect,
          onInsert: () => onInsert(idx.name),
          onMenu: onIndexMenu == null ? null : (pos) => onIndexMenu(pos, idx),
          labelWidget: _indexLabelWidget(context, idx),
        ),
      );
    }
  }
  if (foreignKeys.isNotEmpty) {
    if (schema.columns.isNotEmpty || schema.indexes.isNotEmpty) {
      widgets.add(const SchemaSectionDivider()); // 索引↔外键 分割线
    }
    widgets.add(
      buildTreeGroupHeader(
        context,
        LucideIcons.link,
        foreignKeysLabel,
        '${foreignKeys.length}',
      ),
    );
    for (final fk in foreignKeys) {
      widgets.add(
        _interactiveSchemaLeaf(
          context: context,
          key: fkKeyOf(fk),
          iconData: LucideIcons.link,
          iconColor: AppDesignSystem.schemaPurple,
          isSelected: isSelected,
          onSelect: onSelect,
          onInsert: () => onInsert(fk.name),
          onMenu: onFkMenu == null ? null : (pos) => onFkMenu(pos, fk),
          labelWidget: _fkLabelWidget(context, fk),
        ),
      );
    }
  }
  return widgets;
}
