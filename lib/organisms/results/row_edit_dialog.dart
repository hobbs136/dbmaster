// T14（J1-a）· 结果网格行级编辑 —— 方案 a 显式化路线。
//
// 2026-08-24「网格永不进编辑态」拍板于 2026-10-13 由用户重开：仅 browse
// 数据 tab 的行右键提供「编辑此行」（可靠表身份 = TabProvider.browseTarget
// + PK 定位），手写 SQL 结果网格不开放。本文件是「无假保存」四铁律的
// 实现载体（任务书 T14 约束节）：
// ① 无预览不执行 —— 预览 SQL 与执行 SQL 由同一函数（[buildRowUpdateSql]）
//   生成，且确认时刻只生成一次（同一字符串实例既进确认门展示又进执行器），
//   禁止两处拼装；
// ② 确认门逐行 —— 每次保存一行一道门（内嵌 [DestructiveConfirmDialog]），
//   无「应用到全部行」/批量形态；
// ③ 审计全覆盖 —— 成功与失败都落 `AuditLogService.recordQuery`
//   （`isWriteQuery: true`）；审计写失败不阻塞 UI（AppLogger 记录）；
// ④ readonly fail-closed —— 入口在调用方禁用（results_widget 可用性判定）
//   + 本文件默认执行器显式拦截（[ReadOnlyBlockedException]）+ 服务层
//   `_isWriteQuery` UPDATE 关键字闸门（既有零改）三层保险。
//
// 执行通道：`dbService.executeQueryBypassDmlDetailed` ——「用户确认后执行」
// 的既有 detailed 孪生（与 T5/T8 维护命令同属 dbService 既有执行面；绕开
// 编辑器 DML 拦截链——本 dialog 的预览确认门即该路径唯一门；readonly 闸门
// 与查询历史在 detailed 通道内照常生效）。返回 affectedRows 供「行已不
// 存在」（UPDATE 影响 0 行）判定。
//
// 边界（任务书 T14）：二进制/未知类型列只读展示、不进 SET（不猜字面量）；
// PK 列只读；SET 为空（零变更）不允许进预览；执行失败/影响 0 行时网格不
// 刷新（返回 false）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../atoms/app_loading.dart';
import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../molecules/destructive_confirm_dialog.dart';
import '../../providers/app_provider.dart';
import '../../services/audit_log_service.dart';
import '../../services/readonly_guard.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/sql_escape_utils.dart';

// ============================================================================
// 值模型与列类型分类
// ============================================================================

/// 表单产出的新值：[text] 为用户原始输入；[isNull] 为 true 时写入 SQL NULL
/// （[text] 被忽略）。空文本对字符串列是合法值（'' ≠ NULL）。
class RowEditCellValue {
  final String text;
  final bool isNull;

  const RowEditCellValue(this.text, {this.isNull = false});

  const RowEditCellValue.sqlNull() : text = '', isNull = true;
}

/// 行编辑字段分类。[readonlyLiteral] = 二进制/未知类型：表单只读展示、
/// 不进 SET（fail-closed，不做字面量猜测）。
enum RowEditFieldKind { number, boolean, text, readonlyLiteral }

const Set<String> _kReadonlyTypes = {
  'blob',
  'tinyblob',
  'mediumblob',
  'longblob',
  'binary',
  'varbinary',
  'bytea',
  'image',
  'raw',
  'longraw',
  'bfile',
  'geometry',
  'point',
  'linestring',
  'polygon',
  'geometrycollection',
  'multipoint',
  'multilinestring',
  'multipolygon',
  'box',
  'circle',
  'path',
};

const Set<String> _kNumberTypes = {
  'tinyint',
  'smallint',
  'mediumint',
  'int',
  'integer',
  'bigint',
  'decimal',
  'dec',
  'numeric',
  'float',
  'double',
  'doubleprecision',
  'real',
  'bit',
  'money',
  'smallmoney',
  'number',
  'int2',
  'int4',
  'int8',
  'float4',
  'float8',
};

const Set<String> _kBooleanTypes = {'boolean', 'bool'};

