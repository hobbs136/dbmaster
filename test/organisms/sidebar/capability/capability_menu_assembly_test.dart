// C14 · 能力菜单装配单测：port 门控 / 组合并 / 项覆盖 / 徽章解析 /
// core 插件内容 × 能力真值表。
//
// 用例登记：docs/test/unified_test_spec.md「侧边栏能力菜单（CAP-MENU）」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

/// 门控语义 fake：按类型持一组取真能力位（含未知位 = false 语义）。
class _FakePort implements DbCapabilityPort {
  final Map<DatabaseType, Set<String>> caps;
  _FakePort(this.caps);

  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      caps[type]?.contains(capabilityId) ?? false;

  @override
  Set<String> capabilitiesOf(DatabaseType type) =>
      caps[type] ?? const <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试 fake 仅实现能力位查询');
}

/// 真值表 fake：委托 CapabilityTable（core 插件内容 × 真值表面）。
class _TablePort implements DbCapabilityPort {
  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      CapabilityTable.has(type, capabilityId);

  @override
  Set<String> capabilitiesOf(DatabaseType type) => CapabilityTable.of(type);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试 fake 仅实现能力位查询');
}

SidebarCapabilityGroup _group(
  String id,
  List<SidebarCapabilityItem> items,
) =>
    SidebarCapabilityGroup(
      id: id,
      label: (l10n) => 'g-$id',
      icon: LucideIcons.database,
      items: items,
    );

SidebarCapabilityItem _item(
  String id, {
  String? capabilityId,
  String label = 'i',
}) =>
    SidebarCapabilityItem(
      id: id,
      capabilityId: capabilityId,
      label: (l10n) => label,
      icon: LucideIcons.table2,
    );

class _DataPlugin implements SidebarPlugin {
  _DataPlugin(this.descriptor, this.groups);

  @override
  final PluginDescriptor descriptor;

  final List<SidebarCapabilityGroup> groups;

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) => groups;

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) =>
      const [];

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) =>
      const [];
}

