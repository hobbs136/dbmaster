// 生产守卫消费接线测试（B-07 挂接点①端到端；production_guard_routing_test
// 的 sibling——seam 级分流断言见 routing 文件，此处覆盖消费链）。
//
// 验收条款直译：
// - production + no-WHERE DELETE 经 helper 链（经典 QueryExecutionHelper）→
//   guard 弹窗出现（非 DmlConfirmDialog）；
// - 确认后 bypass 执行（executeQueryBypassDmlAndUpdateResults 通道）；
// - 取消 → logDmlBlocked 审计调用（sql/decision 断言）；
// - gate 链（SqlStatementGateRunner 生产守卫臂）：productionGuardConfirm
//   回调承载守卫（dmlConfirm 不得触达）、确认 → bypass 通道执行、取消 →
//   productionGuardCancelled + 异常负载透出（审计字段承载）、回调缺位 →
//   fail-closed 取消（零执行）；
// - 工作台手动链（run() 终局映射）：productionGuardCancelled → logDmlBlocked
//   审计 + 「已取消」消息。
//
// ProductionGuardRequiredException 全部取真实 seam 产物（interceptor
// .checkDmlSafety(environment: production)），不从实现反推。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/core/commands/query_execution_helper.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_execution_actions.dart';
import 'package:dbmaster/organisms/dialogs/dml_confirm_dialog.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/query_execution_interceptor.dart';
import 'package:dbmaster/services/sql_statement_gate_runner.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// 真实 seam 产物：production + 阻断级 SQL → ProductionGuardRequiredException
/// （routing 文件已断言类型分流，此处取实例供消费链注入）。
ProductionGuardRequiredException productionGuardOf(
  QueryExecutionInterceptor interceptor,
  String sql,
) {
  try {
    interceptor.checkDmlSafety(
      sql: sql,
      dbType: DatabaseType.mysql,
      connectionId: 'conn-prod',
      environment: ConnectionEnvironment.production,
    );
  } on ProductionGuardRequiredException catch (e) {
    return e;
  }
  fail('production + $sql 应抛 ProductionGuardRequiredException（seam 前置校验）');
}

/// 审计记录（logDmlBlocked 观察面——生产实现经 DmlSafetyService 落
/// AppLogger 无 widget 观察面，故在拦截器子类记录，不旁路真实出口语义）。
class _AuditRecord {
  const _AuditRecord(this.sql, this.connectionId, this.riskLevel, this.decision);
  final String sql;
  final String connectionId;
  final DmlRiskLevel riskLevel;
  final AuditDecision decision;
}

class _SpyInterceptor extends QueryExecutionInterceptor {
  final List<_AuditRecord> blocked = [];

  @override
  void logDmlBlocked({
    required String sql,
    required String connectionId,
    required DmlRiskLevel riskLevel,
    required AuditDecision decision,
  }) {
    blocked.add(_AuditRecord(sql, connectionId, riskLevel, decision));
  }
}

class _SpyDatabaseService extends DatabaseService {
  final _SpyInterceptor spyInterceptor = _SpyInterceptor();

  /// bypass 通道观察面：经典编辑器臂（executeQueryBypassDml）与工作台
  /// detailed 臂（executeQueryBypassDmlDetailed）各自的触达记录。
  final List<String> bypassDmlCalls = [];
  final List<String> bypassDmlDetailedCalls = [];

  @override
  QueryExecutionInterceptor get interceptor => spyInterceptor;

  @override
  Future<List<Map<String, dynamic>>> executeQueryBypassDml(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    bypassDmlCalls.add(sql);
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<QueryExecutionResult> executeQueryBypassDmlDetailed(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    bypassDmlDetailedCalls.add(sql);
    return QueryExecutionResult(
      const <Map<String, dynamic>>[],
      affectedRows: 0,
    );
  }
}

/// helper 链探针（沿 workbench_execution_actions_test._CountingAppProvider
/// 形态）：executeCurrentQueryAndRecord 抛真实守卫信号；bypass 双通道计数。
class _GuardProbeAppProvider extends AppProvider {
  _GuardProbeAppProvider({
    required ConnectionProvider connectionProvider,
    required this.guardException,
  }) : super(connectionProvider: connectionProvider);

  final ProductionGuardRequiredException guardException;
  int bypassDmlCalls = 0;
  int bypassDdlCalls = 0;

  @override
  QueryTab? get activeTab => QueryTab(
        id: 'probe-tab',
        title: 'Probe',
        sql: 'DELETE FROM orders',
        connectionId: 'conn-prod',
        databaseName: 'db_prod',
      );

