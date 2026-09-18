//! SQL 安全审查 — Finding 模型 + Severity 枚举（ADR-0003 Part A）。
//!
//! 一条 [SafetyFinding] 代表安全审查引擎发现的一个问题（如列不存在、
//! 缺 LIMIT）。规则（[SafetyRule]）产出 findings，引擎聚合后按严重度
//! 排序，[ExecutionGateDialog] 展示给用户。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 审查发现的严重度。映射到弹窗的颜色/图标体系（复用 DdlConfirmDialog
/// 的 RiskLevel 配色：high→orange/warning、medium→warning、low→info）。
enum Severity {
  /// 低风险——静默通过（不弹窗），仅在状态栏/审计中记录。
  low,

  /// 中风险——弹窗展示，但用户可选择继续执行。
  medium,

  /// 高风险——弹窗置顶展示，建议用户修正或知情继续。
  high,
}

/// 安全审查发现的一条问题。
class SafetyFinding {
  /// 规则 ID（如 'schema_compat'、'missing_limit'），用于开关/日志。
  final String ruleId;

  /// 严重度（决定弹窗着色 + 是否触发弹窗）。
  final Severity severity;

  /// 一句话标题（如「列 'status' 不存在」）。
  final String title;

  /// 详细描述（如「该列可能已被删除或改名」）。
  final String description;

  /// 修复建议 SQL（可选）。非 null 时弹窗展示「采用建议」按钮。
  final String? suggestion;

  /// 涉及的表名（可选，用于上下文展示）。
  final String? affectedTable;

  /// 多语句脚本审查时，标注来自第几条语句（从 1 开始，0 = 单语句）。
  final int statementIndex;

  /// B3：finding 涉及的起始行号（1-based，相对编辑器全文）。
  /// 0 = 无行号信息（向后兼容，不画行级红点）。
  final int lineStart;

  /// B3：finding 涉及的结束行号（1-based，含）。0 = 无行号信息。
  final int lineEnd;

  const SafetyFinding({
    required this.ruleId,
    required this.severity,
    required this.title,
    required this.description,
    this.suggestion,
    this.affectedTable,
    this.statementIndex = 0,
    this.lineStart = 0,
    this.lineEnd = 0,
  });

  /// 严重度对应的图标。
  static IconData iconFor(Severity severity) {
    switch (severity) {
      case Severity.high:
        return LucideIcons.circleAlert;
      case Severity.medium:
        return LucideIcons.triangleAlert;
      case Severity.low:
        return LucideIcons.info;
    }
  }
}
