import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/pro/schema_diff_sync/schema_sync_service.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/molecules/actionable_error.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 同步执行对话框 — 显示实时进度、逐条结果、回滚信息
class SchemaSyncExecutorDialog extends StatefulWidget {
  final SyncPlan plan;
  final String connectionId;
  final String databaseName;
  final DatabaseType dbType;
  final SchemaSyncService syncService;

  const SchemaSyncExecutorDialog({
    super.key,
    required this.plan,
    required this.connectionId,
    required this.databaseName,
    required this.dbType,
    required this.syncService,
  });

  /// 显示同步执行对话框，返回最终结果
  static Future<SyncResult?> show({
    required BuildContext context,
    required SyncPlan plan,
    required String connectionId,
    required String databaseName,
    required DatabaseType dbType,
    required SchemaSyncService syncService,
    bool dryRun = false,
  }) {
    return showDialog<SyncResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SchemaSyncExecutorDialogStateful(
        plan: plan,
        connectionId: connectionId,
        databaseName: databaseName,
        dbType: dbType,
        syncService: syncService,
        dryRun: dryRun,
      ),
    );
  }

  @override
  State<SchemaSyncExecutorDialog> createState() =>
      _SchemaSyncExecutorDialogState();
}

class _SchemaSyncExecutorDialogState extends State<SchemaSyncExecutorDialog> {
  SyncProgress? _progress;
  SyncResult? _result;
  bool _isRunning = true;
  String? _error;
  //跨流事件累计 —— 仅当服务端发射过 rollingBack 阶段（PG 自动回滚）
  // 时为 true。终端事件阶段恒为 completed/failed，无法用它判断是否回滚。
  bool _didRollback = false;

  @override
  void initState() {
    super.initState();
    _startExecution();
  }

