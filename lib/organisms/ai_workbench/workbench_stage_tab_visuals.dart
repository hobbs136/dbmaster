//! 舞台 tab kind → 视觉映射注册表（C1，AI 工作台先行批任务书 §6.0）。
//!
//! **本文件是 [WorkbenchStageTabKind] → 图标/标签映射的唯一事实源**
//! （v2 §8-7「tab 条与产物条图标/标签一致性」的结构性消解：单一注册表 +
//! 一例回归守卫，取代此前 stage / strip 双份私有 switch 的双改维护）。
//! 既有 4 kind 映射逐字搬移自 workbench_stage.dart 与
//! workbench_artifact_strip.dart 原私有函数，值与文案 key 零变化；
//! sessionList 由 v2 A2 增补（messageCircle + agentStageTabSessions，R5）；
//! history 由 v2 A3 增补（history + agentStageTabHistory）；
//! savedQueries 由 v2 A4 增补（bookmark + agentStageTabSavedQueries）；
//! execution 由 v2 B1 增补（squareTerminal + agentStageTabExecution；
//! squareTerminal 已在 Lucide 子集，无需再生成字体）。
//! observe 由 2b.1 增补（activity + agentStageTabObserve；activity 已在
//! Lucide 子集，无需再生成字体——R11 实证）。
//! optimization 由 2b.3 增补（gauge + agentStageTabOptimization；gauge 已在
//! Lucide 子集，无需再生成字体——R11 实证）。
//!
//! 新增 kind 只改这里 + stage 内容槽（`_buildSlot`）两处：舞台 tab 条与
//! 产物条均为本 extension 的纯消费方，同 kind 恒同图标、同默认标签。
//! 第二批剩余 kind（taskList / taskRunHistory / report / safetyReport /
//! export / bookmark）落此扩展位，本批不实现。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import 'workbench_stage.dart' show WorkbenchStageTabKind;

/// kind → 视觉映射（唯一事实源）：舞台 tab 条（§5.2）与产物条（§6.1）的
/// 类型图标/默认标签均消费本 extension，不许任何文件再落映射副本。
extension WorkbenchStageTabKindVisuals on WorkbenchStageTabKind {
  /// 类型图标（tab 条 14 / 产物条 12；尺寸与颜色由消费方决定，此处只定图形）。
  IconData get icon {
    return switch (this) {
      WorkbenchStageTabKind.grid => LucideIcons.table,
      WorkbenchStageTabKind.structure => LucideIcons.listTree,
      WorkbenchStageTabKind.editor => LucideIcons.code,
      WorkbenchStageTabKind.chart => LucideIcons.chartColumn,
      WorkbenchStageTabKind.sessionList => LucideIcons.messageCircle,
      WorkbenchStageTabKind.history => LucideIcons.history,
      WorkbenchStageTabKind.savedQueries => LucideIcons.bookmark,
      WorkbenchStageTabKind.execution => LucideIcons.squareTerminal,
      WorkbenchStageTabKind.observe => LucideIcons.activity,
      WorkbenchStageTabKind.optimization => LucideIcons.gauge,
    };
  }

  /// 类型默认标签（tab.title 缺席时的回退；既有 key 逐字沿用）。
  String label(AppLocalizations l10n) {
    return switch (this) {
      WorkbenchStageTabKind.grid => l10n.agentStageTabGrid,
      WorkbenchStageTabKind.structure => l10n.agentStageTabStructure,
      WorkbenchStageTabKind.editor => l10n.agentStageTabEditor,
      WorkbenchStageTabKind.chart => l10n.agentStageTabChart,
      WorkbenchStageTabKind.sessionList => l10n.agentStageTabSessions,
      WorkbenchStageTabKind.history => l10n.agentStageTabHistory,
      WorkbenchStageTabKind.savedQueries => l10n.agentStageTabSavedQueries,
      WorkbenchStageTabKind.execution => l10n.agentStageTabExecution,
      WorkbenchStageTabKind.observe => l10n.agentStageTabObserve,
      WorkbenchStageTabKind.optimization => l10n.agentStageTabOptimization,
    };
  }
}
