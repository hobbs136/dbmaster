// 经典 AI 面板「执行 SQL」路径生产守卫臂（批4 修复轮 security P2-①）。
//
// 验收条款直译：production 连接 + AI 面板执行无 WHERE DELETE → 守卫弹窗
// 出现（非错误消息渲染）；取消 → logDmlBlocked 审计 + 零执行；确认 →
// bypass 重执（仅 guard true 之后）。
//
// Harness：pumpPanel 形态沿 ai_panel_no_implicit_writeback_test；守卫 seam
// 产物与 spy 观察面沿 test/services/production_guard_consumption_test 同款
// （真实 checkDmlSafety(environment: production) 异常，不从实现反推）。
// 有界 pump 不用 pumpAndSettle（面板可能存在常驻动画，仓内既有惯例）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/dialogs/dml_confirm_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/query_execution_interceptor.dart';

/// 真实 seam 产物：production + 阻断级 SQL → ProductionGuardRequiredException
/// （production_guard_consumption_test 同款）。
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

class _AuditRecord {
  const _AuditRecord(this.sql, this.connectionId, this.decision);
  final String sql;
  final String connectionId;
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
    blocked.add(_AuditRecord(sql, connectionId, decision));
  }
}

/// bypass 通道与审计观察面（经典 AI 面板臂消费非 detailed bypass 双通道）。
class _SpyDatabaseService extends DatabaseService {
  final _SpyInterceptor spyInterceptor = _SpyInterceptor();
  final List<String> bypassDmlCalls = [];
  final List<String> bypassDdlCalls = [];

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
  Future<List<Map<String, dynamic>>> executeQueryBypassDdl(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    bypassDdlCalls.add(sql);
    return const <Map<String, dynamic>>[];
  }
}

/// 面板执行通道探针：executeQuery 抛真实守卫信号（_executeSql 的执行入口）。
class _PanelProbeAppProvider extends AppProvider {
  _PanelProbeAppProvider({
    required ConnectionProvider connectionProvider,
    required this.guardException,
  }) : super(connectionProvider: connectionProvider);

  final ProductionGuardRequiredException guardException;
  int executeCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executeCalls++;
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

  late _SpyDatabaseService spyDb;
  late _PanelProbeAppProvider app;

  Future<void> pumpPanel(WidgetTester tester) async {
    spyDb = _SpyDatabaseService();
    app = _PanelProbeAppProvider(
      connectionProvider: ConnectionProvider(dbService: spyDb),
      guardException: productionGuardOf(
        QueryExecutionInterceptor(),
        'DELETE FROM orders',
      ),
    );
    app.aiPanel.setSelectedConnection('conn-prod');
    app.aiPanel.ensureSession();
    // 预置 tab：跳过 _executeSql 的 tabs.isEmpty→addNewTab 分支。
    await app.tab.openQueryTab(
      connectionId: 'conn-prod',
      databaseName: 'db_prod',
      sql: 'SELECT 1',
    );
    app.addAiMessage(
      AiMessage(
        id: 'seed-delete',
        isUser: false,
        content: 'Delete all rows.',
        code: 'DELETE FROM orders',
        isDangerous: false,
        timestamp: DateTime.now(),
      ),
    );
    final layout = LayoutPreferencesProvider();
    await layout.load();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layout,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: AiPanelWidget()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 代码块执行钮 → ConfirmExecuteDialog（会话放行集为空）→ 允许本次 →
  /// _executeSql 触达守卫 seam、守卫弹窗出现。返回时弹窗已打开。
  Future<void> executeUntilGuardOpen(WidgetTester tester) async {
    final play = find.descendant(
      of: find.byType(AiMessageItem),
      matching: find.byIcon(LucideIcons.play),
    );
    expect(play, findsOneWidget, reason: '代码块执行按钮应可见');
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.aiPanelConfirmExecute));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(l10n.prodGuardTitleL2),
      findsOneWidget,
      reason: '守卫弹窗应出现（替代兜底错误渲染）',
    );
  }

  testWidgets(
    'production no-WHERE DELETE → 守卫弹窗出现非错误渲染；取消 → 审计 + 零执行',
    (tester) async {
      await pumpPanel(tester);
      await executeUntilGuardOpen(tester);

      expect(find.byType(DmlConfirmDialog), findsNothing);
      expect(app.executeCalls, 1, reason: '语句经 executeQuery 通道触达守卫 seam');
      expect(
        app.aiMessages
            .where((m) => m.content.contains(l10n.aiPanelExecuteFailed)),
        isEmpty,
        reason: '守卫异常不得以错误消息原文渲染（兜底臂违约）',
      );

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l10n.prodGuardTitleL2), findsNothing, reason: '弹窗关闭');
      expect(spyDb.bypassDmlCalls, isEmpty, reason: '取消 → 零执行');
      expect(spyDb.bypassDdlCalls, isEmpty);
      expect(
        spyDb.spyInterceptor.blocked,
        hasLength(1),
        reason: '取消 → logDmlBlocked 审计调用（不旁路）',
      );
      final audit = spyDb.spyInterceptor.blocked.single;
      expect(audit.sql, 'DELETE FROM orders');
      expect(audit.connectionId, 'conn-prod');
      expect(audit.decision, AuditDecision.cancelled);
      final last = app.aiMessages.last;
      expect(last.content, l10n.operationCancelled, reason: '取消提示沿面板消息惯例');
      expect(last.content.contains('ProductionGuardRequired'), isFalse);
      // 冲刷会话持久化 debounce Timer（consumption 测试同款）。
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('guard 确认 → bypass 重执（非 DDL → BypassDml 通道；仅 guard true 后）', (
    tester,
  ) async {
    await pumpPanel(tester);
    await executeUntilGuardOpen(tester);
    expect(spyDb.bypassDmlCalls, isEmpty, reason: '确认前零执行');

    // L2 免输入：确认钮直接可达。
    await tester.tap(find.text(l10n.prodGuardConfirmDrop));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      spyDb.bypassDmlCalls,
      equals(const ['DELETE FROM orders']),
      reason: 'guard true → 非 DDL 语句经 DML bypass 通道重执',
    );
    expect(spyDb.bypassDdlCalls, isEmpty);
    expect(
      spyDb.spyInterceptor.blocked,
      isEmpty,
      reason: '确认路径不落取消审计',
    );
    expect(
      app.aiMessages.last.content.contains(l10n.aiPanelExecuteSuccess(0)),
      isTrue,
      reason: '执行结果按既有确认后形态回消息流',
    );
    // 冲刷 SnackBar 自动关闭与会话持久化 debounce Timer。
    await tester.pump(const Duration(seconds: 5));
  });
}