  Future<void> _startExecution() async {
    try {
      final stream = widget.syncService.executeWithProgress(
        plan: widget.plan,
        connectionId: widget.connectionId,
        databaseName: widget.databaseName,
        dbType: widget.dbType,
        dryRun: false,
      );

      await for (final progress in stream) {
        if (!mounted) return;
        setState(() => _progress = progress);

        //记录中途的 rollingBack 阶段（PG 自动回滚）。
        // rollingBack 是非终端事件，后面还会跟一个 completed/failed。
        if (progress.phase == SyncExecutionPhase.rollingBack) {
          _didRollback = true;
        }

        if (progress.phase == SyncExecutionPhase.completed ||
            progress.phase == SyncExecutionPhase.failed) {
          //rollbackScript 仅在 completed 阶段从 error 取（服务端契约：
          // 回滚脚本放在终端 completed 事件的 error 字段）；failed 阶段的 error
          // 是真正的错误信息，应显示到错误容器而非当作脚本。
          final isCompleted = progress.phase == SyncExecutionPhase.completed;
          _result = SyncResult(
            successCount: progress.successCount,
            failureCount: progress.failureCount,
            skippedCount: progress.skippedCount,
            steps: progress.completedSteps,
            totalDuration: Duration.zero,
            didRollback: _didRollback,
            rollbackScript: isCompleted ? progress.error : null,
          );
          //failed 阶段也要展示错误信息（原实现仅在 catch 中设置）。
          if (!isCompleted && progress.error != null) {
            _error = progress.error;
          }
          if (mounted) {
            setState(() => _isRunning = false);
          }
          return;
        }
      }

      if (mounted) {
        setState(() => _isRunning = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isRunning ? LucideIcons.refreshCw : LucideIcons.circleCheckBig,
            color: _isRunning ? context.themeColors.accentBlue : Colors.green,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(_isRunning ? 'Executing Sync Plan' : 'Sync Complete'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress bar
            if (_progress != null) ...[
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _progress!.percentComplete.clamp(0.0, 1.0),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Text(
                    '${_progress!.currentStep}/${_progress!.totalSteps}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space3),
              // Phase indicator
              _buildPhaseChip(),
              const SizedBox(height: AppDesignSystem.space3),
            ],
            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
                // 红框 Text → ActionableError（可复制 + AI 分析）
                child: ActionableError(
                  message: _error!,
                  connectionId: widget.connectionId,
                  databaseName: widget.databaseName,
                  onAnalyze: () {
                    final msg = _error;
                    if (msg == null) return;
                    unawaited(
                      context.read<AppProvider>().analyzeErrorWithAi(
                        errorText: msg,
                        connectionId: widget.connectionId,
                        databaseName: widget.databaseName,
                        locale: LocaleProvider.codeOf(
                          Localizations.localeOf(context),
                        ),
                      ),
                    );
                  },
                ),
              ),
            // Step list
            Expanded(
              child: _progress == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _progress!.completedSteps.length,
                      itemBuilder: (context, index) {
                        final step = _progress!.completedSteps[index];
                        return _StepRow(step: step, index: index + 1);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (_isRunning)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          )
        else ...[
          //Rollback info —— PG 自动回滚（橙）或 MySQL/Doris 手动回滚脚本（蓝）。
          if (_result != null &&
              (_result!.didRollback || _result!.rollbackScript != null))
            _buildRollbackBanner(),
          // Summary
          if (_result != null) _buildSummary(),
          const SizedBox(width: AppDesignSystem.space2),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_result),
            child: const Text('Close'),
          ),
        ],
      ],
    );
  }

  Widget _buildPhaseChip() {
    final phase = _progress?.phase ?? SyncExecutionPhase.validating;
    final (String label, Color color) = switch (phase) {
      SyncExecutionPhase.validating => ('Validating', Colors.blue),
      SyncExecutionPhase.executing => (
        'Executing',
        context.themeColors.accentBlue,
      ),
      SyncExecutionPhase.rollingBack => ('Rolling Back', Colors.orange),
      SyncExecutionPhase.completed => ('Completed', Colors.green),
      SyncExecutionPhase.failed => ('Failed', context.themeColors.error),
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            '✅ ${_result!.successCount}  ❌ ${_result!.failureCount}  ⏭ ${_result!.skippedCount}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildSummary() {
    final result = _result!;
    return Row(
      children: [
        _SummaryCount(
          label: 'Success',
          count: result.successCount,
          color: Colors.green,
        ),
        const SizedBox(width: AppDesignSystem.space2),
        _SummaryCount(
          label: 'Failed',
          count: result.failureCount,
          color: Colors.red,
        ),
        const SizedBox(width: AppDesignSystem.space2),
        _SummaryCount(
          label: 'Skipped',
          count: result.skippedCount,
          color: Colors.grey,
        ),
      ],
    );
  }

  ///回滚信息横幅。
  /// - [SyncResult.didRollback] == true：事务型 DB（PG）已自动回滚 → 橙色提示。
  /// - 否则但 rollbackScript 非空：非事务型 DB（MySQL/Doris）生成手动回滚脚本 → 蓝色提示。
  /// 两种情况都渲染可复制的回滚脚本。
  Widget _buildRollbackBanner() {
    final result = _result!;
    final rolledBack = result.didRollback;
    final script = result.rollbackScript;

    final (String title, String hint, Color color) = rolledBack
        ? (
            '⚠ Transaction rolled back',
            'All changes were rolled back automatically.',
            Colors.orange,
          )
        : (
            'ℹ Manual rollback script available',
            'Non-transactional DB: review and apply the script below manually to undo.',
            Colors.blue,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(hint, style: TextStyle(fontSize: 12, color: color)),
          if (script != null && script.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  script,
                  style: const TextStyle(
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SchemaSyncExecutorDialogStateful extends StatelessWidget {
  final SyncPlan plan;
  final String connectionId;
  final String databaseName;
  final DatabaseType dbType;
  final SchemaSyncService syncService;
  final bool dryRun;

  const _SchemaSyncExecutorDialogStateful({
    required this.plan,
    required this.connectionId,
    required this.databaseName,
    required this.dbType,
    required this.syncService,
    required this.dryRun,
  });

  @override
  Widget build(BuildContext context) {
    return SchemaSyncExecutorDialog(
      plan: plan,
      connectionId: connectionId,
      databaseName: databaseName,
      dbType: dbType,
      syncService: syncService,
    );
  }
}

class _StepRow extends StatelessWidget {
  final SyncStep step;
  final int index;

  const _StepRow({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (step.status) {
      SyncStepStatus.success => (LucideIcons.circleCheckBig, Colors.green),
      SyncStepStatus.failed => (LucideIcons.circleAlert, Colors.red),
      SyncStepStatus.skipped => (LucideIcons.skipForward, Colors.grey),
      SyncStepStatus.running => (
        LucideIcons.hourglass,
        context.themeColors.accentBlue,
      ),
      SyncStepStatus.pending => (LucideIcons.circle, Colors.grey),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          '#$index: ${step.operation.description}',
          style: TextStyle(
            fontSize: 13,
            color: step.status == SyncStepStatus.failed
                ? context.themeColors.error
                : null,
          ),
        ),
        subtitle: step.error != null
            // Text → SelectableText（可选中复制）
            ? SelectableText(
                step.error!,
                style: TextStyle(
                  color: context.themeColors.error,
                  fontSize: 11,
                ),
              )
            : step.duration != null
            ? Text(
                '${step.duration!.inMilliseconds}ms',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              )
            : null,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SelectableText(
              step.operation.sql,
              style: const TextStyle(
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCount extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SummaryCount({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