const Set<String> _kTextTypes = {
  'char',
  'varchar',
  'nchar',
  'nvarchar',
  'character',
  'charactervarying',
  'text',
  'tinytext',
  'mediumtext',
  'longtext',
  'clob',
  'string',
  'date',
  'datetime',
  'timestamp',
  'time',
  'timetz',
  'timestamptz',
  'year',
  'interval',
  'json',
  'jsonb',
  'xml',
  'uuid',
  'guid',
  'enum',
  'set',
  'inet',
  'cidr',
  'macaddr',
  'macaddr8',
  'tsvector',
  'tsquery',
};

/// 按列类型分类。小写化、去空格、去 `(N)` 参数后精确匹配名单；未识别
/// 类型一律 [RowEditFieldKind.readonlyLiteral]（fail-closed）。
RowEditFieldKind rowEditFieldKindFor(String columnType) {
  final base = columnType
      .toLowerCase()
      .replaceAll(' ', '')
      .replaceAll(RegExp(r'\(.*\)'), '');
  if (_kReadonlyTypes.contains(base)) return RowEditFieldKind.readonlyLiteral;
  if (_kNumberTypes.contains(base)) return RowEditFieldKind.number;
  if (_kBooleanTypes.contains(base)) return RowEditFieldKind.boolean;
  if (_kTextTypes.contains(base)) return RowEditFieldKind.text;
  return RowEditFieldKind.readonlyLiteral;
}

/// 数字字面量校验（int/float 均走 double.parse；拒绝 NaN/Infinity——
/// SQL 字面量不接受）。
bool rowEditIsValidNumberLiteral(String text) {
  final parsed = double.tryParse(text);
  return parsed != null && parsed.isFinite;
}

/// 布尔字面量归一：true/t/1/yes → TRUE；false/f/0/no → FALSE。
String? rowEditNormalizeBooleanLiteral(String text) {
  switch (text.toLowerCase()) {
    case 'true':
    case 't':
    case '1':
    case 'yes':
      return 'TRUE';
    case 'false':
    case 'f':
    case '0':
    case 'no':
      return 'FALSE';
    default:
      return null;
  }
}

// ============================================================================
// UPDATE 生成（铁律①：预览与执行同源的唯一生成函数）
// ============================================================================

/// MySQL 协议族（字符串字面量中反斜杠是转义字符，R1-P1 注入面）。
/// 以 `DatabaseType` 实际枚举为准（models/database_models.dart）。
const Set<DatabaseType> _kBackslashStringDialects = {
  DatabaseType.mysql,
  DatabaseType.mariadb,
  DatabaseType.tidb,
  DatabaseType.oceanbase,
  DatabaseType.doris,
  DatabaseType.starrocks,
};

/// 字符串字面量按方言转义：MySQL 协议族先 `\`→`\\` 再 `'`→`''`
/// （[SqlEscapeUtils.escapeMySqlString]）；其余方言（PG/SQLite/SQL Server
/// 等）反斜杠非串转义字符，沿用 [SqlEscapeUtils.escapeString] 单引号双写。
String _escapeStringLiteralFor(String value, DatabaseType type) =>
    _kBackslashStringDialects.contains(type)
        ? SqlEscapeUtils.escapeMySqlString(value)
        : SqlEscapeUtils.escapeString(value);

