// ============================================================================
// C16 · SQLite 侧边栏插件真库 E2E（本地 .db 文件，spec 050 ATTACH 语境）
//
// 覆盖 C16 新运行时链路：
// 1. 插件整树分缝：连接后 SidebarTree 经 _buildGlobalNodesForType →
//    SqliteSidebarPlugin.buildGlobalTree 渲染扁平结构（Tables/Views/
//    Indexes/Triggers/Database Info）；
// 2. ATTACH 跨库语境：provider.connection.attachDatabase 附加第二个真
//    .db 文件 → 树切换为多库 header 形态（main + alias），附加库子树
//    可展开（其表来自真文件）；
// 3. 能力项激活：sqlite.pragma → PRAGMA Explorer（真 PRAGMA 读取）、
//    sqlite.attach → AttachDatabaseDialog 打开。
//
// 真库：SQLiteTestConfig 临时文件（本地文件数据库，无服务器依赖）。
// 建库走 SQLiteAdapter.executeSqlScript（attach_live_test 同模式）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/attach_database_dialog.dart';
import 'package:dbmaster/organisms/connection/pragma_panel.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/organisms/sidebar/plugins/sqlite_sidebar_plugin.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/sqlite_test_config.dart';

Widget _host(AppProvider provider, {Widget? child}) {
  return MultiProvider(
    providers: [
      // 树内连接状态点（server-platform M1 起）watch 团队服务器连接态。
      ChangeNotifierProvider<ServerConnectionProvider>(
        create: (_) => ServerConnectionProvider(),
      ),
      ChangeNotifierProvider<AppProvider>.value(value: provider),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      locale: const Locale('en'),
      home: Scaffold(body: child ?? const SizedBox.shrink()),
    ),
  );
}

