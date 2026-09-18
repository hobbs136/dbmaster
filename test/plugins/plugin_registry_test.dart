// C01a · UI 插件注册框架单测：描述符语义 + 注册表行为
// （注册/查询/冲突/override/封口/多命中）。
//
// 用例登记：docs/test/unified_test_spec.md 「UI 插件框架（PLG）」。
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/plugins/ai_skill_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/plugin_registry.dart';
import 'package:dbmaster/plugins/result_renderer_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

void main() {
  group('PluginDescriptor', () {
    test('supports：空集 = 全类型适用', () {
      const descriptor = PluginDescriptor(
        id: 'core-renderer',
        icon: LucideIcons.table2,
      );
      for (final type in DatabaseType.values) {
        expect(descriptor.supports(type), isTrue, reason: type.name);
      }
    });

    test('supports：成员判定', () {
      const descriptor = PluginDescriptor(
        id: 'mysql-connection-plugin',
        supportedTypes: {DatabaseType.mysql, DatabaseType.doris},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      );
      expect(descriptor.supports(DatabaseType.mysql), isTrue);
      expect(descriptor.supports(DatabaseType.doris), isTrue);
      expect(descriptor.supports(DatabaseType.postgresql), isFalse);
    });

    test('相等性按 id（注册表去重依赖）', () {
      const a = PluginDescriptor(id: 'x', icon: LucideIcons.caseSensitive);
      const b = PluginDescriptor(
        id: 'x',
        icon: LucideIcons.clock,
        source: PluginSource.ai,
      );
      const c = PluginDescriptor(id: 'y', icon: LucideIcons.caseSensitive);
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });

  group('PluginRegistry · 注册与查询', () {
    test('按类型查连接表单插件；无命中返回 null', () {
      final registry = PluginRegistry();
      final mysql = FakeConnectionFormPlugin(
        const PluginDescriptor(
          id: 'mysql-connection-plugin',
          supportedTypes: {DatabaseType.mysql},
          source: PluginSource.databaseType,
          icon: LucideIcons.database,
        ),
      );
      registry.registerConnectionForm(mysql);

      expect(registry.connectionFormFor(DatabaseType.mysql), same(mysql));
      expect(registry.connectionFormFor(DatabaseType.redis), isNull);
    });

    test('按类型查侧边栏插件（多命中合并，注册序）', () {
      final registry = PluginRegistry();
      final core = FakeSidebarPlugin(
        const PluginDescriptor(
          id: 'core-sidebar',
          source: PluginSource.core,
          icon: LucideIcons.layoutGrid,
        ),
      );
      final redis = FakeSidebarPlugin(
        const PluginDescriptor(
          id: 'redis-plugin',
          supportedTypes: {DatabaseType.redis},
          source: PluginSource.databaseType,
          icon: LucideIcons.zap,
        ),
      );
      registry.registerSidebar(core);
      registry.registerSidebar(redis);

      // C14 能力菜单语义：core 通用件 + per-type 件合并返回
      expect(registry.sidebarPluginsFor(DatabaseType.redis), [core, redis]);
      expect(registry.sidebarPluginsFor(DatabaseType.sqlite), [core]);
    });

    test('多个插件命中同一类型：取注册序首个，不抛异常', () {
      final registry = PluginRegistry();
      final first = FakeConnectionFormPlugin(
        const PluginDescriptor(
          id: 'mysql-form-a',
          supportedTypes: {DatabaseType.mysql},
          icon: LucideIcons.database,
        ),
      );
      final second = FakeConnectionFormPlugin(
        const PluginDescriptor(
          id: 'mysql-form-b',
          supportedTypes: {DatabaseType.mysql},
          icon: LucideIcons.database,
        ),
      );
      registry.registerConnectionForm(first);
      registry.registerConnectionForm(second);

      expect(registry.connectionFormFor(DatabaseType.mysql), same(first));
    });

    test('id 冲突跨种类也拒绝（全局 id 空间）', () {
      final registry = PluginRegistry();
      registry.registerConnectionForm(
        FakeConnectionFormPlugin(
          const PluginDescriptor(id: 'dup', icon: LucideIcons.database),
        ),
      );

      expect(
        () => registry.registerSidebar(
          FakeSidebarPlugin(
            const PluginDescriptor(id: 'dup', icon: LucideIcons.zap),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('override: true 替换同 id 插件（含跨种类）', () {
      final registry = PluginRegistry();
      final oss = FakeConnectionFormPlugin(
        const PluginDescriptor(
          id: 'sql-connection-plugin',
          supportedTypes: {DatabaseType.mysql},
          icon: LucideIcons.database,
        ),
      );
      registry.registerConnectionForm(oss);

      final pro = FakeConnectionFormPlugin(
        const PluginDescriptor(
          id: 'sql-connection-plugin',
          supportedTypes: {DatabaseType.mysql, DatabaseType.sqlserver},
          source: PluginSource.core,
          icon: LucideIcons.database,
        ),
      );
      registry.registerConnectionForm(pro, override: true);

      expect(registry.connectionFormFor(DatabaseType.mysql), same(pro));
      expect(registry.pluginCount, 1);
    });

    test('seal 后注册抛 StateError（编译期注册边界）', () {
      final registry = PluginRegistry();
      registry.seal();

      expect(
        () => registry.registerResultRenderer(
          FakeResultRendererPlugin(
            const PluginDescriptor(id: 'r', icon: LucideIcons.table2),
            'table',
          ),
        ),
        throwsStateError,
      );
    });

    test('descriptorById 徽章反查', () {
      final registry = PluginRegistry();
      final renderer = FakeResultRendererPlugin(
        const PluginDescriptor(
          id: 'sql-result-renderer',
          supportedTypes: {DatabaseType.mysql},
          icon: LucideIcons.table2,
        ),
        'table',
      );
      registry.registerResultRenderer(renderer);

      expect(
        registry.descriptorById('sql-result-renderer')?.id,
        'sql-result-renderer',
      );
      expect(registry.descriptorById('missing'), isNull);
    });
  });

  group('PluginRegistry · 渲染器查询', () {
    late PluginRegistry registry;
    late FakeResultRendererPlugin table;
    late FakeResultRendererPlugin json;
    late FakeResultRendererPlugin redisView;

    setUp(() {
      registry = PluginRegistry();
      table = FakeResultRendererPlugin(
        const PluginDescriptor(id: 'table-renderer', icon: LucideIcons.table2),
        'table',
        shapes: const {ResultDataShape.sqlRows},
      );
      json = FakeResultRendererPlugin(
        const PluginDescriptor(id: 'json-renderer', icon: LucideIcons.braces),
        'json',
        shapes: const {ResultDataShape.sqlRows, ResultDataShape.nosqlDocument},
      );
      redisView = FakeResultRendererPlugin(
        const PluginDescriptor(
          id: 'redis-result-renderer',
          supportedTypes: {DatabaseType.redis},
          source: PluginSource.databaseType,
          icon: LucideIcons.zap,
        ),
        'keyvalue',
        shapes: const {ResultDataShape.redisKeyValue},
      );
      registry.registerResultRenderer(table);
      registry.registerResultRenderer(json);
      registry.registerResultRenderer(redisView);
    });

    test('按形态过滤', () {
      final renderers = registry.resultRenderersFor(
        shape: ResultDataShape.sqlRows,
      );
      expect(renderers.map((r) => r.descriptor.id), [
        'table-renderer',
        'json-renderer',
      ]);
    });

    test('按类型 + 形态组合过滤', () {
      final renderers = registry.resultRenderersFor(
        type: DatabaseType.redis,
        shape: ResultDataShape.redisKeyValue,
      );
      expect(renderers.map((r) => r.descriptor.id), ['redis-result-renderer']);
    });

    test('类型过滤不影响全类型通用渲染器', () {
      final renderers = registry.resultRenderersFor(type: DatabaseType.mongodb);
      expect(renderers.map((r) => r.descriptor.id), [
        'table-renderer',
        'json-renderer',
      ]);
    });

    test('无过滤返回全部（注册序）', () {
      expect(registry.resultRenderersFor().length, 3);
    });
  });

  group('AiSkillPlugin · 占位契约', () {
    test('注册与列举（C23 消费前的注册表通路验证）', () {
      final registry = PluginRegistry();
      registry.registerAiSkill(
        FakeAiSkillPlugin(
          const PluginDescriptor(
            id: 'nl2sql-skill',
            source: PluginSource.ai,
            icon: LucideIcons.sparkles,
          ),
          'sql',
        ),
      );

      final skills = registry.aiSkills;
      expect(skills, hasLength(1));
      expect(skills.first.skillGroupId, 'sql');
      expect(skills.first.descriptor.source, PluginSource.ai);
    });

    test('envelope 形态（type/content 载体）', () {
      const envelope = AiSkillEnvelope(
        type: AiSkillEnvelopeType.sql,
        content: 'SELECT 1',
      );
      expect(envelope.type, AiSkillEnvelopeType.sql);
      expect(envelope.content, 'SELECT 1');
    });
  });
}