/// J1-a 行级 UPDATE 生成 —— 预览与执行共用的唯一纯函数（同输入恒同输出）。
///
/// - [changedValues] 仅含变更列（表单 diff 产物），输出顺序按
///   [tableColumns] 声明序稳定；
/// - [rowValues] 当前行原值（WHERE 锚 = PK 列原值字面量）；
/// - 值字面量：null → `NULL`、数字原文本、布尔归一 TRUE/FALSE、字符串按
///   方言转义（MySQL 协议族 [_escapeStringLiteralFor]，R1-P1）；标识符按
///   方言引号（AGENTS §3.5，[SqlEscapeUtils.escapeQualifiedIdentifier]）。
///
/// 不变量（调用方可用性判定已保证；violation = 上游 bug，loud 失败）：
/// PK 列 ≥1、PK 原值非 null 且为 num/bool/String、变更列全部为可编辑
/// 类型且值合法。SET 为空由调用方禁止进预览（零变更不生成 SQL）。
String buildRowUpdateSql({
  required String qualifiedTableName,
  required DatabaseType databaseType,
  required List<DbColumn> tableColumns,
  required Map<String, dynamic> rowValues,
  required Map<String, RowEditCellValue> changedValues,
}) {
  final pkColumns = tableColumns.where((c) => c.isPrimaryKey).toList();
  if (pkColumns.isEmpty) {
    throw StateError('J1-a: 无 PK 列，入口应已禁用（可用性判定②）');
  }
  if (changedValues.isEmpty) {
    throw StateError('J1-a: 零变更不允许生成 UPDATE（铁律：SET 非空）');
  }

  String whereLiteral(dynamic value) {
    if (value is num) return value.toString();
    if (value is bool) return value ? 'TRUE' : 'FALSE';
    if (value is String) return _escapeStringLiteralFor(value, databaseType);
    throw StateError('J1-a: PK 值类型不可靠（${value.runtimeType}），入口应已禁用');
  }

  final table = SqlEscapeUtils.escapeQualifiedIdentifier(
    qualifiedTableName,
    databaseType,
  );
  final buffer = StringBuffer('UPDATE $table SET ');

  var first = true;
  for (final col in tableColumns) {
    final value = changedValues[col.name];
    if (value == null) continue;
    final kind = rowEditFieldKindFor(col.type);
    String literal;
    if (value.isNull) {
      literal = 'NULL';
    } else {
      switch (kind) {
        case RowEditFieldKind.number:
          if (!rowEditIsValidNumberLiteral(value.text)) {
            throw StateError('J1-a: 列 ${col.name} 数字字面量非法: ${value.text}');
          }
          literal = value.text;
        case RowEditFieldKind.boolean:
          final normalized = rowEditNormalizeBooleanLiteral(value.text);
          if (normalized == null) {
            throw StateError('J1-a: 列 ${col.name} 布尔字面量非法: ${value.text}');
          }
          literal = normalized;
        case RowEditFieldKind.text:
          literal = _escapeStringLiteralFor(value.text, databaseType);
        case RowEditFieldKind.readonlyLiteral:
          throw StateError('J1-a: 列 ${col.name} 为只读类型，不进 SET');
      }
    }
    if (!first) buffer.write(', ');
    first = false;
    buffer.write(
      '${SqlEscapeUtils.escapeIdentifierForType(col.name, databaseType)}'
      ' = $literal',
    );
  }

  buffer.write(' WHERE ');
  var firstWhere = true;
  for (final pk in pkColumns) {
    final original = rowValues[pk.name];
    if (original == null) {
      throw StateError('J1-a: PK 列 ${pk.name} 原值为 null，入口应已禁用');
    }
    if (!firstWhere) buffer.write(' AND ');
    firstWhere = false;
    buffer.write(
      '${SqlEscapeUtils.escapeIdentifierForType(pk.name, databaseType)}'
      ' = ${whereLiteral(original)}',
    );
  }

  return buffer.toString();
}

// ============================================================================
// 执行 / 审计 / 取列接缝（生产默认 + 测试注入，AI-SEX 批先例）
// ============================================================================

/// 执行器接缝：返回受影响行数（供「行已不存在」判定）。
typedef RowEditExecutor =
    Future<int?> Function(
      AppProvider provider,
      String connectionId,
      String? databaseName,
      String sql,
    );

/// 行编辑审计载荷（recordQuery 口径子集；测试断言面）。
typedef RowEditAuditRecord = ({
  String connectionId,
  String? databaseName,
  String sql,
  Duration executionTime,
  bool success,
  String? errorMessage,
});

/// 审计器接缝。
typedef RowEditAuditor = Future<void> Function(RowEditAuditRecord record);

/// PK 元数据取列接缝（results_widget 可用性判定消费；widget 测试注入）。
typedef RowEditColumnsFetcher =
    Future<List<DbColumn>> Function(
      AppProvider provider,
      String connectionId,
      String? databaseName,
      String qualifiedTableName,
    );

