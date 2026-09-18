//! 执行门弹窗（ADR-0003 Part A + D1/D10/D11）。
//!
//! 合并安全审查 findings + DDL 影响分析为单一弹窗，替代原来安全审查
//! 弹窗 + DdlConfirmDialog 的串联。支持单语句和多语句两种形态。
//! 警告不阻断——用户始终可选择「知情继续执行」。
//!
//! C22 M2 迁移：文案全量 l10n 化（原硬编码中文），严重度标签改
//! safetySeverity* 键 + 语义色徽章（原型 security-review.html 语汇）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../services/safety/safety_finding.dart';
import '../../theme/app_theme.dart';

/// 执行门弹窗的返回动作。
enum ExecutionGateAction {
  /// 用户取消——不执行任何语句。
  cancel,

  /// 采用建议——替换编辑器 SQL（仅单 finding 有 suggestion 时可用）。
  /// 调用方替换 SQL 后不自动执行（用户需二次确认）。
  applySuggestion,

  /// 知情继续执行——忽略所有风险执行原 SQL。
  proceed,

  /// 跳过高危，执行其余（仅多语句模式）。
  /// 调用方过滤掉 high finding 的语句后执行剩余。
  skipHighRisk,
}

/// 执行门弹窗。
///
/// 单语句模式：`findings` 来自一条 SQL 的审查。
/// 多语句模式：`findings` 来自多条 SQL 的审查，每个 finding 带 `statementIndex`。
/// 多语句时传入 [statementCount] 启用多语句形态。
class ExecutionGateDialog extends StatefulWidget {
  final List<SafetyFinding> findings;

  /// SQL 语句总数（多语句模式）。null 或 1 = 单语句模式。
  final int? statementCount;

  /// DDL 影响分析文本（可选，合并展示）。
  final String? ddlImpactSummary;

  const ExecutionGateDialog({
    super.key,
    required this.findings,
    this.statementCount,
    this.ddlImpactSummary,
  });

  /// 便捷调用。
  static Future<ExecutionGateAction> show(
    BuildContext context, {
    required List<SafetyFinding> findings,
    int? statementCount,
    String? ddlImpactSummary,
  }) {
    return showDialog<ExecutionGateAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExecutionGateDialog(
        findings: findings,
        statementCount: statementCount,
        ddlImpactSummary: ddlImpactSummary,
      ),
    ).then((v) => v ?? ExecutionGateAction.cancel);
  }

  @override
  State<ExecutionGateDialog> createState() => _ExecutionGateDialogState();
}

class _ExecutionGateDialogState extends State<ExecutionGateDialog> {
  bool _overviewExpanded = false;
  final FocusNode _focusNode = FocusNode();

  bool get _isMultiStatement =>
      widget.statementCount != null && widget.statementCount! > 1;

