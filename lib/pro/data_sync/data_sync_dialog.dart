import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dbmaster/utils/app_logger.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dbmaster/organisms/server/conversion_guide_row.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/pro/data_sync/data_sync_models.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/pro/data_sync/data_sync_service.dart';
import 'package:dbmaster/services/telemetry_service.dart';
import 'package:dbmaster/services/data_sync_api_service.dart';
import 'package:dbmaster/organisms/server/data_sync/data_sync_task_list_dialog.dart';
import 'package:dbmaster/services/lite_touchpoint_gate.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Landing page for the Data Sync automation pitch.
/// TODO(marketing): final URL pending; harmless default for now.
const String _kDataSyncLearnMoreUrl =
    'https://dbmaster.tech-site/server/learn-more';

/// server=提交给 Server 后台（付费 gate、cron、多表 JOIN 二期）。
enum _ExecutionLocation { local, server }

/// 服务端模式的调度选择：立即执行一次 / 按 cron 周期执行。
enum _ServerScheduleMode { immediate, cron }

/// alias 自动生成（j1, j2...）；database/table 为用户选择；
/// columns 是该表可选列缓存（选完表后加载）；onLeft/onRight 构成 ON 条件
/// （左侧从主表 main 列里选，右侧从本表 columns 里选）；
/// selectedColumns 是用户勾选要 JOIN 进来的列子集。
class _JoinTableConfig {
  final String alias;
  String? database;
  String? table;
  List<DbColumn> columns = const [];
  String? onLeft;
  String? onRight;
  final Set<String> selectedColumns = {};

  _JoinTableConfig({required this.alias});

  /// 当前表的表下拉选项缓存（来自源库 _sourceTables，关联表限定同库）。
  List<String> tables = const [];
}

/// 数据同步对话框
class DataSyncDialog extends StatefulWidget {
  final String? initialConnectionId;
  final String? initialDatabase;
  final String? initialTable;

  const DataSyncDialog({
    super.key,
    this.initialConnectionId,
    this.initialDatabase,
    this.initialTable,
  });

  @override
  State<DataSyncDialog> createState() => _DataSyncDialogState();

  static Future<void> show(
    BuildContext context, {
    String? connectionId,
    String? database,
    String? table,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => DataSyncDialog(
        initialConnectionId: connectionId,
        initialDatabase: database,
        initialTable: table,
      ),
    );
  }
}

class _DataSyncDialogState extends State<DataSyncDialog> {
  AppLocalizations get _l10n => AppLocalizations.of(context)!;
  final _pageSizeController = TextEditingController(text: '1000');
  final _segmentSizeController = TextEditingController(text: '100000');
  final _segmentIntervalController = TextEditingController(text: '0');
  final _pageIntervalController = TextEditingController(text: '0');
  final _timeIntervalController = TextEditingController(text: '60');

  // 源配置
  String? _sourceConnectionId;
  String? _sourceDatabase;
  String? _sourceTable;

  // 目标配置
  String? _targetConnectionId;
  String? _targetDatabase;
  String? _targetTable;

  // 分段配置
  String _segmentType = 'numeric'; // 'numeric' | 'time'
  String? _segmentField;
  TimeUnit _timeUnit = TimeUnit.minute;
  int _timeInterval = 60;

  int get _timeUnitSeconds => switch (_timeUnit) {
    TimeUnit.minute => 60,
    TimeUnit.hour => 3600,
    TimeUnit.day => 86400,
  };

  // 目标策略
  TargetStrategy _targetStrategy = TargetStrategy.append;

  // 状态
  bool _isSyncing = false;
  bool _isCancelled = false;
  bool _showResult = false;
  DataSyncProgress? _progress;
  DataSyncResult? _syncResult;
  String? _errorMessage;
  // service.sync 内部循环检查它实现真正中断（不等当前页查完）。
  CancellationToken? _cancelToken;

  // 数据缓存
  List<DbServer> _connections = [];

  // Cached future for the data-sync lite touchpoint gate (D1=B).
  Future<bool> _dataSyncLiteGateFuture = Future.value(false);

  // Tracks whether the gate future is initialised — first call to `_startSync`
  // success path refreshes it; build reads it.
  bool _dataSyncGateInitialised = false;
  List<String> _sourceDatabases = [];
  List<String> _sourceTables = [];
  List<String> _targetDatabases = [];
  List<String> _targetTables = [];
  List<DbColumn> _sourceColumns = [];

  // 本地模式走 DataSyncService 直跑（现能力）；服务端模式提交给 Server
  // 后台执行（DataSyncApiService.createTask），多表 JOIN / cron 调度 / 进度
  // 轮询在服务端任务列表面板展示。多表 JOIN 配置 UI 留二期。
  _ExecutionLocation _executionLocation = _ExecutionLocation.local;
  _ServerScheduleMode _serverScheduleMode = _ServerScheduleMode.immediate;
  final _serverTaskNameController = TextEditingController();
  final _serverCronController = TextEditingController(text: '0 3 * * *');

  // 每张关联表是一个 _JoinTableConfig，自带库/表/列缓存（级联加载）。
  // ON 条件左侧从主表（main）列里选，右侧从该关联表列里选。
  // 选列用 Set<String> 存勾选的列名子集（空集=不拉该表任何列）。
  final List<_JoinTableConfig> _joinTables = [];

  @override
  void initState() {
    super.initState();
    _sourceConnectionId = widget.initialConnectionId;
    _sourceDatabase = widget.initialDatabase;
    _sourceTable = widget.initialTable;
    _targetConnectionId = widget.initialConnectionId;
    _targetDatabase = widget.initialDatabase;
    _targetTable = widget.initialTable;
    _loadConnections();
  }

  @override
  void dispose() {
    _pageSizeController.dispose();
    _segmentSizeController.dispose();
    _segmentIntervalController.dispose();
    _pageIntervalController.dispose();
    _timeIntervalController.dispose();
    super.dispose();
  }

