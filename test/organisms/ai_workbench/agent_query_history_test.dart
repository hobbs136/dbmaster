// AI 执行的 SQL 写入查询历史（agent 来源双写）行为测试（任务 T1）。
//
// 两组：
// ① hook a（工作台执行流 onStatementResult，testWidgets）：成功/失败/跳过
//    三类——断言经典 prefs 历史（source=agent）落位；EXPLAIN/SHOW/
//    INFORMATION_SCHEMA 真实执行但不记。
//    ⚠ SQLite 侧断言不放 testWidgets：sqflite_ffi openDatabase 在
//    testWidgets 的 FakeAsync 区内不完成（探针实测挂起）——SQLite sink 的
//    断言归第②组（同一直呼双写助手，生产路径同源）。
// ② hook b（agent 计划链执行通道包装 withAgentQueryHistory，普通 test）：
//    done/failed 记历史；门控控制流信号（DDL/DML 确认门、DML 警告门、
//    只读拦截——语句未真正执行）不记；EXPLAIN 跳过；确认门 → bypass
//    通道只记真实执行那次（SQLite 无去重，行数是判别面）；含双写助手
//    直呼的双 sink 断言（经典 + SQLite :memory:）。
//
// 组件面沿 workbench_execution_actions_test.dart 的桩模式（mock
// executeQuery + 真 AppProvider + SharedPreferences mock + SQLite :memory:）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/models/query_history.dart';
import 'package:dbmaster/models/query_history/query_record.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';
import 'package:dbmaster/organisms/ai_panel/confirm_execute_dialog.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_execution_actions.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/query_history/query_history_service.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/sql_statement_gate_runner.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';

/// executeQueryDetailed 计数桩（只覆写 facade 执行入口；其余成员沿真实
/// AppProvider。裁决选项 A 起工作台执行走 detailed 通道）。
class _CountingAppProvider extends AppProvider {
  int executeCalls = 0;
  final List<String> executedSql = <String>[];
  Object? throwOnExecute;

  /// 写语句模拟引擎影响行数（null = 不供给 → 回落 rows.length 口径）。
  int? writeAffectedRows;