void main() {
  late AppLocalizations l10n;
  late BuildContext capturedContext;

  Future<void> pumpL10n(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    l10n = AppLocalizations.of(capturedContext)!;
  }

  testWidgets('port 门控：位取 false / 未知位隐藏，null 位无条件展示', (tester) async {
    await pumpL10n(tester);
    final port = _FakePort({
      DatabaseType.mysql: {'a.on'},
    });
    final plugin = _DataPlugin(
      const PluginDescriptor(id: 'p', icon: LucideIcons.database),
      [
        _group('g', [
          _item('on', capabilityId: 'a.on'),
          _item('off', capabilityId: 'a.off'),
          _item('unknown', capabilityId: 'no.such.bit'),
          _item('free'),
        ]),
      ],
    );

    final groups = assembleCapabilityMenu(
      context: capturedContext,
      type: DatabaseType.mysql,
      port: port,
      plugins: [plugin],
      l10n: l10n,
    );

    expect(groups, hasLength(1));
    expect(groups.first.items.map((e) => e.item.id), ['on', 'free']);
  });

  testWidgets('组内全部门控掉 → 整组隐藏', (tester) async {
    await pumpL10n(tester);
    final port = _FakePort({
      DatabaseType.redis: const <String>{},
    });
    final plugin = _DataPlugin(
      const PluginDescriptor(id: 'p', icon: LucideIcons.database),
      [
        _group('empty', [_item('x', capabilityId: 'a.off')]),
        _group('kept', [_item('free')]),
      ],
    );

    final groups = assembleCapabilityMenu(
      context: capturedContext,
      type: DatabaseType.redis,
      port: port,
      plugins: [plugin],
      l10n: l10n,
    );

    expect(groups.map((g) => g.id), ['kept']);
  });

  testWidgets('跨插件同组 id 合并；同项 id 后者覆盖前者（per-type 盖 core）', (tester) async {
    await pumpL10n(tester);
    final port = _FakePort({
      DatabaseType.mysql: const <String>{},
    });
    final core = _DataPlugin(
      const PluginDescriptor(id: 'core-sidebar', icon: LucideIcons.database),
      [
        _group('shared', [
          _item('dup', label: 'core-dup'),
          _item('core-only', label: 'core-only'),
        ]),
      ],
    );
    final typed = _DataPlugin(
      const PluginDescriptor(
        id: 'mysql-plugin',
        supportedTypes: {DatabaseType.mysql},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      ),
      [
        _group('shared', [
          _item('dup', label: 'typed-dup'),
          _item('typed-only', label: 'typed-only'),
        ]),
      ],
    );

    final groups = assembleCapabilityMenu(
      context: capturedContext,
      type: DatabaseType.mysql,
      port: port,
      plugins: [core, typed],
      l10n: l10n,
    );

    expect(groups, hasLength(1));
    final labels = groups.first.items
        .map((e) => e.item.label(l10n))
        .toList();
    // 覆盖项留在原位置（首见序），值取后注册插件
    expect(labels, containsAll(['typed-dup', 'core-only', 'typed-only']));
    expect(labels, isNot(contains('core-dup')));
  });

  test('徽章文本：core / <type>-plugin / ai-plugin', () {
    expect(
      capabilityBadgeLabel(
        const PluginDescriptor(id: 'a', icon: LucideIcons.database),
        DatabaseType.mysql,
      ),
      'core',
    );
    expect(
      capabilityBadgeLabel(
        const PluginDescriptor(
          id: 'b',
          supportedTypes: {DatabaseType.mysql},
          source: PluginSource.databaseType,
          icon: LucideIcons.database,
        ),
        DatabaseType.mysql,
      ),
      'mysql-plugin',
    );
    expect(
      capabilityBadgeLabel(
        const PluginDescriptor(
          id: 'c',
          source: PluginSource.ai,
          icon: LucideIcons.bot,
        ),
        DatabaseType.mysql,
      ),
      'ai-plugin',
    );
  });

  testWidgets('core 插件 × 能力真值表：mysql 全项 / redis 只剩通用位', (tester) async {
    await pumpL10n(tester);
    const plugin = CoreSidebarPlugin();
    final port = _TablePort();

    final mysql = assembleCapabilityMenu(
      context: capturedContext,
      type: DatabaseType.mysql,
      port: port,
      plugins: const [plugin],
      l10n: l10n,
    );
    final mysqlIds = [
      for (final g in mysql)
        for (final e in g.items) e.item.id,
    ];
    expect(mysqlIds, containsAll([
      'proc.list',
      'func.list',
      'trigger.list',
      'schema.diff',
      'ai.assistant',
    ]));
    expect(mysql.map((g) => g.id), ['database-objects', 'advanced']);

    final redis = assembleCapabilityMenu(
      context: capturedContext,
      type: DatabaseType.redis,
      port: port,
      plugins: const [plugin],
      l10n: l10n,
    );
    final redisIds = [
      for (final g in redis)
        for (final e in g.items) e.item.id,
    ];
    // proc/func/trigger 位不含 redis → 隐藏；schema.diff/ai.assistant 恒真
    expect(redisIds, ['schema.diff', 'ai.assistant']);
    expect(redis.map((g) => g.id), ['advanced']);

    // 门控判定来自 port 而非插件自带（铁律 2）：sqlite 的 proc/func/trigger
    // 位全 false → database-objects 整组消失，只剩 advanced
    final sqlite = assembleCapabilityMenu(
      context: capturedContext,
      type: DatabaseType.sqlite,
      port: port,
      plugins: const [plugin],
      l10n: l10n,
    );
    expect(
      sqlite.map((g) => g.id),
      ['advanced'],
      reason: 'sqlite 无 proc/func/trigger 位，对象组应整组隐藏',
    );
  });

  test('活动连接锚定：currentServer 优先 / 回退 tab→选中（须已连接）', () {
    final a = DbServer(
      id: 'a',
      type: DatabaseType.mysql,
      name: 'A',
      host: 'h',
      port: 1,
    );
    final b = DbServer(
      id: 'b',
      type: DatabaseType.redis,
      name: 'B',
      host: 'h',
      port: 2,
    );
    final saved = [a, b];

    // currentServer 非空时直接胜出（不看 tab/选中）
    expect(
      resolveCapabilityMenuServer(
        currentServer: b,
        activeTabConnectionId: 'a',
        selectedConnectionId: 'a',
        isConnected: (_) => true,
        savedConnections: saved,
      ),
      same(b),
    );

    // 回退链：活动 tab 优先于侧栏选中
    expect(
      resolveCapabilityMenuServer(
        currentServer: null,
        activeTabConnectionId: 'a',
        selectedConnectionId: 'b',
        isConnected: (_) => true,
        savedConnections: saved,
      ),
      same(a),
    );

    // 选中节点已连接 → 提供锚点（连接已建但 currentServer 未写入的窗口）
    expect(
      resolveCapabilityMenuServer(
        currentServer: null,
        activeTabConnectionId: null,
        selectedConnectionId: 'b',
        isConnected: (id) => id == 'b',
        savedConnections: saved,
      ),
      same(b),
    );

    // 选中节点未连接 / 未登记 → 不提供（动作假定活连接）
    expect(
      resolveCapabilityMenuServer(
        currentServer: null,
        activeTabConnectionId: null,
        selectedConnectionId: 'b',
        isConnected: (_) => false,
        savedConnections: saved,
      ),
      isNull,
    );
    expect(
      resolveCapabilityMenuServer(
        currentServer: null,
        activeTabConnectionId: null,
        selectedConnectionId: null,
        isConnected: (_) => true,
        savedConnections: saved,
      ),
      isNull,
    );
  });

  testWidgets('core 插件全局树恒空；库级树为泛 SQL 共享兜底（C19 反转契约）', (
    tester,
  ) async {
    await pumpL10n(tester);
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();
    const plugin = CoreSidebarPlugin();
    final globalTree = plugin.buildGlobalTree(
      capturedContext,
      SidebarTreeContext(
        provider: provider,
        connectionId: 'c',
        expandedItems: const {},
        onToggleExpand: (_) {},
      ),
    );
    // C19 分缝反转：core 全局树恒空（能力菜单不渲染树节点）；库级树收编
    // 泛 SQL 共享装配——per-type 恒空类型（MySQL 等）的非空兜底；非 SQL
    // （插件接管）排除。SS 的 schema 树由 C20 per-type 插件先行接管
    // （SqlserverSidebarPlugin 非空即在其前），core 对 SS 不再需要排除
    // 分支——schema-aware 数据顶层 db.tables 为空，落 core 也渲染空树。
    expect(globalTree, isEmpty);
    final dbTreeFor = (DatabaseType type) => plugin.buildDatabaseTree(
      capturedContext,
      SidebarDatabaseTreeContext(
        provider: provider,
        connectionId: 'c',
        server: DbServer(
          id: 'c',
          name: 'T',
          type: type,
          host: 'h',
          port: 1,
        ),
        databaseName: 'd',
        db: Database(name: 'd'),
        searchQuery: '',
        expandedItems: const {},
        onToggleExpand: (_) {},
        expandedTables: const {},
        onToggleTable: (_) {},
        loadedTableSchemas: const {},
        loadedTableForeignKeys: const {},
        loadingTableSchemas: const {},
        tableRowCounts: const {},
        onShowTableMenu: (_, _, _) async {},
        onInsertName: (_) {},
      ),
    );
    // MySQL（库级恒空 per-type 类型）→ core 兜底提供分类树
    expect(dbTreeFor(DatabaseType.mysql), isNotEmpty);
    // SS（C20 起由 per-type 插件先行接管；core 不再排除——空 db 落 core
    // 与 MySQL 同形渲染泛 SQL 分类头，真实分缝序下不可达）与非 SQL
    // （插件接管）→ 后者 core 为空
    expect(dbTreeFor(DatabaseType.sqlserver), isNotEmpty);
    expect(dbTreeFor(DatabaseType.redis), isEmpty);
    expect(dbTreeFor(DatabaseType.mongodb), isEmpty);
  });
}