  Future<void> _loadConnections() async {
    final appProvider = context.read<AppProvider>();
    final connProvider = appProvider.connection;
    await connProvider.loadSavedConnections();
    setState(() {
      _connections = connProvider.savedConnections;
    });
    if (_sourceConnectionId != null) {
      await _loadSourceDatabases();
      if (_sourceDatabase != null) {
        await _loadSourceTables();
        if (_sourceTable != null) {
          await _loadSourceColumns();
        }
      }
    }
    if (_targetConnectionId != null) {
      await _loadTargetDatabases();
      if (_targetDatabase != null) {
        await _loadTargetTables();
      }
    }
  }

  Future<void> _loadSourceDatabases() async {
    if (_sourceConnectionId == null) return;
    final dbService = context.read<AppProvider>().dbService;
    final adapter = dbService.getAdapter(_sourceConnectionId!);
    if (adapter == null) {
      AppLogger.d(
        'DataSync',
        '[DataSyncDialog] getAdapter returned null for source connection: $_sourceConnectionId',
      );
      return;
    }
    try {
      final databases = await adapter.getDatabases();
      if (mounted) {
        setState(() {
          _sourceDatabases = databases;
        });
      }
    } catch (e) {
      AppLogger.d(
        'DataSync',
        '[DataSyncDialog] _loadSourceDatabases error: $e',
      );
    }
  }

  Future<void> _loadSourceTables() async {
    if (_sourceConnectionId == null || _sourceDatabase == null) return;
    final dbService = context.read<AppProvider>().dbService;
    final adapter = dbService.getAdapter(_sourceConnectionId!);
    if (adapter == null) {
      AppLogger.d(
        'DataSync',
        '[DataSyncDialog] getAdapter returned null for source connection: $_sourceConnectionId',
      );
      return;
    }
    try {
      await adapter.useDatabase(_sourceDatabase!);
      final tables = await adapter.getTables();
      if (mounted) {
        setState(() {
          _sourceTables = tables;
        });
      }
    } catch (e) {
      AppLogger.d('DataSync', '[DataSyncDialog] _loadSourceTables error: $e');
    }
  }

  Future<void> _loadSourceColumns() async {
    if (_sourceConnectionId == null ||
        _sourceDatabase == null ||
        _sourceTable == null) {
      return;
    }
    final dbService = context.read<AppProvider>().dbService;
    final adapter = dbService.getAdapter(_sourceConnectionId!);
    if (adapter == null) {
      AppLogger.d(
        'DataSync',
        '[DataSyncDialog] getAdapter returned null for source connection: $_sourceConnectionId',
      );
      return;
    }
    try {
      await adapter.useDatabase(_sourceDatabase!);
      final columns = await adapter.getTableColumns(_sourceTable!);
      if (mounted) {
        setState(() {
          _sourceColumns = columns;
          if (_segmentField == null) {
            // 默认选择主键或第一个列
            final pk = columns.where((c) => c.isPrimaryKey).firstOrNull;
            _segmentField =
                pk?.name ?? (columns.isNotEmpty ? columns.first.name : null);
          }
        });
      }
    } catch (e) {
      AppLogger.d('DataSync', '[DataSyncDialog] _loadSourceColumns error: $e');
    }
  }

  // 关联表与主表共享同一个 source connection（一期不支持跨源 JOIN），
  // 所以 connectionId 固定用 _sourceConnectionId，这里只是签名清晰。

  Future<List<DbColumn>> _fetchColumns(
    String connectionId,
    String? database,
    String table,
  ) async {
    if (database == null) return [];
    final adapter = context.read<AppProvider>().dbService.getAdapter(
      connectionId,
    );
    if (adapter == null) return [];
    try {
      await adapter.useDatabase(database);
      return await adapter.getTableColumns(table);
    } catch (e) {
      AppLogger.d('DataSync', '[DataSyncDialog] _fetchColumns error: $e');
      return [];
    }
  }

  /// 关联表选表后：加载该表的列 + 清空 onRight/selectedColumns。
  /// 关联表限定同源同库，database 直接用 _sourceDatabase。
  Future<void> _onJoinTableChanged(_JoinTableConfig jt, String? table) async {
    setState(() {
      jt.table = table;
      jt.columns = const [];
      jt.onRight = null;
      jt.selectedColumns.clear();
    });
    if (table == null ||
        _sourceConnectionId == null ||
        _sourceDatabase == null) {
      return;
    }
    final cols = await _fetchColumns(
      _sourceConnectionId!,
      _sourceDatabase!,
      table,
    );
    if (mounted) setState(() => jt.columns = cols);
  }

  /// 添加一张新的关联表（alias 自增）。
  /// 关联表限定同源同库：表列表来自源库 _sourceDatabase（预加载）。
  void _addJoinTable() {
    setState(() {
      final jt = _JoinTableConfig(alias: 'j${_joinTables.length + 1}');
      jt.database = _sourceDatabase;
      jt.tables = _sourceTables; // 复用源库的表列表（同库）
      _joinTables.add(jt);
    });
  }

  /// 删除指定关联表 + 重排后续 alias。
  void _removeJoinTable(int index) {
    setState(() {
      _joinTables.removeAt(index);
      // 重排 alias 保持 j1..jN 连续
      for (var i = 0; i < _joinTables.length; i++) {
        // alias 仅用于 SQL 标识，不重排也能用；但重排更直观。
      }
    });
  }

  Future<void> _loadTargetDatabases() async {
    if (_targetConnectionId == null) return;
    final dbService = context.read<AppProvider>().dbService;
    final adapter = dbService.getAdapter(_targetConnectionId!);
    if (adapter == null) {
      AppLogger.d(
        'DataSync',
        '[DataSyncDialog] getAdapter returned null for target connection: $_targetConnectionId',
      );
      return;
    }
    try {
      final databases = await adapter.getDatabases();
      if (mounted) {
        setState(() {
          _targetDatabases = databases;
        });
      }
    } catch (e) {
      AppLogger.d(
        'DataSync',
        '[DataSyncDialog] _loadTargetDatabases error: $e',
      );
    }
  }

