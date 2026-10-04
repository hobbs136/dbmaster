// AI 工作台保存的查询抽屉共享视图测试（v2 先行批 A4，任务书 §6.4 第 4 条六要点）。
//
// 覆盖：① 按连接过滤（上下文连接命中 → savedQueriesForConnection，两连接
// 各 1 条 → 各见各的）；② 无上下文 → 全量列出 + 连接名注记；③ 载入动线
// （Enter / 双击 / 行内「载入」图标）→ openEditorSlot 回调收到正确 SQL 且
// 零执行（计数桩 provider 上 executeQuery 调用数恒 0，手法沿
// workbench_query_history_view_test.dart _CountingAppProvider）；④ 空态
// 三节点。⑤ 舞台单例 tab 恒 1 在 workbench_stage_test.dart savedQueries
// 组；⑥ rail 图标顺序终态在 workbench_session_rail_test.dart。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbServer;
import 'package:dbmaster/organisms/ai_workbench/workbench_saved_query_list_view.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;

/// executeQuery 计数桩（A4 要点 ③：抽屉零执行——任一交互后调用数恒 0）。
class _CountingAppProvider extends AppProvider {
  int executeCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executeCalls++;
    return Future<List<Map<String, dynamic>>>.value(
      <Map<String, dynamic>>[
        <String, dynamic>{'id': 1},
      ],
    );
  }
}

/// 成对发送按下/抬起（AGENTS.md §8-10：缺抬起触发 HardwareKeyboard 断言）。
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
}