/// 默认取列：dbService Facade（service 级 getTableColumns，MySQL 跨库浏览
/// 按 databaseName 限定——与 FilterBar `getTableColumnsForBrowse` 同路径；
/// 异常向上抛，由调用方落错误 snackbar，任务书边界条款）。
Future<List<DbColumn>> _fetchRowEditColumnsDefault(
  AppProvider provider,
  String connectionId,
  String? databaseName,
  String qualifiedTableName,
) {
  return provider.dbService.getTableColumns(
    qualifiedTableName,
    connectionId: connectionId,
    databaseName: databaseName,
  );
}

/// 取列接缝：生产默认走 [_fetchRowEditColumnsDefault]；widget 测试整体覆写
/// （results_widget 可用性判定用例注入 PK 元数据，不连库）。
RowEditColumnsFetcher rowEditColumnsFetcher = _fetchRowEditColumnsDefault;

/// 默认执行器：readonly 显式拦截（第三层 fail-closed，服务层 UPDATE 关键
/// 字闸门之外的独立防线）→ dbService「用户确认后执行」detailed 孪生通道。
/// readonly 判定按 [connectionId] 从 savedConnections 解析（R1-P2 与入口
/// 可用性判定同源；connectionId 未注册 = StateError loud 失败，不冒充只读）。
Future<int?> _executeViaDbService(
  AppProvider provider,
  String connectionId,
  String? databaseName,
  String sql,
) async {
  final server = provider.savedConnections
      .where((s) => s.id == connectionId)
      .firstOrNull;
  if (server == null) {
    throw StateError('connection not found: $connectionId');
  }
  if (server.readOnly) {
    throw const ReadOnlyBlockedException(operation: 'rowEdit');
  }
  final result = await provider.dbService.executeQueryBypassDmlDetailed(
    sql,
    connectionId: connectionId,
    database: databaseName,
  );
  return result.affectedRows;
}

/// 默认审计器：成功/失败均落 recordQuery（铁律③）；SQL 脱敏与截断由
/// recordQuery 内部既有口径处理。
Future<void> _auditRowEdit(RowEditAuditRecord record) async {
  final audit = AuditLogService();
  await audit.initialize();
  audit.recordQuery(
    connectionId: record.connectionId,
    databaseName: record.databaseName,
    sql: record.sql,
    executionTime: record.executionTime,
    success: record.success,
    errorMessage: record.errorMessage,
    isWriteQuery: true,
  );
}

// ============================================================================
// Dialog
// ============================================================================

/// 行级编辑对话框（J1 方案 a）。仅 browse 数据 tab 可达（调用方
/// [RowEditDialog.show] 前已完成可用性判定）。
///
/// 流程：表单（全列字段，PK 列与只读类型列只读展示）→ 变更 diff（未变更
/// 列不进 SET）→ 确认门（[DestructiveConfirmDialog]，extraContent = 与
/// 执行逐字一致的 UPDATE mono 预览）→ 执行 → 审计 → 返回。
/// 返回 true = 该行已更新（调用方重跑浏览查询刷新网格）；取消/失败/影响
/// 0 行均返回 false（零刷新）。
class RowEditDialog extends StatefulWidget {
  final String connectionId;

  /// 目标库名；null = 交给服务层 `database ?? server.database` 回退
  /// （R1-P3：调用方不再 `?? ''` 伪造空库名）。
  final String? databaseName;
  final String qualifiedTableName;
  final List<DbColumn> tableColumns;

  /// 当前行（结果网格原值，WHERE 锚）。
  final Map<String, dynamic> rowValues;

  /// 方言（标识符引号与字面量归一）——由 [show] 按 [connectionId] 解析。
  final DatabaseType databaseType;

  @visibleForTesting
  final RowEditExecutor? execute;

  @visibleForTesting
  final RowEditAuditor? audit;

  const RowEditDialog({
    super.key,
    required this.connectionId,
    required this.databaseName,
    required this.qualifiedTableName,
    required this.tableColumns,
    required this.rowValues,
    required this.databaseType,
    this.execute,
    this.audit,
  });

