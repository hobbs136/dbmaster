//! 舞台容器/子态 → 视觉映射注册表（C1，AI 工作台先行批任务书 §6.0；
//! 批3 T7 容器收敛重构，.specs/tasks-v3.5-ui.md §3-B01）。
//!
//! **本文件是 [WorkbenchStageContainerKind] → 图标/容器标签 与各容器
//! 子态枚举 → 分段标签映射的唯一事实源**（v2 §8-7「tab 条与产物条图标/
//! 标签一致性」的结构性消解：单一注册表 + 一例回归守卫，取代此前
//! stage / strip 双份私有 switch 的双改维护）。
//!
//! 批3 B-01 重构（10 kind → 4 容器）：容器级 visuals（tab 条 / 产物条 /
//! 重开菜单消费）+ subKind 级 label 注册（容器内分段控件消费）。旧 kind
//! 图标沿迁移映射归位：sqlStudio=editor 的 code / dataViz=grid 的 table /
//! schema=structure 的 listTree / diagnostics=execution 的 squareTerminal。
//!
//! 新增 kind 只改这里 + 舞台枚举 + stage 内容槽（`_buildSlot`）三触点：
//! 舞台 tab 条与产物条均为本 extension 的纯消费方，同容器恒同图标、同
//! 容器标签。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import 'workbench_stage.dart'
    show
        DataVizSubKind,
        DiagnosticsSubKind,
        SchemaSubKind,
        SqlStudioSubKind,
        WorkbenchStageContainerKind;

/// 容器 → 视觉映射（唯一事实源）：舞台 tab 条（§5.2）与产物条（§6.1）的
/// 容器图标/容器标签均消费本 extension，不许任何文件再落映射副本。
extension WorkbenchStageContainerKindVisuals on WorkbenchStageContainerKind {
  /// 容器图标（tab 条 14 / 产物条 12；尺寸与颜色由消费方决定，此处只定
  /// 图形——沿旧 kind 迁移映射：editor→code / grid→table /
  /// structure→listTree / execution→squareTerminal）。
  IconData get icon {
    return switch (this) {
      WorkbenchStageContainerKind.sqlStudio => LucideIcons.code,
      WorkbenchStageContainerKind.dataViz => LucideIcons.table,
      WorkbenchStageContainerKind.schema => LucideIcons.listTree,
      WorkbenchStageContainerKind.diagnostics => LucideIcons.squareTerminal,
    };
  }

  /// 容器标签（tab 条恒显 + 产物芯片/重开菜单的 title 回退；批3 新键
  /// agentStageContainer*，T0c 已备六语）。
  String label(AppLocalizations l10n) {
    return switch (this) {
      WorkbenchStageContainerKind.sqlStudio => l10n.agentStageContainerSqlStudio,
      WorkbenchStageContainerKind.dataViz => l10n.agentStageContainerDataViz,
      WorkbenchStageContainerKind.schema => l10n.agentStageContainerSchema,
      WorkbenchStageContainerKind.diagnostics =>
        l10n.agentStageContainerDiagnostics,
    };
  }
}

/// SQL Studio 子态分段标签（edit 沿既有 agentStageTabEditor = "Editor"；
/// diff = agentStageSegDiff）。
extension SqlStudioSubKindVisuals on SqlStudioSubKind {
  /// 分段标签。
  String label(AppLocalizations l10n) {
    return switch (this) {
      SqlStudioSubKind.edit => l10n.agentStageTabEditor,
      SqlStudioSubKind.diff => l10n.agentStageSegDiff,
    };
  }
}

/// Data & Viz 子态分段标签（grid/chart 沿既有 agentStageTabGrid/Chart）。
extension DataVizSubKindVisuals on DataVizSubKind {
  /// 分段标签。
  String label(AppLocalizations l10n) {
    return switch (this) {
      DataVizSubKind.grid => l10n.agentStageTabGrid,
      DataVizSubKind.chart => l10n.agentStageTabChart,
    };
  }
}

/// Schema 子态分段标签（批3 新键 agentStageSchemaColumns/Indexes/Ddl）。
extension SchemaSubKindVisuals on SchemaSubKind {
  /// 分段标签（兼子段标题——内容不重复渲染节标题）。
  String label(AppLocalizations l10n) {
    return switch (this) {
      SchemaSubKind.columns => l10n.agentStageSchemaColumns,
      SchemaSubKind.indexes => l10n.agentStageSchemaIndexes,
      SchemaSubKind.ddl => l10n.agentStageSchemaDdl,
    };
  }
}

/// Diagnostics 子态分段标签（批3 新键 agentStageExplainPlan/LiveMonitor）。
extension DiagnosticsSubKindVisuals on DiagnosticsSubKind {
  /// 分段标签。
  String label(AppLocalizations l10n) {
    return switch (this) {
      DiagnosticsSubKind.explainPlan => l10n.agentStageExplainPlan,
      DiagnosticsSubKind.liveMonitor => l10n.agentStageLiveMonitor,
    };
  }
}
