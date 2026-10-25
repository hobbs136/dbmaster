// UIRV-B7 工作台 composer 640 内层（tasks-ui-review-fixes.md，2026-10-25）。
//
// 验收条款直译（红测先行，不镜像实现）：
// 1. 舞台收起（chat-only）态：composer 内层最大 640px 且与消息流内层列
//    同轴居中；外层对话列仍吃满。
// 2. 舞台并置（split）态：composer 取可用宽（≤640 时自然填满，不制造
//    侧空白）。
// 3. composer 垂直几何沿既有 token（80 min / 200 max）。
// 4. 发送按钮在框内（composer 内层范围之内），不出现跨屏通栏 Send。
// 5. SQL/结果/工具卡不套 640 限制（fluid 规则回归）。
//
// AiInputArea 组件本身零修改（契约：不加宽度参数）——本文件只消费它。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_host.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_chat_view.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';
import 'package:dbmaster/theme/design_system.dart';

AiMessage _sqlCardMessage() => AiMessage(
  id: 'b7_sql_card',
  isUser: false,
  content: '',
  timestamp: DateTime.now(),
  type: AiMessageType.toolResult,
  toolName: 'workbench',
  toolResultData: <String, dynamic>{
    'workbench': WorkbenchSqlCardPayload(
      sql: 'UPDATE users SET name = 1 WHERE id = 2',
      statementType: 'UPDATE',
      isWrite: true,
    ).toJson(),
  },
  status: AiMessageStatus.completed,
);

Future<void> pumpChatViewAtWidth(
  WidgetTester tester,
  double width, {
  List<AiMessage> messages = const [],
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final app = AppProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: WorkbenchChatView(actions: WorkbenchCardActions()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (messages.isNotEmpty) {
    app.aiPanel.ensureSession();
    for (final m in messages) {
      app.addAiMessage(m);
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WorkbenchUsageStatsService.instance.resetForTesting();
  });

  group('UIRV-B7 composer 640 内层', () {
    testWidgets(
      'B7-001 chat-only 宽列：composer 内层 ≤640 且同轴居中，外层对话列吃满',
      (tester) async {
        await pumpChatViewAtWidth(tester, 1280);

        final chatRect = tester.getRect(find.byType(WorkbenchChatView));
        expect(
          chatRect.width,
          1280,
          reason: '外层对话列仍吃满（不复活 760/880 外壳）',
        );

        final composerRect = tester.getRect(find.byType(AiInputArea));
        expect(
          composerRect.width,
          lessThanOrEqualTo(
            AppDesignSystem.workbenchChatReadableMaxWidth,
          ),
          reason: 'composer 内层最大 640px',
        );
        expect(
          (composerRect.center.dx - chatRect.center.dx).abs(),
          lessThan(1.0),
          reason: 'composer 内层与消息流内层列同轴居中',
        );
      },
    );

    testWidgets(
      'B7-002 窄列（split 语义，可用宽 < 640）：composer 自然填满不制造侧空白',
      (tester) async {
        await pumpChatViewAtWidth(tester, 480);

        final chatRect = tester.getRect(find.byType(WorkbenchChatView));
        final composerRect = tester.getRect(find.byType(AiInputArea));
        expect(
          composerRect.width,
          closeTo(chatRect.width, 1.0),
          reason: '可用宽小于 640 时 composer 取满可用宽（chat 360-520 不变）',
        );
        expect(
          (composerRect.center.dx - chatRect.center.dx).abs(),
          lessThan(1.0),
        );
      },
    );

    testWidgets(
      'B7-003 composer 垂直几何沿既有 token：高 ≥80 且 ≤200',
      (tester) async {
        await pumpChatViewAtWidth(tester, 1280);

        final composerRect = tester.getRect(find.byType(AiInputArea));
        expect(composerRect.height,
            greaterThanOrEqualTo(AppDesignSystem.workbenchComposerMinHeight));
        expect(composerRect.height,
            lessThanOrEqualTo(AppDesignSystem.workbenchComposerMaxHeight));
      },
    );

    testWidgets(
      'B7-004 发送按钮在 composer 框内，无跨屏通栏 Send',
      (tester) async {
        await pumpChatViewAtWidth(tester, 1280);

        final composerRect = tester.getRect(find.byType(AiInputArea));
        final sendIconFinder = find.descendant(
          of: find.byType(AiInputArea),
          matching: find.byIcon(LucideIcons.send),
        );
        expect(sendIconFinder, findsOneWidget);
        final sendRect = tester.getRect(sendIconFinder);
        expect(
          composerRect.contains(sendRect.center),
          isTrue,
          reason: '发送动作位于 composer 内层范围之内（框内底行），'
              '不是横贯全屏的通栏禁用 Send',
        );
      },
    );

    testWidgets(
      'B7-005 SQL 工具卡不套 640 限制：宽列下吃满对话列宽（fluid 回归）',
      (tester) async {
        await pumpChatViewAtWidth(tester, 1280,
            messages: [_sqlCardMessage()]);

        expect(find.byType(SqlToolCard), findsOneWidget);
        final cardRect = tester.getRect(find.byType(SqlToolCard));
        expect(
          cardRect.width,
          greaterThan(AppDesignSystem.workbenchChatReadableMaxWidth),
          reason: 'SQL/结果/工具卡走既有 fluid 规则，不受 640 内层封顶',
        );
      },
    );
  });
}