/// 构造独立 .db 文件（建表 + 插数据），返回路径；调用方负责 cleanup。
Future<String> _buildExtraDb(String tag) async {
  final path = SQLiteTestConfig.generateTestDatabasePath().replaceAll(
    RegExp(r'\.db$'),
    '_$tag.db',
  );
  final helper = SQLiteAdapter();
  final conn = DatabaseConnection(
    id: 'extra_$tag',
    name: 'extra $tag',
    host: path,
    port: 0,
    type: DatabaseType.sqlite,
  );
  expect(await helper.connect(conn), isTrue, reason: '附加库文件创建失败');
  await helper.executeSqlScript(
    'CREATE TABLE ext_probe(id INTEGER PRIMARY KEY, note TEXT);'
    "INSERT INTO ext_probe(note) VALUES ('c16');",
  );
  await helper.disconnect();
  return path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;
  late String mainDbPath;
  String? extraDbPath; // 仅 ATTACH 类用例赋值，tearDown 判空调理

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mainDbPath = SQLiteTestConfig.generateTestDatabasePath();
    provider = AppProvider();
    server = DbServer(
      id: 'c16-e2e-sqlite',
      type: DatabaseType.sqlite,
      name: 'C16 SQLite',
      host: mainDbPath,
      port: 0,
    );
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
    await SQLiteTestConfig.cleanupDatabase(mainDbPath);
    if (extraDbPath != null) {
      await SQLiteTestConfig.cleanupDatabase(extraDbPath!);
    }
  });

  Future<void> connectAndSeedMain(WidgetTester tester) async {
    await tester.runAsync(() async {
      await provider.connection.saveConnection(server);
      final connected = await provider.connection.connectToServer(server);
      expect(connected, isTrue, reason: '本地 SQLite 连接失败');
      await provider.connection.dbService.executeSqlScript(
        'CREATE TABLE main_probe(id INTEGER PRIMARY KEY, name TEXT);',
        connectionId: server.id,
      );
    });
  }

  testWidgets('C16-LT-TREE：插件整树渲染扁平分类 + 表叶子', (tester) async {
    await connectAndSeedMain(tester);

    final treeKey = GlobalKey<_ExpandableTreeState>();
    await tester.pumpWidget(
      _host(provider, child: _ExpandableTree(key: treeKey)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 展开连接节点（插件树在连接卡展开区内）
    final connFinder = find.ancestor(
      of: find.text('C16 SQLite'),
      matching: find.byType(TreeItem),
    );
    expect(connFinder, findsOneWidget, reason: '连接卡片未渲染');
    await tester.tap(connFinder);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 扁平结构：分类头直出（懒加载 FutureBuilder → 真文件元数据）
    expect(find.text('Tables'), findsOneWidget);
    expect(find.text('Views'), findsOneWidget);
    expect(find.text('Indexes'), findsOneWidget);
    expect(find.text('Triggers'), findsOneWidget);
    expect(find.text('Database Info'), findsOneWidget);

    // 展开 Tables → 真文件中的表叶子
    await tester.tap(find.text('Tables'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('main_probe'), findsOneWidget);
  });

  testWidgets('C16-LT-ATTACH：附加真库后树切换多库 header 形态', (tester) async {
    await connectAndSeedMain(tester);
    final extra = await _buildExtraDb('c16');
    extraDbPath = extra;

    await tester.runAsync(() async {
      final res = await provider.connection.attachDatabase(
        server.id,
        extra,
        'archive_c16',
      );
      expect(res.success, isTrue, reason: 'ATTACH 失败: ${res.errorDetail}');
    });

    final treeKey = GlobalKey<_ExpandableTreeState>();
    await tester.pumpWidget(
      _host(provider, child: _ExpandableTree(key: treeKey)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final connFinder = find.ancestor(
      of: find.text('C16 SQLite'),
      matching: find.byType(TreeItem),
    );
    await tester.tap(connFinder);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 多库形态：main 与附加库均渲染 header（spec 050）
    expect(find.text('main'), findsOneWidget);
    expect(find.text('archive_c16'), findsOneWidget);

    // 展开附加库 header → 懒加载子树渲染 Tables 分类。
    // C16 存量缺陷已修复（getDatabaseInfo sqlite 特判：跳过 useDatabase +
    // alias 透传到 `<alias>.sqlite_master`）：附加库头下列**附加库自己的**
    // 表（ext_probe），main 的表（main_probe）不得串库。
    await tester.tap(find.text('archive_c16'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Tables'), findsOneWidget);

    await tester.tap(find.text('Tables'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    // per-alias 内容正确性（原缺陷：此处列的是 main 的 main_probe）。
    expect(find.text('ext_probe'), findsOneWidget,
        reason: '附加库头下应列出附加库自己的表');
    expect(find.text('main_probe'), findsNothing,
        reason: 'main 的表不得串进附加库子树（原存量缺陷形态）');
  });

  testWidgets('C16-LT-CAP-PRAGMA：sqlite.pragma 项激活 → PRAGMA Explorer', (
    tester,
  ) async {
    await connectAndSeedMain(tester);

    SidebarCapabilityItem? pragmaItem;
    await tester.pumpWidget(
      _host(
        provider,
        child: Builder(
          builder: (context) {
            for (final group
                in const SqliteSidebarPlugin().capabilityGroups(context)) {
              for (final item in group.items) {
                if (item.id == 'sqlite.pragma') pragmaItem = item;
              }
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(pragmaItem, isNotNull, reason: 'sqlite 插件应提供 sqlite.pragma 项');

    await tester.runAsync(() async {
      pragmaItem!.onActivate!();
    });
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.byType(PragmaExplorerDialog), findsOneWidget);
  });

  testWidgets('C16-LT-CAP-ATTACH：sqlite.attach 项激活 → Attach 对话框', (
    tester,
  ) async {
    await connectAndSeedMain(tester);
    extraDbPath = await _buildExtraDb('cap');

    SidebarCapabilityItem? attachItem;
    await tester.pumpWidget(
      _host(
        provider,
        child: Builder(
          builder: (context) {
            for (final group
                in const SqliteSidebarPlugin().capabilityGroups(context)) {
              for (final item in group.items) {
                if (item.id == 'sqlite.attach') attachItem = item;
              }
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(attachItem, isNotNull);

    await tester.runAsync(() async {
      attachItem!.onActivate!();
    });
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(AttachDatabaseDialog), findsOneWidget);
  });
}

/// 有状态树包装：expandedItems 归测试侧持有（tap → toggle → setState 重建）。
class _ExpandableTree extends StatefulWidget {
  const _ExpandableTree({super.key});

  @override
  State<_ExpandableTree> createState() => _ExpandableTreeState();
}

class _ExpandableTreeState extends State<_ExpandableTree> {
  Set<String> expandedItems = {};

  @override
  Widget build(BuildContext context) {
    return SidebarTree(
      expandedItems: expandedItems,
      expandedDatabases: const {},
      expandedTables: const {},
      loadingDatabases: const {},
      onToggleExpand: (key) {
        setState(() {
          expandedItems = expandedItems.contains(key)
              ? ({...expandedItems}..remove(key))
              : {...expandedItems, key};
        });
      },
      onToggleDatabase: (_) {},
      onToggleTable: (_) {},
      onLoadDatabaseInfo: (_, _) async {},
      onShowConnectionManager: () {},
      onShowSettings: () {},
      onShowERDiagram: () {},
      onShowStoredProcedures: () {},
      onShowTriggers: () {},
    );
  }
}