  List<SafetyFinding> get _highFindings =>
      widget.findings.where((f) => f.severity == Severity.high).toList();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final hasHigh = _highFindings.isNotEmpty;
    final hasSuggestion = widget.findings.any((f) => f.suggestion != null);
    // 全部语句都是 high → 跳过按钮禁用。
    final allHigh =
        _isMultiStatement &&
        widget.findings.isNotEmpty &&
        widget.findings.every((f) => f.severity == Severity.high);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: AlertDialog(
        backgroundColor: colors.bgSecondary,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        title: _buildTitle(context),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.ddlImpactSummary != null)
                  _buildDdlImpactCard(context),
                if (_isMultiStatement) _buildOverview(context),
                ...widget.findings.map((f) => _buildFindingCard(context, f)),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        actions: _buildActions(context, hasHigh, hasSuggestion, allHigh),
      ),
    );
  }

  // ── 标题 ──

  Widget _buildTitle(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final count = widget.findings.length;
    final hasHigh = _highFindings.isNotEmpty;
    return Row(
      children: [
        Icon(
          hasHigh ? LucideIcons.circleAlert : LucideIcons.triangleAlert,
          color: hasHigh ? colors.accentRed : colors.warning,
          size: 24,
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: Text(
            _isMultiStatement
                ? l10n.gateTitleMulti(widget.statementCount!, count)
                : l10n.gateTitleSingle(count),
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.pop(context, ExecutionGateAction.cancel),
          tooltip: l10n.commonCancel,
        ),
      ],
    );
  }

  // ── DDL 影响分析卡片（合并展示）──

  Widget _buildDdlImpactCard(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.accentRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleAlert, color: colors.accentRed, size: 18),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.gateDdlImpactTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  widget.ddlImpactSummary!,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 多语句概览（折叠/展开）──

  Widget _buildOverview(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final high = _highFindings.length;
    final medium = widget.findings
        .where((f) => f.severity == Severity.medium)
        .length;
    final low = widget.findings.where((f) => f.severity == Severity.low).length;
    final total = widget.statementCount!;
    final okCount =
        total - widget.findings.map((f) => f.statementIndex).toSet().length;

    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      child: InkWell(
        onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppDesignSystem.space1_5,
          ),
          child: Row(
            children: [
              Icon(
                _overviewExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  l10n.gateOverview(total, high, medium, low, okCount),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Finding 卡片 ──

  Widget _buildFindingCard(BuildContext context, SafetyFinding f) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final (sevLabel, sevColor) = switch (f.severity) {
      Severity.high => (l10n.safetySeverityHigh, colors.accentRed),
      Severity.medium => (l10n.safetySeverityMedium, colors.warning),
      Severity.low => (l10n.safetySeverityLow, colors.accentBlue),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: sevColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                SafetyFinding.iconFor(f.severity),
                color: sevColor,
                size: 18,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              if (_isMultiStatement && f.statementIndex > 0)
                Padding(
                  padding: const EdgeInsets.only(right: AppDesignSystem.space2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: sevColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.gateStatementLabel(f.statementIndex),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: sevColor,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  f.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              // 严重度徽章（原型语汇：container 底 + 语义色文本）。
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1_5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: sevColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  sevLabel,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    fontWeight: FontWeight.w600,
                    color: sevColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          Text(
            f.description,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          if (f.suggestion != null) ...[
            const SizedBox(height: AppDesignSystem.space2),
            _buildSuggestion(context, f.suggestion!, sevColor),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestion(BuildContext context, String sql, Color sevColor) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.lightbulb, size: 14, color: sevColor),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.gateSuggestionLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: sevColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: colors.borderColor),
          ),
          child: Text(
            sql,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // ── 按钮区 ──

  List<Widget> _buildActions(
    BuildContext context,
    bool hasHigh,
    bool hasSuggestion,
    bool allHigh,
  ) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final actions = <Widget>[];

    // 取消（始终可用，Esc 快捷键）
    actions.add(
      TextButton(
        onPressed: () => Navigator.pop(context, ExecutionGateAction.cancel),
        child: Text(
          _isMultiStatement ? l10n.gateCancelAll : l10n.commonCancel,
          style: TextStyle(color: colors.textSecondary),
        ),
      ),
    );

    // 多语句：跳过高危执行其余
    if (_isMultiStatement) {
      final skipCount = _highFindings.length;
      final execCount = (widget.statementCount ?? 1) - skipCount;
      actions.add(
        TextButton(
          onPressed: allHigh
              ? null
              : () => Navigator.pop(context, ExecutionGateAction.skipHighRisk),
          child: Text(
            allHigh
                ? l10n.gateAllHighDisabled
                : l10n.gateSkipHighRisk(skipCount, execCount),
            style: TextStyle(
              color: allHigh ? colors.textMuted : colors.warning,
            ),
          ),
        ),
      );
    }

    // 采用全部建议（有 suggestion 时）
    if (hasSuggestion) {
      actions.add(
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, ExecutionGateAction.applySuggestion),
          child: Text(l10n.gateApplySuggestions),
        ),
      );
    }

    // 知情继续执行（红色警告）
    actions.add(
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.accentRed,
          side: BorderSide(color: colors.accentRed),
        ),
        onPressed: () => Navigator.pop(context, ExecutionGateAction.proceed),
        child: Text(_isMultiStatement ? l10n.gateProceedAll : l10n.gateProceed),
      ),
    );

    return actions.reversed.toList(); // 主按钮在右
  }

  // ── 键盘 ──

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.pop(context, ExecutionGateAction.cancel);
      }
    }
  }
}
