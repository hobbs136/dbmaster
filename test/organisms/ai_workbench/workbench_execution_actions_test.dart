// T13 执行动作编排组件面测试（design-ai-workbench §6.2/§11.1 R6）。
//
// 组件面以 mock executeQuery 调用计数断言闸门语义（真库断言归 T15）：
// - AC6.1/6.2 写 SQL 必弹确认、cancel 零执行（计数 == 0）；
// - AC6.3 确认（allowOnce/allowSession）→ 执行 + 结果卡落卡；
// - AC6.4 只读 SQL 不弹确认直接执行；
// - AC6.5 确认界面含 SQL 全文 + 目标连接/库行；
// - allowSession 入会话放行集 → 二次执行免弹（镜像 _allowedSessionServers）；
// - 双异常路由：DdlConfirmationRequiredException → DdlConfirmDialog、
//   DmlConfirmationRequiredException → DmlConfirmDialog（不裸奔）；
// - M4 对齐：DROP TABLE 真管线形态（管线 DML 检查先于 DDL 分析 →
//   DmlConfirmationRequiredException critical 键入确认）走 dmlConfirm 回调，
//   非 DdlConfirmDialog；取消零执行；
// - AC9.4 失败落错误卡不静默；AC9.5 多语句逐条执行逐条落卡；
// - 上下文不可用 → 错误卡 + 「去设置连接」出口；空白 SQL 不进确认流；
// - 统计三分类映射（queryGen/ddlPerm/bulkMaint，§6.4）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';
import 'package:dbmaster/organisms/ai_panel/confirm_execute_dialog.dart';
import 'package:dbmaster/organisms/ai_panel/ddl_confirm_dialog.dart';
import 'package:dbmaster/organisms/dialogs/dml_confirm_dialog.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_execution_actions.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart'
    show StageExecutionData, StageExecutionStatus;
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';

/// executeQueryDetailed 计数桩（只覆写 facade 执行入口；其余成员沿真实
/// AppProvider。裁决选项 A 起工作台执行走 detailed 通道）。
class _CountingAppProvider extends AppProvider {
  int executeCalls = 0;
  final List<String> executedSql = <String>[];
  Object? throwOnExecute;

  /// B1 用：按语句内容选择性抛错的钩子（返回非 null 即抛；null = 不抛）。
  /// 用于混合批「单语句失败」与「gate #2 选择性拦截」形态。
  Object? Function(String sql)? throwForSql;

  /// 按语句内容定制引擎影响行数（裁决选项 A：写语句回传真值；null 回调
  /// 走默认——只读 null、写 1）。DDL 0 抑制 / DML 直显语义测试用。
  int? Function(String sql)? affectedRowsFor;

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
    final Object? custom = throwForSql?.call(sql);
    if (custom != null) throw custom;
    // 网关形态对齐（detailed 通道）：只读语句回传 1 行（affectedRows
    // null）；写语句空行集 + 引擎 affectedRows（默认 1）。
    final bool isSelect = sql.trim().toUpperCase().startsWith('SELECT');
    final int? affectedRows = isSelect
        ? null
        : (affectedRowsFor?.call(sql) ?? 1);
    return Future<QueryExecutionResult>.value(
      QueryExecutionResult(
        isSelect
            ? <Map<String, dynamic>>[
                <String, dynamic>{'id': 1, 'name': 'alpha'},
              ]
            : <Map<String, dynamic>>[],
        affectedRows: affectedRows,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkbenchUsageStatsService.instance.resetForTesting();
  });

