// T2 保存查询链路：host 分发 + 壳层接线 + 守卫/错误面测试。
//
// 覆盖：
// - host：WorkbenchCardActions.onSaveQuery 透传至 SQL 卡（payload 卡 +
//   code 拦截卡两构造点）；
// - 壳层接线：点「保存为查询」→ 命名对话框（默认名 = SQL 首行）→ 确认 →
//   AppProvider.saveQuery 被调（QueryTab 字段断言）→ 成功 SnackBar；
// - 守卫：无生效连接 → 提示选择连接 SnackBar + 打开上下文选择器；
// - 错误：同名冲突（DuplicateSavedQueryNameException）→ 改名重试提示；
//   其他异常 → 通用失败提示。
//
// saveQuery 为本地 prefs 持久化（非数据库操作），facade 以测试子类桩承接；
// TabProvider.saveQuery 的同名冲突真实行为由 test/providers/tab_provider_test.dart 覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/organisms/ai_workbench/save_query_naming_dialog.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_host.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_picker.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart'
    show DuplicateSavedQueryNameException, QueryTab;

const String _cardSql = 'SELECT * FROM users';

AiMessage _sqlCardMessage() => AiMessage(
  id: 'sql-card-save-1',
  isUser: false,
  content: '',
  timestamp: DateTime.now(),
  type: AiMessageType.toolResult,
  toolName: 'workbench',
  toolResultData: <String, dynamic>{
    'workbench': const WorkbenchSqlCardPayload(
      sql: _cardSql,
      statementType: 'SELECT',
      isWrite: false,
    ).toJson(),
  },
  status: AiMessageStatus.completed,
);

/// saveQuery 计数桩：记录入参 / 抛指定异常。
class _SaveSpyAppProvider extends AppProvider {
  _SaveSpyAppProvider({this.throwOnSave});

  final Object? throwOnSave;
  final List<QueryTab> saved = <QueryTab>[];

  @override
  Future<bool> saveQuery(QueryTab queryTab) async {
    final Object? thrown = throwOnSave;
    if (thrown != null) throw thrown;
    saved.add(queryTab);
    return true;
  }
}

Future<_SaveSpyAppProvider> _pumpShellWithCard(
  WidgetTester tester, {
  required _SaveSpyAppProvider app,
}) async {
  app.setAiPanelOpen(true);
  app.setAiPanelFullscreen(true);
  app.aiPanel.ensureSession();
  app.addAiMessage(_sqlCardMessage());
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: AiWorkbenchShell()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 上下文锁定版（conn-1 / db1）。
Future<_SaveSpyAppProvider> _pumpShellWithLockedContext(
  WidgetTester tester, {
  required _SaveSpyAppProvider app,
}) async {
  final _SaveSpyAppProvider pumped = await _pumpShellWithCard(tester, app: app);
  pumped.aiPanel.lockWorkbenchContext('conn-1', 'db1');
  await tester.pumpAndSettle();
  return pumped;
}

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: child,
      ),
    ),
  ),
);

