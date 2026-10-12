// DBT-T4 · PostgreSQL 表维护聚合入口（W-04）——勾选表 + 选动作
// → 逐表确认执行。形态沿 T3 同名件（mysql_table_maintenance_entry_dialog，
// 两文件独立、可对照但互不依赖）。
//
// 零新执行通道：ANALYZE 走 sidebar_tree 表维护既有链路同一门控
// （ConfirmMaintenanceDialog → runTableMaintenance →
// TableMaintenanceResultDialog，与右键菜单 _doMaintenance 同一三件，
// 命令同为 TableMaintenanceCommand.analyze——runTableMaintenance 内
// buildSql 按当前连接 PG 分支产出 `ANALYZE "table"`），不批量静默执行
// ——取消某表确认 = 跳过该表继续下一表。
//
// DBT-T8（feat/db-tooling-completion W-09，2026-10-12）：VACUUM/REINDEX
// 两动作按预留位接入 [_commands]。与 ANALYZE 的既有链路分支不同——
// 维护命令改库统计/索引结构（写路径高风险面），走**专属确认门**
// （DestructiveConfirmDialog + pgVacuumConfirm/pgReindexConfirm 带参文案）
// → 执行（[PgMaintenanceExecutor] 接缝，默认 provider 既有执行面）→
// **AuditLogService 落账**（SQL 过 audit_sql_sanitizer 既有口径）→ 内联
// **结果行**（成功+耗时 / 失败+引擎错误原文）。VACUUM 未选表 = 库级全量
// （裸 `VACUUM`，目标 = 当前所选库；通道核实 2026-10-12 通过——网关
// 单语句非事务通道无事务块拒绝）。REINDEX 仅表级（聚合入口无索引选择面，
// 索引级留待后续；自决登记见任务回报）。VACUUM FULL 不做（锁表重写，
// 超出包装范围——任务书约束）。
// 取数/执行回调由插件注入（ProcessManagerDialog loader 先例的测试缝），
// 插件侧接到 provider 既有面，本文件不触碰 adapter。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../models/table_maintenance_command.dart';
import '../../molecules/destructive_confirm_dialog.dart';
import '../../providers/app_provider.dart';
import '../../services/audit_log_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../connection/error_boundary.dart';
import 'confirm_maintenance_dialog.dart';
import 'table_maintenance_result_dialog.dart';

/// VACUUM/REINDEX 执行器接缝（DBT-T8）：默认经 provider 既有执行面
/// （AppProvider.executeQuery，与 runTableMaintenance 同一 provider 面，
/// database 参数路由到所选库）；测试注入计数（取消 = 零执行断言面）。
typedef PgMaintenanceExecutor =
    Future<void> Function(String connectionId, String databaseName, String sql);

/// 维护命令审计载荷（AuditLogService.recordQuery 口径子集；测试断言面）。
typedef PgMaintenanceAuditRecord =
    ({
      String connectionId,
      String databaseName,
      String sql,
      Duration executionTime,
      bool success,
      String? errorMessage,
    });

/// 审计器接缝（DBT-T8）：默认落 AuditLogService，测试注入 mock。
typedef PgMaintenanceAuditor =
    Future<void> Function(PgMaintenanceAuditRecord record);

