// DBT-T10 · MongoDB currentOp / killOp 面板（W-11）。
//
// 与 MySQL/PG 进程管理（capability/process_manager_dialog.dart）对称的
// Mongo 变体——派生而非复用的原因：① opid 为 num/String 双形态（分片
// 集群 "shard:nnn"），ProcessListEntry 的 int id 无法无损承载（int 化
// 失败归 0 会错杀/空杀）；② 确认门与结果文案需 Mongo 专键
// （mongoCurrentOpKillConfirm/Killed/KillFailed，ARB 由 T0 冻结）；③
// 列集不同（opid/ns/command/secs/client 五列 vs MySQL 单行 label）。
//
// - currentOp 只读列表：`inprog` 条目 → [MongoOpEntry]（admin 库命令经
//   adapter 薄包装 getCurrentOp，插件闭包注入 [loadOps]）；完整 command
//   文档 + appName 经 Tooltip 展示；
// - killOp = 高风险面（修改操作状态）：**逐行确认门（opid 明示）** →
//   执行（[killOp] 闭包）→ 结果 snackbar + 列表复查刷新。fire-and-forget
//   语义：killOp 对已消失 opid 亦回 ok:1，成功文案 = 「请求已受理」，
//   实际终止由复查列表呈现（目标行消失）；不做批量全杀（任务书约束）；
// - 审计：AuditLogService.recordQuery 维护命令落账（先 initialize；SQL
//   经 AuditSqlSanitizer 既有脱敏口径 + 截断）；审计写失败不阻塞 UI
//   （AppLogger 记录）；
// - 取消确认 = 零执行零审计（测试钉住）；
// - [loadOps]/[killOp] 为必填注入接缝（ProcessManagerDialog loader 形态）；
//   [audit] 为 @visibleForTesting 可覆盖接缝（T5/AI-SEX 先例），生产走
//   [_auditKillOp] 默认审计器。
//
// 裁决结论（security 裁决 b，2026-10-12，与 adapter.killOp 注释同源）：
// 只读连接当前可发 killOp（server WRITE_COMMANDS 与客户端 validateCommand
// 关键字面均未判写），**放行 + UI 标注**（面板顶部
// mongoCurrentOpReadonlyNote 常显；与 MySQL kill query 先例一致，
// db_handler.rs:883-913 无 read_only 检查；server 端 WRITE_COMMANDS 保持
// 不加，mongo.rs 注释登记归呈报包）。确认门 + 审计为任务书既定交付。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../services/audit_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// currentOp `inprog` 条目的规范化形态（opid 保 wire 原生类型直传 killOp）。
@immutable
class MongoOpEntry {
  const MongoOpEntry({
    required this.opId,
    required this.namespace,
    required this.operation,
    required this.secsRunning,
    required this.client,
    required this.active,
    this.appName,
    this.commandJson,
    this.commandSummary = '',
  });

  /// 操作 id：standalone 为数值、分片集群为 "shard:nnn" 字符串。保持
  /// wire 原生类型（num/String）直传 killOp——display 侧才 toString，
  /// 不做字符串往返解析（防精度/形态漂移）。
  final Object opId;
  final String namespace;

  /// 操作类型（op 字段：command/getmore/insert/update/remove/…）。
  final String operation;
  final int secsRunning;
  final String client;
  final bool active;

  /// 客户端应用名（appName，可缺省）。
  final String? appName;

  /// 完整 command 文档的紧凑 JSON（Tooltip 展示；可缺省）。
  final String? commandJson;

  /// Command 列摘要：`<命令首键>[: 标量值]`（如 `find: orders`）——完整
  /// 文档进 Tooltip；构造时派生（build 零解析）。
  final String commandSummary;

  /// currentOp 响应文档 → 规范化条目列表（secs_running 降序——长操作
  /// 排前，进程面板的核心关注点；缺省字段容错归零/空）。
  static List<MongoOpEntry> listFromCurrentOp(Map<String, dynamic> doc) {
    final inprog = doc['inprog'];
    if (inprog is! List) return const [];
    final entries = [
      for (final item in inprog)
        if (item is Map) MongoOpEntry.fromOpDoc(Map<String, dynamic>.from(item)),
    ];
    entries.sort((a, b) => b.secsRunning.compareTo(a.secsRunning));
    return entries;
  }