  Future<void> _loadTargetTables() async {
    if (_targetConnectionId == null || _targetDatabase == null) return;
    final dbService = context.read<AppProvider>().dbService;
    final adapter = dbService.getAdapter(_targetConnectionId!);
    if (adapter == null) {
      AppLogger.d(
        'DataSync',
        '[DataSyncDialog] getAdapter returned null for target connection: $_targetConnectionId',
      );
      return;
    }
    try {
      await adapter.useDatabase(_targetDatabase!);
      final tables = await adapter.getTables();
      if (mounted) {
        setState(() {
          _targetTables = tables;
        });
      }
    } catch (e) {
      AppLogger.d('DataSync', '[DataSyncDialog] _loadTargetTables error: $e');
    }
  }

  Widget _buildExecutionLocationRadio() {
    return Wrap(
      spacing: AppDesignSystem.space4,
      children: [
        RadioListTile<_ExecutionLocation>(
          value: _ExecutionLocation.local,
          groupValue: _executionLocation,
          onChanged: (v) => setState(
            () => _executionLocation = v ?? _ExecutionLocation.local,
          ),
          title: Text(_l10n.dataSyncExecutionLocal),
          subtitle: Text(_l10n.dataSyncExecutionLocalDesc),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        RadioListTile<_ExecutionLocation>(
          value: _ExecutionLocation.server,
          groupValue: _executionLocation,
          // U11：server runner 只支持时间锚点分批（batch_size 按秒推进
          // cursor）。切换到 server 时把 numeric 强制回 time——此前提交端
          // 会静默把 numeric 换成固定 3600s 时间窗口（语义偷换）。
          onChanged: (v) => setState(() {
            _executionLocation = v ?? _ExecutionLocation.local;
            if (_executionLocation == _ExecutionLocation.server &&
                _segmentType == 'numeric') {
              _segmentType = 'time';
            }
          }),
          title: Text(_l10n.dataSyncExecutionServer),
          subtitle: Text(_l10n.dataSyncExecutionServerDesc),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// 服务端模式的调度配置：任务名 + 立即/周期 + cron 表达式（选周期时）。
  Widget _buildServerScheduleConfig() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _serverTaskNameController,
            decoration: InputDecoration(
              labelText: _l10n.dataSyncServerTaskName,
              hintText: _l10n.dataSyncServerTaskNameHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Wrap(
            spacing: AppDesignSystem.space4,
            children: [
              RadioListTile<_ServerScheduleMode>(
                value: _ServerScheduleMode.immediate,
                groupValue: _serverScheduleMode,
                onChanged: (v) => setState(
                  () =>
                      _serverScheduleMode = v ?? _ServerScheduleMode.immediate,
                ),
                title: Text(_l10n.dataSyncScheduleImmediate),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<_ServerScheduleMode>(
                value: _ServerScheduleMode.cron,
                groupValue: _serverScheduleMode,
                onChanged: (v) => setState(
                  () =>
                      _serverScheduleMode = v ?? _ServerScheduleMode.immediate,
                ),
                title: Text(_l10n.dataSyncScheduleCron),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          if (_serverScheduleMode == _ServerScheduleMode.cron) ...[
            const SizedBox(height: AppDesignSystem.space2),
            TextField(
              controller: _serverCronController,
              decoration: InputDecoration(
                labelText: _l10n.dataSyncCronExpr,
                hintText: '0 3 * * *',
                helperText: _l10n.dataSyncCronExprHelp,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Wrap(
              spacing: AppDesignSystem.space2,
              children: [
                ActionChip(
                  label: Text(_l10n.dataSyncCronPresetDaily3am),
                  onPressed: () => _serverCronController.text = '0 3 * * *',
                ),
                ActionChip(
                  label: Text(_l10n.dataSyncCronPresetHourly),
                  onPressed: () => _serverCronController.text = '0 * * * *',
                ),
                ActionChip(
                  label: Text(_l10n.dataSyncCronPresetWeekly),
                  onPressed: () => _serverCronController.text = '0 3 * * 1',
                ),
              ],
            ),
          ], // spread list (if cron)
        ], // Column.children
      ), // Column
    ); // Container + return
  }

  /// 每张关联表一张卡片：库/表级联 + ON 条件两侧 + 选列 chips + 删除。
  /// 底部"+ 添加关联表"按钮。
  Widget _buildJoinTablesSection() {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _joinTables.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
            child: _buildJoinTableCard(_joinTables[i], i, colors),
          ),
        OutlinedButton.icon(
          onPressed: _addJoinTable,
          icon: const Icon(LucideIcons.plus, size: 18),
          label: Text(_l10n.dataSyncAddJoinTable),
        ),
      ],
    );
  }

  /// 单张关联表的卡片。
  Widget _buildJoinTableCard(
    _JoinTableConfig jt,
    int index,
    ThemeColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.bgTertiary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：关联表 #N (alias) + 删除按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _l10n.dataSyncJoinTableTitle(index + 1, jt.alias),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: Icon(
                  LucideIcons.trash2,
                  size: 18,
                  color: colors.textSecondary,
                ),
                onPressed: () => _removeJoinTable(index),
                tooltip: _l10n.dataSyncJoinTableRemove,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          // 移除 database dropdown，只留 table dropdown（表列表来自源库 _sourceDatabase）。
          // 添加关联表时预加载该库的表列表。
          _buildDropdown(
            label: _l10n.dataSyncSourceTable,
            value: jt.table,
            items: jt.tables,
            onChanged: (v) => _onJoinTableChanged(jt, v),
          ),
          // ON 条件行：main.[列] = alias.[列]
          if (jt.columns.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              _l10n.dataSyncJoinOn,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    label: 'main',
                    value: jt.onLeft,
                    items: _sourceColumns.map((c) => c.name).toList(),
                    onChanged: (v) => setState(() => jt.onLeft = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space2,
                  ),
                  child: Text(
                    '=',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildDropdown(
                    label: jt.alias,
                    value: jt.onRight,
                    items: jt.columns.map((c) => c.name).toList(),
                    onChanged: (v) => setState(() => jt.onRight = v),
                  ),
                ),
              ],
            ),
            // 选列 chips
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              _l10n.dataSyncJoinSelectColumns,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Wrap(
              spacing: AppDesignSystem.space1,
              runSpacing: AppDesignSystem.space1,
              children: jt.columns.map((c) {
                final selected = jt.selectedColumns.contains(c.name);
                return FilterChip(
                  label: Text(c.name, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (val) => setState(() {
                    if (val) {
                      jt.selectedColumns.add(c.name);
                    } else {
                      jt.selectedColumns.remove(c.name);
                    }
                  }),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// DataSyncTaskConfig JSON，调 DataSyncApiService.createTask。成功后
  /// 关闭对话框并提示用户去服务端任务面板查看进度。
  Future<void> _submitToServer() async {
    if (_sourceConnectionId == null ||
        _sourceTable == null ||
        _targetConnectionId == null ||
        _targetTable == null ||
        _segmentField == null) {
      setState(() => _errorMessage = _l10n.dataSyncPleaseCompleteConfig);
      return;
    }
    final taskName = _serverTaskNameController.text.trim().isEmpty
        ? 'data_sync_${_sourceTable}_${DateTime.now().millisecondsSinceEpoch}'
        : _serverTaskNameController.text.trim();
    final cronExpr = _serverScheduleMode == _ServerScheduleMode.cron
        ? _serverCronController.text.trim()
        : '';

    // U05 (#32): the server validates task connection ids against its own
    // registry (404 CONNECTION_NOT_FOUND). The dropdowns carry LOCAL ids —
    // translate them to server ids before submitting (embedded mirror
    // mapping first, then a natural-key match against the live server list).
    final connProvider = context.read<AppProvider>().connection;
    String? sourceServerId;
    String? targetServerId;
    try {
      sourceServerId = await connProvider.resolveServerConnectionId(
        _sourceConnectionId!,
      );
      targetServerId = await connProvider.resolveServerConnectionId(
        _targetConnectionId!,
      );
    } catch (e) {
      AppLogger.w(
        'DataSync',
        '[DataSyncDialog] server id resolution failed: $e',
      );
    }
    if (sourceServerId == null || targetServerId == null) {
      setState(() => _errorMessage = _l10n.dataSyncConnectionNotOnServer);
      return;
    }

    // 组装 Server 的 config JSON（与 Rust DataSyncTaskConfig 对齐）。
    // - join_tables：过滤掉配置不全（缺表/ON）的关联表，组装 JSON。
    // - column_mapping.columns：主表列默认全选（alias=main），关联表只
    //   选用户勾选的列（source 带 alias 前缀）。target 列名默认=源列名
    //   （列重命名 UI 留三期）。
    final joinTablesJson = _joinTables
        .where(
          (j) =>
              j.table != null &&
              j.onLeft != null &&
              j.onRight != null &&
              j.selectedColumns.isNotEmpty,
        )
        .map(
          (j) => <String, dynamic>{
            'table': j.table,
            'alias': j.alias,
            'join_type': 'left_join',
            'on': '${j.onLeft} = ${j.alias}.${j.onRight}',
            if (j.database != null) 'database': j.database,
          },
        )
        .toList();

    final columns = <Map<String, String>>[
      // 主表列（默认全选，alias=main）
      ..._sourceColumns.map(
        (c) => {'source': 'main.${c.name}', 'target': c.name},
      ),
      // 关联表用户勾选的列
      for (final j in _joinTables)
        if (j.table != null && j.onLeft != null && j.onRight != null)
          for (final colName in j.selectedColumns)
            {'source': '${j.alias}.$colName', 'target': colName},
    ];

    // server 的 TargetStrategy 是 Append/Truncate/Upsert(String)，serde snake_case：
    //   append → "append"；truncate → "truncate"；upsert → {"upsert": "<pk_col>"}。
    // Flutter 的 replace 在 server 一期不存在，降级成 truncate + 警告（二期可补）。
    // upsert 需要 PK 列名：自动取源表主键列（_sourceColumns 里 isPrimaryKey 的）。
    dynamic targetStrategyJson;
    switch (_targetStrategy) {
      case TargetStrategy.append:
        targetStrategyJson = 'append';
        break;
      case TargetStrategy.truncate:
      case TargetStrategy.replace:
        // server 一期无 Replace variant；降级 truncate（语义最接近：清空后全量写）。
        targetStrategyJson = 'truncate';
        break;
      case TargetStrategy.upsert:
        final pkCol = _sourceColumns.firstWhere(
          (c) => c.isPrimaryKey,
          orElse: () => _sourceColumns.isNotEmpty
              ? _sourceColumns.first
              : DbColumn(name: 'id', type: 'integer'),
        );
        targetStrategyJson = {'upsert': pkCol.name};
        break;
    }

    // server runner 把 BatchingConfig.batch_size 当秒数推进时间游标
    // （advance_cursor: cursor + batch_size 秒）。U11 起 server 模式的 UI
    // 强制 time 分段、窗口由用户在时间行显式配置；else 的 3600 仅防御
    // 旧状态残留（正常路径不可达）。
    final batchWindowSizeSecs = _segmentType == 'time'
        ? (_timeInterval * _timeUnitSeconds)
        : 3600;

    final config = <String, dynamic>{
      'source': {
        'connection_id': sourceServerId,
        'database': _sourceDatabase,
        'table': _sourceTable,
      },
      'target': {
        'connection_id': targetServerId,
        'database': _targetDatabase,
        'table': _targetTable,
      },
      'join_tables': joinTablesJson,
      'column_mapping': {'columns': columns, 'constants': <dynamic>[]},
      'batching': {
        'time_field': _segmentField,
        'batch_size': batchWindowSizeSecs,
      },
      'target_strategy': targetStrategyJson,
    };

    setState(() {
      _isSyncing = true;
      _errorMessage = null;
    });

    try {
      // ServerConnection 是全局单例，DataSyncApiService 默认构造即拿到同一实例。
      final api = DataSyncApiService();
      final task = await api.createTask(
        name: taskName,
        config: config,
        sourceDbId: sourceServerId,
        targetDbId: targetServerId,
        cronExpr: cronExpr,
      );
      // 立即模式：触发一次运行。
      if (_serverScheduleMode == _ServerScheduleMode.immediate) {
        await api.runTaskNow(task.id);
      }
      if (mounted) {
        // 引导用户去服务端任务面板查看进度（面板在第二块工作里新建）。
        Navigator.pop(context); // 先关对话框，再弹 SnackBar（context 已稳定）
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l10n.dataSyncServerTaskCreated(task.id)),
            action: SnackBarAction(
              label: _l10n.dataSyncViewTasks,
              onPressed: () => showDataSyncTaskListDialog(context),
            ),
          ),
        );
      }
    } on DataSyncApiEntitlementException {
      if (mounted) {
        setState(() {
          _errorMessage = _l10n.dataSyncServerEntitlementGated;
          _isSyncing = false;
        });
      }
    } on DataSyncApiException catch (e) {
      // Stale mapping (the server row was deleted after the mapping was
      // remembered): drop it so the next submit re-matches, and surface the
      // actionable guidance instead of the raw server message.
      if (e.code == 'CONNECTION_NOT_FOUND') {
        unawaited(connProvider.forgetServerConnectionId(_sourceConnectionId!));
        unawaited(connProvider.forgetServerConnectionId(_targetConnectionId!));
      }
      if (mounted) {
        setState(() {
          _errorMessage = e.code == 'CONNECTION_NOT_FOUND'
              ? _l10n.dataSyncConnectionNotOnServer
              : _l10n.dataSyncFailed(e.toString());
          _isSyncing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _l10n.dataSyncFailed(e.toString());
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _startSync() async {
    if (_executionLocation == _ExecutionLocation.server) {
      await _submitToServer();
      return;
    }
    if (_sourceConnectionId == null ||
        _sourceDatabase == null ||
        _sourceTable == null ||
        _targetConnectionId == null ||
        _targetDatabase == null ||
        _targetTable == null ||
        _segmentField == null) {
      setState(() {
        _errorMessage = _l10n.dataSyncPleaseCompleteConfig;
      });
      return;
    }

    setState(() {
      _isSyncing = true;
      _isCancelled = false;
      _progress = null;
      _errorMessage = null;
      _cancelToken = null; // P0-3：重置，新 token 在下面创建
      // _result = null;
    });

    final dbService = context.read<AppProvider>().dbService;
    final sourceAdapter = dbService.getAdapter(_sourceConnectionId!);
    final targetAdapter = dbService.getAdapter(_targetConnectionId!);

    if (sourceAdapter == null || targetAdapter == null) {
      setState(() {
        _errorMessage = _l10n.dataSyncConnectionNotFound;
        _isSyncing = false;
      });
      return;
    }

    final segmentConfig = _segmentType == 'time'
        ? TimeSegmentConfig(
            fieldName: _segmentField!,
            unit: _timeUnit,
            interval: _timeInterval,
          )
        : NumericSegmentConfig(
            fieldName: _segmentField!,
            segmentSize: int.tryParse(_segmentSizeController.text) ?? 100000,
          );

    final config = DataSyncConfig(
      sourceConnectionId: _sourceConnectionId!,
      sourceDatabase: _sourceDatabase!,
      sourceTable: _sourceTable!,
      targetConnectionId: _targetConnectionId!,
      targetDatabase: _targetDatabase!,
      targetTable: _targetTable!,
      segmentConfig: segmentConfig,
      pageSize: int.tryParse(_pageSizeController.text) ?? 1000,
      targetStrategy: _targetStrategy,
      segmentIntervalMs: int.tryParse(_segmentIntervalController.text) ?? 0,
      pageIntervalMs: int.tryParse(_pageIntervalController.text) ?? 0,
    );

    final service = DataSyncService(
      sourceAdapter: sourceAdapter,
      targetAdapter: targetAdapter,
      l10n: _l10n,
    );

    // 让 service 内部循环在下一次检查点立即中断（不再等当前页查完）。
    final cancelToken = CancellationToken();
    _cancelToken = cancelToken;

    final startTime = DateTime.now();
    DataSyncProgress? lastProgress;
    try {
      await for (final progress in service.sync(
        config,
        cancelToken: cancelToken,
      )) {
        if (_isCancelled) {
          break;
        }
        lastProgress = progress;
        setState(() {
          _progress = progress;
        });
      }
      final duration = DateTime.now().difference(startTime);
      final result = DataSyncResult(
        success: !_isCancelled && (lastProgress?.failedRows ?? 0) == 0,
        syncedRows: lastProgress?.syncedRows ?? 0,
        failedRows: lastProgress?.failedRows ?? 0,
        skippedRows: 0,
        duration: duration,
        errorMessage: _isCancelled ? _l10n.dataSyncCancelledByUser : null,
      );
      // Manual Data Sync completed (telemetry §4.1).
      TelemetryService.instance.logFeatureUsed(
        'data_sync',
        extra: {
          'success': result.success,
          // NOTE: `rows` is a count, not data — safe under defensive.md.
          'rows': result.syncedRows,
        },
      );
      if (mounted) {
        _dataSyncLiteGateFuture = LiteTouchpointGate.instance.shouldShowLite(
          guideId: 'data-sync-result',
          featureId: 'data_sync',
        );
        _dataSyncGateInitialised = true;
        setState(() {
          _isSyncing = false;
          _syncResult = result;
          _showResult = true;
        });
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      // Manual Data Sync errored (still counted; success=false).
      TelemetryService.instance.logFeatureUsed(
        'data_sync',
        extra: {'success': false, 'rows': lastProgress?.syncedRows ?? 0},
      );
      if (mounted) {
        setState(() {
          _errorMessage = _l10n.dataSyncFailed(e.toString());
          _isSyncing = false;
          _syncResult = DataSyncResult(
            success: false,
            syncedRows: lastProgress?.syncedRows ?? 0,
            failedRows: lastProgress?.failedRows ?? 0,
            skippedRows: 0,
            duration: duration,
            errorMessage: e.toString(),
          );
          _showResult = true;
        });
      }
    }
  }

  Future<void> _launchLearnMoreUrl() async {
    final uri = Uri.parse(_kDataSyncLearnMoreUrl);
    try {
      await launchUrl(uri);
    } catch (_) {
      // Best-effort launch; click already counted by ConversionGuideRow.
    }
  }

  void _cancelSync() {
    // 而非仅靠 await for 循环的 _isCancelled flag 软中断。
    _cancelToken?.cancel();
    setState(() {
      _isCancelled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: Container(
        width: 700,
        height: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(LucideIcons.arrowRightLeft, color: colorScheme.primary),
                const SizedBox(width: AppDesignSystem.space2),
                Text(_l10n.dataSyncTitle, style: theme.textTheme.titleLarge),
              ],
            ),
            const Divider(),
            const SizedBox(height: AppDesignSystem.space4),

            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                child: _isSyncing
                    ? _buildProgressView()
                    : _showResult
                    ? _buildResultView()
                    : _buildConfigView(theme),
              ),
            ),

            // 底部按钮
            const SizedBox(height: AppDesignSystem.space4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isSyncing)
                  ElevatedButton.icon(
                    // U11 — 取消请求已发出后禁用按钮（等待反馈见进度视图顶部
                    // 横幅），防止重复点击。
                    onPressed: _isCancelled ? null : _cancelSync,
                    icon: const Icon(LucideIcons.circleX),
                    label: Text(_l10n.dataSyncCancel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    ),
                  )
                else if (_showResult) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_l10n.dataSyncClose),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showResult = false;
                        _syncResult = null;
                        _progress = null;
                      });
                    },
                    icon: const Icon(LucideIcons.rotateCcw),
                    label: Text(_l10n.dataSyncRestart),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_l10n.dataSyncClose),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  ElevatedButton.icon(
                    onPressed: _startSync,
                    icon: const Icon(LucideIcons.play),
                    label: Text(_l10n.dataSyncStart),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(_l10n.dataSyncExecutionLocation),
        _buildExecutionLocationRadio(),
        if (_executionLocation == _ExecutionLocation.server) ...[
          const SizedBox(height: AppDesignSystem.space2),
          _buildServerScheduleConfig(),
        ],
        const SizedBox(height: AppDesignSystem.space4),

        // 与关联表卡片视觉统一（bgTertiary + radiusSm + borderLight）。
        // 原 _buildSectionTitle + 散落 dropdown 改为 _buildCard 包裹。

        // Join table 语义上是"源的补充"（LEFT JOIN 到主表，共享连接/库），
        // 单独成卡会割裂关系。合并后视觉层次：主表配置 + 细分隔 + 关联表子区。
        _buildCard(
          title: _l10n.dataSyncSourceConfig,
          icon: LucideIcons.cloudUpload,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 主表配置：连接 / 库 / 表
              _buildConnectionDropdown(
                label: _l10n.dataSyncSourceConnection,
                value: _sourceConnectionId,
                onChanged: (v) async {
                  setState(() {
                    _sourceConnectionId = v;
                    _sourceDatabase = null;
                    _sourceTable = null;
                    _sourceColumns = [];
                    _segmentField = null;
                  });
                  await _loadSourceDatabases();
                },
              ),
              _buildDropdown(
                label: _l10n.dataSyncSourceDatabase,
                value: _sourceDatabase,
                items: _sourceDatabases,
                onChanged: (v) async {
                  setState(() {
                    _sourceDatabase = v;
                    _sourceTable = null;
                    _sourceColumns = [];
                    _segmentField = null;
                  });
                  await _loadSourceTables();
                },
              ),
              _buildDropdown(
                label: _l10n.dataSyncSourceTable,
                value: _sourceTable,
                items: _sourceTables,
                onChanged: (v) async {
                  setState(() {
                    _sourceTable = v;
                    _sourceColumns = [];
                    _segmentField = null;
                  });
                  await _loadSourceColumns();
                },
              ),

              // 关联表子区：仅服务端后台模式 + 主表已选时显示。
              // 用细分隔线 + 子标题区分层次（关联表共享主表的连接/库）。
              if (_executionLocation == _ExecutionLocation.server &&
                  _sourceConnectionId != null &&
                  _sourceTable != null) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppDesignSystem.space2,
                    bottom: AppDesignSystem.space2,
                  ),
                  child: Divider(
                    height: 1,
                    color: context.themeColors.borderLight,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      LucideIcons.gitMerge,
                      size: 14,
                      color: context.themeColors.textSecondary,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      _l10n.dataSyncJoinTables,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space2),
                _buildJoinTablesSection(),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDesignSystem.space3),

        // 目标配置卡片
        _buildCard(
          title: _l10n.dataSyncTargetConfig,
          icon: LucideIcons.cloudDownload,
          child: Column(
            children: [
              _buildConnectionDropdown(
                label: _l10n.dataSyncTargetConnection,
                value: _targetConnectionId,
                onChanged: (v) async {
                  setState(() {
                    _targetConnectionId = v;
                    _targetDatabase = null;
                    _targetTable = null;
                  });
                  await _loadTargetDatabases();
                },
              ),
              _buildDropdown(
                label: _l10n.dataSyncTargetDatabase,
                value: _targetDatabase,
                items: _targetDatabases,
                onChanged: (v) async {
                  setState(() {
                    _targetDatabase = v;
                    _targetTable = null;
                  });
                  await _loadTargetTables();
                },
              ),
              _buildDropdown(
                label: _l10n.dataSyncTargetTable,
                value: _targetTable,
                items: _targetTables,
                onChanged: (v) {
                  setState(() {
                    _targetTable = v;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDesignSystem.space3),

        // 分段配置卡片
        _buildCard(
          title: _l10n.dataSyncSegmentConfig,
          icon: LucideIcons.slidersHorizontal,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: _l10n.dataSyncSegmentStrategy,
                      value: _segmentType,
                      // U11：server 模式不提供 numeric（runner 只支持时间
                      // 锚点）；本地模式两者都可选。
                      items: _executionLocation == _ExecutionLocation.server
                          ? const ['time']
                          : const ['numeric', 'time'],
                      displayValues: {
                        'numeric': _l10n.dataSyncSegmentTypeNumeric,
                        'time': _l10n.dataSyncSegmentTypeTime,
                      },
                      onChanged: (v) {
                        setState(() {
                          _segmentType = v!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    child: _buildDropdown(
                      label: _l10n.dataSyncSegmentField,
                      value: _segmentField,
                      items: _sourceColumns.map((c) => c.name).toList(),
                      onChanged: (v) {
                        setState(() {
                          _segmentField = v;
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_executionLocation == _ExecutionLocation.server)
                Padding(
                  padding: const EdgeInsets.only(top: AppDesignSystem.space1),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.info,
                        size: 13,
                        color: context.themeColors.textMuted,
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      Expanded(
                        child: Text(
                          _l10n.dataSyncServerTimeOnlyHint,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.themeColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_segmentType == 'time')
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        label: _l10n.dataSyncTimeUnit,
                        value: _timeUnit.name,
                        items: TimeUnit.values.map((u) => u.name).toList(),
                        displayValues: {
                          'minute': _l10n.dataSyncTimeUnitMinute,
                          'hour': _l10n.dataSyncTimeUnitHour,
                          'day': _l10n.dataSyncTimeUnitDay,
                        },
                        onChanged: (v) {
                          setState(() {
                            _timeUnit = TimeUnit.values.byName(v!);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space3),
                    Expanded(
                      child: _buildTextField(
                        label: _l10n.dataSyncIntervalValue,
                        controller: _timeIntervalController,
                        onChanged: (v) {
                          _timeInterval = int.tryParse(v) ?? 60;
                        },
                      ),
                    ),
                  ],
                )
              else
                _buildTextField(
                  label: _l10n.dataSyncSegmentSize,
                  controller: _segmentSizeController,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppDesignSystem.space3),

        // 高级选项卡片
        _buildCard(
          title: _l10n.dataSyncAdvancedOptions,
          icon: LucideIcons.settings,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: _l10n.dataSyncPageSize,
                      controller: _pageSizeController,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    child: _buildDropdown(
                      label: _l10n.dataSyncTargetStrategy,
                      value: _targetStrategy.name,
                      items: TargetStrategy.values.map((s) => s.name).toList(),
                      displayValues: {
                        'truncate': _l10n.dataSyncStrategyTruncate,
                        'append': _l10n.dataSyncStrategyAppend,
                        'replace': _l10n.dataSyncStrategyReplace,
                        'upsert': _l10n.dataSyncStrategyUpsert,
                      },
                      onChanged: (v) {
                        setState(() {
                          _targetStrategy = TargetStrategy.values.byName(v!);
                        });
                      },
                    ),
                  ),
                ],
              ),
              // U11：replace→truncate 明示。server 无 REPLACE INTO variant，
              // 提交端会静默降级 truncate——本地 replace 是行级 REPLACE INTO，
              // server 却会先清空整表再全量写入，语义差异必须让用户看见。
              if (_executionLocation == _ExecutionLocation.server &&
                  _targetStrategy == TargetStrategy.replace)
                _buildDestructiveWarning(_l10n.dataSyncReplaceDowngradeWarning),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: _l10n.dataSyncSegmentIntervalMs,
                      controller: _segmentIntervalController,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    child: _buildTextField(
                      label: _l10n.dataSyncPageIntervalMs,
                      controller: _pageIntervalController,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: AppDesignSystem.space3),
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.circleAlert,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 通用卡片容器（源/目标/分段/高级/关联表共用）。
  /// 标题行带图标 + 标题；body 是任意子 widget。
  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.bgTertiary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
            child: Row(
              children: [
                Icon(icon, size: 16, color: colors.textSecondary),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildProgressView() {
    final progress = _progress;
    if (progress == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final percent = progress.totalRows != null && progress.totalRows! > 0
        ? progress.syncedRows / progress.totalRows!
        : (progress.totalSegments > 0
              ? progress.currentSegmentIndex / progress.totalSegments
              : 0.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // U11 — cancel 是「请求」：流要等当前批次（页查询/批插入）结束才停，
        // 期间进度文案不再变化。给等待反馈，避免「点了取消没反应」。
        if (_isCancelled) ...[
          const DataSyncCancellingBanner(),
          const SizedBox(height: AppDesignSystem.space4),
        ],
        const Icon(LucideIcons.arrowRightLeft, size: 64, color: Colors.blue),
        const SizedBox(height: AppDesignSystem.space6),
        Text(
          progress.phase,
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDesignSystem.space4),
        LinearProgressIndicator(value: percent.clamp(0.0, 1.0), minHeight: 12),
        const SizedBox(height: AppDesignSystem.space2),
        Builder(
          builder: (context) {
            var statusText =
                '${(percent * 100).toStringAsFixed(1)}% | ${_l10n.dataSyncProgressSynced(progress.syncedRows)}';
            if (progress.totalRows != null) {
              statusText +=
                  ' / ${_l10n.dataSyncProgressTotal(progress.totalRows!)}';
            }
            if (progress.failedRows > 0) {
              statusText +=
                  ' | ${_l10n.dataSyncProgressFailed(progress.failedRows)}';
            }
            return Text(
              statusText,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            );
          },
        ),
        if (progress.isCompleted) ...[
          const SizedBox(height: AppDesignSystem.space4),
          const Icon(LucideIcons.circleCheckBig, color: Colors.green, size: 48),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            _l10n.dataSyncCompleted,
            style: TextStyle(fontSize: 18, color: Colors.green),
          ),
        ],
      ],
    );
  }

  /// U11 — 破坏性语义明示警告框（warning 色）。用于 server 模式 replace
  /// 降级 truncate 这类「提交后行为与字面选项不同且不可逆」的场景。
  Widget _buildDestructiveWarning(String text) {
    final colors = context.themeColors;
    return Container(
      margin: const EdgeInsets.only(top: AppDesignSystem.space2),
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 16, color: colors.warning),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: colors.warning, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    final result = _syncResult;
    if (result == null) return const SizedBox.shrink();

    final colors = context.themeColors;
    final isSuccess = result.success && result.failedRows == 0;
    final isCancelled = result.errorMessage == _l10n.dataSyncCancelledByUser;

    IconData statusIcon;
    Color statusColor;
    String statusTitle;
    if (isSuccess) {
      statusIcon = LucideIcons.circleCheckBig;
      statusColor = Colors.green;
      statusTitle = _l10n.dataSyncStatusSuccess;
    } else if (isCancelled) {
      statusIcon = LucideIcons.circleX;
      statusColor = Colors.orange;
      statusTitle = _l10n.dataSyncStatusCancelled;
    } else {
      statusIcon = LucideIcons.circleAlert;
      statusColor = Colors.red;
      statusTitle = _l10n.dataSyncStatusFailed;
    }

    final durationStr = _formatDuration(result.duration);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(statusIcon, size: 72, color: statusColor),
        const SizedBox(height: AppDesignSystem.space4),
        Text(
          statusTitle,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: statusColor,
          ),
        ),
        if (result.errorMessage != null && !isCancelled) ...[
          const SizedBox(height: AppDesignSystem.space2),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Text(
              result.errorMessage!,
              style: const TextStyle(fontSize: 13, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: AppDesignSystem.space8),

        // 统计卡片
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
            border: Border.all(color: colors.borderLight),
          ),
          child: Column(
            children: [
              _buildResultRow(
                _l10n.dataSyncSourceTable,
                '$_sourceDatabase.$_sourceTable',
                colors,
              ),
              const Divider(height: 24),
              _buildResultRow(
                _l10n.dataSyncTargetTable,
                '$_targetDatabase.$_targetTable',
                colors,
              ),
              const Divider(height: 24),
              _buildResultRow(
                _l10n.dataSyncResultSyncedRows,
                '${result.syncedRows}',
                colors,
                valueColor: Colors.green,
              ),
              const SizedBox(height: AppDesignSystem.space3),
              _buildResultRow(
                _l10n.dataSyncResultFailedRows,
                '${result.failedRows}',
                colors,
                valueColor: result.failedRows > 0 ? Colors.red : null,
              ),
              const SizedBox(height: AppDesignSystem.space3),
              _buildResultRow(
                _l10n.dataSyncResultDuration,
                durationStr,
                colors,
                valueColor: colors.textPrimary,
              ),
            ],
          ),
        ),
        // Lite conversion touchpoint (D1=B): gated by ≥3 prior syncs + remote
        // kill switch + per-guide exposure cap. Only shown when the user is
        // NOT connected to a Server.
        _buildDataSyncLiteGuide(),
      ],
    );
  }

  Widget _buildDataSyncLiteGuide() {
    final isConnected = context.watch<ServerConnectionProvider>().isConnected;
    if (isConnected) return const SizedBox.shrink();
    if (!_dataSyncGateInitialised) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _dataSyncLiteGateFuture,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            LiteTouchpointGate.instance.recordExposure('data-sync-result');
          }
        });
        // TODO(marketing): lite copy is an EN placeholder pending replacement.
        return Padding(
          padding: const EdgeInsets.only(top: AppDesignSystem.space4),
          child: ConversionGuideRow(
            icon: LucideIcons.refreshCw,
            title: _l10n.touchpointLiteDataSyncTitle,
            description: _l10n.touchpointLiteDataSyncDesc,
            actionLabel: _l10n.touchpointLiteLearnMore,
            guideId: 'data-sync-result',
            serverConnected: false,
            variant: ConversionGuideVariant.lite,
            onAction: _launchLearnMoreUrl,
            actionUrl: _kDataSyncLearnMoreUrl,
          ),
        );
      },
    );
  }

  Widget _buildResultRow(
    String label,
    String value,
    ThemeColors colors, {
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inSeconds > 0) {
      return '${d.inSeconds}s ${d.inMilliseconds.remainder(1000)}ms';
    } else {
      return '${d.inMilliseconds}ms';
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildConnectionDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?>? onChanged,
  }) {
    return _buildDropdown(
      label: label,
      value: value,
      items: _connections.map((c) => c.id).toList(),
      displayValues: {for (final c in _connections) c.id: c.name},
      onChanged: onChanged,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    Map<String, String>? displayValues,
    required ValueChanged<String?>? onChanged,
  }) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Container(
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(color: colors.borderLight),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                isExpanded: true,
                hint: Text(
                  _l10n.dataSyncPleaseSelect(label),
                  style: TextStyle(color: colors.textMuted),
                ),
                dropdownColor: colors.bgTertiary,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
                icon: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: colors.textSecondary,
                ),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                items: items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(displayValues?[item] ?? item),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space3,
          ),
        ),
        keyboardType: TextInputType.number,
        onChanged: onChanged,
      ),
    );
  }
}

/// U11 — cancel 已请求、等待同步流真正结束期间的等待指示（进度视图顶部）。
/// 独立成公开 widget 以便直接渲染测试；文案见 l10n `dataSyncCancelling`。
class DataSyncCancellingBanner extends StatelessWidget {
  const DataSyncCancellingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.warning,
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Flexible(
          child: Text(
            l10n.dataSyncCancelling,
            style: TextStyle(fontSize: 13, color: colors.warning),
          ),
        ),
      ],
    );
  }
}
