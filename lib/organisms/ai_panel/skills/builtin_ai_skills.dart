// C23.1 · 内置 AI 技能插件（OSS 默认注册）。
//
// 技能 v1 = 提示词模板 + envelope 期望：点击技能 → 选中 + promptTemplate
// 填入输入框，发送走既有对话链路（orchestrator），结果按 resultType 经
// AiResultRenderer envelope 分发渲染。本地工具执行（/optimize 等）仍在
// slash 菜单，不在技能层。分组对齐原型 ai-panel-skills 四组；Pro 层按同
// id + override: true 替换（spec 045 接缝，与类身份无关）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../plugins/ai_skill_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';

@immutable
class BuiltinAiSkill implements AiSkillPlugin {
  @override
  final PluginDescriptor descriptor;
  @override
  final String skillGroupId;
  @override
  final String Function(AppLocalizations l10n) displayName;
  @override
  final String Function(AppLocalizations l10n)? description;
  @override
  final String Function(AppLocalizations l10n)? promptTemplate;
  @override
  final AiSkillEnvelopeType resultType;

  BuiltinAiSkill({
    required String id,
    required IconData icon,
    required this.skillGroupId,
    required this.displayName,
    this.description,
    this.promptTemplate,
    this.resultType = AiSkillEnvelopeType.markdown,
  }) : descriptor = PluginDescriptor(id: id, source: PluginSource.ai, icon: icon);
}

/// 内置技能全集（注册序 = 目录展示序）。
///
/// 非 const：displayName/promptTemplate 是闭包（l10n 惰性求值），
/// Dart 闭包字面量不构成 const 表达式；注册发生在运行期引导，无损失。
final List<BuiltinAiSkill> builtinAiSkills = [
  // SQL 类
  BuiltinAiSkill(
    id: 'nl2sql-plugin',
    icon: LucideIcons.messageSquareCode,
    skillGroupId: AiSkillGroupIds.sql,
    displayName: (l10n) => l10n.aiSkillNl2sqlName,
    description: (l10n) => l10n.aiSkillNl2sqlDesc,
    resultType: AiSkillEnvelopeType.sql,
  ),
  BuiltinAiSkill(
    id: 'sql-explain-plugin',
    icon: LucideIcons.bookOpen,
    skillGroupId: AiSkillGroupIds.sql,
    displayName: (l10n) => l10n.aiSkillSqlExplainName,
    description: (l10n) => l10n.aiSkillSqlExplainDesc,
    promptTemplate: (l10n) => l10n.aiSkillSqlExplainPrompt,
  ),
  BuiltinAiSkill(
    id: 'query-optimizer-plugin',
    icon: LucideIcons.zap,
    skillGroupId: AiSkillGroupIds.sql,
    displayName: (l10n) => l10n.aiSkillQueryOptimizerName,
    description: (l10n) => l10n.aiSkillQueryOptimizerDesc,
    promptTemplate: (l10n) => l10n.aiSkillQueryOptimizerPrompt,
  ),
  // 数据类
  BuiltinAiSkill(
    id: 'data-cleaning-plugin',
    icon: LucideIcons.brushCleaning,
    skillGroupId: AiSkillGroupIds.data,
    displayName: (l10n) => l10n.aiSkillDataCleaningName,
    description: (l10n) => l10n.aiSkillDataCleaningDesc,
    promptTemplate: (l10n) => l10n.aiSkillDataCleaningPrompt,
  ),
  BuiltinAiSkill(
    id: 'import-mapping-plugin',
    icon: LucideIcons.fileInput,
    skillGroupId: AiSkillGroupIds.data,
    displayName: (l10n) => l10n.aiSkillImportMappingName,
    description: (l10n) => l10n.aiSkillImportMappingDesc,
    promptTemplate: (l10n) => l10n.aiSkillImportMappingPrompt,
    resultType: AiSkillEnvelopeType.json,
  ),
  // 结构类
  BuiltinAiSkill(
    id: 'schema-analysis-plugin',
    icon: LucideIcons.binary,
    skillGroupId: AiSkillGroupIds.schema,
    displayName: (l10n) => l10n.aiSkillSchemaAnalysisName,
    description: (l10n) => l10n.aiSkillSchemaAnalysisDesc,
    promptTemplate: (l10n) => l10n.aiSkillSchemaAnalysisPrompt,
  ),
  BuiltinAiSkill(
    id: 'schema-diff-plugin',
    icon: LucideIcons.gitCompare,
    skillGroupId: AiSkillGroupIds.schema,
    displayName: (l10n) => l10n.aiSkillSchemaDiffName,
    description: (l10n) => l10n.aiSkillSchemaDiffDesc,
    promptTemplate: (l10n) => l10n.aiSkillSchemaDiffPrompt,
    resultType: AiSkillEnvelopeType.diff,
  ),
  BuiltinAiSkill(
    id: 'index-suggest-plugin',
    icon: LucideIcons.listTree,
    skillGroupId: AiSkillGroupIds.schema,
    displayName: (l10n) => l10n.aiSkillIndexSuggestName,
    description: (l10n) => l10n.aiSkillIndexSuggestDesc,
    promptTemplate: (l10n) => l10n.aiSkillIndexSuggestPrompt,
  ),
  // 运维类
  BuiltinAiSkill(
    id: 'error-diagnosis-plugin',
    icon: LucideIcons.stethoscope,
    skillGroupId: AiSkillGroupIds.ops,
    displayName: (l10n) => l10n.aiSkillErrorDiagnosisName,
    description: (l10n) => l10n.aiSkillErrorDiagnosisDesc,
    promptTemplate: (l10n) => l10n.aiSkillErrorDiagnosisPrompt,
  ),
  BuiltinAiSkill(
    id: 'slow-query-plugin',
    icon: LucideIcons.timer,
    skillGroupId: AiSkillGroupIds.ops,
    displayName: (l10n) => l10n.aiSkillSlowQueryName,
    description: (l10n) => l10n.aiSkillSlowQueryDesc,
    promptTemplate: (l10n) => l10n.aiSkillSlowQueryPrompt,
  ),
];
