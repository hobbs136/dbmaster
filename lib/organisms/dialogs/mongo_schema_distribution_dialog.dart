// DBT-T17 · MongoDB Schema 类型分布 dialog（W-14，只读可视化）。
//
// 集合字段类型构成的只读投影（Navicat 对齐项）：选库/集合 → 推断 schema →
// 集合级「按 dominant BSON 类型分组的分布条（每类型字段数 + 占比条）」+
// 字段级列表（字段名 / 类型 chip（Mixed 特标）/ presence 条 / 嵌套可展开
// subFields 一层——展开深度沿任务书建议 1 层，自决清单登记）。
//
// - 数据面：构造注入接缝（MongoGridFsDialog / _MongoExplainDialog 同形态）——
//   库清单 / 集合清单 / schema 加载三面；生产由插件闭包绑定 AppProvider
//   既有 per-connection facade `loadMongoDBSchema`（INFERENCE 既有默认抽样
//   100，不放大）+ `getMongoDBSchema` 读取，零 adapter/模型改动。
// - 缓存边界（既有，登记备查）：facade 缓存 key = `connectionId:collection`
//   **不含库名**——跨库同名集合会串缓存。dialog 侧处置 = 每次选库/选集合都
//   显式 load 再读（load 恒重取并覆写缓存，从不裸读共享缓存），即按
//   「库+集合」维度管理加载调用；该既有边界不改 facade（任务书约束）。
// - 状态机：选集合 loading / 失败（facade 静默失败由插件闭包显式抛出——
//   workbench_mongo_schema_view 本地推导同因）/ 空态（totalSampled=0 或
//   字段空）/ 数据态；零 Timer、零写路径。
// - 图表 = 既有 token 的简单条形（FractionallySizedBox），零图表依赖。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/mongodb/inferred_schema.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// 库清单加载器。
typedef MongoSchemaDistDatabaseLoader =
    Future<List<String>> Function(String connectionId);

/// 指定库的集合清单加载器。
typedef MongoSchemaDistCollectionLoader =
    Future<List<String>> Function(String connectionId, String database);

/// schema 加载器（选库/集合 → adapter 原始输出 map）。失败抛异常；实现侧
/// 负责先 load 再读（缓存边界见文件头注）。
typedef MongoSchemaDistSchemaLoader =
    Future<Map<String, dynamic>> Function(String database, String collection);

/// MongoDB Schema 类型分布对话框（选库 → 选集合 → 类型分布只读渲染）。
class MongoSchemaDistributionDialog extends StatefulWidget {
  const MongoSchemaDistributionDialog({
    super.key,
    required this.connectionId,
    required this.loadDatabases,
    required this.loadCollections,
    required this.loadSchema,
  });

  final String connectionId;
  final MongoSchemaDistDatabaseLoader loadDatabases;
  final MongoSchemaDistCollectionLoader loadCollections;
  final MongoSchemaDistSchemaLoader loadSchema;

  /// 便捷打开（生产入口由插件调用——闭包绑定 AppProvider 既有 facade）。
  static Future<void> show(
    BuildContext context, {
    required String connectionId,
    required MongoSchemaDistDatabaseLoader loadDatabases,
    required MongoSchemaDistCollectionLoader loadCollections,
    required MongoSchemaDistSchemaLoader loadSchema,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MongoSchemaDistributionDialog(
        connectionId: connectionId,
        loadDatabases: loadDatabases,
        loadCollections: loadCollections,
        loadSchema: loadSchema,
      ),
    );
  }

  @override
  State<MongoSchemaDistributionDialog> createState() =>
      _MongoSchemaDistributionDialogState();
}

