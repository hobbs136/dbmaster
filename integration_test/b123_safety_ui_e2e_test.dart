//
// 对应《B1-B2-B3-E2E测试文档》场景①（安全审查规则分区 + 开关/阈值生效）、
// 场景②（索引推荐「应用此索引」）、场景③（行级红点）。
//
// 运行（连真实 MySQL，参数经 DBMASTER_MYSQL_* 提供）：
//   flutter test -d windows integration_test/b123_safety_ui_e2e_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/organisms/connection/settings_dialog.dart';
import 'package:dbmaster/organisms/dialogs/execution_gate_dialog.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/sql_validator_service.dart'
    show ErrorSeverity;
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// 测试表名（文档 demo_safety_test）。
const _table = 'demo_safety_test';

/// 测试表行数（1500 行：阈值下限 1000，需行数 > 1000 才能验证阈值）。
const _rowCount = 1500;

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('B1/B2/B3 UI E2E（真实 MySQL 8.0）', () {
    late AppProvider provider;
    late MySQLAdapter seedAdapter;
    late ThemeProvider themeProvider;
    late LocaleProvider localeProvider;
    late LayoutPreferencesProvider layoutProvider;
    late String testDbName;
    bool connected = false;

    /// 只保留「缺 LIMIT」规则，关掉两条 EXPLAIN 规则，隔离开关/阈值验证。
    Future<void> isolateMissingLimitRule() async {
      await provider.querySettings.setExplainFullScanEnabled(false);
      await provider.querySettings.setExplainEstimatedRowsEnabled(false);
      await provider.querySettings.setMissingLimitEnabled(true);
    }

    // ── 准备：建真实测试库 + demo_safety_test（1500 行）──────────────────
    setUp(() async {
      seedAdapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();

      final seedConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: '',
      );
      try {
        final ok = await seedAdapter.connect(seedConn);
        if (!ok) {
          connected = false;
          return;
        }
        connected = true;
        await seedAdapter.createDatabase(testDbName);
        await seedAdapter.useDatabase(testDbName);
        await seedAdapter.executeQuery(
          'CREATE TABLE `$_table` ('
          'id INT PRIMARY KEY AUTO_INCREMENT, '
          'user_id INT, '
          'status VARCHAR(20), '
          'created_at DATETIME'
          ')',
        );
        // 调大递归 CTE 层数上限（MySQL 默认 1000 层，插 1500 行会超限）。
        await seedAdapter.executeQuery(
          'SET SESSION cte_max_recursion_depth = 10000',
        );
        // 递归 CTE 批量插入 100 行（文档 fill_demo 等价）。
        await seedAdapter.executeQuery(
          'INSERT INTO `$_table` (user_id, status, created_at) '
          'WITH RECURSIVE seq AS ('
          '  SELECT 0 AS n'
          '  UNION ALL SELECT n + 1 FROM seq WHERE n < $_rowCount'
          ') '
          "SELECT n, ELT((n MOD 3) + 1, 'active','inactive','banned'), "
          'NOW() - INTERVAL n DAY FROM seq',
        );
      } catch (_) {
        connected = false;
      }

      // ── AppProvider 连真实 MySQL（默认库指向测试库）──────────────
      AppProvider.devBypassGates = true;
      provider = AppProvider();
      // 复位安全配置到出厂默认（阈值 100000 + 6 开关全开），避免上次测试持久化残留。
      await provider.querySettings.load(); // 先等构造器里异步 load 完成，再复位
      await provider.querySettings.setSafetyConfig(SafetyConfig.defaults);
      final server = DbServer(
        id: 'b123_e2e_${testDbName.hashCode}',
        name: 'B123 E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: testDbName,
      );
      await provider.connection.saveConnection(server);
      if (connected) {
        final connected = await provider.connectToServer(server);
        expect(connected, isTrue, reason: 'AppProvider 连不上 MySQL');
        await provider.refreshDatabases();
        await provider.tab.openQueryTab(
          connectionId: server.id,
          databaseName: testDbName,
        );
        provider.setActiveTab(0);
      }

      themeProvider = ThemeProvider();
      localeProvider = LocaleProvider();
      layoutProvider = LayoutPreferencesProvider();
      await themeProvider.load();
      await localeProvider.load();
      await layoutProvider.load();
    });

    tearDown(() async {
      try {
        await seedAdapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
      } catch (_) {}
      try {
        await seedAdapter.disconnect();
      } catch (_) {}
      try {
        await provider.disconnectConnection(
          connectionId: provider.connection.currentServer?.id ?? '',
        );
      } catch (_) {}
      try {
        provider.dispose();
      } catch (_) {}
    });

    // ── Harness ─────────────────────────────────────────────────────────
    Widget buildHarness(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
          ),
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ],
        child: Consumer2<LocaleProvider, ThemeProvider>(
          builder: (context, locale, theme, _) {
            return MaterialApp(
              locale: locale.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(theme.accentColorValue),
              home: Scaffold(body: child),
            );
          },
        ),
      );
    }

    Future<void> pumpEditor(WidgetTester tester, String sql) async {
      provider.updateTabSql(0, sql);
      await tester.pumpWidget(
        buildHarness(
          const SizedBox(
            width: 1280,
            height: 800,
            child: QueryEditorWidget(tabIndex: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 点击工具栏「执行查询」按钮。
    Future<void> tapRun(WidgetTester tester) async {
      await tester.tap(find.byIcon(LucideIcons.play));
      await tester.pump();
    }

    /// 轮询等待条件成立。
    Future<void> waitFor(
      WidgetTester tester,
      String label,
      bool Function() condition, {
      Duration timeout = const Duration(seconds: 20),
    }) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        if (condition()) return;
        await tester.pump(const Duration(milliseconds: 200));
      }
      throw StateError('等待超时: $label');
    }

    QueryEditorWidgetState editorState(WidgetTester tester) =>
        tester.state<QueryEditorWidgetState>(find.byType(QueryEditorWidget));

    /// 编辑器当前文本。
    String editorText(WidgetTester tester) =>
        editorState(tester).controller.text;

    /// 编辑器行号错误映射（T011 校验 + B3 安全审查合并红点）。
    Map<int, ErrorSeverity> editorErrors(WidgetTester tester) =>
        editorState(tester).mergedEditorErrors;

    /// 模拟真实输入（IME 入口 edit()，触发 onChanged 校验管线——与旧
    /// enterText 等价：程序化 controller.text= 不触发门面回调）。
    Future<void> editorType(WidgetTester tester, String text) async {
      editorState(tester).controller.replaceAllText(text);
      await tester.pump();
    }

    /// 等待查询完全结束（结果已写入且 Run 按钮恢复空闲态）。
    Future<void> runAndWaitIdle(WidgetTester tester, String label) async {
      await tapRun(tester);
      await waitFor(
        tester,
        label,
        () =>
            provider.tab.activeResults.isNotEmpty &&
            find.byIcon(LucideIcons.play).evaluate().isNotEmpty,
      );
    }

    // ═══════════════════════════════════════════════════════════════════
    // 场景① B1：设置页「安全审查规则」分区
    // ═══════════════════════════════════════════════════════════════════
    testWidgets('B1-1: 设置页安全审查规则分区（标题 + 6 开关 + 阈值默认 100000）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!connected) return;

      await tester.pumpWidget(
        buildHarness(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const SettingsDialog(),
                ),
                child: const Text('Open Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);

      // C22 M2 整窗迁移：设置对话框改左导航分页——先切「安全」页
      //（默认页是外观；从外观页点 nav「安全」文本全局唯一）。
      await tester.tap(find.text('安全'));
      await tester.pumpAndSettle();

      // 分区标题。
      await tester.ensureVisible(find.text('安全审查规则'));
      expect(find.text('安全审查规则'), findsOneWidget);

      // 6 条规则标题。
      for (final label in const [
        'Schema 兼容性检查',
        '缺 LIMIT 警告',
        '全表扫描检测（静态）',
        'SQL 注入检测',
        '全表扫描检测（EXPLAIN 实证）',
        '大结果集预警（EXPLAIN）',
      ]) {
        await tester.ensureVisible(find.text(label));
        expect(find.text(label), findsOneWidget, reason: '应显示规则: $label');
      }

      // 阈值输入框存在（按右侧伴随标签定位，同 widget 测试）；默认值 100000 以配置为准。
      final thresholdLabel = find.text('行数阈值（缺 LIMIT / 全表扫 / 大结果集通用）');
      await tester.ensureVisible(thresholdLabel);
      await tester.pumpAndSettle();
      expect(thresholdLabel, findsOneWidget);
      final row = tester.widget<Row>(
        find.ancestor(of: thresholdLabel, matching: find.byType(Row)),
      );
      final thresholdField = find.descendant(
        of: find.byWidget(row),
        matching: find.byType(TextField),
      );
      expect(thresholdField, findsOneWidget, reason: '行数阈值应有对应输入框');
      expect(
        provider.querySettings.safetyConfig.fullScanRowThreshold,
        equals(100000),
        reason: '行数阈值默认应为 100000',
      );

      // 6 个安全规则开关默认 ON（索引 2-7：autocomplete=0 / autoLimit=1 之后的 6 个）。
      final switches = find.descendant(
        of: find.byType(SettingsDialog),
        matching: find.byType(Switch),
      );
      expect(
        tester.widgetList<Switch>(switches).length,
        greaterThanOrEqualTo(8),
      );
      for (var i = 2; i <= 7; i++) {
        expect(
          tester.widget<Switch>(switches.at(i)).value,
          isTrue,
          reason: '安全规则开关索引 $i 应默认全开',
        );
      }
    });

    testWidgets('B1-2: 缺 LIMIT 开关生效（关→不警告，开→警告）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!connected) return;
      // 表 1500 行；阈值 1000（下限）保证缺 LIMIT 规则可触发。
      await isolateMissingLimitRule();
      await provider.querySettings.setFullScanRowThreshold(1000);

      await pumpEditor(tester, 'SELECT * FROM $_table');

      // 关掉缺 LIMIT → 不弹执行门，查询正常返回。
      await provider.querySettings.setMissingLimitEnabled(false);
      await runAndWaitIdle(tester, '查询完成');
      expect(
        find.byType(ExecutionGateDialog),
        findsNothing,
        reason: '缺 LIMIT 规则关闭后不应弹安全审查警告',
      );

      // 打开缺 LIMIT → 同样 SQL 弹执行门（缺 LIMIT finding）。
      await provider.querySettings.setMissingLimitEnabled(true);
      await tapRun(tester);
      await waitFor(
        tester,
        '执行门弹出',
        () => find.byType(ExecutionGateDialog).evaluate().isNotEmpty,
      );
      expect(find.byType(ExecutionGateDialog), findsOneWidget);
      expect(
        find.textContaining('缺 LIMIT'),
        findsWidgets,
        reason: '应显示缺 LIMIT 警告 finding',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('B1-3: 阈值生效（1000 触发，2000 不触发）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!connected) return;
      await isolateMissingLimitRule();

      // 阈值 1000 < 1500 行 → 触发。
      await provider.querySettings.setFullScanRowThreshold(1000);
      await pumpEditor(tester, 'SELECT * FROM $_table');
      await tapRun(tester);
      await waitFor(
        tester,
        '阈值50触发执行门',
        () => find.byType(ExecutionGateDialog).evaluate().isNotEmpty,
      );
      expect(find.byType(ExecutionGateDialog), findsOneWidget);
      expect(find.textContaining('缺 LIMIT'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 阈值 2000 > 1500 行 → 不触发。
      await provider.querySettings.setFullScanRowThreshold(2000);
      await runAndWaitIdle(tester, '阈值200查询完成');
      expect(
        find.byType(ExecutionGateDialog),
        findsNothing,
        reason: '阈值 2000 > 行数 1500 时不应触发缺 LIMIT 警告',
      );
    });

    // ═══════════════════════════════════════════════════════════════════
    // 场景② B2：索引推荐「应用此索引」
    // ═══════════════════════════════════════════════════════════════════
    testWidgets('B2: 查询计划「应用此索引」→ DDL 填入编辑器（不自动执行）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!connected) return;
      await pumpEditor(tester, "SELECT * FROM $_table WHERE status = 'active'");

      // 点工具栏「查询计划」。
      await tester.tap(find.byTooltip('Query Plan'));
      await tester.pumpAndSettle();

      // 弹出查询执行计划对话框 + 索引推荐卡片 + 应用按钮。
      final applyBtn = find.text('Apply This Index');
      expect(applyBtn, findsOneWidget, reason: '索引推荐卡片应显示「应用此索引」按钮');

      // 点击应用 → DDL 填入编辑器、弹窗关闭、横幅提示。
      await tester.ensureVisible(applyBtn);
      await tester.pumpAndSettle();
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      expect(
        editorText(tester),
        contains('CREATE INDEX'),
        reason: '编辑器应填入 CREATE INDEX DDL',
      );
      expect(applyBtn, findsNothing, reason: '查询计划对话框应关闭');
      expect(
        find.textContaining('索引 DDL 已填入编辑器'),
        findsOneWidget,
        reason: '应显示填入横幅',
      );

      // 不自动执行：未弹执行门、无 CREATE INDEX 执行结果。
      // （查询计划本身会执行一次 EXPLAIN，结果面板会留下一条 history 标记，属预期，忽略。）
      expect(
        find.byType(ExecutionGateDialog),
        findsNothing,
        reason: '点击应用后不应自动执行 DDL',
      );
      expect(
        provider.tab.activeResults.any(
          (r) => (r.executedSql ?? '').contains('CREATE INDEX'),
        ),
        isFalse,
        reason: '不应有 CREATE INDEX 的执行结果（DDL 未自动执行）',
      );
    });

    // ═══════════════════════════════════════════════════════════════════
    // 场景③ B3：编辑器行级红点
    // ═══════════════════════════════════════════════════════════════════
    testWidgets('B3: 执行后行级红点显示 + 编辑后消失 + 重执行重现', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!connected) return;
      // 隔离出「缺 LIMIT」medium 与「OR 1=1」high；阈值 1000 保证缺 LIMIT 命中。
      await isolateMissingLimitRule();
      await provider.querySettings.setFullScanRowThreshold(1000);

      // SELECT 在第 3 行（文档 B3 场景的样例）。
      final multiLineSql =
          '-- 第1行：注释\n'
          '-- 第2行：注释\n'
          'SELECT * FROM $_table\n'
          'WHERE id = 1 OR 1=1;';

      await pumpEditor(tester, multiLineSql);
      expect(editorErrors(tester), isEmpty, reason: '初始无红点');

      // 执行 → 执行门弹出，列出注入 + 缺 LIMIT 两条 finding。
      await tapRun(tester);
      await waitFor(
        tester,
        '执行门弹出',
        () => find.byType(ExecutionGateDialog).evaluate().isNotEmpty,
      );
      expect(find.byType(ExecutionGateDialog), findsOneWidget);
      expect(
        find.textContaining('永真式'),
        findsWidgets,
        reason: '应列出 SQL 注入 finding（OR 1=1）',
      );
      expect(
        find.textContaining('缺 LIMIT'),
        findsOneWidget,
        reason: '应列出缺 LIMIT finding',
      );

      // 弹窗期间红点已填充：SELECT 所在第 3 行 = error（high 级取最严重）。
      expect(
        editorErrors(tester)[3],
        ErrorSeverity.error,
        reason: '第 3 行（SELECT）应显示红点（high→error）',
      );

      // 知情继续执行 → 查询真正执行（C22 M2：l10n 化后无 ⚠ 前缀）。
      await tester.tap(find.text('知情继续执行'));
      await runAndWaitIdle(tester, '查询完成');

      // 随便改一个字符（末尾加空格）→ 红点立即消失。
      await editorType(tester, '$multiLineSql ');
      await tester.pump();
      expect(editorErrors(tester), isEmpty, reason: '编辑器内容变化后红点应立即消失（旧行号失效）');

      // 重新执行 → 红点重新出现。
      await tapRun(tester);
      await waitFor(
        tester,
        '执行门再次弹出',
        () => find.byType(ExecutionGateDialog).evaluate().isNotEmpty,
      );
      expect(
        editorErrors(tester)[3],
        ErrorSeverity.error,
        reason: '重新执行后第 3 行红点应重新出现',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    // ═══════════════════════════════════════════════════════════════════
    // 回归：语法错误红点（与安全审查红点同一合并管线）
    // ═══════════════════════════════════════════════════════════════════
    testWidgets('回归: 语法错误行号红点显示（T011 校验管线）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!connected) return;
      await pumpEditor(tester, '');
      // 未闭合括号 → SQLValidatorService 报 error（SELEC 只报 warning 黄点）。
      // 用 enterText 模拟真实输入——程序化设文本（updateTabSql）不触发 onChanged 校验。
      await editorType(tester, 'SELECT * FROM $_table WHERE id = (');
      await tester.pump();
      await waitFor(tester, '语法错误红点出现', () => editorErrors(tester).isNotEmpty);
      expect(
        editorErrors(tester)[1],
        ErrorSeverity.error,
        reason: '未闭合括号应产生第 1 行错误红点',
      );
    });
  });
}
