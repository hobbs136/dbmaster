// AI 工作台查询历史抽屉共享视图测试（v2 先行批 A3，任务书 §6.3 第 7 条七要点）。
//
// 覆盖：① Enter 载入 → onLoadIntoEditor 收到且 SQL 一致（双击同款动线）；
// ② 断言零执行（计数桩 provider 上 executeQuery 调用数恒 0，手法沿
// ai_workbench_shell_test.dart _CountingAppProvider）；③ 搜索即时过滤
// 命中 / 无命中；④ 空态三节点 + 搜索框禁用可见（§8-8）；⑤ agent 徽标按
// source 显隐（workbenchAgentSourceBadge）；⑦ 失败行错误图标存在（不断言
// 颜色）。⑥ 舞台单例复用 tab 恒 1 在 workbench_stage_test.dart history 组。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/query_history.dart' show QueryHistorySource;
import 'package:dbmaster/organisms/ai_workbench/workbench_query_history_view.dart';
import 'package:dbmaster/providers/app_provider.dart';

/// executeQuery 计数桩（A3 要点 ②：抽屉零执行——任一交互后调用数恒 0）。
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
/// 该 Timer，需显式 pump 一步让 onTap（展开 + 聚焦）落地。
Future<void> _settleSingleTap(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// 泵独立查询历史视图（组件面）。[width] 196 = rail 窄列形态（narrow），
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
              child: QueryHistoryListView(
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

/// 经 provider 公有 API 播种历史（时间戳逐条错开毫秒——addQueryHistory 以
/// millisecondsSinceEpoch 生成 id，同毫秒会撞 ValueKey）。基点只取一次
/// DateTime.now() 再逐条减 1ms：逐条各自取 now 时，真实时钟恰前进 1ms 会
/// 使相邻两条同毫秒（id 相撞 → 展开态同源命中两条，全量跑偶发 tap 歧义）。
Future<void> seedHistory(AppProvider app, List<QueryHistorySeed> entries) async {
  final base = DateTime.now();
  var offsetMs = 0;
  for (final e in entries) {
    await app.queryHistory.addQueryHistory(
      sql: e.sql,
      connectionId: 'conn_history',
      connectionName: e.connectionName ?? 'Local MySQL',
      executionTime: e.executionTime,
      affectedRows: e.affectedRows,
      error: e.error,
      timestamp: base.subtract(Duration(milliseconds: offsetMs)),
      source: e.source,
    );
    offsetMs += 1;
  }
}

/// 播种条目描述（测试内轻量值对象；字段与 addQueryHistory 对齐）。
class QueryHistorySeed {
  const QueryHistorySeed({
    required this.sql,
    this.connectionName,
    this.executionTime = 0,
    this.affectedRows = 0,
    this.error,
    this.source = QueryHistorySource.executed,
  });

  final String sql;
  final String? connectionName;
  final int executionTime;
  final int affectedRows;
  final String? error;
  final QueryHistorySource source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('A3-① 动线：Enter / 双击 → 载入编辑器（SQL 一致）', () {
    testWidgets('单击 = 行内展开（不载入）；Enter → onLoadIntoEditor 收到条目 SQL',
        (tester) async {
      const sql = 'SELECT * FROM users WHERE id = 1';
      final (_, loaded) = await _pumpView(
        tester,
        seed: (app) => seedHistory(app, const [QueryHistorySeed(sql: sql)]),
      );

      await tester.tap(find.text(sql));
      await _settleSingleTap(tester);
      expect(loaded, isEmpty, reason: '单击 = 行内展开，不触发载入');

      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(loaded, [sql], reason: 'Enter 载入且 SQL 一致（§8-3）');
    });

    testWidgets('双击 → onLoadIntoEditor（动线第二入口）', (tester) async {
      const sql = 'UPDATE orders SET amount = 1';
      final (_, loaded) = await _pumpView(
        tester,
        seed: (app) => seedHistory(app, const [QueryHistorySeed(sql: sql)]),
      );

      await tester.tap(find.text(sql));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(sql));
      await tester.pumpAndSettle();
      expect(loaded, [sql], reason: '双击载入（§8-3）');
    });

    testWidgets('展开块 = 行内 SQL 全文预览（再击收起）', (tester) async {
      const sql = 'SELECT a,\n       b\nFROM t';
      final (_, loaded) = await _pumpView(
        tester,
        seed: (app) => seedHistory(app, const [QueryHistorySeed(sql: sql)]),
      );

      // 多行 SQL 首行预览。
      expect(find.text('SELECT a,'), findsOneWidget);
      await tester.tap(find.text('SELECT a,'));
      await _settleSingleTap(tester);
      expect(find.text(sql), findsOneWidget, reason: '展开块呈现 SQL 全文');

      await tester.tap(find.text('SELECT a,'));
      await _settleSingleTap(tester);
      expect(find.text(sql), findsNothing, reason: '再击收起');
      expect(loaded, isEmpty, reason: '展开/收起全程不触发载入');
    });
  });

  group('A3-② 断言零执行', () {
    testWidgets('全部条目 × 全部入口交互后 executeQuery 调用数恒 0', (tester) async {
      final counting = _CountingAppProvider();
      final (_, loaded) = await _pumpView(
        tester,
        provider: counting,
        seed: (app) => seedHistory(app, const [
          QueryHistorySeed(sql: 'SELECT * FROM users'),
          QueryHistorySeed(sql: 'DELETE FROM orders WHERE id = 9'),
        ]),
      );

      // 单击展开 + Enter + 双击 + 搜索，全走一遍。
      await tester.tap(find.text('SELECT * FROM users'));
      await _settleSingleTap(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DELETE FROM orders WHERE id = 9'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('DELETE FROM orders WHERE id = 9'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workbench_history_search')),
        'users',
      );
      await tester.pumpAndSettle();

      expect(
        loaded,
        hasLength(2),
        reason: '载入动线本身生效（前置有效性）',
      );
      expect(
        counting.executeCalls,
        0,
        reason: '抽屉无任何形式的执行入口（§5 纪律 6 / v2 §8-11）',
      );
    });
  });

  group('A3-③ 搜索即时过滤', () {
    testWidgets('命中保留 / 未命中过滤 / 无命中态 / 改词恢复', (tester) async {
      final (_, loaded) = await _pumpView(
        tester,
        seed: (app) => seedHistory(app, const [
          QueryHistorySeed(sql: 'SELECT * FROM users'),
          QueryHistorySeed(sql: 'UPDATE orders SET amount = 1'),
        ]),
      );
      const searchKey = ValueKey('workbench_history_search');
      expect(find.text('SELECT * FROM users'), findsOneWidget);
      expect(find.text('UPDATE orders SET amount = 1'), findsOneWidget);

      await tester.enterText(find.byKey(searchKey), 'users');
      await tester.pumpAndSettle();
      expect(find.text('SELECT * FROM users'), findsOneWidget);
      expect(find.text('UPDATE orders SET amount = 1'), findsNothing);

      await tester.enterText(find.byKey(searchKey), 'no_such_token');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workbench_history_no_match')),
        findsOneWidget,
        reason: '搜索无命中呈现无数据态（空态三节点仅在全空时出现）',
      );
      expect(find.text('SELECT * FROM users'), findsNothing);

      await tester.enterText(find.byKey(searchKey), 'users');
      await tester.pumpAndSettle();
      expect(find.text('SELECT * FROM users'), findsOneWidget);
      expect(loaded, isEmpty);
    });
  });

  group('A3-④ 空态（§8-8）', () {
    testWidgets('三节点存在 + 搜索框禁用不隐藏', (tester) async {
      await _pumpView(tester);

      expect(
        find.byKey(const ValueKey('workbench_history_empty')),
        findsOneWidget,
      );
      expect(find.text('No query history'), findsOneWidget);
      expect(find.text('Executed queries will appear here'), findsOneWidget);
      expect(find.byIcon(LucideIcons.history), findsOneWidget);

      const searchKey = ValueKey('workbench_history_search');
      expect(find.byKey(searchKey), findsOneWidget, reason: '搜索框禁用不隐藏');
      final search = tester.widget<TextField>(find.byKey(searchKey));
      expect(search.enabled, isFalse, reason: '空态下搜索框禁用（状态可解释）');
    });
  });

  group('A3-⑤ agent 来源徽标', () {
    testWidgets('source == agent → bot 徽标 + workbenchAgentSourceBadge tooltip；executed 无',
        (tester) async {
      await _pumpView(
        tester,
        seed: (app) => seedHistory(app, const [
          QueryHistorySeed(sql: 'SELECT 1'),
          QueryHistorySeed(sql: 'SELECT 2', source: QueryHistorySource.agent),
        ]),
      );

      expect(find.byTooltip('Agent'), findsOneWidget);
      expect(find.byIcon(LucideIcons.bot), findsOneWidget);
    });
  });

  group('A3-⑦ 失败行', () {
    testWidgets('error 非空 → triangleAlert 图标存在；成功行无（不断言颜色）',
        (tester) async {
      await _pumpView(
        tester,
        seed: (app) => seedHistory(app, const [
          QueryHistorySeed(sql: 'SELECT 1'),
          QueryHistorySeed(sql: 'SELECT 2', error: 'boom: syntax error'),
        ]),
      );

      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    });
  });

  group('A3-⑥ 舞台全宽形态（narrow=false）', () {
    testWidgets('宽形态同组件渲染：条目 / 搜索框在位，无 overflow', (tester) async {
      final (_, loaded) = await _pumpView(
        tester,
        width: 800,
        seed: (app) => seedHistory(app, const [
          QueryHistorySeed(
            sql: 'SELECT * FROM orders',
            affectedRows: 3,
            executionTime: 42,
          ),
        ]),
      );

      expect(find.text('SELECT * FROM orders'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench_history_search')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '宽形态无 overflow');
      expect(loaded, isEmpty);
    });
  });
}
