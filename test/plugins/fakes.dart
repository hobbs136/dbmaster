// C01a · UI 插件注册框架测试用 fakes。
//
// 刻意最小化：只实现接口契约本身，不引 AppProvider / 真实 l10n，
// 验证「框架通路」而非业务行为（后者归 C2/C3/C4 区块测试）。
import 'package:flutter/material.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/plugins/ai_skill_plugin.dart';
import 'package:dbmaster/plugins/connection_form_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/result_renderer_plugin.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 连接表单插件 fake：记录会话创建次数。
class FakeConnectionFormPlugin implements ConnectionFormPlugin {
  FakeConnectionFormPlugin(this.descriptor);

  @override
  final PluginDescriptor descriptor;

  int createdSessions = 0;

  @override
  FakeConnectionFormSession createSession(ConnectionFormPluginContext context) {
    createdSessions++;
    return FakeConnectionFormSession(context);
  }
}

/// 表单会话 fake：build 计数 + collect 时向草稿 host 写标记值。
class FakeConnectionFormSession implements ConnectionFormSession {
  FakeConnectionFormSession(this.formContext);

  final ConnectionFormPluginContext formContext;

  int buildCount = 0;
  bool disposed = false;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return Text('fake-form-${formContext.type.name}');
  }

  @override
  DbServer? collect({bool forSave = false}) =>
      formContext.draft.value.copyWith(host: 'collected-host');

  @override
  void dispose() => disposed = true;
}

/// 侧边栏插件 fake：一组 Redis 风格能力分组（含 port 能力键）。
class FakeSidebarPlugin implements SidebarPlugin {
  FakeSidebarPlugin(this.descriptor);

  @override
  final PluginDescriptor descriptor;

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) => [
    SidebarCapabilityGroup(
      id: 'keyspace',
      label: (AppLocalizations l10n) => '键空间',
      icon: LucideIcons.keyRound,
      items: [
        SidebarCapabilityItem(
          id: 'key-list',
          label: (AppLocalizations l10n) => '键列表',
          icon: LucideIcons.list,
          capabilityId: 'redis.keyspace',
        ),
      ],
    ),
  ];

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) =>
      const [SizedBox.shrink()];

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) =>
      const [];
}

/// 结果渲染器 fake。
class FakeResultRendererPlugin implements ResultRendererPlugin {
  FakeResultRendererPlugin(
    this.descriptor,
    this.viewModeId, {
    Set<ResultDataShape> shapes = const <ResultDataShape>{
      ResultDataShape.sqlRows,
    },
  }) : supportedShapes = shapes;

  @override
  final PluginDescriptor descriptor;

  @override
  final String viewModeId;

  @override
  final Set<ResultDataShape> supportedShapes;

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) =>
      Text('renderer-$viewModeId');
}

/// AI 技能插件 fake（占位契约验证）。
class FakeAiSkillPlugin implements AiSkillPlugin {
  FakeAiSkillPlugin(this.descriptor, this.skillGroupId);

  @override
  final PluginDescriptor descriptor;

  @override
  final String skillGroupId;

  @override
  String Function(AppLocalizations l10n) get displayName =>
      (AppLocalizations l10n) => 'skill';

  // C23 扩展成员：接口默认实现对 implements 不生效（Dart 语义），
  // fake 显式给出与默认一致的值。
  @override
  String Function(AppLocalizations l10n)? get description => null;

  @override
  String Function(AppLocalizations l10n)? get promptTemplate => null;

  @override
  AiSkillEnvelopeType get resultType => AiSkillEnvelopeType.markdown;
}