Widget _hostBody({
  required Map<String, dynamic>? toolResultData,
  required ValueChanged<String> onSaveQuery,
}) => Builder(
  builder: (context) =>
      WorkbenchCardHost.tryBuild(
        context: context,
        message: AiMessage(
          id: 'm-host-1',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'workbench',
          toolResultData: toolResultData,
          status: AiMessageStatus.completed,
        ),
        actions: WorkbenchCardActions(onSaveQuery: onSaveQuery),
      ) ??
      const SizedBox.shrink(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('host 分发：onSaveQuery 透传至 SQL 卡', () {
    testWidgets('payload 卡：点击「保存为查询」携带卡内 SQL', (tester) async {
      String? savedSql;
      await tester.pumpWidget(
        _wrap(
          _hostBody(
            toolResultData: <String, dynamic>{
              'workbench': const WorkbenchSqlCardPayload(
                sql: _cardSql,
                statementType: 'SELECT',
                isWrite: false,
              ).toJson(),
            },
            onSaveQuery: (sql) => savedSql = sql,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlToolCard), findsOneWidget);
      await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
      await tester.pump();
      expect(savedSql, _cardSql);
    });

    testWidgets('code 拦截卡：onSaveQuery 同样透传', (tester) async {
      String? savedSql;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                WorkbenchCardHost.tryBuild(
                  context: context,
                  message: AiMessage(
                    id: 'm-host-code',
                    isUser: false,
                    content: '',
                    code: _cardSql,
                    timestamp: DateTime.now(),
                    type: AiMessageType.chat,
                    status: AiMessageStatus.completed,
                  ),
                  actions: WorkbenchCardActions(
                    onSaveQuery: (sql) => savedSql = sql,
                  ),
                ) ??
                const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlToolCard), findsOneWidget);
      await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
      await tester.pump();
      expect(savedSql, _cardSql);
    });
  });

  group('壳层接线：点按钮 → 对话框 → 确认 → saveQuery', () {
    testWidgets('锁定上下文下保存：QueryTab 字段 == 输入名 + 卡 SQL + 锁定连接/库', (tester) async {
      final app = await _pumpShellWithLockedContext(
        tester,
        app: _SaveSpyAppProvider(),
      );
      final l10n = AppLocalizationsEn();

      expect(find.byType(SqlToolCard), findsOneWidget);
      await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
      await tester.pumpAndSettle();

      // 命名对话框弹出，默认名 = SQL 首行（_cardSql 单行 ≤40 字符原样）。
      expect(find.byType(SaveQueryNamingDialog), findsOneWidget);
      expect(find.text(_cardSql), findsOneWidget);

      await tester.tap(find.byKey(SaveQueryNamingDialog.confirmButtonKey));
      await tester.pumpAndSettle();

      expect(app.saved, hasLength(1), reason: '确认后经 AppProvider facade 保存');
      final QueryTab tab = app.saved.single;
      expect(tab.title, _cardSql);
      expect(tab.sql, _cardSql);
      expect(tab.connectionId, 'conn-1');
      expect(tab.databaseName, 'db1');
      expect(tab.savedQueryId, isNull, reason: '新建保存（savedQueryId 置空）');
      // 成功 SnackBar（l10n.querySaved）。
      expect(find.text(l10n.querySaved(_cardSql)), findsOneWidget);
    });

    testWidgets('对话框取消：零保存', (tester) async {
      final app = await _pumpShellWithLockedContext(
        tester,
        app: _SaveSpyAppProvider(),
      );

      await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SaveQueryNamingDialog.cancelButtonKey));
      await tester.pumpAndSettle();

      expect(app.saved, isEmpty);
    });

    testWidgets('无生效连接：提示选择连接 + 打开上下文选择器，零保存', (tester) async {
      final app = await _pumpShellWithCard(tester, app: _SaveSpyAppProvider());
      final l10n = AppLocalizationsEn();

      await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.workbenchSaveQuerySelectConnection),
        findsOneWidget,
      );
      expect(
        find.byType(WorkbenchContextPicker),
        findsOneWidget,
        reason: '提示后打开既有上下文选择器（与芯片未设置态同一出口）',
      );
      expect(app.saved, isEmpty);

      // 收尾：dismiss 选择器（barrier 可点）。
      await tester.tapAt(const Offset(20, 60));
      await tester.pumpAndSettle();
    });

    testWidgets('同名冲突：DuplicateSavedQueryNameException → 改名重试提示', (
      tester,
    ) async {
      final app = await _pumpShellWithLockedContext(
        tester,
        app: _SaveSpyAppProvider(
          throwOnSave: DuplicateSavedQueryNameException(
            'dup name',
            connectionId: 'conn-1',
          ),
        ),
      );
      final l10n = AppLocalizationsEn();

      await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SaveQueryNamingDialog.confirmButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.savedQueryNameExists('dup name')),
        findsOneWidget,
        reason: '同名冲突提示改名重试（warning 面）',
      );
    });

    testWidgets('其他异常 → 通用失败提示（saveQueryFailed）', (tester) async {
      final app = await _pumpShellWithLockedContext(
        tester,
        app: _SaveSpyAppProvider(throwOnSave: Exception('boom')),
      );
      final l10n = AppLocalizationsEn();

      await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SaveQueryNamingDialog.confirmButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(l10n.saveQueryFailed('')),
        findsOneWidget,
        reason: '未知异常走通用失败提示',
      );
    });
  });
}