  /// 任务书 T14 接口草案签名。方言按 [connectionId] 经
  /// `dbService.getDatabaseType` 解析（R1-P2，弃 currentServer——多连接
  /// 场景 currentServer 可能指向另一连接）；连接缺失/方言不可得
  /// → 直接返回 false（fail-closed，不开窗）。
  static Future<bool> show(
    BuildContext context, {
    required String connectionId,
    required String? databaseName,
    required String qualifiedTableName,
    required List<DbColumn> tableColumns,
    required Map<String, dynamic> rowValues,
  }) async {
    final provider = context.read<AppProvider>();
    final dbType = provider.dbService.getDatabaseType(connectionId);
    if (dbType == null) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => RowEditDialog(
        connectionId: connectionId,
        databaseName: databaseName,
        qualifiedTableName: qualifiedTableName,
        tableColumns: tableColumns,
        rowValues: rowValues,
        databaseType: dbType,
      ),
    );
    return result ?? false;
  }

  @override
  State<RowEditDialog> createState() => _RowEditDialogState();
}

class _RowEditDialogState extends State<RowEditDialog> {
  /// 可编辑列的输入控制器（dispose 成对释放）。
  late final Map<String, TextEditingController> _controllers;

  /// 各可空可编辑列的 NULL 置位态。
  late final Map<String, bool> _nullFlags;

  bool _executing = false;
  String? _errorMessage;
  bool _rowMissing = false;

  /// 对话框打开时点防御：PK 锚不可用（菜单到开窗间隙的极端竞态）→ 只读
  /// 展示 + Save 禁用（fail-closed）。
  late final bool _pkAnchorReady = widget.tableColumns
      .where((c) => c.isPrimaryKey)
      .every(
        (c) =>
            widget.rowValues.containsKey(c.name) &&
            _isLiteralSafe(widget.rowValues[c.name]),
      );

  static bool _isLiteralSafe(dynamic value) {
    return value != null && (value is num || value is bool || value is String);
  }

