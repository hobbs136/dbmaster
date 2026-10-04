// T12 阶段二 card_host 分发测试（design-ai-workbench §4.4/§11.1）。
//
// 覆盖：分发规则三支（workbench payload 按 kind / AiMessage.code 渲染层拦截
// / 无键回退 AiMessageItem）+ 未知 kind 前向兼容（C-2）+ 写徽标判定 =
// AiToolClassifier.isWriteSql（拦截卡实时判定）+ 动作注入透传 + chat_view
// 接线（消息流不动的结构性验证 + T13 动作路由透传）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_table_card.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_host.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_chat_view.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/ai_tool_classifier.dart';

Widget _wrap(Widget child, {double width = 720}) => MaterialApp(
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
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    ),
  ),
);

AiMessage _msg({
  bool isUser = false,
  String content = '',
  String? code,
  Map<String, dynamic>? toolResultData,
  AiMessageType type = AiMessageType.chat,
}) => AiMessage(
  id: 'm-${DateTime.now().microsecondsSinceEpoch}',
  isUser: isUser,
  content: content,
  timestamp: DateTime.now(),
  code: code,
  type: type,
  toolName: type == AiMessageType.toolResult ? 'workbench' : null,
  toolResultData: toolResultData,
  status: AiMessageStatus.completed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('分发规则①：toolResultData[workbench] 按 kind 渲染', () {
    testWidgets('sql_card → SqlToolCard（徽标随 payload）', (tester) async {
      final payload = WorkbenchSqlCardPayload(
        sql: 'UPDATE users SET name = 1 WHERE id = 2',
        statementType: 'UPDATE',
        isWrite: true,
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                WorkbenchCardHost.tryBuild(context: context, message: _msg(
                  type: AiMessageType.toolResult,
                  toolResultData: {'workbench': payload.toJson()},
                )) ?? const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlToolCard), findsOneWidget);
      expect(find.byKey(SqlToolCard.writeBadgeKey), findsOneWidget);
    });

    testWidgets('result_card → ResultTableCard（元信息渲染）', (tester) async {
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT 1',
        rowCount: 7,
        durationMs: 30,
        columns: const ['a'],
        rows: const [
          {'a': 1},
        ],
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                WorkbenchCardHost.tryBuild(context: context, message: _msg(
                  type: AiMessageType.toolResult,
                  toolResultData: {'workbench': payload.toJson()},
                )) ?? const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResultTableCard), findsOneWidget);
      expect(find.text('7 rows · 30 ms'), findsOneWidget);
    });

    testWidgets('result_card「在舞台打开」回调携带 (payload, cardId)（v2 B2 签名）', (
      tester,
    ) async {
      // 非截断有快照（v2 B2 放宽：snapshotRows 非空即可开）。
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT id FROM users',
        rowCount: 3,
        durationMs: 20,
        columns: const ['id'],
        rows: const [
          {'id': 1},
          {'id': 2},
          {'id': 3},
        ],
      );
      final message = _msg(
        type: AiMessageType.toolResult,
        toolResultData: {'workbench': payload.toJson()},
      );
      WorkbenchResultCardPayload? gridPayload;
      String? cardId;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                WorkbenchCardHost.tryBuild(
                  context: context,
                  message: message,
                  actions: WorkbenchCardActions(
                    onOpenResultInGrid: (p, id) {
                      gridPayload = p;
                      cardId = id;
                    },
                  ),
                ) ??
                const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ResultTableCard.openInGridButtonKey));
      await tester.pump();
      expect(gridPayload, isNotNull);
      // 安全：上方 expect(isNotNull) 已收窄。
      expect(gridPayload!.rowCount, 3);
      expect(
        cardId,
        message.id,
        reason: 'v2 B2：回调第二参 = 承载卡的消息 id（构建点注入）',
      );
    });

    testWidgets('error_card → 错误态渲染分支', (tester) async {
      final payload = WorkbenchErrorCardPayload(
        sql: 'SELECT 1',
        summary: 'no context',
        detail: 'effectiveWorkbenchContext == none',
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                WorkbenchCardHost.tryBuild(context: context, message: _msg(
                  type: AiMessageType.toolResult,
                  toolResultData: {'workbench': payload.toJson()},
                )) ?? const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResultTableCard), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(find.byKey(ResultTableCard.errorSummaryKey), findsOneWidget);
    });

    testWidgets('未知 kind → null（C-2 前向兼容，回退既有路径）', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        WorkbenchCardHost.tryBuild(
          context: captured,
          message: _msg(
            type: AiMessageType.toolResult,
            toolResultData: const {
              'workbench': {'kind': 'approval_card', 'future': true},
            },
          ),
        ),
        isNull,
        reason: '未知 kind 的 workbench 消息回退 AiMessageItem（不误渲染）',
      );
    });
  });

  group('分发规则②：AiMessage.code 渲染层拦截为 SQL 卡', () {
    testWidgets('AI 回复 code 块 → SqlToolCard + 正文保留（信息不丢失）', (
      tester,
    ) async {
      final message = _msg(
        content: 'Here is the query you asked for:',
        code: 'SELECT id FROM orders WHERE status = 1',
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => WorkbenchCardHost.tryBuild(
                  context: context,
                  message: message,
                ) ??
                const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlToolCard), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget,
          reason: '正文 markdown 随卡呈现，拦截不丢信息');
      expect(find.text('Here is the query you asked for:'), findsOneWidget);
    });

    testWidgets('写徽标判定 = AiToolClassifier.isWriteSql（拦截卡实时判定）', (
      tester,
    ) async {
      // UPDATE → 写：badge 出现。
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => WorkbenchCardHost.tryBuild(
                  context: context,
                  message: _msg(code: 'UPDATE t SET a = 1'),
                ) ??
                const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.writeBadgeKey), findsOneWidget);
      expect(AiToolClassifier.isWriteSql('UPDATE t SET a = 1'), isTrue);

      // SELECT → 只读：badge 不出现。
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => WorkbenchCardHost.tryBuild(
                  context: context,
                  message: _msg(code: 'SELECT * FROM t'),
                ) ??
                const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.writeBadgeKey), findsNothing);
      expect(AiToolClassifier.isWriteSql('SELECT * FROM t'), isFalse);
    });

    testWidgets('动作注入透传到拦截卡（执行回调携带 SQL）', (tester) async {
      String? executed;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => WorkbenchCardHost.tryBuild(
                  context: context,
                  message: _msg(code: 'DELETE FROM t'),
                  actions: WorkbenchCardActions(
                    onExecuteSql: (sql) => executed = sql,
                  ),
                ) ??
                const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pump();
      expect(executed, 'DELETE FROM t');
    });

    testWidgets('用户消息 code 不拦截（回退既有路径）', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        WorkbenchCardHost.tryBuild(
          context: captured,
          message: _msg(isUser: true, code: 'SELECT 1'),
        ),
        isNull,
      );
    });
  });

  group('分发规则③：无 workbench 键 → null（回退 AiMessageItem）', () {
    testWidgets('普通消息/工具消息（无卡数据）均回退', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        WorkbenchCardHost.tryBuild(
          context: captured,
          message: _msg(content: 'plain chat'),
        ),
        isNull,
      );
      expect(
        WorkbenchCardHost.tryBuild(
          context: captured,
          message: _msg(
            type: AiMessageType.toolResult,
            toolResultData: const {
              'isToolGroup': true,
              'toolCount': 2,
              'tools': <Map<String, dynamic>>[],
            },
          ),
        ),
        isNull,
        reason: '经典工具组消息不进卡分发',
      );
    });
  });

  group('chat_view 接线（消息渲染入口改造）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<AppProvider> pumpChatView(
      WidgetTester tester, {
      WorkbenchCardActions actions = const WorkbenchCardActions(),
    }) async {
      final app = AppProvider();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: app,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(body: WorkbenchChatView(actions: actions)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('workbench SQL 卡消息渲染为卡，普通消息保留 AiMessageItem 路径', (
      tester,
    ) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      final payload = WorkbenchSqlCardPayload(
        sql: 'SELECT 42',
        statementType: 'SELECT',
        isWrite: false,
      );
      app.addAiMessage(
        _msg(
          isUser: true,
          content: 'give me a query',
        ),
      );
      app.addAiMessage(
        _msg(
          type: AiMessageType.toolResult,
          toolResultData: {'workbench': payload.toJson()},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlToolCard), findsOneWidget);
      expect(find.byType(AiMessageItem), findsOneWidget,
          reason: '非工具消息路径保留（用户消息仍走既有渲染）');
      // 渲染层拦截：消息流不变（仍是 2 条，无新建消息）。
      expect(app.aiMessages.length, 2);
    });

    testWidgets('卡「执行」经注入 actions 路由（T13：onExecuteSql 收到 SQL）', (
      tester,
    ) async {
      String? executedSql;
      final app = await pumpChatView(
        tester,
        actions: WorkbenchCardActions(
          onExecuteSql: (sql) => executedSql = sql,
        ),
      );
      app.aiPanel.ensureSession();
      final payload = WorkbenchSqlCardPayload(
        sql: 'SELECT 43',
        statementType: 'SELECT',
        isWrite: false,
      );
      app.addAiMessage(
        _msg(
          type: AiMessageType.toolResult,
          toolResultData: {'workbench': payload.toJson()},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pumpAndSettle();

      expect(
        executedSql,
        'SELECT 43',
        reason: 'T13：卡执行回调经宿主注入的编排入口路由（执行语义归'
            ' WorkbenchExecutionActions，接线面只验证透传）',
      );
      expect(app.aiMessages.length, 1, reason: '编排未触发前不新建消息');
    });
  });
}
