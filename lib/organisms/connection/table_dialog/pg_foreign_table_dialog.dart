// ============================================================================
// DBT-T19（W-16）· PG 外部表设计器（CREATE FOREIGN TABLE 建表入口）
//
// - servers 下拉：pg_foreign_server 目录表只读 SELECT（经 dbService 既有
//   只读执行面）；空 → 「无 foreign server」提示（不内嵌 CREATE SERVER，
//   任务书边界——将来另立）。
// - 列定义可空：CREATE FOREIGN TABLE 无列合法（远程结构由 server 侧定义）。
// - 每动作确认门：DDL 预览门（[DestructiveConfirmDialog] extraContent =
//   mono DDL，预览与执行同一 [PgForeignTableDdl.build] 构造函数——「无假
//   保存」铁律①）。
// - 执行经 provider 既有执行面 `dbService.executeQueryBypassDdlDetailed`
//   （T18 事件设计器同款；自有确认门即本路径唯一门）。
// - 审计：`AuditLogService.recordQuery`（isWriteQuery: true，成功/失败均
//   落；SQL 脱敏与截断由 recordQuery 内部既有口径处理）；审计写失败不阻塞
//   UI（AppLogger 记录）。
// - readonly：入口禁用（server.readOnly UX 收口）+ 服务层 `_isWriteQuery`
//   CREATE 关键字闸门 fail-closed 双保险（既有零改）。
// - 成功后 refreshDatabases（侧边栏树刷新，AGENTS §4.2）。
// ============================================================================
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../molecules/destructive_confirm_dialog.dart';
import '../../../providers/app_provider.dart';
import '../../../services/audit_log_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/sql_escape_utils.dart';
import '../error_boundary.dart';

/// servers 取数注入缝（默认 = dbService 只读执行面查 pg_foreign_server）。
typedef PgForeignServerLoader =
    Future<List<String>> Function(String connectionId);

/// DDL 执行注入缝（默认 = dbService.executeQueryBypassDdlDetailed）。
typedef PgForeignTableExecutor =
    Future<void> Function(
      AppProvider provider,
      String connectionId,
      String databaseName,
      String ddl,
    );

/// 外部表 DDL 审计载荷（recordQuery 口径子集；测试断言面）。
typedef PgForeignTableAuditRecord =
    ({
      String connectionId,
      String databaseName,
      String sql,
      Duration executionTime,
      bool success,
      String? errorMessage,
    });

/// 审计器注入缝：默认落 AuditLogService，测试注入 mock。
typedef PgForeignTableAuditor =
    Future<void> Function(PgForeignTableAuditRecord record);

/// 默认审计器：先 initialize；SQL 脱敏与截断由 recordQuery 内部处理。
Future<void> auditPgForeignTableDdl(PgForeignTableAuditRecord record) async {
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

/// CREATE FOREIGN TABLE DDL 构造（预览与执行同一函数，测试断言面）。
///
/// 与 adapter/事件设计器同族：标识符按 PG 方言双引号（经
/// [SqlEscapeUtils.escapePgIdentifier]），OPTIONS 值经
/// [SqlEscapeUtils.escapeString]（单引号双写）。
class PgForeignTableDdl {
  /// OPTIONS 键 = server 侧选项名（技术字符串，PG 词法标识符）。
  static final RegExp _optionKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// OPTIONS 键合法性（非法词法键 = 表单错误，前置拦截）。
  static bool isValidOptionKey(String key) =>
      _optionKeyPattern.hasMatch(key);

  static String build({
    required String schema,
    required String tableName,
    required String serverName,
    required List<({String name, String type, bool notNull})> columns,
    required List<({String key, String value})> options,
  }) {
    final qualified =
        SqlEscapeUtils.escapePgQualifiedIdentifier('$schema.$tableName');
    final columnList = columns.isEmpty
        ? ''
        : ' (\n'
            '${columns.map((c) {
              return '  ${SqlEscapeUtils.escapePgIdentifier(c.name)} '
                  '${c.type}${c.notNull ? ' NOT NULL' : ''}';
            }).join(',\n')}\n'
            ')';
    final optionList = options.isEmpty
        ? ''
        : '\nOPTIONS (${options.map((o) {
            return '${o.key} ${SqlEscapeUtils.escapeString(o.value)}';
          }).join(', ')})';
    return 'CREATE FOREIGN TABLE $qualified$columnList\n'
        'SERVER ${SqlEscapeUtils.escapePgIdentifier(serverName)}$optionList';
  }
}