  @override
  Future<List<ExecutionResult>> executeCurrentQueryAndRecord({
    String? overrideSql,
    bool skipDdlAnalysis = false,
    void Function(int current, int total)? onStatementProgress,
  }) {
    throw guardException;
  }

  @override
  Future<void> executeQueryBypassDmlAndUpdateResults(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    bypassDmlCalls++;
  }

  @override
  Future<void> executeQueryBypassDdlAndUpdateResults(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    bypassDdlCalls++;
  }
}

/// 工作台手动链探针：executeQueryDetailed 抛真实守卫信号。
class _WorkbenchProbeAppProvider extends AppProvider {
  _WorkbenchProbeAppProvider({
    required ConnectionProvider connectionProvider,
    required this.guardException,
  }) : super(connectionProvider: connectionProvider);

  final ProductionGuardRequiredException guardException;
  int executeCalls = 0;

  @override
  Future<QueryExecutionResult> executeQueryDetailed(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executeCalls++;
    throw guardException;
  }
}

/// 编辑器主执行路径探针：executeCurrentQueryAndRecord 抛真实守卫信号
/// （编辑器消费真 TabProvider tab，不覆写 activeTab）。
class _EditorProbeAppProvider extends AppProvider {
  _EditorProbeAppProvider({
    required ConnectionProvider connectionProvider,
    required this.guardException,
  }) : super(connectionProvider: connectionProvider);

  final ProductionGuardRequiredException guardException;