/// 默认审计器：维护命令事件落 AuditLogService（先 initialize；SQL 脱敏与
/// 截断由 recordQuery 内部既有口径处理）；写失败不阻塞 UI 由调用方兜底。
Future<void> auditPgMaintenance(PgMaintenanceAuditRecord record) async {
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

/// PostgreSQL 表维护聚合入口对话框。
class PostgresqlTableMaintenanceEntryDialog extends StatefulWidget {
  final String connectionId;

  /// 库清单（既有 getDatabases 路径）。
  final Future<List<String>> Function(String connectionId) loadDatabases;

  /// 库内表清单（按所选库路由的既有只读执行路径；PG 聚合入口专用——
  /// 见插件侧注入点注释）。
  final Future<List<String>> Function(String connectionId, String database)
  loadTables;

  /// 维护执行（AppProvider.runTableMaintenance 既有通道；ANALYZE 链路用）。
  final Future<List<Map<String, dynamic>>> Function(
    String connectionId,
    String database,
    String table,
    TableMaintenanceCommand command,
  )
  runMaintenance;

  /// VACUUM/REINDEX 执行接缝（DBT-T8）。null = 生产默认（provider 既有
  /// 执行面）；测试注入计数。
  @visibleForTesting
  final PgMaintenanceExecutor? executeMaintenance;

  /// VACUUM/REINDEX 审计接缝（DBT-T8）。null = 生产默认（AuditLogService）。
  @visibleForTesting
  final PgMaintenanceAuditor? auditMaintenance;

  const PostgresqlTableMaintenanceEntryDialog({
    super.key,
    required this.connectionId,
    required this.loadDatabases,
    required this.loadTables,
    required this.runMaintenance,
    this.executeMaintenance,
    this.auditMaintenance,
  });

  @override
  State<PostgresqlTableMaintenanceEntryDialog> createState() =>
      _PostgresqlTableMaintenanceEntryDialogState();
}

/// 单次 VACUUM/REINDEX 的结果行（内联展示；任务书「成功/失败结果行」）。
class _PgMaintenanceOutcome {
  const _PgMaintenanceOutcome({
    required this.target,
    required this.command,
    required this.success,
    required this.elapsedMs,
    this.error,
  });

  final String target;
  final TableMaintenanceCommand command;
  final bool success;
  final int elapsedMs;
  final String? error;
}

class _PostgresqlTableMaintenanceEntryDialogState
    extends State<PostgresqlTableMaintenanceEntryDialog> {
  /// ANALYZE 走 T4 既有链路；VACUUM/REINDEX 为 DBT-T8 扩展动作位
  /// （专属确认门 + 审计 + 内联结果行，见 _executePgOps）。
  static const List<TableMaintenanceCommand> _commands = [
    TableMaintenanceCommand.analyze,
    TableMaintenanceCommand.vacuum,
    TableMaintenanceCommand.reindex,
  ];

  TableMaintenanceCommand _command = TableMaintenanceCommand.analyze;
  String? _selectedDatabase;
  List<String>? _databases;
  List<String>? _tables;
  Object? _loadError;
  final Set<String> _selectedTables = <String>{};
  bool _running = false;
  List<_PgMaintenanceOutcome> _outcomes = const [];

  @override
  void initState() {
    super.initState();
    _loadDatabases();
  }

  Future<void> _loadDatabases() async {
    try {
      final dbs = await widget.loadDatabases(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _databases = dbs;
        _selectedDatabase = dbs.isNotEmpty ? dbs.first : null;
        _loadError = null;
      });
      if (_selectedDatabase != null) {
        await _loadTables();
      }
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('PgTableMaintenanceEntryDialog', 'load databases', e);
      setState(() {
        _databases = const [];
        _tables = const [];
        _loadError = e;
      });
    }
  }

  Future<void> _loadTables() async {
    final db = _selectedDatabase;
    if (db == null) return;
    setState(() {
      _tables = null;
      _selectedTables.clear();
    });
    try {
      final tables = await widget.loadTables(widget.connectionId, db);
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('PgTableMaintenanceEntryDialog', 'load tables', e);
      setState(() {
        _tables = const [];
        _loadError = e;
      });
    }
  }

  void _toggleTable(String table, bool selected) {
    setState(() {
      if (selected) {
        _selectedTables.add(table);
      } else {
        _selectedTables.remove(table);
      }
    });
  }

  /// 全选/清空当前表清单。
  void _toggleAll(bool selected) {
    final tables = _tables;
    if (tables == null) return;
    setState(() {
      _selectedTables
        ..clear()
        ..addAll(selected ? tables : const <String>[]);
    });
  }

  Future<void> _execute() async {
    final db = _selectedDatabase;
    if (db == null || _running) return;
    // DBT-T8：VACUUM/REINDEX 走专属链路（确认门 + 执行 + 审计 + 结果行）；
    // ANALYZE 维持 T4 既有链路零改动。
    if (_command == TableMaintenanceCommand.vacuum ||
        _command == TableMaintenanceCommand.reindex) {
      await _executePgOps(db);
      return;
    }
    if (_selectedTables.isEmpty) return;
    setState(() => _running = true);
    try {
      // 逐表确认（不批量静默执行）：每表独立 ConfirmMaintenanceDialog 门，
      // 取消 = 跳过该表继续下一表；执行与结果展示与 sidebar_tree 右键
      // 菜单同一三件（ConfirmMaintenanceDialog → runMaintenance →
      // TableMaintenanceResultDialog）。
      for (final table in _selectedTables.toList(growable: false)) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) =>
              ConfirmMaintenanceDialog(tableName: table, command: _command),
        );
        if (confirmed != true || !mounted) continue;
        try {
          final results = await widget.runMaintenance(
            widget.connectionId,
            db,
            table,
            _command,
          );
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (_) => TableMaintenanceResultDialog(
              tableName: table,
              command: _command,
              // PG 标识符双引号、不带库前缀（与 runTableMaintenance 内
              // buildSql 的 PG 分支同款回显）。
              sql: _command.buildSql(
                db,
                table,
                dbType: DatabaseType.postgresql,
              ),
              results: results,
            ),
          );
        } catch (e) {
          if (!mounted) return;
          AppLogger.e('PgTableMaintenanceEntryDialog', 'maintenance', e);
          final l10n = AppLocalizations.of(context)!;
          AppErrorHandler.showErrorSnackBar(
            context,
            l10n.maintenanceFailed(_commandLabel(l10n), e.toString()),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // ── DBT-T8：VACUUM/REINDEX 专属链路 ────────────────────────────────────

  /// 执行接缝解析：null = 生产默认（provider 既有执行面，database 参数
  /// 路由到所选库——与 runTableMaintenance 的库路由同源）。
  Future<void> _executeViaDefault(
    String connectionId,
    String databaseName,
    String sql,
  ) async {
    await context
        .read<AppProvider>()
        .executeQuery(sql, connectionId: connectionId, database: databaseName);
  }

  /// 目标集：VACUUM 未选表 = 库级全量（裸 `VACUUM`，target = 库名）；
  /// 其余逐表（REINDEX TABLE "t"）。SQL 与 runTableMaintenance 内 buildSql
  /// 的 PG 分支同源。
  String _buildPgSql(String database, String target) {
    if (_command == TableMaintenanceCommand.vacuum &&
        _selectedTables.isEmpty) {
      return 'VACUUM';
    }
    return _command.buildSql(
      database,
      target,
      dbType: DatabaseType.postgresql,
    );
  }

  /// 专属确认门（取消 = 零执行零审计，跳过该目标继续下一目标）。
  Future<bool> _confirmPgOp(String target) async {
    final l10n = AppLocalizations.of(context)!;
    final isVacuum = _command == TableMaintenanceCommand.vacuum;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DestructiveConfirmDialog(
        icon: isVacuum ? LucideIcons.sprayCan : LucideIcons.wrench,
        title: _chipLabel(l10n, _command),
        impactTone: DestructiveTone.warning,
        body: isVacuum
            ? l10n.pgVacuumConfirm(target)
            : l10n.pgReindexConfirm(target),
        confirmLabel: l10n.commonConfirm,
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    return confirmed == true;
  }

  Future<void> _executePgOps(String db) async {
    final isVacuum = _command == TableMaintenanceCommand.vacuum;
    // REINDEX 无库级形态；未选表 = 无目标（按钮亦禁用，防御性返回）。
    if (!isVacuum && _selectedTables.isEmpty) return;
    final targets = _selectedTables.isEmpty
        ? <String>[db]
        : _selectedTables.toList(growable: false);
    setState(() {
      _running = true;
      _outcomes = const [];
    });
    final outcomes = <_PgMaintenanceOutcome>[];
    try {
      for (final target in targets) {
        if (!mounted) return;
        final sql = _buildPgSql(db, target);
        final confirmed = await _confirmPgOp(target);
        if (confirmed != true || !mounted) continue;

        final stopwatch = Stopwatch()..start();
        var success = true;
        String? errorMessage;
        try {
          final execute = widget.executeMaintenance ?? _executeViaDefault;
          await execute(widget.connectionId, db, sql);
        } catch (e) {
          success = false;
          // 失败态展示引擎错误原文（任务书边界条款），不吞错。
          errorMessage = e.toString();
        }
        stopwatch.stop();

        // 审计落账——写失败不阻塞 UI（AppLogger 记录后继续）。
        try {
          final audit = widget.auditMaintenance ?? auditPgMaintenance;
          await audit((
            connectionId: widget.connectionId,
            databaseName: db,
            sql: sql,
            executionTime: stopwatch.elapsed,
            success: success,
            errorMessage: errorMessage,
          ));
        } catch (e) {
          AppLogger.w(
            'PgTableMaintenanceEntryDialog',
            'audit log failed (non-blocking): $e',
          );
        }

        if (!mounted) return;
        outcomes.add(
          _PgMaintenanceOutcome(
            target: target,
            command: _command,
            success: success,
            elapsedMs: stopwatch.elapsedMilliseconds,
            error: errorMessage,
          ),
        );
        setState(() => _outcomes = List<_PgMaintenanceOutcome>.of(outcomes));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// 执行按钮可用条件：选了表 → 任一动作可执行；VACUUM 未选表 = 库级
  /// 全量（目标 = 当前所选库，确认门明示库名）；REINDEX 未选表禁用。
  bool get _canExecute {
    if (_running) return false;
    if (_selectedTables.isNotEmpty) return true;
    return _command == TableMaintenanceCommand.vacuum &&
        _selectedDatabase != null;
  }

  String _commandLabel(AppLocalizations l10n) => _chipLabel(l10n, _command);

  /// 动作 chip 文案。ANALYZE 复用既有 analyzeTable（与 PG 右键菜单同标签）；
  /// VACUUM/REINDEX 复用既有 vacuumTable/reindexTable（DBT-T8）。
  String _chipLabel(AppLocalizations l10n, TableMaintenanceCommand command) {
    switch (command) {
      case TableMaintenanceCommand.analyze:
      case TableMaintenanceCommand.pgAnalyze:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.vacuum:
        return l10n.vacuumTable;
      case TableMaintenanceCommand.reindex:
        return l10n.reindexTable;
      default:
        // 未接线命令位兜底：SQL 关键字直显（生产路径不可达——_commands
        // 白名单限定本批命令集）。
        return command.sqlKeyword;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    // R4-d（reviewer P3#10）：动作执行中禁止 Esc/屏障关闭（PopScope 拦
    // maybePop，屏障/Esc 同走该路径）——执行半途关窗会留下不可见在途
    // 维护命令；插件侧 showDialog 另配 barrierDismissible: false 双保险。
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.wrench, size: 20, color: colors.accentBlue),
            const SizedBox(width: AppDesignSystem.space2),
            Text(l10n.pgCapMaintenance),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: 480,
          child: _databases == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(l10n, colors),
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: _canExecute ? _execute : null,
            child: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
            child: Row(
              children: [
                Icon(LucideIcons.triangleAlert, size: 14, color: colors.error),
                const SizedBox(width: AppDesignSystem.space1),
                Expanded(
                  child: Text(
                    l10n.maintenanceFailed(
                      l10n.pgCapMaintenance,
                      _loadError.toString(),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.error),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                l10n.selectDatabase,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedDatabase,
                underline: const SizedBox.shrink(),
                items: [
                  for (final db in _databases ?? const <String>[])
                    DropdownMenuItem<String>(value: db, child: Text(db)),
                ],
                onChanged: (db) {
                  if (db == null || db == _selectedDatabase) return;
                  setState(() => _selectedDatabase = db);
                  _loadTables();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Wrap(
          spacing: AppDesignSystem.space2,
          children: [
            for (final command in _commands)
              ChoiceChip(
                label: Text(_chipLabel(l10n, command)),
                selected: _command == command,
                onSelected: (_) => setState(() => _command = command),
              ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space2),
        // DBT-T8：VACUUM/REINDEX 内联结果行（成功+耗时 / 失败+引擎错误原文）。
        if (_outcomes.isNotEmpty) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 110),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final outcome in _outcomes)
                  _buildOutcomeRow(l10n, colors, outcome),
              ],
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
        ],
        if (_tables == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(child: _buildTableList(l10n, colors)),
      ],
    );
  }

  /// 单条结果行：目标名 + 成功（pgMaintainSuccess + 耗时）/ 失败
  /// （pgMaintainFailed + 引擎错误原文，SelectableText 可复制排查）。
  Widget _buildOutcomeRow(
    AppLocalizations l10n,
    ThemeColors colors,
    _PgMaintenanceOutcome outcome,
  ) {
    final actionLabel = _chipLabel(l10n, outcome.command);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            outcome.success ? LucideIcons.check : LucideIcons.circleAlert,
            size: 14,
            color: outcome.success ? colors.success : colors.error,
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  outcome.success
                      ? '${l10n.pgMaintainSuccess(actionLabel)} · '
                        '${outcome.target} · ${outcome.elapsedMs} ms'
                      : '${l10n.pgMaintainFailed(actionLabel)} · '
                        '${outcome.target}',
                  style: TextStyle(
                    fontSize: 12,
                    color: outcome.success ? colors.success : colors.error,
                  ),
                ),
                if (!outcome.success && outcome.error != null)
                  SelectableText(
                    outcome.error!,
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableList(AppLocalizations l10n, ThemeColors colors) {
    final tables = _tables ?? const <String>[];
    final allSelected =
        tables.isNotEmpty && _selectedTables.length == tables.length;
    return Column(
      children: [
        Row(
          children: [
            Checkbox(
              value: allSelected,
              tristate: false,
              onChanged: (v) => _toggleAll(v == true),
            ),
            Expanded(
              child: Text(
                l10n.selectTablesHint,
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: tables.isEmpty
              ? Center(
                  child: Text(
                    l10n.noTablesAvailable,
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: tables.length,
                  itemExtent: 34,
                  itemBuilder: (context, index) {
                    final table = tables[index];
                    return CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        table,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppDesignSystem.monoFontFamily,
                          fontFamilyFallback:
                              AppDesignSystem.monoFontFamilyFallback,
                          color: colors.textPrimary,
                        ),
                      ),
                      value: _selectedTables.contains(table),
                      onChanged: (v) => _toggleTable(table, v == true),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