/// PG 外部表设计器对话框（任务书 T19 接口草案）。
class PgForeignTableDialog extends StatefulWidget {
  final String connectionId;
  final String databaseName;

  @visibleForTesting
  final PgForeignServerLoader? serverLoader;

  @visibleForTesting
  final PgForeignTableExecutor? executor;

  @visibleForTesting
  final PgForeignTableAuditor? auditor;

  const PgForeignTableDialog({
    super.key,
    required this.connectionId,
    required this.databaseName,
    this.serverLoader,
    this.executor,
    this.auditor,
  });

  static Future<void> show(
    BuildContext context, {
    required String connectionId,
    required String databaseName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PgForeignTableDialog(
        connectionId: connectionId,
        databaseName: databaseName,
      ),
    );
  }

  @override
  State<PgForeignTableDialog> createState() => _PgForeignTableDialogState();
}

class _PgForeignTableDialogState extends State<PgForeignTableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _schemaController = TextEditingController(text: 'public');
  final _tableNameController = TextEditingController();

  bool _loadingServers = true;
  List<String> _servers = const [];
  String? _selectedServer;
  Object? _loadError;
  bool _submitted = false;
  bool _running = false;
  late final bool _readOnly;

  final List<_ForeignColumnRow> _columns = [];
  final List<_ForeignOptionRow> _options = [];

  static const List<String> _dataTypes = [
    'INTEGER',
    'BIGINT',
    'SMALLINT',
    'NUMERIC',
    'REAL',
    'DOUBLE PRECISION',
    'VARCHAR(255)',
    'CHAR(50)',
    'TEXT',
    'BOOLEAN',
    'DATE',
    'TIME',
    'TIMESTAMP',
    'TIMESTAMPTZ',
    'UUID',
    'JSON',
    'JSONB',
    'BYTEA',
    'INET',
  ];

  @override
  void initState() {
    super.initState();
    // 入口禁用面（UX 收口）：服务层 _isWriteQuery CREATE 关键字闸门才是
    // 硬保证（fail-closed 既有）。
    _readOnly = _resolveReadOnly(
      context.read<AppProvider>(),
      widget.connectionId,
    );
    _loadServers();
  }

  static bool _resolveReadOnly(AppProvider provider, String connectionId) {
    for (final server in provider.savedConnections) {
      if (server.id == connectionId) {
        return server.readOnly;
      }
    }
    // 保存清单缺失（如测试注入未保存连接）→ 回落当前连接的只读位。
    return provider.connection.currentServer?.readOnly ?? false;
  }

  @override
  void dispose() {
    _schemaController.dispose();
    _tableNameController.dispose();
    for (final col in _columns) {
      col.dispose();
    }
    for (final opt in _options) {
      opt.dispose();
    }
    super.dispose();
  }

  Future<void> _loadServers() async {
    setState(() {
      _loadingServers = true;
      _loadError = null;
    });
    try {
      final provider = context.read<AppProvider>();
      final load =
          widget.serverLoader ??
          (cid) => _defaultLoadServers(
            provider,
            cid,
            widget.databaseName,
          );
      final servers = await load(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _selectedServer = servers.contains(_selectedServer)
            ? _selectedServer
            : (servers.isNotEmpty ? servers.first : null);
        _loadingServers = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('PgForeignTableDialog', 'load foreign servers failed', e);
      setState(() {
        _loadError = e;
        _loadingServers = false;
      });
    }
  }

  static Future<List<String>> _defaultLoadServers(
    AppProvider provider,
    String connectionId,
    String databaseName,
  ) async {
    final rows = await provider.dbService.executeQuery(
      'SELECT srvname FROM pg_foreign_server ORDER BY srvname',
      connectionId: connectionId,
      // 外部 server 是 per-database 对象——按目标库路由查询（网关 database
      // 参数，与执行器同一路由面）。
      database: databaseName,
    );
    return [
      for (final row in rows) row['srvname']?.toString() ?? '',
    ].where((s) => s.isNotEmpty).toList();
  }

  List<({String name, String type, bool notNull})> get _columnInputs {
    return [
      for (final c in _columns)
        if (c.nameController.text.trim().isNotEmpty)
          (
            name: c.nameController.text.trim(),
            type: c.dataType,
            notNull: c.notNull,
          ),
    ];
  }

  List<({String key, String value})> get _optionInputs {
    return [
      for (final o in _options)
        if (o.keyController.text.trim().isNotEmpty)
          (key: o.keyController.text.trim(), value: o.valueController.text),
    ];
  }

  String? _tableNameError(AppLocalizations l10n) {
    if (!_submitted) return null;
    final name = _tableNameController.text.trim();
    if (name.isEmpty) return l10n.commonRequired;
    return null;
  }

  String? _optionKeyError(_ForeignOptionRow row, AppLocalizations l10n) {
    final key = row.keyController.text.trim();
    if (key.isEmpty) return null; // 空键行 = 跳过（零列合法同族）
    if (!PgForeignTableDdl.isValidOptionKey(key)) return l10n.commonFailed;
    return null;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    final selectedServer = _selectedServer;
    if (selectedServer == null || selectedServer.isEmpty) return;

    // 单一生成函数：预览与执行逐字一致（无假保存铁律①）。
    final ddl = PgForeignTableDdl.build(
      schema: _schemaController.text.trim().isEmpty
          ? 'public'
          : _schemaController.text.trim(),
      tableName: _tableNameController.text.trim(),
      serverName: selectedServer,
      columns: _columnInputs,
      options: _optionInputs,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DestructiveConfirmDialog(
        icon: LucideIcons.cloudCog,
        title: l10n.pgForeignTableTitle,
        impactTone: DestructiveTone.warning,
        confirmLabel: l10n.commonConfirm,
        contentWidth: 620,
        extraContent: _ddlPreview(context, ddl),
        onConfirm: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _running = true);
    final provider = context.read<AppProvider>();
    final execute =
        widget.executor ??
        (prov, cid, db, sql) => prov.dbService.executeQueryBypassDdlDetailed(
              sql,
              connectionId: cid,
              database: db,
            );
    final audit = widget.auditor ?? auditPgForeignTableDdl;
    final stopwatch = Stopwatch()..start();
    try {
      await execute(provider, widget.connectionId, widget.databaseName, ddl);
      stopwatch.stop();
      await _auditQuietly(
        audit,
        (
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          sql: ddl,
          executionTime: stopwatch.elapsed,
          success: true,
          errorMessage: null,
        ),
      );
      if (!mounted) return;
      // 侧边栏树刷新（新外部表可见；失败不阻塞主流程）。
      try {
        await provider.refreshDatabases(connectionId: widget.connectionId);
      } catch (e) {
        AppLogger.e('PgForeignTableDialog', 'refresh databases failed', e);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.commonSuccess),
          backgroundColor: context.themeColors.success,
        ),
      );
    } catch (e) {
      stopwatch.stop();
      await _auditQuietly(
        audit,
        (
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          sql: ddl,
          executionTime: stopwatch.elapsed,
          success: false,
          errorMessage: e.toString(),
        ),
      );
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        AppLocalizations.of(context)!.modifyFailed(e),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// 审计写失败不阻塞 UI（AppLogger 记录，任务书边界条款）。
  Future<void> _auditQuietly(
    PgForeignTableAuditor audit,
    PgForeignTableAuditRecord record,
  ) async {
    try {
      await audit(record);
    } catch (e) {
      AppLogger.e('PgForeignTableDialog', 'audit write failed', e);
    }
  }

  Widget _ddlPreview(BuildContext context, String sql) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.pgForeignTableDdlPreview,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              sql,
              key: const Key('pgft_ddl_preview'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return PopScope(
      // DDL 执行在途禁止关闭（R4-d 先例：半途关窗留不可见在途命令）。
      canPop: !_running,
      child: AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.cloudCog, size: 20, color: colors.accentBlue),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                '${l10n.pgForeignTableTitle} · ${widget.databaseName}',
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 640,
          height: 560,
          child: Form(
            key: _formKey,
            child: _loadingServers
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? _buildError(l10n, colors)
                    : _buildForm(l10n, colors),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('pgft_create'),
            // readonly = 入口禁用（UX 收口；服务层 CREATE 关键字闸门
            // fail-closed 为硬保证）；无可用 server 亦禁用（边界条款）。
            onPressed: (_readOnly || _running || _selectedServer == null)
                ? null
                : _submit,
            child: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.commonAdd),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppLocalizations l10n, ThemeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.triangleAlert, size: 28, color: colors.error),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.modifyFailed(_loadError.toString()),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          TextButton.icon(
            onPressed: _running ? null : _loadServers,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n, ThemeColors colors) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_readOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.lock,
                    size: 14,
                    color: colors.warning,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Expanded(
                    child: Text(
                      l10n.readOnlyModeBlocked,
                      style: TextStyle(fontSize: 12, color: colors.warning),
                    ),
                  ),
                ],
              ),
            ),
          if (_servers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 14,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Expanded(
                    child: Text(
                      // 边界条款：不内嵌 CREATE SERVER（将来另立）。
                      l10n.pgForeignTableNoServers,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('pgft_server_field'),
              initialValue: _selectedServer,
              decoration: InputDecoration(
                labelText: l10n.pgForeignTableServer,
                labelStyle: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                ),
                isDense: true,
              ),
              items: _servers
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, style: const TextStyle(fontSize: 12)),
                    ),
                  )
                  .toList(),
              onChanged: _running
                  ? null
                  : (v) => setState(() => _selectedServer = v),
            ),
          const SizedBox(height: AppDesignSystem.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _schemaController,
                  key: const Key('pgft_schema_field'),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n.dbDialogSchema,
                    labelStyle: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _tableNameController,
                  key: const Key('pgft_table_field'),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n.tableName,
                    labelStyle: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                    isDense: true,
                  ),
                  validator: (_) => _tableNameError(l10n),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          _buildColumnsSection(l10n, colors),
          const SizedBox(height: AppDesignSystem.space3),
          _buildOptionsSection(l10n, colors),
        ],
      ),
    );
  }

  Widget _buildColumnsSection(AppLocalizations l10n, ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.tableColumns,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
            TextButton.icon(
              key: const Key('pgft_col_add'),
              onPressed: () =>
                  setState(() => _columns.add(_ForeignColumnRow())),
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(l10n.addColumn, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        for (final entry in _columns.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: entry.value.nameController,
                    key: Key('pgft_col_name_${entry.key}'),
                    style: TextStyle(color: colors.textPrimary, fontSize: 11),
                    decoration: InputDecoration(
                      hintText: l10n.connName,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    key: Key('pgft_col_type_${entry.key}'),
                    initialValue: entry.value.dataType,
                    isExpanded: true,
                    style: TextStyle(color: colors.textPrimary, fontSize: 11),
                    decoration: const InputDecoration(isDense: true),
                    items: _dataTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _running
                        ? null
                        : (v) => setState(
                            () => entry.value.dataType = v ?? 'INTEGER',
                          ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Checkbox(
                    value: entry.value.notNull,
                    activeColor: colors.error,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: _running
                        ? null
                        : (v) =>
                              setState(() => entry.value.notNull = v ?? false),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: colors.error,
                  ),
                  onPressed: () => setState(() {
                    _columns[entry.key].dispose();
                    _columns.removeAt(entry.key);
                  }),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOptionsSection(AppLocalizations l10n, ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.pgForeignTableOptions,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
            TextButton.icon(
              key: const Key('pgft_opt_add'),
              onPressed: () =>
                  setState(() => _options.add(_ForeignOptionRow())),
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(l10n.commonAdd, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        for (final entry in _options.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.value.keyController,
                    key: Key('pgft_opt_key_${entry.key}'),
                    style: TextStyle(color: colors.textPrimary, fontSize: 11),
                    decoration: const InputDecoration(isDense: true),
                    validator: (_) =>
                        _optionKeyError(entry.value, l10n),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: entry.value.valueController,
                    key: Key('pgft_opt_value_${entry.key}'),
                    style: TextStyle(color: colors.textPrimary, fontSize: 11),
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: colors.error,
                  ),
                  onPressed: () => setState(() {
                    _options[entry.key].dispose();
                    _options.removeAt(entry.key);
                  }),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ForeignColumnRow {
  final nameController = TextEditingController();
  String dataType = 'INTEGER';
  bool notNull = false;

  void dispose() {
    nameController.dispose();
  }
}

class _ForeignOptionRow {
  final keyController = TextEditingController();
  final valueController = TextEditingController();

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