  @override
  Future<List<ExecutionResult>> executeCurrentQueryAndRecord({
    String? overrideSql,
    bool skipDdlAnalysis = false,
    void Function(int current, int total)? onStatementProgress,
  }) {
    throw guardException;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('gate 链消费（gate-runner 生产守卫臂，B-07）', () {
    late QueryExecutionInterceptor interceptor;

    setUp(() {
      interceptor = QueryExecutionInterceptor();
    });

    testWidgets(
      'production no-WHERE DELETE → productionGuardConfirm 承载（非 dmlConfirm）；确认 → bypass 执行',
      (tester) async {
        final guard = productionGuardOf(interceptor, 'DELETE FROM orders');
        final guardConfirmCalls = <ProductionGuardRequiredException>[];
        final dmlConfirmCalls = <DmlConfirmationRequiredException>[];
        final bypassed = <String>[];
        final result = await const SqlStatementGateRunner().run(
          sql: 'DELETE FROM orders',
          deps: SqlGateRunDeps(
            execute: (statement) async => throw guard,
            dmlConfirm: (e) async {
              dmlConfirmCalls.add(e);
              return SqlGateConfirmDecision.confirmed;
            },
            productionGuardConfirm: (e) async {
              guardConfirmCalls.add(e);
              return SqlGateConfirmDecision.confirmed;
            },
            executeBypassDdl: (statement) async {
              bypassed.add('ddl|$statement');
              return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
            },
            executeBypassDml: (statement) async {
              bypassed.add('dml|$statement');
              return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
            },
          ),
        );

        expect(guardConfirmCalls, hasLength(1), reason: '守卫弹窗绑定点（productionGuardConfirm）被触达');
        expect(
          dmlConfirmCalls,
          isEmpty,
          reason: 'production 分流不得走既有 DML 确认门（DmlConfirmDialog 绑定点）',
        );
        expect(result.status, SqlBatchStatus.completed);
        expect(
          bypassed,
          equals(const ['dml|DELETE FROM orders']),
          reason: 'guard 确认 true → 经 DML bypass 通道执行（语句非 DDL）',
        );
      },
    );

    testWidgets('guard 取消 → productionGuardCancelled + 异常负载透出 + 零 bypass', (tester) async {
      final guard = productionGuardOf(interceptor, 'DELETE FROM orders');
      final bypassed = <String>[];
      final result = await const SqlStatementGateRunner().run(
        sql: 'DELETE FROM orders',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw guard,
          productionGuardConfirm: (e) async => SqlGateConfirmDecision.cancelled,
          executeBypassDdl: (statement) async {
            bypassed.add('ddl|$statement');
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          executeBypassDml: (statement) async {
            bypassed.add('dml|$statement');
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.productionGuardCancelled);
      expect(bypassed, isEmpty, reason: '取消（false/Esc/AI 分流）→ 零执行');
      expect(
        result.productionGuardException,
        same(guard),
        reason: '异常负载随终局透出（sql/analysis 审计字段承载）',
      );
      expect(result.results.single.status, SqlStatementStatus.skipped);
    });

    testWidgets('回调缺位 → fail-closed 视同取消（零执行）', (tester) async {
      final guard = productionGuardOf(interceptor, 'DELETE FROM orders');
      final bypassed = <String>[];
      final result = await const SqlStatementGateRunner().run(
        sql: 'DELETE FROM orders',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw guard,
          executeBypassDdl: (statement) async {
            bypassed.add('ddl|$statement');
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          executeBypassDml: (statement) async {
            bypassed.add('dml|$statement');
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(
        result.status,
        SqlBatchStatus.productionGuardCancelled,
        reason: '消费方未接 guard 回调 → fail-closed 视同取消',
      );
      expect(bypassed, isEmpty, reason: 'production 高危不因回调缺位静默放行');
    });
  });

  group('helper 链消费（经典 QueryExecutionHelper，B-07）', () {
    Future<(_GuardProbeAppProvider, _SpyDatabaseService)> pumpHelper(
      WidgetTester tester,
    ) async {
      final spyDb = _SpyDatabaseService();
      final provider = _GuardProbeAppProvider(
        connectionProvider: ConnectionProvider(dbService: spyDb),
        guardException: productionGuardOf(QueryExecutionInterceptor(), 'DELETE FROM orders'),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('run'),
                    onPressed: () =>
                        QueryExecutionHelper.executeWithConfirm(context),
                    child: const Text('run'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (provider, spyDb);
    }

    testWidgets('guard 弹窗出现（L2，非 DmlConfirmDialog）；取消 → logDmlBlocked 审计', (tester) async {
      final (provider, spyDb) = await pumpHelper(tester);

      await tester.tap(find.byKey(const ValueKey('run')));
      await tester.pumpAndSettle();

      // 守卫弹窗出现：L2（无 WHERE DELETE 非破坏族）标题；非既有 DML 确认门。
      expect(find.text(l10n.prodGuardTitleL2), findsOneWidget);
      expect(
        find.byType(DmlConfirmDialog),
        findsNothing,
        reason: 'production 阻断级 DML 不得走既有 DmlConfirmDialog',
      );

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.prodGuardTitleL2), findsNothing, reason: '弹窗关闭');
      expect(provider.bypassDmlCalls, 0, reason: '取消 → 零 bypass 执行');
      expect(provider.bypassDdlCalls, 0);
      expect(spyDb.spyInterceptor.blocked, hasLength(1), reason: '取消 → logDmlBlocked 审计调用（不旁路）');
      final audit = spyDb.spyInterceptor.blocked.single;
      expect(audit.sql, 'DELETE FROM orders');
      expect(audit.decision, AuditDecision.cancelled);
    });

    testWidgets('guard 确认 → bypass 重执（bypass 只在 guard true 之后）', (tester) async {
      final (provider, spyDb) = await pumpHelper(tester);

      await tester.tap(find.byKey(const ValueKey('run')));
      await tester.pumpAndSettle();

      // L2 免输入：确认钮直接可达。
      await tester.tap(find.text(l10n.prodGuardConfirmDrop));
      await tester.pumpAndSettle();

      expect(
        provider.bypassDmlCalls,
        1,
        reason: 'guard true → DML bypass 重执（语句非 DDL）',
      );
      expect(provider.bypassDdlCalls, 0);
      expect(
        spyDb.spyInterceptor.blocked,
        isEmpty,
        reason: '确认路径不落取消审计',
      );
    });
  });

  group('工作台手动链消费（run() gate #2 生产守卫，B-07）', () {
    Future<(_WorkbenchProbeAppProvider, _SpyDatabaseService)> pumpWorkbench(
      WidgetTester tester,
    ) async {
      final spyDb = _SpyDatabaseService();
      final provider = _WorkbenchProbeAppProvider(
        connectionProvider: ConnectionProvider(dbService: spyDb),
        guardException: productionGuardOf(QueryExecutionInterceptor(), 'DELETE FROM orders'),
      );
      provider.aiPanel.ensureSession();
      provider.aiPanel.lockWorkbenchContext('conn-prod', 'db_prod');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
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
                      'DELETE FROM orders',
                      // 会话放行集预置（gate #1 写确认免弹，直达 gate #2 消费面）。
                      allowedWriteServers: const {'conn-prod'},
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
      return (provider, spyDb);
    }

    testWidgets('guard 弹窗出现（非 DmlConfirmDialog）；取消 → logDmlBlocked 审计 + 零 bypass', (tester) async {
      final (provider, spyDb) = await pumpWorkbench(tester);

      await tester.tap(find.byKey(const ValueKey('run')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.prodGuardTitleL2), findsOneWidget, reason: '手动链绑守卫回调 → guard 弹窗出现');
      expect(find.byType(DmlConfirmDialog), findsNothing);
      expect(provider.executeCalls, 1, reason: '语句经 execute 通道触达守卫 seam');

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.prodGuardTitleL2), findsNothing, reason: '弹窗关闭');
      expect(spyDb.bypassDmlDetailedCalls, isEmpty, reason: '取消 → 零 bypass 执行');
      expect(spyDb.spyInterceptor.blocked, hasLength(1), reason: '取消 → logDmlBlocked 审计调用（不旁路）');
      final audit = spyDb.spyInterceptor.blocked.single;
      expect(audit.sql, 'DELETE FROM orders');
      expect(audit.connectionId, 'conn-prod');
      expect(audit.decision, AuditDecision.cancelled);
      // 冲刷会话持久化 500ms debounce Timer（app_commands_test 同款）。
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('guard 确认 → bypass 通道执行（bypass 只在 guard true 之后）', (tester) async {
      final (_, spyDb) = await pumpWorkbench(tester);

      await tester.tap(find.byKey(const ValueKey('run')));
      await tester.pumpAndSettle();

      // L2 免输入：确认钮直接可达。
      await tester.tap(find.text(l10n.prodGuardConfirmDrop));
      await tester.pumpAndSettle();

      expect(
        spyDb.bypassDmlDetailedCalls,
        equals(const ['DELETE FROM orders']),
        reason: 'guard true → 经 detailed DML bypass 通道执行（语句非 DDL）',
      );
      expect(
        spyDb.spyInterceptor.blocked,
        isEmpty,
        reason: '确认路径不落取消审计',
      );
      // 结果卡落卡触发会话持久化 debounce——冲刷（app_commands_test 同款）。
      await tester.pump(const Duration(milliseconds: 600));
    });
  });

  group('编辑器主执行路径消费（_executeQuery catch 臂，B-07）', () {
    /// 泵编辑器（沿 query_editor_shortcuts_test 形态：ThemeProvider +
    /// LayoutPreferencesProvider 必需）。「非 production 库型」tab 供编辑器
    /// 消费（databaseType null → 安全审查静默跳过，直达执行臂）。
    Future<_SpyDatabaseService> pumpEditor(WidgetTester tester) async {
      final spyDb = _SpyDatabaseService();
      final provider = _EditorProbeAppProvider(
        connectionProvider: ConnectionProvider(dbService: spyDb),
        guardException: productionGuardOf(
          QueryExecutionInterceptor(),
          'DELETE FROM orders',
        ),
      );
      await provider.tab.openQueryTab(
        connectionId: 'conn-prod',
        databaseName: 'db_prod',
        sql: 'DELETE FROM orders',
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppProvider>.value(value: provider),
            ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider(),
            ),
            ChangeNotifierProvider<LayoutPreferencesProvider>(
              create: (_) => LayoutPreferencesProvider(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SizedBox(
                width: 1280,
                height: 800,
                child: QueryEditorWidget(tabIndex: 0),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return spyDb;
    }

    testWidgets('guard 弹窗出现（非 DmlConfirmDialog）；取消 → logDmlBlocked 审计 + 零 bypass', (tester) async {
      final spyDb = await pumpEditor(tester);

      // 工具栏运行钮触发 _executeQuery（沿编辑器既有执行入口）。执行期
      // elapsed 周期计时器持续排帧 → 弹窗打开期间禁 pumpAndSettle（会
      // timeout），用显式时长推进；取消后 finally 复位执行态方可 settle。
      await tester.tap(find.text(l10n.toolbarExecute));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l10n.prodGuardTitleL2), findsOneWidget, reason: '编辑器主执行路径分流到生产守卫弹窗');
      expect(find.byType(DmlConfirmDialog), findsNothing);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text(l10n.prodGuardTitleL2), findsNothing, reason: '弹窗关闭');
      expect(spyDb.bypassDmlCalls, isEmpty, reason: '取消 → 零 bypass 执行');
      expect(spyDb.spyInterceptor.blocked, hasLength(1), reason: '取消 → logDmlBlocked 审计调用（不旁路）');
      final audit = spyDb.spyInterceptor.blocked.single;
      expect(audit.sql, 'DELETE FROM orders');
      expect(audit.decision, AuditDecision.cancelled);
    });

    testWidgets('guard 确认 → 编辑器 DML bypass 重执（沿 DmlConfirm 臂同款 API）', (tester) async {
      final spyDb = await pumpEditor(tester);

      await tester.tap(find.text(l10n.toolbarExecute));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // L2 免输入：确认钮直接可达。
      await tester.tap(find.text(l10n.prodGuardConfirmDrop));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        spyDb.bypassDmlCalls,
        equals(const ['DELETE FROM orders']),
        reason: 'guard true → 编辑器 DML bypass 重执（DmlConfirm 臂同款 API）',
      );
      expect(spyDb.spyInterceptor.blocked, isEmpty, reason: '确认路径不落取消审计');
    });
  });
}