  /// 泵编排触发面：按钮经 [WorkbenchExecutionActions.run] 驱动（与卡动作
  /// 同入口）。[sql] 经闭包捕获（测试体内可变）。[batches]（B1）传入即
  /// 捕获 execution tab 批次推送（onExecutionBatch 回调）。
  Future<_CountingAppProvider> pumpHarness(
    WidgetTester tester, {
    required String Function() sql,
    required Set<String> allowed,
    List<StageExecutionData>? batches,
  }) async {
    final app = _CountingAppProvider();
    app.aiPanel.ensureSession();
    // 锁定上下文：effectiveWorkbenchContext 走锁定快照（连接名 id 兜底）。
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
                    sql(),
                    allowedWriteServers: allowed,
                    onExecutionBatch: batches?.add,
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

  group('AC6.1/6.2 写确认闸门（cancel 零执行）', () {
    testWidgets('写 SQL 必弹确认；cancel → executeQuery 零调用（计数断言）', (tester) async {
      final allowed = <String>{};
      final app = await pumpHarness(
        tester,
        sql: () => "UPDATE users SET name = 'x' WHERE id = 1",
        allowed: allowed,
      );

      await triggerRun(tester);
      expect(
        find.byType(ConfirmExecuteDialog),
        findsOneWidget,
        reason: 'AC6.1：写 SQL 必出现确认步骤',
      );

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(app.executeCalls, 0, reason: 'AC6.2：取消 → 什么都不执行');
      expect(app.aiMessages, isEmpty, reason: '取消不落卡不落消息（设计原文）');
      expect(allowed, isEmpty, reason: 'cancel 不入会话放行集');
    });

    testWidgets('批量含写语句且 cancel → 整批零执行（两遍法）', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => "SELECT 1; UPDATE t SET a = 1; SELECT 2",
        allowed: <String>{},
      );

      await triggerRun(tester);
      expect(find.byType(ConfirmExecuteDialog), findsOneWidget);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(app.executeCalls, 0, reason: 'AC6.1 批量形态：确认前不执行任何语句（含只读语句）');
    });
  });

  group('AC6.3/6.5 确认执行', () {
    testWidgets('allowOnce → 执行一次 + 结果卡落卡', (tester) async {
      final allowed = <String>{};
      final app = await pumpHarness(
        tester,
        sql: () => "UPDATE users SET name = 'x' WHERE id = 1",
        allowed: allowed,
      );

      await triggerRun(tester);
      await tester.tap(find.text(l10n.aiPanelConfirmExecute));
      await tester.pumpAndSettle();

      expect(app.executeCalls, 1, reason: 'AC6.3：确认后执行');
      expect(
        app.executedSql.single,
        "UPDATE users SET name = 'x' WHERE id = 1",
      );
      expect(app.aiMessages.length, 1);
      final card = app.aiMessages.single.toolResultData?['workbench'];
      expect(
        card is Map && card['kind'] == 'result_card',
        isTrue,
        reason: 'AC4.4：成功落结果卡',
      );
      expect(allowed, isEmpty, reason: 'allowOnce 仅本次，不入会话放行集');
    });

    testWidgets('确认界面含 SQL 全文与目标连接/库行（AC6.5）', (tester) async {
      await pumpHarness(
        tester,
        sql: () => 'DELETE FROM logs WHERE id = 9',
        allowed: <String>{},
      );

      await triggerRun(tester);
      // SQL 全文（对话框内命令块）。
      expect(find.text('DELETE FROM logs WHERE id = 9'), findsOneWidget);
      // 目标行（workbenchConfirmTarget(connection, database)）。
      expect(
        find.text('Target: conn-1 · db1'),
        findsOneWidget,
        reason: 'AC6.5：目标连接/库名可见',
      );

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
    });
  });

  group('AC6.4 只读直接执行', () {
    testWidgets('SELECT 不弹确认直接执行；allowSession 钮不存在于只读路径', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT * FROM users LIMIT 5',
        allowed: <String>{},
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 1, reason: 'AC6.4：只读直接执行');
      expect(
        find.byType(ConfirmExecuteDialog),
        findsNothing,
        reason: '只读不出现确认步骤',
      );
      expect(
        app.aiMessages.single.toolResultData?['workbench']
            is Map<String, dynamic>,
        isTrue,
      );
    });
  });

  group('allowSession 会话放行集（镜像 _allowedSessionServers）', () {
    testWidgets('allowSession → 入集 → 二次写执行免弹', (tester) async {
      final allowed = <String>{};
      final app = await pumpHarness(
        tester,
        sql: () => "UPDATE users SET name = 'x' WHERE id = 1",
        allowed: allowed,
      );

      // 第一次：弹确认 → allowSession。
      await triggerRun(tester);
      await tester.tap(find.text(l10n.aiPanelAllowSession));
      await tester.pumpAndSettle();
      expect(app.executeCalls, 1);
      expect(allowed, contains('conn-1'), reason: 'allowSession 入集（key=连接）');

      // 第二次：同连接写语句不再弹确认。
      await triggerRun(tester);
      await tester.pump(); // 若误弹对话框，此处帧后仍会存在 → 下一断言捕获
      expect(
        find.byType(ConfirmExecuteDialog),
        findsNothing,
        reason: '会话放行集内免弹',
      );
      await tester.pumpAndSettle();
      expect(app.executeCalls, 2, reason: '二次执行真实发生');
    });

    testWidgets('放行集已含连接 → 首次执行也免弹', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'DROP TABLE legacy_tmp',
        allowed: {'conn-1'},
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmExecuteDialog), findsNothing);
      expect(app.executeCalls, 1);
    });
  });

  group('双异常路由（gate #2 管线门禁，不裸奔）', () {
    testWidgets(
      'DdlConfirmationRequiredException → DdlConfirmDialog；取消记「已取消」',
      (tester) async {
        final app = await pumpHarness(
          tester,
          sql: () => 'DROP TABLE risky_one',
          allowed: {'conn-1'}, // gate #1 已放行，直达管线异常
        );
        app.throwOnExecute = DdlConfirmationRequiredException(
          sql: 'DROP TABLE risky_one',
          impactReport: ImpactReport(
            ddlStatement: 'DROP TABLE risky_one',
            targetTable: 'risky_one',
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

        await triggerRun(tester);
        await tester.pump();
        expect(
          find.byType(DdlConfirmDialog),
          findsOneWidget,
          reason: 'DDL 异常接住 → DDL 确认对话框，不裸奔',
        );

        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();

        expect(app.executeCalls, 1, reason: '首次尝试执行了 1 次（被管线拦截）');
        expect(
          app.aiMessages.single.content,
          l10n.aiPanelDdlOperationCancelled,
          reason: '取消 → 消息流记「已取消」，无裸异常文案',
        );
      },
    );

    testWidgets(
      'DmlConfirmationRequiredException → DmlConfirmDialog（经典 AI 面板不处理的缺口）',
      (tester) async {
        final app = await pumpHarness(
          tester,
          sql: () => "UPDATE orders SET status = 'x'",
          allowed: {'conn-1'},
        );
        app.throwOnExecute = DmlConfirmationRequiredException(
          sql: "UPDATE orders SET status = 'x'",
          analysis: const RiskAnalysisResult(
            riskLevel: DmlRiskLevel.high,
            affectedObjects: [],
          ),
          statements: const [],
        );

        await triggerRun(tester);
        await tester.pump();
        expect(
          find.byType(DmlConfirmDialog),
          findsOneWidget,
          reason: 'DML 异常接住 → DML 确认对话框（新增验收：不裸奔）',
        );

        await tester.tap(find.text(l10n.commonCancel).first);
        await tester.pumpAndSettle();

        expect(
          app.aiMessages.single.content,
          l10n.operationCancelled,
          reason: '取消 → 审计 + 「已取消」消息，无裸异常文案',
        );
        expect(
          app.aiMessages.single.toolResultData?['workbench'],
          isNull,
          reason: '取消不落错误卡（用户主动取消非失败）',
        );
      },
    );

    testWidgets(
      'DROP TABLE 真管线形态 → dmlConfirm 回调 critical 键入确认；取消零执行（M4）',
      (tester) async {
        final app = await pumpHarness(
          tester,
          sql: () => 'DROP TABLE legacy_tmp',
          allowed: {'conn-1'}, // gate #1 已放行，直达管线异常（真管线序：DML 检查先于 DDL 分析）
        );
        app.throwOnExecute = DmlConfirmationRequiredException(
          sql: 'DROP TABLE legacy_tmp',
          analysis: const RiskAnalysisResult(
            riskLevel: DmlRiskLevel.critical,
            triggers: [RiskTrigger.dropTable],
            affectedObjects: ['legacy_tmp'],
          ),
          statements: const [],
        );

        await triggerRun(tester);
        await tester.pump();
        expect(
          find.byType(DmlConfirmDialog),
          findsOneWidget,
          reason:
              'M4：DROP TABLE 真管线（DML 检查先于 DDL 分析，dropTable 判 critical）'
              '走 DmlConfirmDialog，非 DdlConfirmDialog',
        );
        expect(
          find.byType(DdlConfirmDialog),
          findsNothing,
          reason: 'M4：DROP 类真管线不经 DdlConfirmDialog',
        );
        expect(
          find.byType(TextField),
          findsOneWidget,
          reason: 'critical → 键入对象名确认形态（requireTypedConfirmation 激活）',
        );

        await tester.tap(find.text(l10n.commonCancel).first);
        await tester.pumpAndSettle();

        expect(app.executeCalls, 1, reason: '仅管线拦截的 1 次尝试；取消后零执行（无 bypass 重试）');
        expect(
          app.aiMessages.single.content,
          l10n.operationCancelled,
          reason: '取消 → 「已取消」消息 + 拦截审计，无裸异常文案',
        );
        expect(
          app.aiMessages.single.toolResultData?['workbench'],
          isNull,
          reason: '取消不落任何卡（结果卡/错误卡都不落）',
        );
      },
    );
  });

  group('失败与守卫（AC9.4 + 上下文/空白守卫）', () {
    testWidgets('执行失败 → 错误卡落卡不静默（AC9.4）', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT broken(',
        allowed: <String>{},
      );
      app.throwOnExecute = Exception('syntax error near ("');

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 1);
      final card = app.aiMessages.single.toolResultData?['workbench'];
      expect(
        card is Map && card['kind'] == 'error_card',
        isTrue,
        reason: 'AC9.4：失败呈错误卡，非静默',
      );
      expect((card as Map)['summary'], l10n.aiPanelExecuteFailed);
      expect(
        card['detail'].toString(),
        contains('syntax error'),
        reason: '技术详情承载异常原文',
      );
    });

    testWidgets('错误卡 detail 落卡前脱敏（F5：凭据不入会话明文持久化）', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT 1',
        allowed: <String>{},
      );
      app.throwOnExecute = Exception(
        'connect failed: password=secret123 host=192.168.3.128',
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      final card = app.aiMessages.single.toolResultData?['workbench'] as Map;
      final String detail = card['detail'].toString();
      expect(
        detail,
        isNot(contains('secret123')),
        reason: 'F5：驱动异常中的连接串密码必须被脱敏',
      );
      expect(detail, contains('***'), reason: '脱敏占位符存在');
    });

    testWidgets('畸形 SQL（未闭合注释）拆分失败 → fail-closed 零执行 + 错误卡（F1）', (
      tester,
    ) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT 1; DROP TABLE x; /*',
        allowed: <String>{},
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(
        app.executeCalls,
        0,
        reason: 'F1：拆分异常不整块回退执行——整块过闸会被前缀判读误判只读（fail-open）',
      );
      expect(find.byType(ConfirmExecuteDialog), findsNothing);
      final card = app.aiMessages.single.toolResultData?['workbench'];
      expect(
        card is Map && card['kind'] == 'error_card',
        isTrue,
        reason: '拆分失败呈错误卡，不静默（错误卡自带「重试」/「在经典中打开」出口）',
      );
      expect((card as Map)['summary'], l10n.aiPanelExecuteFailed);
      expect(
        (card['detail'] as String?) ?? '',
        contains('split'),
        reason: 'detail 说明无法安全拆分',
      );
    });

    testWidgets('上下文不可用 → 错误卡 + 「去设置连接」出口 + 零执行', (tester) async {
      final app = _CountingAppProvider();
      // 不锁定上下文、无连接/tab → effectiveWorkbenchContext = none。
      app.aiPanel.ensureSession();
      final allowed = <String>{};
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
                      'SELECT 1',
                      allowedWriteServers: allowed,
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

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 0, reason: '无上下文不执行');
      final card = app.aiMessages.single.toolResultData?['workbench'];
      expect(card is Map && card['kind'] == 'error_card', isTrue);
      expect(
        find.text(l10n.workbenchErrorSetupConnection),
        findsOneWidget,
        reason: '「去设置连接」出口（SnackBar 动作）',
      );
      expect(find.text(l10n.workbenchErrorNoContext), findsOneWidget);
    });

    testWidgets('空白 SQL → 错误卡，不进确认流（T06 语义守卫）', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => '   ',
        allowed: <String>{},
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(
        find.byType(ConfirmExecuteDialog),
        findsNothing,
        reason: '空白不进确认流（isWriteSql 空白判写，先守卫）',
      );
      expect(app.executeCalls, 0);
      final card = app.aiMessages.single.toolResultData?['workbench'];
      expect(card is Map && card['kind'] == 'error_card', isTrue);
      expect(
        (card as Map)['summary'],
        l10n.workbenchErrorEmptySql,
        reason: '空白守卫专用文案，不再复用 aiPanelExecuteFailed',
      );
    });
  });

  group('AC9.5 多语句逐条执行逐条落卡 + 统计三分类（§6.4 按语句类型，P1-2）', () {
    testWidgets('两条只读语句 → 两次执行、两张结果卡、逐条 queryGen（批量不再整体归 bulkMaint）', (
      tester,
    ) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT 1; SELECT 2',
        allowed: <String>{},
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 2, reason: '逐条执行');
      expect(app.executedSql, containsAll(['SELECT 1', 'SELECT 2']));
      expect(app.aiMessages.length, 2, reason: '逐条落卡');

      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      expect(export.ops['queryGen'], 2, reason: '只读语句逐条计 queryGen（按语句自身类型）');
      expect(
        export.ops['bulkMaint'],
        isNull,
        reason: '批量维度不再整体归 bulkMaint（§6.4 修正）',
      );
      expect(export.toolCards['resultCard'], 2);
    });

    testWidgets('单条只读 → queryGen；单条 DML → bulkMaint；单条 DDL → ddlPerm', (
      tester,
    ) async {
      final readApp = await pumpHarness(
        tester,
        sql: () => 'SELECT 42',
        allowed: <String>{},
      );
      await triggerRun(tester);
      await tester.pumpAndSettle();
      expect(readApp.executeCalls, 1);

      final dmlApp = await pumpHarness(
        tester,
        sql: () => "UPDATE t SET a = 1 WHERE id = 1",
        allowed: {'conn-1'},
      );
      await triggerRun(tester);
      await tester.pumpAndSettle();
      expect(dmlApp.executeCalls, 1);

      final ddlApp = await pumpHarness(
        tester,
        sql: () => 'CREATE TABLE t (id INT)',
        allowed: {'conn-1'},
      );
      await triggerRun(tester);
      await tester.pumpAndSettle();
      expect(ddlApp.executeCalls, 1);

      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      expect(export.ops['queryGen'], 1, reason: '只读成功 → queryGen');
      expect(
        export.ops['bulkMaint'],
        1,
        reason: 'DML 写（INSERT/UPDATE/DELETE/REPLACE）→ bulkMaint',
      );
      expect(
        export.ops['ddlPerm'],
        1,
        reason:
            'DDL（CREATE/DROP/ALTER/TRUNCATE/RENAME/GRANT/REVOKE 等）→ ddlPerm',
      );
      expect(export.toolCards['sqlCard'], 3, reason: 'SQL 卡执行成功计数（按成功语句）');
    });

    testWidgets('混合批量：只读与 DML 各按自身类型计数', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT 1; UPDATE t SET a = 1',
        allowed: {'conn-1'},
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 2);
      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      expect(export.ops['queryGen'], 1, reason: '批量内只读语句计 queryGen');
      expect(export.ops['bulkMaint'], 1, reason: '批量内 DML 语句计 bulkMaint');
    });

    testWidgets('部分失败：批量第二条失败 → 成功/失败各成卡互不淹没', (tester) async {
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT 1; SELECT 2',
        allowed: <String>{},
      );
      app.throwOnExecute = Exception('boom');

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 2, reason: '部分失败不中断后续语句');
      expect(app.aiMessages.length, 2);
      final kinds = app.aiMessages
          .map((m) => (m.toolResultData?['workbench'] as Map)['kind'])
          .toList();
      expect(
        kinds,
        everyElement('error_card'),
        reason: '本桩两条均失败（桩按调用全量抛错）——逐条落错误卡可辨识',
      );
    });
  });

  group('B1 execution tab 批次推送（R3/R4，永不空开）', () {
    testWidgets('混合批（含写）→ 批末推送一次，行 = 批内全部语句（含只读，执行序）', (
      tester,
    ) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () => "SELECT 1; INSERT INTO t VALUES (1); SELECT 2",
        allowed: {'conn-1'},
        batches: batches,
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 3, reason: '三句逐条执行');
      expect(batches, hasLength(1), reason: '批末推送恰好一次');
      final data = batches.single;
      expect(
        data.tabKey,
        StageExecutionData.manualTabKey,
        reason: 'R4：手动批单例键 manual（复用刷新不累积）',
      );
      expect(data.title, startsWith('Execution '), reason: '标题含时间戳');
      expect(
        data.rows.map((r) => r.sql),
        ['SELECT 1', 'INSERT INTO t VALUES (1)', 'SELECT 2'],
        reason: 'R3：行 = 批内全部语句（含只读），执行序',
      );
      expect(
        data.rows.map((r) => r.status),
        everyElement(StageExecutionStatus.done),
      );
      // 指标口径（裁决选项 A detailed 通道）：只读行无影响行概念（引擎
      // null → 降级不显）；写语句（INSERT）affectedRows = 引擎真值 1
      // （不再空行集降级）；耗时逐行在位。
      expect(
        data.rows[0].affectedRows,
        isNull,
        reason: '只读语句无影响行概念（引擎 null），chip 不显',
      );
      expect(
        data.rows[1].affectedRows,
        1,
        reason: '写语句行 affectedRows 有值 = 引擎真值（detailed 通道贯通）',
      );
      expect(
        data.rows.every((r) => r.durationMs != null),
        isTrue,
        reason: '耗时逐行在位（runner stopwatch 口径）',
      );
    });

    testWidgets('DDL 展示语义（裁决定案）：引擎报 0 抑制 chip；DML 直显引擎值（含 0）', (
      tester,
    ) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () => 'UPDATE t SET a = 1 WHERE id = 99; '
            'CREATE TABLE t2 (id INT); '
            'INSERT INTO t3 VALUES (1)',
        allowed: {'conn-1'},
        batches: batches,
      );
      // 引擎值：UPDATE 命中 0 行（DML 直显 0）；CREATE TABLE 报 0
      // （MySQL DDL 成功常报 0 → 抑制）；INSERT 报 1。
      app.affectedRowsFor = (sql) {
        if (sql.contains('CREATE TABLE')) return 0;
        if (sql.contains('INSERT')) return 1;
        return 0;
      };

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 3);
      expect(batches, hasLength(1));
      final data = batches.single;
      expect(
        data.rows.map((r) => r.sql),
        [
          'UPDATE t SET a = 1 WHERE id = 99',
          'CREATE TABLE t2 (id INT)',
          'INSERT INTO t3 VALUES (1)',
        ],
      );
      expect(
        data.rows[0].affectedRows,
        0,
        reason: 'DML 直显引擎值（含 0）——UPDATE 命中 0 行如实显示',
      );
      expect(
        data.rows[1].affectedRows,
        isNull,
        reason: 'DDL 引擎报 0（MySQL DDL 成功常报 0）→ 抑制 chip，仅 >0 显示',
      );
      expect(
        data.rows[2].affectedRows,
        1,
        reason: 'INSERT 引擎真值 1 贯通',
      );
    });

    testWidgets('DDL 引擎报 >0 → 显示真值（抑制只针对 0）', (tester) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () => 'CREATE TABLE t2 (id INT)',
        allowed: {'conn-1'},
        batches: batches,
      );
      app.affectedRowsFor = (_) => 4;

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(batches, hasLength(1));
      expect(
        batches.single.rows.single.affectedRows,
        4,
        reason: 'DDL 引擎报 4 → 直显（抑制只针对 0）',
      );
    });

    testWidgets('失败行 error 全文入 data + 部分失败不中断（AC9.5）', (tester) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () =>
            'INSERT INTO t VALUES (1); '
            'UPDATE missing_t SET a = 1 WHERE id = 2 LIMIT 1',
        allowed: {'conn-1'},
        batches: batches,
      );
      app.throwForSql = (sql) => sql.contains('missing_t')
          ? Exception('boom: table missing_t not found')
          : null;

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 2, reason: '部分失败不中断后续语句');
      expect(batches, hasLength(1));
      final data = batches.single;
      expect(data.rows, hasLength(2));
      expect(data.rows[0].status, StageExecutionStatus.done);
      expect(data.rows[1].status, StageExecutionStatus.failed);
      expect(
        data.rows[1].error,
        contains('boom: table missing_t not found'),
        reason: '失败行错误全文入投影（脱敏后原文）',
      );
      expect(data.rows[1].durationMs, isNotNull);
    });

    testWidgets('纯只读批不推（结果卡已承载，R3）', (tester) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () => 'SELECT 1; SELECT 2',
        allowed: <String>{},
        batches: batches,
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 2, reason: '只读批正常执行');
      expect(batches, isEmpty, reason: '纯只读批不推 execution tab（R3）');
    });

    testWidgets('gate #1 写确认取消（零执行）不推（永不空开，v1 §3.7）', (tester) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () => 'INSERT INTO t VALUES (1)',
        allowed: <String>{},
        batches: batches,
      );

      await triggerRun(tester);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(app.executeCalls, 0, reason: '取消零执行');
      expect(batches, isEmpty, reason: '全取消（零执行）不推——永不空开');
    });

    testWidgets('拆分失败（fail-closed 零执行）不推（F1）', (tester) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () => 'INSERT INTO t VALUES (1); /*',
        allowed: {'conn-1'},
        batches: batches,
      );

      await triggerRun(tester);
      await tester.pumpAndSettle();

      expect(app.executeCalls, 0, reason: '拆分失败零执行');
      expect(batches, isEmpty, reason: '拆分失败不推——永不空开');
    });

    testWidgets('gate #2 DDL 取消：已执行行 + skipped 行同批入投影（R3 全语句行）', (
      tester,
    ) async {
      final batches = <StageExecutionData>[];
      final app = await pumpHarness(
        tester,
        sql: () => 'INSERT INTO t VALUES (1); DROP TABLE risky_x',
        allowed: {'conn-1'}, // gate #1 已放行，直达管线异常
        batches: batches,
      );
      app.throwForSql = (sql) => sql.contains('risky_x')
          ? DdlConfirmationRequiredException(
              sql: sql,
              impactReport: ImpactReport(
                ddlStatement: sql,
                targetTable: 'risky_x',
                ddlType: 'DROP',
                riskLevel: RiskLevel.high,
                affectedObjects: const [],
                dependencies: const [],
                warnings: const [],
                recommendations: const [],
                requiresConfirmation: true,
                analyzedAt: DateTime.now(),
              ),
            )
          : null;

      await triggerRun(tester);
      await tester.pump();
      expect(
        find.byType(DdlConfirmDialog),
        findsOneWidget,
        reason: 'DROP 触发 DDL 双门确认',
      );
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(
        app.executeCalls,
        2,
        reason: 'INSERT 已执行 1 次 + DROP 被管线拦截的 1 次尝试',
      );
      expect(batches, hasLength(1), reason: '批内有真实执行（INSERT done）→ 推');
      final data = batches.single;
      expect(data.rows, hasLength(2), reason: '行 = 全批语句（含 skipped）');
      expect(data.rows[0].status, StageExecutionStatus.done);
      expect(
        data.rows[1].status,
        StageExecutionStatus.skipped,
        reason: '门控取消语句未执行 → skipped 行',
      );
      expect(
        data.rows[1].durationMs,
        isNull,
        reason: '未执行语句无指标（降级「状态 + SQL」）',
      );
      expect(data.rows[1].error, isNull);
    });
  });
}