/// 单击后越过双击判别窗（kDoubleTapTimeout ≈ 300ms）：条目同时注册
/// onTap/onDoubleTap，单击回调被延迟到窗口关闭——pumpAndSettle 只推帧不推
/// 该 Timer，需显式 pump 一步让 onTap（聚焦）落地。
Future<void> _settleSingleTap(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// 泵独立保存的查询视图（组件面）。[width] 196 = rail 窄列形态（narrow），
/// 800 = 舞台全宽形态；返回载入回调收到的 SQL 列表（recorder）。
Future<(AppProvider, List<String>)> _pumpView(
  WidgetTester tester, {
  AppProvider? provider,
  double width = 196,
  Future<void> Function(AppProvider app)? seed,
}) async {
  final app = provider ?? AppProvider();
  final loaded = <String>[];
  if (seed != null) {
    await seed(app);
  }
  await tester.binding.setSurfaceSize(const Size(1024, 800));
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 600,
              child: SavedQueryListView(
                narrow: width <= 240,
                onLoadIntoEditor: loaded.add,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (app, loaded);
}

/// 经 provider 公有 API 播种保存查询（`tab.saveQuery` 同一管线——与经典
/// 侧「保存查询」同源，copyWith 保留 sql / connectionId / databaseName）。
Future<void> seedSavedQueries(
  AppProvider app,
  List<SavedQuerySeed> seeds,
) async {
  for (final s in seeds) {
    await app.tab.saveQuery(
      QueryTab(
        id: s.id,
        title: s.title,
        sql: s.sql,
        connectionId: s.connectionId,
        databaseName: s.databaseName,
      ),
    );
  }
}

/// 播种两条连接（名称用于全量态连接名注记断言；测试播种专用入口
/// `addSavedServerForTest`，connection_provider.dart:2168）。
void seedConnections(AppProvider app) {
  app.connection.addSavedServerForTest(
    DbServer(id: 'conn_a', name: 'Alpha MySQL', host: 'a', port: 3306),
  );
  app.connection.addSavedServerForTest(
    DbServer(
      id: 'conn_b',
      name: 'Beta Postgres',
      type: DatabaseType.postgresql,
      host: 'b',
      port: 5432,
    ),
  );
}

/// 播种条目描述（测试内轻量值对象；字段与 tab.saveQuery 对齐）。
class SavedQuerySeed {
  const SavedQuerySeed({
    required this.id,
    required this.title,
    required this.sql,
    this.connectionId,
    this.databaseName,
  });

  final String id;
  final String title;
  final String sql;
  final String? connectionId;
  final String? databaseName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('A4-① 按连接过滤（上下文连接命中 → savedQueriesForConnection）', () {
    testWidgets('两连接各 1 条 → 各见各的（切换上下文跟随）', (tester) async {
      final (app, loaded) = await _pumpView(
        tester,
        seed: (app) async {
          seedConnections(app);
          await seedSavedQueries(app, const [
            SavedQuerySeed(
              id: 'qa',
              title: 'Alpha users',
              sql: 'SELECT * FROM a_users',
              connectionId: 'conn_a',
              databaseName: 'shop_a',
            ),
            SavedQuerySeed(
              id: 'qb',
              title: 'Beta orders',
              sql: 'SELECT * FROM b_orders',
              connectionId: 'conn_b',
              databaseName: 'shop_b',
            ),
          ]);
          // 上下文连接 = conn_a（侧栏 currentServer 源，无会话锁）。
          app.connection.setCurrentServer(
            app.savedConnections.firstWhere((s) => s.id == 'conn_a'),
          );
        },
      );

      expect(find.text('Alpha users'), findsOneWidget);
      expect(find.text('Beta orders'), findsNothing, reason: '命中上下文连接 → 只列该连接的保存查询');
      expect(
        find.text('shop_a'),
        findsOneWidget,
        reason: '上下文命中态注记 = 库名（§6.4 条款 2 库名注记）',
      );

      // 切换上下文连接 → 过滤跟随（connection 通知经 facade 转发重建）。
      app.connection.setCurrentServer(
        app.savedConnections.firstWhere((s) => s.id == 'conn_b'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Beta orders'), findsOneWidget);
      expect(find.text('Alpha users'), findsNothing);
      expect(loaded, isEmpty, reason: '过滤切换不触发载入');
    });
  });

  group('A4-② 无上下文 → 全量 + 连接名注记', () {
    testWidgets('未命中/无上下文 → 列全部本地保存查询，条目标注连接名',
        (tester) async {
      await _pumpView(
        tester,
        seed: (app) async {
          seedConnections(app);
          await seedSavedQueries(app, const [
            SavedQuerySeed(
              id: 'qa',
              title: 'Alpha users',
              sql: 'SELECT * FROM a_users',
              connectionId: 'conn_a',
              databaseName: 'shop_a',
            ),
            SavedQuerySeed(
              id: 'qb',
              title: 'Beta orders',
              sql: 'SELECT * FROM b_orders',
              connectionId: 'conn_b',
            ),
          ]);
          // 不设 currentServer / 活动 tab / 侧栏选中 → 上下文 none。
        },
      );

      expect(
        find.text('Alpha users'),
        findsOneWidget,
        reason: '无上下文 → 列全部本地保存查询（载入不依赖连接）',
      );
      expect(find.text('Beta orders'), findsOneWidget);
      // 连接名注记（196 窄列 = 单行 '连接名 · 库名'，textContaining 断言）。
      expect(find.textContaining('Alpha MySQL'), findsOneWidget);
      expect(find.textContaining('Beta Postgres'), findsOneWidget);
    });

    testWidgets('宽形态注记分段铺开（连接名 / 库名各自独立段）', (tester) async {
      await _pumpView(
        tester,
        width: 800,
        seed: (app) async {
          seedConnections(app);
          await seedSavedQueries(app, const [
            SavedQuerySeed(
              id: 'qa',
              title: 'Alpha users',
              sql: 'SELECT * FROM a_users',
              connectionId: 'conn_a',
              databaseName: 'shop_a',
            ),
          ]);
        },
      );

      expect(find.text('Alpha MySQL'), findsOneWidget);
      expect(find.text('shop_a'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '宽形态无 overflow');
    });
  });

  group('A4-③ 载入动线（Enter / 双击 / 行内图标）+ 断言零执行', () {
    testWidgets('单击聚焦（不载入）→ Enter → onLoadIntoEditor 收到条目 SQL',
        (tester) async {
      const sql = 'SELECT * FROM users WHERE id = 1';
      final (_, loaded) = await _pumpView(
        tester,
        seed: (app) => seedSavedQueries(app, const [
          SavedQuerySeed(id: 'q1', title: 'Users list', sql: sql),
        ]),
      );

      await tester.tap(find.text('Users list'));
      await _settleSingleTap(tester);
      expect(loaded, isEmpty, reason: '单击 = 聚焦，不触发载入');

      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(loaded, [sql], reason: 'Enter 载入且 SQL 一致（§8-3）');
    });

    testWidgets('双击 → 载入；行内「载入」图标 → 载入', (tester) async {
      const sqlA = 'UPDATE orders SET amount = 1';
      const sqlB = 'DELETE FROM logs WHERE id = 9';
      final (_, loaded) = await _pumpView(
        tester,
        seed: (app) => seedSavedQueries(app, const [
          SavedQuerySeed(id: 'qa', title: 'Order fix', sql: sqlA),
          SavedQuerySeed(id: 'qb', title: 'Log purge', sql: sqlB),
        ]),
      );

      await tester.tap(find.text('Order fix'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Order fix'));
      await tester.pumpAndSettle();
      expect(loaded, [sqlA], reason: '双击载入（§8-3）');

      // 行内图标被外层条目的双击判别窗延迟（条目注册 onDoubleTap，图标
      // 嵌套 InkWell 的 onTap 待窗关闭后 arena 才落——同 A3 单击 350ms 手法）。
      await tester.tap(
        find.byKey(const ValueKey('workbench_saved_query_load_qb')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(loaded, [sqlA, sqlB], reason: '行内「载入」图标 = 主动作第三入口');
    });

    testWidgets('全部条目 × 全部入口交互后 executeQuery 调用数恒 0', (tester) async {
      final counting = _CountingAppProvider();
      final (_, loaded) = await _pumpView(
        tester,
        provider: counting,
        seed: (app) => seedSavedQueries(app, const [
          SavedQuerySeed(
            id: 'q1',
            title: 'Read all',
            sql: 'SELECT * FROM users',
            connectionId: 'conn_a',
          ),
          SavedQuerySeed(
            id: 'q2',
            title: 'Write thing',
            sql: 'DELETE FROM orders WHERE id = 9',
            connectionId: 'conn_a',
          ),
        ]),
      );

      // 单击聚焦 + Enter + 双击 + 行内图标，全走一遍（图标点击同样需 pump
      // 越过条目双击判别窗——见上方 A4-③ 双击/图标用例注释）。
      await tester.tap(find.text('Read all'));
      await _settleSingleTap(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write thing'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Write thing'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workbench_saved_query_load_q1')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        loaded,
        ['SELECT * FROM users', 'DELETE FROM orders WHERE id = 9',
          'SELECT * FROM users'],
        reason: '三条入口各自生效：Enter（q1）/ 双击（q2）/ 行内图标（q1）',
      );
      expect(
        counting.executeCalls,
        0,
        reason: '抽屉无任何形式的执行入口（§5 纪律 6 / v2 §8-11；载入不执行）',
      );
    });
  });

  group('A4-④ 空态（§8-8 本地空态）', () {
    testWidgets('三节点存在：bookmark 图标 + 标题 + hint', (tester) async {
      await _pumpView(tester);

      expect(
        find.byKey(const ValueKey('workbench_saved_queries_empty')),
        findsOneWidget,
      );
      expect(find.text('No saved queries'), findsOneWidget);
      expect(
        find.text('Save a query in the classic editor first'),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.bookmark), findsOneWidget);
    });
  });
}
