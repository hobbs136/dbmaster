// T5（W-05/W-08）· SQLite 维护三件入口 —— VACUUM / ANALYZE / REINDEX。
//
// 本计划第一个写路径能力（改库文件 = 高风险面）：
// - 每动作独立确认门（[DestructiveConfirmDialog] 唯一外壳，取消 = 零执行）；
// - 执行通道 = provider 既有执行面（dbService 单语句非事务通道；VACUUM 不可
//   在事务块内执行，树内 `_optimizeDatabase` 同一通道先例）；
// - 结果行：成功 + 耗时 / 失败 + 引擎错误原文（不吞错；失败后按钮恢复 =
//   重试入口，SQLITE_BUSY 类错误由用户重试消解）；
// - 审计：`AuditLogService.recordQuery` 维护命令落账（内部过
//   `AuditSqlSanitizer` 既有脱敏口径 + 500 字符截断）；审计写失败不阻塞
//   UI（AppLogger 记录，任务书边界条款）；
// - 只读连接 fail-closed：维护命令不在 `_isWriteQuery`/`isWriteCommand`
//   关键字面（服务层与适配器两层只读守卫均拦不到），此处显式拦截——沿
//   adapter 维护方法（`SQLiteAdapter.vacuum` 的 `guardReadOnly`）同语义。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../molecules/destructive_confirm_dialog.dart';
import '../../providers/app_provider.dart';
import '../../services/audit_log_service.dart';
import '../../services/readonly_guard.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// 维护动作三件。[sql] 为单语句非事务命令（无分号，审计/执行同源）。
enum SqliteMaintenanceAction {
  vacuum('VACUUM'),
  analyze('ANALYZE'),
  reindex('REINDEX');

  const SqliteMaintenanceAction(this.sql);
  final String sql;
}

extension SqliteMaintenanceActionX on SqliteMaintenanceAction {
  /// 面板动作名（l10n：sqliteMaintainVacuum / Analyze / Reindex）。
  String label(AppLocalizations l10n) => switch (this) {
        SqliteMaintenanceAction.vacuum => l10n.sqliteMaintainVacuum,
        SqliteMaintenanceAction.analyze => l10n.sqliteMaintainAnalyze,
        SqliteMaintenanceAction.reindex => l10n.sqliteMaintainReindex,
      };

  IconData get icon => switch (this) {
        SqliteMaintenanceAction.vacuum => LucideIcons.sprayCan,
        SqliteMaintenanceAction.analyze => LucideIcons.chartLine,
        SqliteMaintenanceAction.reindex => LucideIcons.wrench,
      };
}

/// 执行器接缝：默认经 provider 既有执行面（生产路径），测试注入计数。
typedef SqliteMaintenanceExecutor =
    Future<void> Function(
      AppProvider provider,
      String connectionId,
      String sql,
    );

/// 维护命令审计载荷（recordQuery 口径子集；测试断言面）。
typedef SqliteMaintenanceAuditRecord =
    ({
      String connectionId,
      String databaseName,
      String sql,
      Duration executionTime,
      bool success,
      String? errorMessage,
    });

/// 审计器接缝：默认落 AuditLogService，测试注入 mock。
typedef SqliteMaintenanceAuditor =
    Future<void> Function(SqliteMaintenanceAuditRecord record);

/// 默认执行器：只读 fail-closed → dbService 单语句非事务通道。
Future<void> _executeViaDbService(
  AppProvider provider,
  String connectionId,
  String sql,
) async {
  // 维护命令改库文件但不在两层守卫的关键字面（INSERT/UPDATE/…），显式拦截
  // 只读连接；连接缺失同样拒绝（fail-closed，readonly_guard FR-003 语义）。
  DbServer? server;
  for (final candidate in provider.savedConnections) {
    if (candidate.id == connectionId) {
      server = candidate;
      break;
    }
  }
  if (server == null || server.readOnly) {
    throw ReadOnlyBlockedException(
      databaseType: DatabaseType.sqlite,
      operation: 'maintenance',
      commandName: sql,
    );
  }
  await provider.connection.dbService.executeQuery(
    sql,
    connectionId: connectionId,
  );
}

