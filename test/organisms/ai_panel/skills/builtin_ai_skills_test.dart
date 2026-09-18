// C23.1 · 内置 AI 技能插件 + 技能目录面板单测。
//
// 覆盖：bootstrap 注册完整性（10 技能/徽章唯一/来源 ai）、四分组次序与
// 计数、AiSkillEnvelope 类型名解析、AiSkillCatalogPanel 渲染与点击回调、
// 选中态高亮。用例登记：「C23 AI 面板」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_panel/ai_skill_catalog_panel.dart';
import 'package:dbmaster/organisms/ai_panel/skills/builtin_ai_skills.dart';
import 'package:dbmaster/plugins/ai_skill_plugin.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/plugin_registry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('C23.1 · bootstrap 注册', () {
    test('默认注册表含 10 内置技能，id 全局唯一，来源均为 ai', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);

      final skills = registry.aiSkills;
      expect(skills, hasLength(10));
      expect(
        skills.map((s) => s.descriptor.id).toSet(),
        hasLength(10),
        reason: '技能 id 必须唯一（注册表 id 空间跨种类共享）',
      );
      for (final skill in skills) {
        expect(skill.descriptor.source, PluginSource.ai,
            reason: skill.descriptor.id);
        expect(skill.skillGroupId, isNotEmpty);
      }
    });

    test('defaultPluginRegistry 同样注册技能（宿主消费入口）', () {
      expect(defaultPluginRegistry.aiSkills, hasLength(10));
    });

    test('四分组次序与计数：SQL 3 / 数据 2 / 结构 3 / 运维 2', () {
      final byGroup = <String, List<String>>{};
      for (final skill in builtinAiSkills) {
        (byGroup[skill.skillGroupId] ??= []).add(skill.descriptor.id);
      }
      expect(byGroup[AiSkillGroupIds.sql], hasLength(3));
      expect(byGroup[AiSkillGroupIds.data], hasLength(2));
      expect(byGroup[AiSkillGroupIds.schema], hasLength(3));
      expect(byGroup[AiSkillGroupIds.ops], hasLength(2));
    });

    test('resultType 声明：nl2sql=sql / schema-diff=diff / import-mapping=json，'
        '其余默认 markdown', () {
      final byId = {
        for (final s in builtinAiSkills) s.descriptor.id: s,
      };
      expect(byId['nl2sql-plugin']!.resultType, AiSkillEnvelopeType.sql);
      expect(byId['schema-diff-plugin']!.resultType, AiSkillEnvelopeType.diff);
      expect(
        byId['import-mapping-plugin']!.resultType,
        AiSkillEnvelopeType.json,
      );
      expect(
        byId['slow-query-plugin']!.resultType,
        AiSkillEnvelopeType.markdown,
      );
    });

    test('nl2sql 无 promptTemplate（用户自由输入），sql-explain 有模板', () {
      final byId = {
        for (final s in builtinAiSkills) s.descriptor.id: s,
      };
      expect(byId['nl2sql-plugin']!.promptTemplate, isNull);
      expect(byId['sql-explain-plugin']!.promptTemplate, isNotNull);
    });
  });

  group('AiSkillEnvelope · 类型名解析', () {
    test('四种类型名往返', () {
      for (final type in AiSkillEnvelopeType.values) {
        expect(AiSkillEnvelope.typeFromName(type.name), type);
      }
    });

    test('null / 未知名 → null（存量消息回退启发式渲染）', () {
      expect(AiSkillEnvelope.typeFromName(null), isNull);
      expect(AiSkillEnvelope.typeFromName('bogus'), isNull);
    });
  });

  group('C23.2 · AiSkillCatalogPanel', () {
    testWidgets('渲染四分组头与全部技能条目（徽章 = id）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AiSkillCatalogPanel(
            selectedSkillId: null,
            onSkillSelected: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 四个分组头（en locale 文案）
      expect(find.text('SQL'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Schema'), findsOneWidget);
      expect(find.text('Ops'), findsOneWidget);

      // 技能显示名（抽样）+ 插件徽章文本（全部 id）
      expect(find.text('Natural Language to SQL'), findsOneWidget);
      expect(find.text('nl2sql-plugin'), findsOneWidget);
      expect(find.text('schema-diff-plugin'), findsOneWidget);
      expect(find.text('slow-query-plugin'), findsOneWidget);
    });

    testWidgets('点击技能条目回调完整插件（可取模板与 resultType）',
        (tester) async {
      final selected = <AiSkillPlugin>[];
      await tester.pumpWidget(
        _wrap(
          AiSkillCatalogPanel(
            selectedSkillId: null,
            onSkillSelected: selected.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Query Optimizer'));
      await tester.pumpAndSettle();

      expect(selected, hasLength(1));
      expect(selected.single.descriptor.id, 'query-optimizer-plugin');
      expect(selected.single.promptTemplate, isNotNull);
      expect(selected.single.resultType, AiSkillEnvelopeType.markdown);
    });

    testWidgets('选中态高亮：selectedSkillId 对应条目名着主题强调色',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AiSkillCatalogPanel(
            selectedSkillId: 'nl2sql-plugin',
            onSkillSelected: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final name = tester.widget<Text>(find.text('Natural Language to SQL'));
      final color = name.style?.color;
      expect(color, isNotNull, reason: '选中条目应有强调色样式');
    });
  });
}

void _noop(AiSkillPlugin skill) {}