  @override
  Future<QueryExecutionResult> executeQueryDetailed(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executeCalls++;
    executedSql.add(sql);
    if (throwOnExecute != null) throw throwOnExecute!;
    final bool isSelect = sql.trim().toUpperCase().startsWith('SELECT');
    return Future<QueryExecutionResult>.value(
      QueryExecutionResult(
        isSelect
            ? <Map<String, dynamic>>[
                <String, dynamic>{'id': 1, 'name': 'alpha'},
              ]
            : <Map<String, dynamic>>[],
        affectedRows: isSelect ? null : (writeAffectedRows ?? 1),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  /// 泵编排触发面（workbench_execution_actions_test.dart 同款桩模式）。
  Future<_CountingAppProvider> pumpHarness(
    WidgetTester tester, {
    required String sql,
  }) async {
    final app = _CountingAppProvider();
    app.aiPanel.ensureSession();
    // 锁定上下文：effectiveWorkbenchContext 走锁定快照（savedConnections
    // 未命中时连接名以 id 兜底）。
    app.aiPanel.lockWorkbenchContext('conn-1', 'db1');
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('run'),
                  onPressed: () => WorkbenchExecutionActions.run(
                    context,
                    sql,
                    allowedWriteServers: <String>{},
                  ),
                  child: const Text('run'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> triggerRun(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('run')));
    await tester.pump();
  }

  /// 冲刷双写助手的 unawaited 写入（mock prefs 即时完成，pump 兜底微任务
  /// 排空；SQLite 侧在 testWidgets 内走 MissingPluginException 吞错路径，
  /// 不影响经典断言）。
  Future<void> drainHistoryWrites(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
  }

  group('hook a：onStatementResult 写历史（成功/失败/跳过，经典 prefs 面）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      WorkbenchUsageStatsService.instance.resetForTesting();
    });

    testWidgets('成功：经典历史记录（source=agent + 锁定上下文字段 + 持久化 JSON 标记）', (
      tester,
    ) async {
      final app = await pumpHarness(tester, sql: 'SELECT * FROM users');
      await triggerRun(tester);
      await tester.pumpAndSettle();
      await drainHistoryWrites(tester);

      expect(app.executeCalls, 1);
      expect(app.queryHistory.historyCount, 1);
      final entry = app.queryHistory.queryHistory.single;
      expect(entry.source, QueryHistorySource.agent);
      expect(entry.sql, 'SELECT * FROM users');
      expect(entry.connectionId, 'conn-1');
      expect(
        entry.connectionName,
        'conn-1',
        reason: '锁定上下文连接名（savedConnections 未命中以 id 兜底）',
      );
      expect(entry.database, 'db1');
      expect(entry.affectedRows, 1);
      expect(entry.error, isNull);

      // 持久化 JSON 带 agent 标记（prefs 往返源）。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('query_history'), contains('"source":"agent"'));
    });

    testWidgets('失败：error 落经典历史，affectedRows=0', (tester) async {
      final app = await pumpHarness(tester, sql: 'SELECT broken(');
      app.throwOnExecute = Exception('boom');
      await triggerRun(tester);
      await tester.pumpAndSettle();
      await drainHistoryWrites(tester);

      expect(app.executeCalls, 1);
      expect(app.queryHistory.historyCount, 1);
      final entry = app.queryHistory.queryHistory.single;
      expect(entry.source, QueryHistorySource.agent);
      expect(entry.error, contains('boom'));
      expect(entry.affectedRows, 0);
    });

    testWidgets('写语句历史 affectedRows = 引擎真值（非 rows.length 冒充，裁决）', (
      tester,
    ) async {
      final app = await pumpHarness(tester, sql: 'INSERT INTO t VALUES (1)');
      app.writeAffectedRows = 5;
      await triggerRun(tester);
      // gate #1 写确认（写语句必弹）。
      expect(find.byType(ConfirmExecuteDialog), findsOneWidget);
      await tester.tap(find.text(l10n.aiPanelConfirmExecute));
      await tester.pumpAndSettle();
      await drainHistoryWrites(tester);

      expect(app.executeCalls, 1);
      expect(app.queryHistory.historyCount, 1);
      final entry = app.queryHistory.queryHistory.single;
      expect(entry.source, QueryHistorySource.agent);
      expect(
        entry.affectedRows,
        5,
        reason: '写语句历史 affectedRows = 引擎真值 5，非 rows.length(0) 冒充',
      );
      expect(entry.error, isNull);
    });

    testWidgets('跳过：EXPLAIN 真实执行但不记历史（拦截器同口径）', (tester) async {
      final app = await pumpHarness(tester, sql: 'EXPLAIN SELECT 1');
      await triggerRun(tester);
      await tester.pumpAndSettle();
      await drainHistoryWrites(tester);

      expect(app.executeCalls, 1, reason: 'EXPLAIN 真实执行（结果卡照常）');
      expect(app.queryHistory.historyCount, 0, reason: 'EXPLAIN 不记历史');
    });

    testWidgets('跳过：SHOW 与 INFORMATION_SCHEMA 同口径', (tester) async {
      final app = await pumpHarness(tester, sql: 'SHOW TABLES');
      await triggerRun(tester);
      await tester.pumpAndSettle();
      await drainHistoryWrites(tester);
      expect(app.executeCalls, 1);
      expect(app.queryHistory.historyCount, 0);

      final app2 = await pumpHarness(
        tester,
        sql: 'SELECT * FROM INFORMATION_SCHEMA.TABLES',
      );
      await triggerRun(tester);
      await tester.pumpAndSettle();
      await drainHistoryWrites(tester);
      expect(app2.executeCalls, 1);
      expect(app2.queryHistory.historyCount, 0);
    });
  });