  /// 单条 inprog 文档 → 条目（缺省容错）。
  static MongoOpEntry fromOpDoc(Map<String, dynamic> doc) {
    final command = doc['command'];
    String? commandJson;
    var commandSummary = '';
    if (command is Map && command.isNotEmpty) {
      try {
        commandJson = const JsonEncoder().convert(command);
      } catch (_) {
        commandJson = null;
      }
      final first = command.entries.first;
      final value =
          first.value is String || first.value is num || first.value is bool
          ? ': ${first.value}'
          : '';
      commandSummary = '${first.key}$value';
    }
    return MongoOpEntry(
      opId: doc['opid'] ?? '',
      namespace: doc['ns']?.toString() ?? '',
      operation: doc['op']?.toString() ?? '-',
      secsRunning: doc['secs_running'] is num
          ? (doc['secs_running'] as num).toInt()
          : 0,
      client: doc['client']?.toString() ?? '',
      active: doc['active'] == true,
      appName: doc['appName']?.toString(),
      commandJson: commandJson,
      commandSummary: commandSummary,
    );
  }

  /// killOp 审计 SQL 形态（展示用；脱敏与截断由 recordQuery 内部口径处理）。
  String get killCommandLabel => 'killOp {op: $opId}';
}

/// currentOp 加载器接缝（插件注入 adapter 薄包装闭包；测试注入 mock）。
typedef MongoCurrentOpLoader =
    Future<List<MongoOpEntry>> Function(String connectionId);

/// killOp 执行器接缝（确认门后调用；返回 ok 语义）。
typedef MongoKillOpExecutor =
    Future<bool> Function(String connectionId, Object opId);

/// killOp 审计载荷（recordQuery 口径子集；测试断言面）。
typedef MongoKillOpAuditRecord = ({
  String connectionId,
  String databaseName,
  String sql,
  Duration executionTime,
  bool success,
  String? errorMessage,
});

/// 审计器接缝：默认落 AuditLogService，测试注入 mock。
typedef MongoKillOpAuditor = Future<void> Function(
  MongoKillOpAuditRecord record,
);

