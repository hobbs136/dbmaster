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
// T8 预留（feat/db-tooling-completion W-09/W-10）：本 dialog 骨架的
// 动作位为数据驱动（[_commands] chips + [_chipLabel] 映射），T8 扩展
// VACUUM / REINDEX 时向 [_commands] 追加命令并补 label 映射即可；
// 本批（T4）不实现 VACUUM/REINDEX 执行。
// 取数/执行回调由插件注入（ProcessManagerDialog loader 先例的测试缝），
// 插件侧接到 provider 既有面，本文件不触碰 adapter。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../models/table_maintenance_command.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../connection/error_boundary.dart';
import 'confirm_maintenance_dialog.dart';
import 'table_maintenance_result_dialog.dart';

/// PostgreSQL 表维护聚合入口对话框。
class PostgresqlTableMaintenanceEntryDialog extends StatefulWidget {
  final String connectionId;

  /// 库清单（既有 getDatabases 路径）。
  final Future<List<String>> Function(String connectionId) loadDatabases;

  /// 库内表清单（按所选库路由的既有只读执行路径；PG 聚合入口专用——
  /// 见插件侧注入点注释）。
  final Future<List<String>> Function(String connectionId, String database)
  loadTables;

  /// 维护执行（AppProvider.runTableMaintenance 既有通道）。
  final Future<List<Map<String, dynamic>>> Function(
    String connectionId,
    String database,
    String table,
    TableMaintenanceCommand command,
  )
  runMaintenance;

  const PostgresqlTableMaintenanceEntryDialog({
    super.key,
    required this.connectionId,
    required this.loadDatabases,
    required this.loadTables,
    required this.runMaintenance,
  });

  @override
  State<PostgresqlTableMaintenanceEntryDialog> createState() =>
      _PostgresqlTableMaintenanceEntryDialogState();
}

class _PostgresqlTableMaintenanceEntryDialogState
    extends State<PostgresqlTableMaintenanceEntryDialog> {
  /// 本批（DBT-T4）只接 ANALYZE——与 sidebar_tree PG 右键菜单同一命令、
  /// 同一既有链路。T8 预留：VACUUM/REINDEX 动作位（见文件头注释）。
  static const List<TableMaintenanceCommand> _commands = [
    TableMaintenanceCommand.analyze,
  ];

  TableMaintenanceCommand _command = TableMaintenanceCommand.analyze;
  String? _selectedDatabase;
  List<String>? _databases;
  List<String>? _tables;
  Object? _loadError;
  final Set<String> _selectedTables = <String>{};
  bool _running = false;

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
    if (db == null || _selectedTables.isEmpty || _running) return;
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

  String _commandLabel(AppLocalizations l10n) => _chipLabel(l10n, _command);

  /// 动作 chip 文案。T4 仅 ANALYZE（复用既有 analyzeTable，与 PG 右键
  /// 菜单同标签）；T8 扩展 VACUUM/REINDEX 时在此补 case 与对应 key。
  String _chipLabel(AppLocalizations l10n, TableMaintenanceCommand command) {
    switch (command) {
      case TableMaintenanceCommand.analyze:
      case TableMaintenanceCommand.pgAnalyze:
        return l10n.analyzeTable;
      default:
        // T8 预留命令位兜底：SQL 关键字直显（生产路径不可达——_commands
        // 白名单限定本批命令集）。
        return command.sqlKeyword;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
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
          onPressed:
              _selectedTables.isNotEmpty && !_running ? _execute : null,
          child: _running
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.commonConfirm),
        ),
      ],
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
        if (_tables == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(child: _buildTableList(l10n, colors)),
      ],
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
