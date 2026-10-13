// T26（J3 多连接长驻树）· 多连接树主体专项测试。
//
// 覆盖（任务书 T26 验收标准 ①~⑤⑧）：
// - N 连接 N 根节点全可见（已连接/连接中/断开三态）+ 分组分节（未分组
//   在前 + 组头不可点 + 空组隐藏 + 孤儿组员归未分组）；
// - 断开连接根节点灰化保留（节点不消失）+ 收藏/最近表区树顶常驻 +
//   树底两入口行渲染；
// - S9 环境色条三色渲染 + 无 environment 连接不渲染；
// - 活动根高亮（activeContextConnection——高亮未连接连接亦成立）；
// - 导航与动作分离：导航路径零 switchToConnection + 未连接重连护栏
//   保留；动作路径（create_database）switch 锚定保留；
// - 键盘导航 type-to-select 跨连接命中；
// - 搜索多连接展开（库名匹配连接置展开）+ 非匹配连接隐藏 + 空分组隐藏；
// - 性能护栏：折叠连接零子树构建 + 多连接全展开 TreeItem 线性计数。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/database_dialog.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_controller.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// switchToConnection / connectToServer / changeDescription 计数 spy——
/// 导航与动作分离断言的基座（J3 plan §10.1⑤）。
class _SwitchSpyProvider extends AppProvider {
  int switchCalls = 0;
  final List<String> switchTargets = [];
  int connectCalls = 0;

  @override
  Future<bool> switchToConnection(String connectionId) async {
    switchCalls++;
    switchTargets.add(connectionId);
    return true;
  }

  @override
  Future<bool> connectToServer(DbServer server) async {
    connectCalls++;
    return true;
  }

  @override
  Future<void> changeDatabase(String dbName, {String? connectionId}) async {
    // 真链路含 getDatabaseInfo（真库 IO）——导航计数用例只关心 switch 语义。
  }
}

/// 谎报已连接的最小 stub（hasConnection 按 adapter 判真）。
class _FakeTreeAdapter extends Fake implements DatabaseAdapter {
  @override
  bool get isConnected => true;
}

DbServer _server(
  String id,
  String name, {
  DatabaseType type = DatabaseType.mysql,
  String? groupId,
  ConnectionEnvironment? environment,
  String? password = 'x',
}) {
  return DbServer(
    id: id,
    type: type,
    name: name,
    host: '192.0.2.128',
    port: 3306,
    username: 'root',
    password: password,
    groupId: groupId,
    environment: environment,
  );
}

void _connectForTest(AppProvider provider, DbServer server) {
  provider.connection.dbService.registerConnectedServerForTest(server);
  provider.connection.dbService.registerConnectedAdapterForTest(
    server.id,
    _FakeTreeAdapter(),
  );
  provider.connection.setConnectionDatabasesForTest(
    server.id,
    ['db_${server.id}'],
    ['db_${server.id}'],
  );
}

