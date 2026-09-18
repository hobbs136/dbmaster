// C01a · UI 插件注册框架单测：三接口 + AiSkill 占位的生命周期与契约行为。
//
// 覆盖：连接表单会话（createSession → build → collect → dispose、多会话
// 隔离、草稿 ValueNotifier 桥）、侧边栏能力分组元数据（capabilityId 仅作
// port 查询键）、渲染器 build 通路。
//
// 用例登记：「UI 插件框架（PLG）」。
import 'package:flutter/material.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/result_filter.dart' show ColumnDataType;
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/plugins/connection_form_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/result_renderer_plugin.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

DbServer _draftServer() => DbServer(
  id: 'srv-1',
  name: 'draft',
  host: 'localhost',
  port: 3306,
  type: DatabaseType.mysql,
);

void main() {
  group('ConnectionFormPlugin · 会话生命周期', () {
    testWidgets('createSession → build → collect → dispose 全链路', (
      tester,
    ) async {
      final plugin = FakeConnectionFormPlugin(
        const PluginDescriptor(
          id: 'mysql-connection-plugin',
          supportedTypes: {DatabaseType.mysql},
          source: PluginSource.databaseType,
          icon: LucideIcons.database,
        ),
      );
      final draft = ConnectionDraft(_draftServer());
      addTearDown(draft.dispose);
      final formContext = ConnectionFormPluginContext(
        type: DatabaseType.mysql,
        draft: draft,
      );

      final session = plugin.createSession(formContext);
      expect(plugin.createdSessions, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: session.build)),
        ),
      );
      expect(find.text('fake-form-mysql'), findsOneWidget);
      expect(session.buildCount, 1);

      final collected = session.collect();
      // collect 基于会话字段合并草稿：标记字段来自表单，基础字段保留。
      expect(collected?.host, 'collected-host');
      expect(collected?.name, 'draft');
      expect(collected?.id, 'srv-1');

      session.dispose();
      expect(session.disposed, isTrue);
    });

    testWidgets('同一插件多会话互不共享状态（插件本体无状态）', (tester) async {
      final plugin = FakeConnectionFormPlugin(
        const PluginDescriptor(
          id: 'pg-connection-plugin',
          supportedTypes: {DatabaseType.postgresql},
          source: PluginSource.databaseType,
          icon: LucideIcons.database,
        ),
      );
      final draftA = ConnectionDraft(
        _draftServer().copyWith(id: 'a', type: DatabaseType.postgresql),
      );
      final draftB = ConnectionDraft(
        _draftServer().copyWith(id: 'b', type: DatabaseType.postgresql),
      );
      addTearDown(draftA.dispose);
      addTearDown(draftB.dispose);

      final sessionA = plugin.createSession(
        ConnectionFormPluginContext(
          type: DatabaseType.postgresql,
          draft: draftA,
        ),
      );
      final sessionB = plugin.createSession(
        ConnectionFormPluginContext(
          type: DatabaseType.postgresql,
          draft: draftB,
        ),
      );
      expect(plugin.createdSessions, 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: sessionA.build)),
        ),
      );
      expect(sessionA.buildCount, 1);
      expect(sessionB.buildCount, 0);

      final collectedA = sessionA.collect();
      expect(collectedA?.id, 'a');
      // B 会话草稿不受 A 会话 collect 影响。
      expect(draftB.value.host, 'localhost');

      sessionA.dispose();
      sessionB.dispose();
      expect(sessionA.disposed, isTrue);
      expect(sessionB.disposed, isTrue);
    });

    testWidgets('草稿 ValueNotifier 桥：宿主推新值对会话可见', (tester) async {
      final plugin = FakeConnectionFormPlugin(
        const PluginDescriptor(id: 'f', icon: LucideIcons.database),
      );
      final draft = ConnectionDraft(_draftServer());
      addTearDown(draft.dispose);
      final session = plugin.createSession(
        ConnectionFormPluginContext(type: DatabaseType.mysql, draft: draft),
      );

      // 宿主改头部字段（如名称）——表单下次 collect 以最新草稿为基底。
      draft.update(draft.value.copyWith(name: 'renamed'));

      final collected = session.collect();
      expect(collected?.name, 'renamed');
      expect(collected?.host, 'collected-host');
    });

    test('判等陷阱守卫：DbServer 同 id copyWith == 相等，draft.update 仍生效', () {
      // ConnectionDraft 存在的理由（见其类注释）：ValueNotifier 会把
      // 「== 相等」的新值静默丢弃，DbServer 恰好只按 id 判等。此用例
      // 锁定该语义，防止有人把 update 改回性能更「优雅」的相等性短路。
      final base = _draftServer();
      final renamed = base.copyWith(name: 'renamed');
      expect(renamed == base, isTrue, reason: 'DbServer 按 id 判等的前提');

      final draft = ConnectionDraft(base);
      addTearDown(draft.dispose);
      var notified = 0;
      draft.addListener(() => notified++);

      draft.update(renamed);
      expect(draft.value.name, 'renamed');
      expect(notified, 1);
    });
  });

  group('SidebarPlugin · 能力分组元数据', () {
    testWidgets('capabilityGroups 提供分组与 port 能力键（纯元数据）', (tester) async {
      final plugin = FakeSidebarPlugin(
        const PluginDescriptor(
          id: 'redis-plugin',
          supportedTypes: {DatabaseType.redis},
          source: PluginSource.databaseType,
          icon: LucideIcons.zap,
        ),
      );
      List<SidebarCapabilityGroup>? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = plugin.capabilityGroups(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, isNotNull);
      expect(captured!.length, 1);
      final group = captured!.first;
      expect(group.id, 'keyspace');
      expect(group.items, hasLength(1));
      // capabilityId 是 port 查询键（铁律 2）：插件只声明「需要什么能力」，
      // 不声明能力是否可用——真值由宿主查 DbCapabilityPort 裁决。
      expect(group.items.first.capabilityId, 'redis.keyspace');
      expect(group.items.first.onActivate, isNull);
    });
  });

  group('ResultRendererPlugin · 渲染通路', () {
    testWidgets('build 消费 ResultRenderContext（ExecutionResult 载体）', (
      tester,
    ) async {
      const renderer = _ConstResultRenderer();
      const statement = SQLStatement(
        index: 0,
        sql: 'SELECT 1',
        type: SQLType.select,
        lineStart: 1,
        lineEnd: 1,
      );
      final renderContext = ResultRenderContext(
        result: ExecutionResult(
          statement: statement,
          success: true,
          data: const <Map<String, dynamic>>[
            {'id': 1},
          ],
          executionTime: const Duration(milliseconds: 5),
        ),
        rows: const <Map<String, dynamic>>[
          {'id': 1},
        ],
        columns: const <String>['id'],
        columnTypes: const <String, ColumnDataType>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => renderer.build(context, renderContext),
          ),
        ),
      );
      expect(find.text('renderer-table'), findsOneWidget);
    });
  });
}

/// 无状态 const 渲染器（区别于 fakes.dart 的可变 fake，专测 build 通路）。
class _ConstResultRenderer implements ResultRendererPlugin {
  const _ConstResultRenderer();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: 'sql-result-renderer',
    icon: LucideIcons.table2,
  );

  @override
  String get viewModeId => 'table';

  @override
  Set<ResultDataShape> get supportedShapes => const <ResultDataShape>{
    ResultDataShape.sqlRows,
  };

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) =>
      const Text('renderer-table');
}