  group('hook b：计划链执行通道包装（withAgentQueryHistory，双 sink 断言）', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // SQLite 历史预初始化为 :memory:（普通 test 的真实异步区——sqflite_ffi
      // 在 testWidgets FakeAsync 区内 openDatabase 不完成，见文件头注记）。
      // 双写助手内的无参 initialize 随之幂等短路，不再走 path_provider。
      final QueryHistoryService service = QueryHistoryService();
      await service.initialize(customPath: ':memory:');
      await service.clearHistory();
    });

    tearDown(() async {
      await QueryHistoryService().close();
    });

    /// 冲刷 unawaited 写入（普通 test 的真实异步区）。
    Future<void> drain() =>
        Future<void>.delayed(const Duration(milliseconds: 30));

    test('双写助手直呼：经典 prefs 历史 + SQLite 历史双落（source=agent）', () async {
      final app = AppProvider();
      WorkbenchExecutionActions.recordAgentQueryHistory(
        app,
        sql: 'SELECT id FROM t',
        connectionId: 'plan-conn',
        database: 'plandb',
        durationMs: 12,
        affectedRows: 2,
      );
      await drain();

      // ① 经典 prefs 历史。
      expect(app.queryHistory.historyCount, 1);
      final entry = app.queryHistory.queryHistory.single;
      expect(entry.source, QueryHistorySource.agent);
      expect(entry.sql, 'SELECT id FROM t');
      expect(entry.connectionId, 'plan-conn');
      expect(entry.database, 'plandb');
      expect(entry.affectedRows, 2);
      expect(entry.error, isNull);

      // ② SQLite 历史。
      final records = await QueryHistoryService().search(
        const SearchCriteria(keywords: 'SELECT id FROM t'),
      );
      expect(records, hasLength(1));
      expect(records.single.isSuccess, isTrue);
      expect(records.single.rowCount, 2);
      expect(records.single.connectionId, 'plan-conn');
      expect(records.single.databaseName, 'plandb');
    });

    test('done：包装后执行成功 → 双写历史（affectedRows=行数）', () async {
      final app = AppProvider();
      final wrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        databaseName: 'plandb',
        execute: (String sql) async => SqlStatementOutcome(
          rows: <Map<String, dynamic>>[
            <String, dynamic>{'id': 1},
            <String, dynamic>{'id': 2},
          ],
        ),
      );

      final outcome = await wrapped('SELECT id FROM t');
      expect(outcome.rows, hasLength(2));
      await drain();

      expect(app.queryHistory.historyCount, 1);
      final entry = app.queryHistory.queryHistory.single;
      expect(entry.source, QueryHistorySource.agent);
      expect(entry.affectedRows, 2);
      expect(entry.error, isNull);

      final records = await QueryHistoryService().search(
        const SearchCriteria(keywords: 'SELECT id FROM t'),
      );
      expect(records, hasLength(1));
      expect(records.single.isSuccess, isTrue);
      expect(records.single.rowCount, 2);
    });

    test('done：写语句 affectedRows = 引擎真值（非 rows.length 冒充，裁决）', () async {
      final app = AppProvider();
      final wrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        databaseName: 'plandb',
        execute: (String sql) async => const SqlStatementOutcome(
          rows: <Map<String, dynamic>>[],
          affectedRows: 5,
        ),
      );

      final outcome = await wrapped('INSERT INTO t VALUES (1)');
      expect(outcome.rows, isEmpty, reason: '写语句不回传行（网关形态）');
      expect(outcome.affectedRows, 5);
      await drain();

      expect(app.queryHistory.historyCount, 1);
      final entry = app.queryHistory.queryHistory.single;
      expect(entry.source, QueryHistorySource.agent);
      expect(
        entry.affectedRows,
        5,
        reason: '写语句历史 affectedRows = 引擎真值 5，非 rows.length(0) 冒充',
      );
      expect(entry.error, isNull);

      final records = await QueryHistoryService().search(
        const SearchCriteria(keywords: 'INSERT INTO t'),
      );
      expect(records, hasLength(1));
      expect(records.single.isSuccess, isTrue);
      expect(records.single.rowCount, 5, reason: 'SQLite 历史 rowCount = 真值');
    });

    test('failed：真执行失败记 error 且异常继续上抛', () async {
      final app = AppProvider();
      Future<SqlStatementOutcome> failing(String sql) async {
        throw Exception('boom');
      }
      final wrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: failing,
      );

      await expectLater(wrapped('SELECT broken('), throwsA(isA<Exception>()));
      await drain();

      expect(app.queryHistory.historyCount, 1);
      final entry = app.queryHistory.queryHistory.single;
      expect(entry.source, QueryHistorySource.agent);
      expect(entry.error, contains('boom'));
      expect(entry.affectedRows, 0);

      final records = await QueryHistoryService().search(
        const SearchCriteria(keywords: 'broken'),
      );
      expect(records, hasLength(1));
      expect(records.single.isSuccess, isFalse);
      expect(records.single.errorMessage, contains('boom'));
    });

    test('DML 确认门（未执行）→ 不记历史', () async {
      final app = AppProvider();
      Future<SqlStatementOutcome> gateBlocked(String sql) async {
        throw DmlConfirmationRequiredException(
          sql: sql,
          analysis: const RiskAnalysisResult(
            riskLevel: DmlRiskLevel.high,
            affectedObjects: [],
          ),
          statements: const [],
        );
      }
      final wrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: gateBlocked,
      );

      await expectLater(
        wrapped('UPDATE t SET a = 1'),
        throwsA(isA<DmlConfirmationRequiredException>()),
      );
      await drain();

      expect(
        app.queryHistory.historyCount,
        0,
        reason: '门控控制流信号：语句未真正执行不记（经典先例同口径）',
      );
      expect(
        await QueryHistoryService().search(const SearchCriteria()),
        isEmpty,
      );
    });

    test('DDL 确认门（未执行）→ 不记历史', () async {
      final app = AppProvider();
      Future<SqlStatementOutcome> gateBlocked(String sql) async {
        throw DdlConfirmationRequiredException(
          sql: sql,
          impactReport: ImpactReport(
            ddlStatement: sql,
            targetTable: 't',
            ddlType: 'DROP',
            riskLevel: RiskLevel.high,
            affectedObjects: const [],
            dependencies: const [],
            warnings: const [],
            recommendations: const [],
            requiresConfirmation: true,
            analyzedAt: DateTime.now(),
          ),
        );
      }
      final wrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: gateBlocked,
      );

      await expectLater(
        wrapped('DROP TABLE t'),
        throwsA(isA<DdlConfirmationRequiredException>()),
      );
      await drain();

      expect(app.queryHistory.historyCount, 0);
      expect(
        await QueryHistoryService().search(const SearchCriteria()),
        isEmpty,
      );
    });

    test('DML 警告门与只读拦截（未执行）→ 不记历史', () async {
      final app = AppProvider();
      Future<SqlStatementOutcome> warningBlocked(String sql) async {
        throw DmlWarningRequiredException(
          sql: sql,
          analysis: const RiskAnalysisResult(
            riskLevel: DmlRiskLevel.high,
            affectedObjects: [],
          ),
        );
      }
      final warningWrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: warningBlocked,
      );
      await expectLater(
        warningWrapped('UPDATE t SET a = 1'),
        throwsA(isA<DmlWarningRequiredException>()),
      );
      await drain();

      Future<SqlStatementOutcome> readOnlyBlocked(String sql) async {
        throw const ReadOnlyBlockedException(operation: 'UPDATE');
      }
      final readOnlyWrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: readOnlyBlocked,
      );
      await expectLater(
        readOnlyWrapped('UPDATE t SET a = 1'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      await drain();

      expect(app.queryHistory.historyCount, 0);
      expect(
        await QueryHistoryService().search(const SearchCriteria()),
        isEmpty,
      );
    });

    test('EXPLAIN 经计划链成功执行 → 跳过不记', () async {
      final app = AppProvider();
      final wrapped = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: (String sql) async =>
            const SqlStatementOutcome(rows: <Map<String, dynamic>>[]),
      );

      await wrapped('EXPLAIN SELECT 1');
      await drain();

      expect(app.queryHistory.historyCount, 0, reason: 'EXPLAIN 不记历史');
      expect(
        await QueryHistoryService().search(const SearchCriteria()),
        isEmpty,
      );
    });

    test('确认门 → bypass 通道：SQLite 只落真实执行那一行（无去重可判别）', () async {
      final app = AppProvider();
      Future<SqlStatementOutcome> gateBlocked(String sql) async {
        throw DmlConfirmationRequiredException(
          sql: sql,
          analysis: const RiskAnalysisResult(
            riskLevel: DmlRiskLevel.high,
            affectedObjects: [],
          ),
          statements: const [],
        );
      }
      final gatePath = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: gateBlocked,
      );
      await expectLater(
        gatePath('UPDATE t SET a = 1'),
        throwsA(isA<DmlConfirmationRequiredException>()),
      );
      await drain();

      // bypass 通道（runner 确认后重执行同语句）——同一包装工厂。
      final bypassPath = WorkbenchExecutionActions.withAgentQueryHistory(
        app,
        connectionId: 'plan-conn',
        execute: (String sql) async =>
            const SqlStatementOutcome(rows: <Map<String, dynamic>>[]),
      );
      await bypassPath('UPDATE t SET a = 1');
      await drain();

      // SQLite 无去重：若门控尝试被误记，此处会是 2 行。
      final records = await QueryHistoryService().search(
        const SearchCriteria(keywords: 'UPDATE t SET a = 1'),
      );
      expect(records, hasLength(1), reason: '门控尝试不记，bypass 真实执行记一条');
      expect(records.single.isSuccess, isTrue);

      // 经典历史同语句同连接去重置顶后留 1 条，且应为 bypass 成功记录。
      expect(app.queryHistory.historyCount, 1);
      expect(app.queryHistory.queryHistory.single.error, isNull);
    });
  });
}