/// 默认审计器：killOp 维护命令事件落 AuditLogService（先 initialize；SQL
/// 脱敏与截断由 recordQuery 内部既有口径处理）。
Future<void> _auditKillOp(MongoKillOpAuditRecord record) async {
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

/// MongoDB currentOp / killOp 对话框（状态机沿 ProcessManagerDialog /
/// PgLocksDialog 同款：loading / error / empty / data，手动刷新，零 Timer）。
class MongoProcessDialog extends StatefulWidget {
  const MongoProcessDialog({
    super.key,
    required this.connectionId,
    required this.loadOps,
    required this.killOp,
    this.audit,
  });

  final String connectionId;

  /// currentOp 列表加载器（插件注入 adapter 薄包装）。
  final MongoCurrentOpLoader loadOps;

  /// killOp 执行器（与 adapter 薄包装同一路径）。
  final MongoKillOpExecutor killOp;

  /// 审计接缝（null = 默认 AuditLogService 落账）。
  @visibleForTesting
  final MongoKillOpAuditor? audit;

  /// 便捷打开（生产入口由插件调用——闭包绑定 adapter 薄包装）。
  static Future<void> show(
    BuildContext context, {
    required String connectionId,
    required MongoCurrentOpLoader loadOps,
    required MongoKillOpExecutor killOp,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MongoProcessDialog(
        connectionId: connectionId,
        loadOps: loadOps,
        killOp: killOp,
      ),
    );
  }

  @override
  State<MongoProcessDialog> createState() => _MongoProcessDialogState();
}

class _MongoProcessDialogState extends State<MongoProcessDialog> {
  List<MongoOpEntry>? _entries;
  bool _loading = true;
  String? _error;

  /// 一次一个 kill（防重入：执行中禁用全部行内 Kill 与刷新）。
  bool _killing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_killing) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.loadOps(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('MongoProcessDialog', 'load currentOp failed', e);
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// killOp 全流程：确认门（opid 明示）→ 执行 → 审计 → 结果 + 复查刷新。
  Future<void> _confirmAndKill(MongoOpEntry entry) async {
    if (_killing) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(l10n.mongoCurrentOpKillConfirm(entry.opId.toString())),
        content: Text(
          '${entry.namespace.isEmpty ? '-' : entry.namespace} · '
          '${entry.operation} · ${entry.client}',
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.processListKillQuery),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _killing = true);
    final stopwatch = Stopwatch()..start();
    bool ok;
    String? errorMessage;
    try {
      ok = await widget.killOp(widget.connectionId, entry.opId);
    } catch (e) {
      ok = false;
      errorMessage = e.toString();
    } finally {
      stopwatch.stop();
    }

    // 审计（成功/失败都落账；审计写失败不阻塞 UI）。
    try {
      await (widget.audit ?? _auditKillOp)(
        (
          connectionId: widget.connectionId,
          databaseName: 'admin',
          sql: entry.killCommandLabel,
          executionTime: stopwatch.elapsed,
          success: ok,
          errorMessage: errorMessage,
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.e('MongoProcessDialog', 'killOp audit failed', e, stackTrace);
    }

    if (!mounted) return;
    setState(() => _killing = false);
    final colors = context.themeColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.mongoCurrentOpKilled(entry.opId.toString())
              : l10n.mongoCurrentOpKillFailed(entry.opId.toString()),
        ),
        backgroundColor: ok ? colors.accentGreen : colors.error,
      ),
    );
    // 复查刷新（fire-and-forget 语义下目标是否真终止由列表呈现）。
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.activity, size: 20, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.mongoCurrentOpTitle),
          const Spacer(),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: (_loading || _killing) ? null : _refresh,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 440,
        // security 裁决 b（2026-10-12）：killOp 放行 + UI 标注——只读
        // 语义说明常显面板顶部（一行 muted，不随加载态消失）。
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
              child: Text(
                l10n.mongoCurrentOpReadonlyNote,
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _buildError(colors)
                  : (_entries?.isEmpty ?? true)
                  ? _buildEmpty(l10n, colors)
                  : _buildTable(l10n, colors),
            ),
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

  Widget _buildError(ThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        child: Text(
          _error!,
          style: TextStyle(color: colors.error, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, ThemeColors colors) {
    return Center(
      child: Text(
        l10n.mongoCurrentOpEmpty,
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
    );
  }

  Widget _buildTable(AppLocalizations l10n, ThemeColors colors) {
    final entries = _entries ?? const <MongoOpEntry>[];
    final rows = [
      for (final e in entries)
        DataRow(
          cells: [
            // 行内动作置首列：横向滚动下恒在视口内（不做批量全杀——逐行确认）。
            // Key 含 opid——DataTable 行为私有 widget 类型，测试经 Key 定位
            // 目标行的 Kill 按钮（能力面板 harness Key 同款先例）。
            DataCell(
              SizedBox(
                width: 84,
                child: TextButton(
                  key: Key('killop_${e.opId}'),
                  onPressed: _killing ? null : () => _confirmAndKill(e),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.error,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(64, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    l10n.processListKillQuery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            DataCell(
              Text(e.opId.toString(), style: _cellStyle(colors, mono: true)),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  e.namespace.isEmpty ? '-' : e.namespace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cellStyle(colors),
                ),
              ),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Tooltip(
                  message: rowTooltip(e),
                  waitDuration: const Duration(milliseconds: 400),
                  child: Text(
                    e.commandSummary.isEmpty
                        ? e.operation
                        : '${e.operation} ${e.commandSummary}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _cellStyle(colors, mono: true),
                  ),
                ),
              ),
            ),
            DataCell(
              Text(
                _formatSeconds(e.secsRunning),
                // 长操作（>5s）警示色——进程面板核心关注点（MySQL 同阈值）。
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: e.secsRunning > 5 ? colors.error : colors.textPrimary,
                ),
              ),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  e.client.isEmpty ? '-' : e.client,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cellStyle(colors),
                ),
              ),
            ),
          ],
        ),
    ];
    // 无条件横向滚动（PgLocksDialog 同分支）：DataTable 在无界宽下取自然
    // 列宽，避免有界宽下的列挤压溢出；Kill 首列恒在视口内。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingTextStyle: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
          ),
          dataRowMinHeight: 30,
          dataRowMaxHeight: 30,
          columnSpacing: 20,
          columns: [
            // 行内动作列（Kill；无列头文案）。
            const DataColumn(label: SizedBox.shrink()),
            DataColumn(label: Text(l10n.mongoCurrentOpColOpId), numeric: true),
            DataColumn(label: Text(l10n.mongoCurrentOpColNamespace)),
            DataColumn(label: Text(l10n.mongoCurrentOpColCommand)),
            DataColumn(
              label: Text(l10n.mongoCurrentOpColSeconds),
              numeric: true,
            ),
            DataColumn(label: Text(l10n.mongoCurrentOpColClient)),
          ],
          rows: rows,
        ),
      ),
    );
  }

  /// 行 Tooltip 内容：完整 command JSON + appName + active（可全缺省）。
  static String rowTooltip(MongoOpEntry e) {
    final parts = <String>[
      if (e.commandJson != null && e.commandJson!.isNotEmpty) e.commandJson!,
      if (e.appName != null && e.appName!.isNotEmpty) 'appName: ${e.appName}',
      'active: ${e.active}',
    ];
    return parts.join('\n');
  }

  TextStyle _cellStyle(ThemeColors colors, {bool mono = false}) => TextStyle(
    fontSize: 12,
    color: colors.textPrimary,
    fontFamily: mono ? AppDesignSystem.monoFontFamily : null,
    fontFamilyFallback: mono ? AppDesignSystem.monoFontFamilyFallback : null,
  );

  /// 秒数 → '12s' / '2m 05s'（沿 PgLocksDialog 同款可读化）。
  static String _formatSeconds(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