/// 默认审计器：维护命令事件落 AuditLogService（先 initialize；SQL 脱敏与
/// 截断由 recordQuery 内部既有口径处理）。
Future<void> _auditMaintenance(SqliteMaintenanceAuditRecord record) async {
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

/// SQLite 维护三件对话框（T5 任务书接口草案：show 签名锁定）。
///
/// 三动作各带独立确认门；执行经 [SqliteMaintenanceExecutor]（默认
/// provider 既有执行面）；结果行内联展示。[execute]/[audit] 为
/// `@visibleForTesting` 注入接缝（AI-SEX 批先例），生产经 [show] 走默认。
///
/// R4-d 同款（收口追加批，2026-10-12）：任一动作执行中禁止 Esc/屏障关闭
/// （[PopScope] 拦 maybePop，两路径同走该路径）——执行半途关窗会留下不可见
/// 在途维护命令。
class SqliteMaintenanceDialog extends StatefulWidget {
  final String connectionId;

  /// 展示用（库路径/别名），随审计 databaseName 一并落账。
  final String databaseName;

  @visibleForTesting
  final SqliteMaintenanceExecutor? execute;

  @visibleForTesting
  final SqliteMaintenanceAuditor? audit;

  const SqliteMaintenanceDialog({
    super.key,
    required this.connectionId,
    required this.databaseName,
    this.execute,
    this.audit,
  });

  static Future<void> show(
    BuildContext context, {
    required String connectionId,
    required String databaseName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SqliteMaintenanceDialog(
        connectionId: connectionId,
        databaseName: databaseName,
      ),
    );
  }

  @override
  State<SqliteMaintenanceDialog> createState() =>
      _SqliteMaintenanceDialogState();
}

class _SqliteMaintenanceDialogState extends State<SqliteMaintenanceDialog> {
  /// 执行中动作行计数（>0 = 执行中；多动作可并行发起，计数归零才恢复可关）。
  int _runningCount = 0;

  void _notifyRunning(bool running) {
    setState(() => _runningCount += running ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: _runningCount == 0,
      child: AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          l10n.sqliteMaintainTitle,
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.databaseName,
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                for (final action in SqliteMaintenanceAction.values) ...[
                  _MaintenanceActionRow(
                    action: action,
                    connectionId: widget.connectionId,
                    databaseName: widget.databaseName,
                    execute: widget.execute ?? _executeViaDbService,
                    audit: widget.audit ?? _auditMaintenance,
                    onRunningChanged: _notifyRunning,
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _runningCount == 0 ? () => Navigator.pop(context) : null,
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }
}

enum _MaintainPhase { idle, running, done }

/// 单个维护动作行：按钮（idle/done 可发起，running 禁用）+ 内联结果。
class _MaintenanceActionRow extends StatefulWidget {
  final SqliteMaintenanceAction action;
  final String connectionId;
  final String databaseName;
  final SqliteMaintenanceExecutor execute;
  final SqliteMaintenanceAuditor audit;

  /// 运行态上报（R4-d：对话框按执行中行数收放 PopScope 可关性）。
  final ValueChanged<bool> onRunningChanged;

  const _MaintenanceActionRow({
    required this.action,
    required this.connectionId,
    required this.databaseName,
    required this.execute,
    required this.audit,
    required this.onRunningChanged,
  });

  @override
  State<_MaintenanceActionRow> createState() => _MaintenanceActionRowState();
}

class _MaintenanceActionRowState extends State<_MaintenanceActionRow> {
  _MaintainPhase _phase = _MaintainPhase.idle;
  int? _elapsedMs;
  String? _error;

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context)!;
    final actionLabel = widget.action.label(l10n);

    // 确认门（取消 = 零执行、零审计、零 provider 依赖）。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DestructiveConfirmDialog(
        icon: widget.action.icon,
        title: actionLabel,
        impactTone: DestructiveTone.warning,
        body: l10n.sqliteMaintainConfirmAction(actionLabel),
        confirmLabel: l10n.commonConfirm,
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    setState(() {
      _phase = _MaintainPhase.running;
      _error = null;
      _elapsedMs = null;
    });
    // R4-d：进入执行态即上报（对话框此间禁 Esc/屏障关闭）。
    widget.onRunningChanged(true);

    final stopwatch = Stopwatch()..start();
    var success = true;
    String? errorMessage;
    try {
      await widget.execute(provider, widget.connectionId, widget.action.sql);
    } catch (e) {
      success = false;
      // 只读拦截映射本地化文案；其余展示引擎错误原文（任务书边界条款）。
      errorMessage = e is ReadOnlyBlockedException
          ? l10n.readOnlyModeBlocked
          : e.toString();
    }
    stopwatch.stop();

    // 审计落账——写失败不阻塞 UI（AppLogger 记录后继续）。
    try {
      await widget.audit(
        (
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          sql: widget.action.sql,
          executionTime: stopwatch.elapsed,
          success: success,
          errorMessage: errorMessage,
        ),
      );
    } catch (e) {
      AppLogger.w(
        'SqliteMaintenance',
        'audit log failed (non-blocking): $e',
      );
    }

    if (!mounted) return;
    // R4-d：执行结束先解除关闭屏障，再落结果态。
    widget.onRunningChanged(false);
    setState(() {
      _phase = _MaintainPhase.done;
      _elapsedMs = stopwatch.elapsedMilliseconds;
      _error = errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final actionLabel = widget.action.label(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _phase == _MaintainPhase.running
              ? null
              : () => unawaited(_run()),
          icon: _phase == _MaintainPhase.running
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(widget.action.icon, size: 16),
          label: Text(actionLabel),
        ),
        if (_phase != _MaintainPhase.idle)
          Padding(
            padding: const EdgeInsets.only(
              left: AppDesignSystem.space2,
              top: AppDesignSystem.space1,
            ),
            child: _buildResult(context, l10n, actionLabel),
          ),
      ],
    );
  }

  Widget _buildResult(
    BuildContext context,
    AppLocalizations l10n,
    String actionLabel,
  ) {
    switch (_phase) {
      case _MaintainPhase.running:
        return Text(
          l10n.sqliteMaintainRunning(actionLabel),
          style: TextStyle(color: context.themeColors.textMuted, fontSize: 12),
        );
      case _MaintainPhase.done:
        if (_error == null) {
          return Row(
            children: [
              Icon(
                LucideIcons.check,
                size: 14,
                color: context.themeColors.success,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                '${l10n.sqliteMaintainSuccess(actionLabel)} · $_elapsedMs ms',
                style: TextStyle(
                  color: context.themeColors.success,
                  fontSize: 12,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.circleAlert,
                  size: 14,
                  color: context.themeColors.error,
                ),
                const SizedBox(width: AppDesignSystem.space1),
                Text(
                  l10n.sqliteMaintainFailed(actionLabel),
                  style: TextStyle(
                    color: context.themeColors.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: AppDesignSystem.space4,
                top: AppDesignSystem.space1,
              ),
              child: SelectableText(
                _error!,
                style: TextStyle(
                  color: context.themeColors.error,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        );
      case _MaintainPhase.idle:
        return const SizedBox.shrink();
    }
  }
}