  /// 表单展示列：元数据列 ∩ 结果列集，按元数据声明序。
  late final List<DbColumn> _formColumns = widget.tableColumns
      .where((c) => widget.rowValues.containsKey(c.name))
      .toList();

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _nullFlags = {};
    for (final col in _formColumns) {
      // 全列建控制器（PK/只读类型列只读展示仍需预填原值）。
      final controller = TextEditingController(
        text: widget.rowValues[col.name]?.toString() ?? '',
      );
      final kind = rowEditFieldKindFor(col.type);
      if (!col.isPrimaryKey && kind != RowEditFieldKind.readonlyLiteral) {
        controller.addListener(_onFormChanged);
        _nullFlags[col.name] = widget.rowValues[col.name] == null;
      }
      _controllers[col.name] = controller;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  /// 表单 diff：仅文本实际变化 / NULL 态翻转的列进 SET（未变更列不进）。
  Map<String, RowEditCellValue> _computeChanges() {
    final changes = <String, RowEditCellValue>{};
    for (final col in widget.tableColumns) {
      final controller = _controllers[col.name];
      if (controller == null) continue;
      final original = widget.rowValues[col.name];
      final wasNull = original == null;
      final nowNull = _nullFlags[col.name] ?? false;
      if (nowNull) {
        if (!wasNull) changes[col.name] = const RowEditCellValue.sqlNull();
      } else {
        final originalText = original?.toString() ?? '';
        if (controller.text != originalText) {
          changes[col.name] = RowEditCellValue(controller.text);
        }
      }
    }
    return changes;
  }

  /// 值合法性（按列类型）：非法输入 = Save 禁用 + 预览区告警行。
  List<String> _invalidColumns(Map<String, RowEditCellValue> changes) {
    final invalid = <String>[];
    for (final col in widget.tableColumns) {
      final value = changes[col.name];
      if (value == null || value.isNull) continue;
      switch (rowEditFieldKindFor(col.type)) {
        case RowEditFieldKind.number:
          if (!rowEditIsValidNumberLiteral(value.text)) invalid.add(col.name);
        case RowEditFieldKind.boolean:
          if (rowEditNormalizeBooleanLiteral(value.text) == null) {
            invalid.add(col.name);
          }
        case RowEditFieldKind.text:
        case RowEditFieldKind.readonlyLiteral:
          break;
      }
    }
    return invalid;
  }

  bool get _hasReadonlyTypedColumn => _formColumns.any(
    (c) =>
        !c.isPrimaryKey &&
        rowEditFieldKindFor(c.type) == RowEditFieldKind.readonlyLiteral,
  );

  String? _buildPreviewSql() {
    if (!_pkAnchorReady) return null;
    final changes = _computeChanges();
    if (changes.isEmpty) return null;
    if (_invalidColumns(changes).isNotEmpty) return null;
    try {
      return buildRowUpdateSql(
        qualifiedTableName: widget.qualifiedTableName,
        databaseType: widget.databaseType,
        tableColumns: widget.tableColumns,
        rowValues: widget.rowValues,
        changedValues: changes,
      );
    } on StateError {
      // 防御：不变量破坏时不展示半成品 SQL（Save 已被校验先行禁用）。
      return null;
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;
    // 铁律①：确认时刻只生成一次，同一字符串实例进确认门展示并执行。
    final sql = buildRowUpdateSql(
      qualifiedTableName: widget.qualifiedTableName,
      databaseType: widget.databaseType,
      tableColumns: widget.tableColumns,
      rowValues: widget.rowValues,
      changedValues: _computeChanges(),
    );

    // 铁律②：逐行确认门（取消 = 零执行零审计）。
    final gateConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DestructiveConfirmDialog(
        icon: LucideIcons.pencilLine,
        title: l10n.rowEditPreviewTitle,
        impactTone: DestructiveTone.warning,
        impactDescription: l10n.rowEditConfirmImpact(widget.qualifiedTableName),
        confirmLabel: l10n.commonConfirm,
        extraContent: _SqlPreviewBox(sql),
        contentWidth: 640,
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    if (gateConfirmed != true) return;
    if (!mounted) return;

    setState(() {
      _executing = true;
      _errorMessage = null;
      _rowMissing = false;
    });

    final provider = context.read<AppProvider>();
    final stopwatch = Stopwatch()..start();
    var success = true;
    String? errorMessage;
    int? affectedRows;
    try {
      affectedRows = await (widget.execute ?? _executeViaDbService)(
        provider,
        widget.connectionId,
        widget.databaseName,
        sql,
      );
    } catch (e) {
      success = false;
      errorMessage = e is ReadOnlyBlockedException
          ? l10n.readOnlyModeBlocked
          : e.toString();
    }
    stopwatch.stop();

    // 铁律③：成功与失败均落审计；写失败不阻塞 UI。
    try {
      await (widget.audit ?? _auditRowEdit)((
        connectionId: widget.connectionId,
        databaseName: widget.databaseName,
        sql: sql,
        executionTime: stopwatch.elapsed,
        success: success,
        errorMessage: errorMessage,
      ));
    } catch (e) {
      AppLogger.w('RowEdit', 'audit log failed (non-blocking): $e');
    }

    if (!mounted) return;
    if (success && (affectedRows == null || affectedRows > 0)) {
      // 成功 → 关窗返回 true（调用方重跑浏览查询 + 成功反馈）。
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _executing = false;
      if (success && affectedRows == 0) {
        // 并发变更：重查后行已不存在（UPDATE 影响 0 行），审计照落。
        _rowMissing = true;
        _errorMessage = null;
      } else {
        _errorMessage = errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final changes = _computeChanges();
    final invalid = _invalidColumns(changes);
    final canSave =
        !_executing && _pkAnchorReady && changes.isNotEmpty && invalid.isEmpty;

    return PopScope(
      // 执行中禁止 Esc/屏障关闭（T5 R4-d 同款收紧——半途关窗留下不可见在途
      // UPDATE）。
      canPop: !_executing,
      child: AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          l10n.rowEditTitle(widget.qualifiedTableName),
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_hasReadonlyTypedColumn) ...[
                  Text(
                    l10n.rowEditBinaryColumnSkipped,
                    style: TextStyle(
                      color: context.themeColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                ],
                for (final col in _formColumns) ...[
                  _buildFieldRow(context, col),
                  const SizedBox(height: AppDesignSystem.space2),
                ],
                const SizedBox(height: AppDesignSystem.space1),
                _buildPreviewSection(context, l10n, changes, invalid),
                if (_rowMissing) ...[
                  const SizedBox(height: AppDesignSystem.space3),
                  _buildRowMissingBanner(context, l10n),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppDesignSystem.space3),
                  _buildErrorBanner(context, l10n, _errorMessage!),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _executing ? null : () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          LoadingButton(
            label: l10n.commonSave,
            onPressed: canSave ? () => unawaited(_confirm()) : null,
            isLoading: _executing,
            backgroundColor: context.themeColors.accentBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(BuildContext context, DbColumn col) {
    final l10n = AppLocalizations.of(context)!;
    final kind = rowEditFieldKindFor(col.type);
    final isPk = col.isPrimaryKey;
    final readonlyByType = kind == RowEditFieldKind.readonlyLiteral;
    final editable = !isPk && !readonlyByType;
    final controller = _controllers[col.name];
    final isNull = _nullFlags[col.name] ?? false;
    final colors = context.themeColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              col.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            if (isPk) ...[
              const SizedBox(width: AppDesignSystem.space2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1_5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: colors.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  'PK',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.accentBlue,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              col.type,
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: editable && !isNull && !_executing,
                readOnly: isPk || readonlyByType,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textPrimary,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: isNull ? 'NULL' : null,
                ),
              ),
            ),
            // NULL 置位：仅可空且可编辑的列（'NULL' ≠ ''——显式写 SQL NULL）。
            if (editable && col.isNullable) ...[
              const SizedBox(width: AppDesignSystem.space2),
              InkWell(
                onTap: _executing
                    ? null
                    : () => setState(() {
                        _nullFlags[col.name] = !(isNull);
                      }),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: Checkbox(
                          value: isNull,
                          onChanged: _executing
                              ? null
                              : (v) => setState(
                                  () => _nullFlags[col.name] = v ?? false,
                                ),
                        ),
                      ),
                      const SizedBox(width: AppDesignSystem.space1),
                      Text(
                        'NULL',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        if (readonlyByType && !isPk) ...[
          const SizedBox(height: AppDesignSystem.space0_5),
          Text(
            l10n.rowEditBinaryColumnSkipped,
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewSection(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, RowEditCellValue> changes,
    List<String> invalid,
  ) {
    final colors = context.themeColors;
    if (invalid.isNotEmpty) {
      // 非法输入 = Save 禁用 + 告警行（列名为技术标识符，非 l10n 文案）。
      return Container(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.triangleAlert, size: 16, color: colors.warning),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                '${l10n.commonWarning}: ${invalid.join(', ')}',
                style: TextStyle(fontSize: 12, color: colors.textPrimary),
              ),
            ),
          ],
        ),
      );
    }
    final sql = _buildPreviewSql();
    if (sql == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
        child: Text(
          l10n.rowEditZeroChanges,
          style: TextStyle(fontSize: 12, color: colors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.rowEditPreviewTitle,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        _SqlPreviewBox(sql),
      ],
    );
  }

  Widget _buildRowMissingBanner(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 16, color: colors.warning),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              l10n.rowEditRowMissing,
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    AppLocalizations l10n,
    String message,
  ) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.circleAlert, size: 16, color: colors.error),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.rowEditFailed,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          SelectableText(
            message,
            style: TextStyle(fontSize: 11, color: colors.error),
          ),
        ],
      ),
    );
  }
}

/// mono SQL 预览盒：表单预览区与确认门 extraContent 共用（同一字符串渲染）。
class _SqlPreviewBox extends StatelessWidget {
  final String sql;

  const _SqlPreviewBox(this.sql);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: SelectableText(
        sql,
        style: TextStyle(
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontSize: 12,
          color: context.themeColors.textPrimary,
        ),
      ),
    );
  }
}