class _MongoSchemaDistributionDialogState
    extends State<MongoSchemaDistributionDialog> {
  List<String> _databases = const [];
  List<String> _collections = const [];
  String? _selectedDatabase;
  String? _selectedCollection;
  bool _loadingCollections = false;
  String? _listError;

  bool _loadingSchema = false;
  Map<String, dynamic>? _schema;
  String? _schemaError;

  /// 已展开嵌套字段的字段名集（每字段一层 subFields）。
  final Set<String> _expandedFields = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDatabases());
  }

  Future<void> _loadDatabases() async {
    try {
      final dbs = await widget.loadDatabases(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _databases = dbs;
        _listError = null;
      });
    } catch (e) {
      AppLogger.e('MongoSchemaDist', '加载库清单失败: $e');
      if (!mounted) return;
      setState(() => _listError = e.toString());
    }
  }

  Future<void> _selectDatabase(String database) async {
    if (database == _selectedDatabase) return;
    setState(() {
      _selectedDatabase = database;
      _selectedCollection = null;
      _collections = const [];
      _loadingCollections = true;
      _schema = null;
      _schemaError = null;
      _expandedFields.clear();
    });
    try {
      final collections = await widget.loadCollections(
        widget.connectionId,
        database,
      );
      if (!mounted) return;
      setState(() {
        _collections = collections;
        _loadingCollections = false;
      });
    } catch (e) {
      AppLogger.e('MongoSchemaDist', '加载集合清单失败: $e');
      if (!mounted) return;
      setState(() {
        _listError = e.toString();
        _loadingCollections = false;
      });
    }
  }

  /// 选集合 → 每次显式 load 再读（缓存边界处置，见文件头注）。
  Future<void> _selectCollection(String collection) async {
    final database = _selectedDatabase;
    if (database == null) return;
    setState(() {
      _selectedCollection = collection;
      _loadingSchema = true;
      _schema = null;
      _schemaError = null;
      _expandedFields.clear();
    });
    try {
      final raw = await widget.loadSchema(database, collection);
      if (!mounted) return;
      setState(() {
        _schema = raw;
        _loadingSchema = false;
      });
    } catch (e) {
      AppLogger.e('MongoSchemaDist', '加载 Schema 分布失败: $e');
      if (!mounted) return;
      setState(() {
        _schemaError = e.toString();
        _loadingSchema = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: Text(l10n.mongoSchemaDistTitle),
      content: SizedBox(
        width: 620,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSelectors(l10n),
            if (_listError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.loadFailed(_listError ?? ''),
                  style: TextStyle(
                    color: context.themeColors.error,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                ),
              ),
            const SizedBox(height: AppDesignSystem.space2),
            Expanded(child: _buildResult(l10n)),
          ],
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

  Widget _buildSelectors(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: DropdownButton<String>(
            value: _selectedDatabase,
            isExpanded: true,
            hint: Text(l10n.connectionDatabase),
            items: [
              for (final db in _databases)
                DropdownMenuItem<String>(value: db, child: Text(db)),
            ],
            onChanged: (db) {
              if (db != null) _selectDatabase(db);
            },
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: DropdownButton<String>(
            value: _selectedCollection,
            isExpanded: true,
            hint: Text(l10n.sidebarCollections),
            items: [
              for (final collection in _collections)
                DropdownMenuItem<String>(
                  value: collection,
                  child: Text(collection),
                ),
            ],
            onChanged: (collection) {
              if (collection != null) _selectCollection(collection);
            },
          ),
        ),
        if (_loadingCollections)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  /// 结果区：未选集合空位 / 加载态 / 失败态 / 空态 / 数据态。
  Widget _buildResult(AppLocalizations l10n) {
    final collection = _selectedCollection;
    if (collection == null) {
      return const SizedBox.shrink();
    }
    if (_loadingSchema) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final error = _schemaError;
    if (error != null) {
      return SingleChildScrollView(
        child: Text(
          l10n.loadFailed(error),
          key: const Key('mongo_schema_dist_error'),
          style: TextStyle(
            color: context.themeColors.error,
            fontSize: AppDesignSystem.fontSizeSm,
          ),
        ),
      );
    }
    final raw = _schema;
    if (raw == null) {
      return const SizedBox.shrink();
    }
    final inferred = InferredDocumentSchema.fromAdapterOutput(raw);
    if (inferred.isEmpty) {
      return Center(
        child: Text(
          l10n.mongoSchemaDistEmpty,
          key: const Key('mongo_schema_dist_empty'),
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: AppDesignSystem.fontSizeMd,
          ),
        ),
      );
    }
    return _buildContent(l10n, inferred);
  }

  /// 数据态：头行（集合名 + 字段数徽标 + 抽样数）→ 集合级类型分布 →
  /// 字段级列表。
  Widget _buildContent(AppLocalizations l10n, InferredDocumentSchema inferred) {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头行：集合名 + 字段数徽标 + 抽样数（均为数据非新文案——抽样数
        // 走预登记 mongoSchemaDistSampled）。
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(color: colors.bgSecondary),
          child: Row(
            children: [
              Icon(
                LucideIcons.chartColumn,
                size: 16,
                color: AppDesignSystem.dbMongodb,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  inferred.collectionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeMd,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space0_5,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(
                    AppDesignSystem.radiusSm,
                  ),
                ),
                child: Text(
                  '${inferred.fields.length}',
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.mongoSchemaDistSampled('${inferred.totalSampled}'),
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: ListView(
            key: const Key('mongo_schema_dist_list'),
            children: [
              ..._buildTypeGroups(inferred),
              Divider(
                height: AppDesignSystem.space4,
                color: colors.dividerColor,
              ),
              ..._buildFieldRows(l10n, inferred.fields, depth: 0),
            ],
          ),
        ),
      ],
    );
  }

  /// 集合级分布：字段按 dominant BSON 类型分组（计数降序 + 类型名升序稳定
  /// 排序），每类型「类型标签 + 字段数 + 占比条」。
  List<Widget> _buildTypeGroups(InferredDocumentSchema inferred) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final totalFields = inferred.fields.length;
    final counts = <String, int>{};
    for (final field in inferred.fields) {
      counts[field.bsonType] = (counts[field.bsonType] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return [
      for (final entry in entries)
        Padding(
          key: Key('mongo_schema_dist_group_${entry.key}'),
          padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.mongoSchemaDistFieldType(entry.key),
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeSm,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    l10n.mongoSchemaDistFieldCount('${entry.value}'),
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space1),
              _bar(
                entry.value / totalFields,
                AppDesignSystem.dbMongodb,
              ),
            ],
          ),
        ),
    ];
  }

  /// 字段级列表行（嵌套字段展开一层——展开深度沿任务书建议；subFields
  /// 由模型断言保证非空，仍显式守卫避免裸 `!`）。
  List<Widget> _buildFieldRows(
    AppLocalizations l10n,
    List<SchemaField> fields, {
    required int depth,
  }) {
    return [
      for (final field in fields) ...[
        _buildFieldRow(l10n, field, depth),
        if (field.isNested && _expandedFields.contains(field.name))
          Builder(
            key: Key('mongo_schema_dist_sub_${field.name}'),
            builder: (_) {
              final sub = field.subFields;
              if (sub == null || sub.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildFieldRows(l10n, sub, depth: depth + 1),
              );
            },
          ),
      ],
    ];
  }

  Widget _buildFieldRow(AppLocalizations l10n, SchemaField field, int depth) {
    final colors = context.themeColors;
    final isMixed = field.bsonType.toLowerCase() == 'mixed';
    return Padding(
      padding: EdgeInsets.only(
        left: AppDesignSystem.space4 * depth,
        top: AppDesignSystem.space1,
        bottom: AppDesignSystem.space1,
      ),
      child: Row(
        children: [
          // 嵌套展开开关（无嵌套 = 对齐占位，行间视觉对齐）。
          if (field.isNested)
            InkWell(
              key: Key('mongo_schema_dist_toggle_${field.name}'),
              onTap: () => setState(() {
                if (_expandedFields.contains(field.name)) {
                  _expandedFields.remove(field.name);
                } else {
                  _expandedFields.add(field.name);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.all(AppDesignSystem.space0_5),
                child: Icon(
                  _expandedFields.contains(field.name)
                      ? LucideIcons.chevronDown
                      : LucideIcons.chevronRight,
                  size: 14,
                  color: colors.textSecondary,
                ),
              ),
            )
          else
            const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Text(
              field.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (field.isNested) ...[
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.mongoSchemaDistNested,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textMuted,
              ),
            ),
          ],
          const SizedBox(width: AppDesignSystem.space2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space1_5,
              vertical: AppDesignSystem.space0_5,
            ),
            decoration: BoxDecoration(
              color: isMixed
                  ? colors.warning.withValues(alpha: 0.15)
                  : colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              // Mixed 特标（任务书锁定：类型 chip 对混合类型显式标注）。
              isMixed ? l10n.mongoSchemaDistMixed : field.bsonType,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: FontWeight.w500,
                color: isMixed
                    ? colors.warning
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 72,
            child: _bar(field.presenceRatio, _presenceColor(field.presenceRatio)),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 92,
            child: Text(
              l10n.mongoSchemaDistPresence(
                '${(field.presenceRatio * 100).toStringAsFixed(0)}%',
              ),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 简单条形（既有 token，零图表依赖）：底槽 bgTertiary + 左对齐填充。
  Widget _bar(double fraction, Color color) {
    final colors = context.themeColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: SizedBox(
        height: 6,
        child: Container(
          color: colors.bgTertiary,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ),
      ),
    );
  }

  /// presence 阈值色（theme token，沿 schema_field_item 阈值语义）。
  Color _presenceColor(double ratio) {
    final colors = context.themeColors;
    if (ratio >= 0.9) return colors.success;
    if (ratio >= 0.5) return colors.warning;
    return colors.error;
  }
}