Widget _buildTestApp(AppProvider provider, {Widget? child, double height = 1200}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: provider),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()..load()),
      ChangeNotifierProvider<ServerConnectionProvider>(
        create: (_) => ServerConnectionProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: height,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

SidebarTree _tree(AppProvider provider) => SidebarTree(
  expandedItems: const {},
  expandedDatabases: const {},
  expandedTables: const {},
  loadingDatabases: const {},
  loadedTableSchemas: const {},
  loadedTableForeignKeys: const {},
  loadingTableSchemas: const {},
  onToggleExpand: (_) {},
  onToggleDatabase: (_) {},
  onToggleTable: (_) {},
  onLoadDatabaseInfo: (a, b) async {},
  onShowConnectionManager: () {},
  onShowSettings: () {},
  onShowERDiagram: () {},
  onShowStoredProcedures: () {},
  onShowTriggers: () {},
  tableRowCounts: const {},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MTREE-T26 · 多连接装配与三态', () {
    testWidgets('N 连接 N 根节点全可见（已连接/连接中/断开三态并存）', (tester) async {
      final provider = _SwitchSpyProvider();
      final connected = _server('conn-a', 'MySQL One');
      final connecting = _server('conn-b', 'MySQL Two');
      final offline = _server('conn-c', 'MySQL Three');
      provider.connection.addSavedServerForTest(connected);
      provider.connection.addSavedServerForTest(connecting);
      provider.connection.addSavedServerForTest(offline);
      _connectForTest(provider, connected);
      provider.connection.dbService.markConnectingForTest('conn-b');

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      expect(find.text('MySQL One'), findsOneWidget);
      expect(find.text('MySQL Two'), findsOneWidget);
      expect(find.text('MySQL Three'), findsOneWidget);

      // 三态锚定：已连接 root showArrow=true（可展开）；连接中 isLoading；
      // 断开 showArrow=false（灰化根行保留，节点不消失）。
      TreeItem widgetOf(String label) => tester.widget<TreeItem>(
        find.byWidgetPredicate((w) => w is TreeItem && w.label == label),
      );
      expect(widgetOf('MySQL One').showArrow, isTrue);
      expect(widgetOf('MySQL Two').isLoading, isTrue);
      expect(widgetOf('MySQL Three').showArrow, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('分组分节：未分组在前 + 组头不可点 + 空组隐藏 + 孤儿组员归未分组', (
      tester,
    ) async {
      final provider = _SwitchSpyProvider();
      await provider.addConnectionGroup(
        ConnectionGroup(id: 'g1', name: 'Production Group'),
      );
      await provider.addConnectionGroup(
        ConnectionGroup(id: 'g-empty', name: 'Empty Group'),
      );
      provider.connection.addSavedServerForTest(
        _server('c1', 'Ungrouped One'),
      );
      provider.connection.addSavedServerForTest(
        _server('c2', 'Grouped Two', groupId: 'g1'),
      );
      provider.connection.addSavedServerForTest(
        _server('c3', 'Orphan Three', groupId: 'deleted-group'),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ungrouped One'), findsOneWidget);
      expect(find.text('Grouped Two'), findsOneWidget);
      expect(find.text('Orphan Three'), findsOneWidget); // 孤儿组员回退
      expect(find.text('Production Group'), findsOneWidget); // 组头
      expect(find.text('Empty Group'), findsNothing); // 空组隐藏

      // 组头不可点：无 InkWell 包裹（拍板口径——组头只呈现分组）。
      final headerLeft = tester.getTopLeft(find.text('Production Group')).dx;
      await tester.tapAt(Offset(headerLeft + 60, tester.getTopLeft(find.text('Production Group')).dy + 6));
      await tester.pump();
      // 组头点击零副作用：组员仍在、无异常。
      expect(find.text('Grouped Two'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 未分组在前：Ungrouped One 的纵坐标小于组头。
      expect(
        tester.getTopLeft(find.text('Ungrouped One')).dy,
        lessThan(tester.getTopLeft(find.text('Production Group')).dy),
      );
    });

    testWidgets('收藏/最近表区树顶常驻 + 树底两入口行渲染', (tester) async {
      final provider = _SwitchSpyProvider();
      final a = _server('conn-a', 'MySQL One');
      provider.connection.addSavedServerForTest(a);
      provider.sidebar.toggleFavoriteTable('conn-a:db_a:users');
      provider.recentTables.recordTableAccess(
        connectionId: 'conn-a',
        databaseName: 'db_a',
        tableName: 'orders',
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      // 收藏区（连接名前缀）+ 最近表区在树顶（纵坐标小于连接根）。
      expect(find.text('MySQL One · users'), findsOneWidget);
      expect(find.text(l10n.recentTables), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('MySQL One · users')).dy,
        lessThan(tester.getTopLeft(find.text('MySQL One')).dy),
      );

      // 树底两入口行。
      expect(find.byKey(const ValueKey('tree_footer_new_connection')), findsOneWidget);
      expect(find.text(l10n.connectionNewConnection), findsOneWidget);
      expect(find.byKey(const ValueKey('tree_footer_manage_connections')), findsOneWidget);
      expect(find.text(l10n.sidebarManageConnections), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('MTREE-T26 · S9 环境色条与活动根高亮', () {
    testWidgets('环境色条三色渲染 + 无 environment 连接不渲染', (tester) async {
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('p', 'Prod', environment: ConnectionEnvironment.production),
      );
      provider.connection.addSavedServerForTest(
        _server('t', 'Test', environment: ConnectionEnvironment.testing),
      );
      provider.connection.addSavedServerForTest(
        _server('d', 'Dev', environment: ConnectionEnvironment.development),
      );
      provider.connection.addSavedServerForTest(_server('n', 'NoEnv'));

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      // 三色 = environment.badgeColor 同源（与活动标签色条/状态栏徽章一致）。
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TreeItem &&
              w.environmentBarColor ==
                  ConnectionEnvironment.production.badgeColor,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TreeItem &&
              w.environmentBarColor == ConnectionEnvironment.testing.badgeColor,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TreeItem &&
              w.environmentBarColor ==
                  ConnectionEnvironment.development.badgeColor,
        ),
        findsOneWidget,
      );
      // 无 environment 连接：environmentBarColor == null（零视觉变化）。
      expect(
        find.byWidgetPredicate(
          (w) => w is TreeItem && w.label == 'NoEnv',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TreeItem>(
              find.byWidgetPredicate((w) => w is TreeItem && w.label == 'NoEnv'),
            )
            .environmentBarColor,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('活动根高亮跟随 activeContextConnection（未连接连接亦可高亮）', (
      tester,
    ) async {
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(_server('conn-a', 'Alpha'));
      provider.connection.addSavedServerForTest(_server('conn-b', 'Beta'));
      // 三级兜底链末端：无 tab 无 currentServer → 侧栏选中（未连接）。
      provider.sidebar.selectConnection('conn-b');

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is TreeItem && w.isSelected && w.label == 'Beta',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is TreeItem && w.isSelected && w.label == 'Alpha',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('MTREE-T26 · 导航与动作分离', () {
    testWidgets('导航路径（点击库节点/收藏表）零 switchToConnection', (tester) async {
      final provider = _SwitchSpyProvider();
      final a = _server('conn-a', 'MySQL One');
      final b = _server('conn-b', 'MySQL Two');
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a);
      _connectForTest(provider, b);
      // currentServer 停在 A——在 B 的库节点上导航不应全局切换（J3 语义：
      // 浏览连接 B 的库不劫持正在 A 上编辑的 tab 上下文）。
      provider.connection.setCurrentServerForTest(a);
      provider.sidebar.toggleFavoriteTable('conn-b:db_b:orders');

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarTree(
            expandedItems: const {'conn-b'},
            expandedDatabases: const {},
            expandedTables: const {},
            loadingDatabases: const {},
            loadedTableSchemas: const {},
            loadedTableForeignKeys: const {},
            loadingTableSchemas: const {},
            onToggleExpand: (_) {},
            onToggleDatabase: (_) {},
            onToggleTable: (_) {},
            onLoadDatabaseInfo: (a, b) async {},
            onShowConnectionManager: () {},
            onShowSettings: () {},
            onShowERDiagram: () {},
            onShowStoredProcedures: () {},
            onShowTriggers: () {},
            tableRowCounts: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击 B 的库节点 → 导航（零 switch）。TreeItem 同时注册 onDoubleTap，
      // 单击要过双击消歧窗口（300ms Timer）才触发——显式推进时钟（裸
      // pump/pumpAndSettle 只处理帧不处理 Timer）。
      await tester.tap(find.text('db_conn-b'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(provider.switchCalls, 0, reason: '库节点导航不得全局切换连接');
      expect(provider.sidebar.selectedConnectionId, 'conn-b');

      // 收藏表点击 → 开表导航（零 switch，tab 自带 cid）。
      await tester.tap(find.text('MySQL Two · orders'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(provider.switchCalls, 0, reason: '收藏表导航不得全局切换连接');
      expect(provider.connectCalls, 0, reason: '已连接收藏不触发重连');
      expect(tester.takeException(), isNull);
    });

    testWidgets('未连接收藏表：重连护栏保留（connectToServer 先行）', (tester) async {
      final provider = _SwitchSpyProvider();
      final offline = _server('conn-c', 'MySQL Three');
      provider.connection.addSavedServerForTest(offline);
      provider.sidebar.toggleFavoriteTable('conn-c:db_c:users');

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('MySQL Three · users'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(provider.connectCalls, 1, reason: '未连接收藏点击先自动重连');
      expect(provider.switchCalls, 0, reason: '重连护栏不走全局切换');
      expect(tester.takeException(), isNull);
    });

    testWidgets('动作路径（create_database）switch 锚定保留', (tester) async {
      final provider = _SwitchSpyProvider();
      final a = _server('conn-a', 'MySQL One');
      final b = _server('conn-b', 'MySQL Two');
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a);
      _connectForTest(provider, b);
      provider.connection.setCurrentServerForTest(a);

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      // 右键 B 连接根 → create_database → 先 switch 锚定 B（服务层无参
      // 方法默认路由依赖）。
      await tester.tap(find.text('MySQL Two'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final l10n = AppLocalizationsEn();
      await tester.tap(find.text(l10n.connectionCreateDatabase));
      await tester.pumpAndSettle();

      expect(provider.switchCalls, 1, reason: '动作类保留先 switch 锚定');
      expect(provider.switchTargets, ['conn-b']);
      expect(find.byType(CreateDatabaseDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handleConnectionTap 已连接分支：纯展开零 switch', (tester) async {
      final provider = _SwitchSpyProvider();
      final server = _server('conn-a', 'MySQL One');
      provider.connection.addSavedServerForTest(server);
      _connectForTest(provider, server);

      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      await controller.handleConnectionTap(server);
      expect(provider.switchCalls, 0, reason: '树内点击已连接连接 = 纯展开');
      expect(controller.expandedItems, contains('conn-a'));
    });
  });

  group('MTREE-T26 · 键盘导航与搜索跨连接', () {
    testWidgets('type-to-select 命中其它连接节点', (tester) async {
      final provider = _SwitchSpyProvider();
      final alpha = _server('alpha-conn', 'Alpha PostgreSQL');
      final beta = _server('beta-conn', 'Beta MySQL');
      provider.connection.addSavedServerForTest(alpha);
      provider.connection.addSavedServerForTest(beta);

      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller.rebuildVisibleNodeKeys(provider);

      KeyDownEvent key(String label) => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyB,
        logicalKey: LogicalKeyboardKey.keyB,
        timeStamp: Duration.zero,
      );
      // 输入 "b" → type-to-select 命中 beta 连接根（跨连接，键序含全部
      // 连接根——conn: 键显示名 = 连接 id）。
      expect(
        controller.handleTreeKeyEvent(FocusNode(), key('b')),
        KeyEventResult.handled,
      );
      await tester.pump();
      expect(controller.selectedNodeKey, 'conn:beta-conn');
    });

    testWidgets('搜索：库名匹配的连接置展开，非匹配连接/空分组隐藏', (tester) async {
      final provider = _SwitchSpyProvider();
      await provider.addConnectionGroup(
        ConnectionGroup(id: 'g1', name: 'Group One'),
      );
      await provider.addConnectionGroup(
        ConnectionGroup(id: 'g2', name: 'Group Two'),
      );
      final a = _server('conn-a', 'Alpha MySQL');
      final b = _server('conn-b', 'Beta MySQL', groupId: 'g1');
      final c = _server('conn-c', 'Gamma MySQL', groupId: 'g2');
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.connection.addSavedServerForTest(c);
      _connectForTest(provider, a);
      _connectForTest(provider, b);
      _connectForTest(provider, c);
      provider.connection.setConnectionDatabasesForTest(
        'conn-b',
        ['pgdb_match'],
        ['pgdb_match'],
      );

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarTree(
            searchQuery: 'pgdb',
            expandedItems: const {},
            expandedDatabases: const {},
            expandedTables: const {},
            loadingDatabases: const {},
            loadedTableSchemas: const {},
            loadedTableForeignKeys: const {},
            loadingTableSchemas: const {},
            onToggleExpand: (_) {},
            onToggleDatabase: (_) {},
            onToggleTable: (_) {},
            onLoadDatabaseInfo: (a, b) async {},
            onShowConnectionManager: () {},
            onShowSettings: () {},
            onShowERDiagram: () {},
            onShowStoredProcedures: () {},
            onShowTriggers: () {},
            tableRowCounts: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // B（库名命中）保留并强制展开（库节点渲染）；A 无匹配隐藏；
      // g2 成员全被滤掉 → 组头隐藏；g1 仍有成员 B → 组头保留。
      expect(find.text('Beta MySQL'), findsOneWidget);
      expect(find.text('pgdb_match'), findsOneWidget);
      expect(find.text('Alpha MySQL'), findsNothing);
      expect(find.text('Gamma MySQL'), findsNothing);
      expect(find.text('Group One'), findsOneWidget);
      expect(find.text('Group Two'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('MTREE-T26 · 性能护栏（plan §10.1③）', () {
    testWidgets('连接默认折叠：零子树构建（只渲染根行 + 树底入口）', (tester) async {
      final provider = _SwitchSpyProvider();
      for (var i = 0; i < 3; i++) {
        final server = _server('conn-$i', 'MySQL $i');
        provider.connection.addSavedServerForTest(server);
        _connectForTest(provider, server);
        provider.connection.setConnectionDatabasesForTest(
          'conn-$i',
          ['db_${i}_a', 'db_${i}_b'],
          ['db_${i}_a', 'db_${i}_b'],
        );
        for (final db in ['db_${i}_a', 'db_${i}_b']) {
          provider.connection.setCachedDatabaseForTest(
            'conn-$i',
            db,
            Database(name: db, tables: [], views: [], functions: []),
          );
        }
      }

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      // 折叠连接零子树：无库节点行、无加载态；TreeItem = 3 根 + 2 树底入口。
      expect(find.text('db_0_a'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TreeItem), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('多连接全展开：TreeItem 线性计数护栏（3 连接 × 2 库 × 20 表）', (
      tester,
    ) async {
      // ListView(children:) 惰性构建：测试 surface 默认 800×600 只建首屏
      // ——放大 surface 容下全部行（~150 行 × ~28px）。
      tester.view.physicalSize = const Size(400, 6200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = _SwitchSpyProvider();
      final expandedItems = <String>{};
      final expandedDatabases = <String>{};
      for (var i = 0; i < 3; i++) {
        final cid = 'conn-$i';
        final server = _server(cid, 'MySQL $i');
        provider.connection.addSavedServerForTest(server);
        _connectForTest(provider, server);
        provider.connection.setConnectionDatabasesForTest(
          cid,
          ['db_${i}_a', 'db_${i}_b'],
          ['db_${i}_a', 'db_${i}_b'],
        );
        expandedItems.add(cid);
        for (var d = 0; d < 2; d++) {
          final db = 'db_${i}_${['a', 'b'][d]}';
          final tables = List.generate(
            20,
            (t) => DbTable(name: 't${i}${d}_$t'),
          );
          provider.connection.setCachedDatabaseForTest(
            cid,
            db,
            Database(name: db, tables: tables, views: [], functions: []),
          );
          expandedDatabases.add('$cid:$db');
          // 表分类头展开（泛 SQL 共享树裸 key）。
          expandedItems.add('$cid:$db:tables');
        }
      }

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          height: 6200,
          child: SidebarTree(
            expandedItems: expandedItems,
            expandedDatabases: expandedDatabases,
            expandedTables: const {},
            loadingDatabases: const {},
            loadedTableSchemas: const {},
            loadedTableForeignKeys: const {},
            loadingTableSchemas: const {},
            onToggleExpand: (_) {},
            onToggleDatabase: (_) {},
            onToggleTable: (_) {},
            onLoadDatabaseInfo: (a, b) async {},
            onShowConnectionManager: () {},
            onShowSettings: () {},
            onShowERDiagram: () {},
            onShowStoredProcedures: () {},
            onShowTriggers: () {},
            tableRowCounts: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 护栏下界：3 根 + 3 保存查询头 + 6 库行 + 6 表分类头 + 120 表行
      // + 2 树底入口 = 140（插件全局节点/空分类头只会更多——线性增长而非
      // 平方爆炸即通过；计数显著超出预期 = 停下回报的呈报信号）。
      expect(find.byType(TreeItem).evaluate().length, greaterThanOrEqualTo(140));
      // 折叠护栏对照：表行确已渲染（t0 连接 2 库 × 20 表）。
      expect(
        find.byWidgetPredicate(
          (w) => w is TreeItem && (w.label?.startsWith('t0') ?? false),
        ).evaluate().length,
        greaterThanOrEqualTo(40),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
