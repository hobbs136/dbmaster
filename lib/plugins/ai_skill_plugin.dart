// C01a · UI 插件注册框架 —— AI 技能插件接口。
//
// C23 二期实现（AI 面板三栏重构 + skill 接口化）：技能目录（面板左栏）
// 消费 `PluginRegistry.aiSkills`，按 [skillGroupId] 分组渲染。技能 v1 =
// 提示词模板 + envelope 期望（点击填充输入框，结果按 [resultType] 渲染），
// 本地工具执行（/optimize 等）仍走 slash 菜单，不在技能插件层。
// envelope 形态来自原型 §6.1：统一 `{type: sql|markdown|diff|json,
// content}`，面板按 type 选择渲染组件。原 `AiSkill` 死代码
// （ai_skill_service.dart）已删除，内置技能以本接口实现重落（走 l10n）。
import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import 'plugin_descriptor.dart';

/// AI 技能返回内容的载体类型（统一 envelope 的 type 字段）。
enum AiSkillEnvelopeType { sql, markdown, diff, json }

/// AI 技能统一返回 envelope：面板按 [type] 分发渲染组件。
@immutable
class AiSkillEnvelope {
  final AiSkillEnvelopeType type;
  final String content;

  const AiSkillEnvelope({required this.type, required this.content});

  /// type 字段的序列化名（AiMessage.envelopeType 持久化用）。
  String get typeName => type.name;

  /// 从序列化名解析；未知名返回 null（存量/异常数据回退启发式渲染）。
  static AiSkillEnvelopeType? typeFromName(String? name) {
    if (name == null) return null;
    for (final t in AiSkillEnvelopeType.values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// 技能目录分组 id（原型：SQL 类 / 数据类 / 结构类 / 运维类）。
abstract class AiSkillGroupIds {
  static const String sql = 'sql';
  static const String data = 'data';
  static const String schema = 'schema';
  static const String ops = 'ops';
}

/// AI 技能插件接口（成员全抽象，与 C01a 其他插件接口一致——implements
/// 必须显式给出全部成员；无 promptTemplate 的技能返回 null，结果类型
/// 不敏感的技能返回 [AiSkillEnvelopeType.markdown]）。
abstract interface class AiSkillPlugin {
  PluginDescriptor get descriptor;

  /// 技能目录分组 id（[AiSkillGroupIds]）。
  String get skillGroupId;

  /// 技能本地化显示名。
  String Function(AppLocalizations l10n) get displayName;

  /// 技能本地化描述（目录条目第二行；null = 不显示）。
  String Function(AppLocalizations l10n)? get description;

  /// 点击技能时填入输入框的提示词模板（null = 仅选中不填充）。
  String Function(AppLocalizations l10n)? get promptTemplate;

  /// 技能结果期望的 envelope 类型（渲染层提示）。
  AiSkillEnvelopeType get resultType;
}
