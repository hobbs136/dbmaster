// DBT-T3 · MySQL 表维护聚合入口（W-02）——勾选表 + 选动作
// （ANALYZE / OPTIMIZE / CHECK）→ 逐表确认执行。
//
// 零新执行通道：每个动作仍走 sidebar_tree 表维护既有链路同一门控
// （ConfirmMaintenanceDialog → runTableMaintenance →
// TableMaintenanceResultDialog，与右键菜单 _doMaintenance 同一三件），
// 不批量静默执行——取消某表确认 = 跳过该表继续下一表。
// 取数/执行回调由插件注入（ProcessManagerDialog loader 先例的测试缝），
// 插件侧接到 provider 既有面（dbService.getDatabases/getTables +
// AppProvider.runTableMaintenance），本文件不触碰 adapter。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/table_maintenance_command.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../connection/error_boundary.dart';
import 'confirm_maintenance_dialog.dart';
import 'table_maintenance_result_dialog.dart';

/// MySQL 表维护聚合入口对话框。
class MysqlTableMaintenanceEntryDialog extends StatefulWidget {
  final String connectionId;

  /// 库清单（既有 getDatabases 路径）。
  final Future<List<String>> Function(String connectionId) loadDatabases;

  /// 库内表清单（既有 getTables 路径）。
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

  const MysqlTableMaintenanceEntryDialog({
    super.key,
    required this.connectionId,
    required this.loadDatabases,
    required this.loadTables,
    required this.runMaintenance,
  });

  @override
  State<MysqlTableMaintenanceEntryDialog> createState() =>
      _MysqlTableMaintenanceEntryDialogState();
}

class _MysqlTableMaintenanceEntryDialogState
    extends State<MysqlTableMaintenanceEntryDialog> {
  static const List<TableMaintenanceCommand> _commands = [
    TableMaintenanceCommand.analyze,
    TableMaintenanceCommand.optimize,
    TableMaintenanceCommand.check,
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
      AppLogger.e('MysqlTableMaintenanceEntryDialog', 'load databases', e);
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
      AppLogger.e('MysqlTableMaintenanceEntryDialog', 'load tables', e);
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
              sql: _command.buildSql(db, table),
              results: results,
            ),
          );
        } catch (e) {
          if (!mounted) return;
          AppLogger.e('MysqlTableMaintenanceEntryDialog', 'maintenance', e);
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

  String _commandLabel(AppLocalizations l10n) {
    switch (_command) {
      case TableMaintenanceCommand.analyze:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.optimize:
        return l10n.optimizeTable;
      case TableMaintenanceCommand.check:
        return l10n.checkTable;
      // MySQL 聚合入口不提供 PG 命令（_commands 白名单限定三件）；
      // 防御性兜底走 SQL 关键字。
      default:
        return _command.sqlKeyword;
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
          Text(l10n.mysqlCapMaintenance),
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
                      l10n.mysqlCapMaintenance,
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

  String _chipLabel(AppLocalizations l10n, TableMaintenanceCommand command) {
    switch (command) {
      case TableMaintenanceCommand.analyze:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.optimize:
        return l10n.optimizeTable;
      case TableMaintenanceCommand.check:
        return l10n.checkTable;
      default:
        return command.sqlKeyword;
    }
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
