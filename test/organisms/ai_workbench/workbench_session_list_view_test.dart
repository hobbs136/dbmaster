// v2 A2 SessionListView 组件测试（AI 工作台先行批任务书 §6.2）。
//
// 会话列表自 rail 抽取为共享组件（rail 内容页 196 + 舞台 sessionList 单例
// tab 双形态同源，v2 §8-5）。本文件直接测组件本体：
// - showHeader 参数化：true = 头栏（标题 40 + 新建钮）/ false = 纯列表；
// - 会话管理语义在共享组件内保留：新建 + recordSession 统计 / 删除即时 +
//   撤销恢复 / 改名（§5 纪律 6：会话生命周期而非数据面）；
// - 196 窄列长标题 ellipsis + Tooltip 兜底（v2 A2 补）。
// 经 rail 的行为回归网见 workbench_session_rail_test.dart（零语义变化）；
// 舞台 tab 形态见 workbench_stage_test.dart / ai_workbench_shell_test.dart。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_conversation_session.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_session_list_view.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkbenchUsageStatsService.instance.resetForTesting();
    tempDir = Directory.systemTemp.createTempSync('session_list_view_test_');
    // deleteSession 的文件清理（_deleteSessionFiles）需要文档目录；
    // 指向临时目录（mock 手法沿 workbench_session_rail_test.dart）。
    const channels = [
      MethodChannel('plugins.flutter.io/path_provider'),
      MethodChannel('plugins.flutter.io/path_provider_foundation'),
      MethodChannel('plugins.flutter.io/path_provider_linux'),
      MethodChannel('plugins.flutter.io/path_provider_windows'),
    ];
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
    }
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // 防抖 persist 的挂起 IO 在 Windows 上可能仍短时占用临时目录；
      // 留给系统临时目录清理，不影响测试结论。
    }
  });

  AiConversationSession sessionOf(String id, String title, DateTime updatedAt) =>
      AiConversationSession(
        id: id,
        title: title,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        messageIds: const [],
      );

  /// 泵独立 SessionListView（组件面）。[listWidth] 约束列表宽（196 = rail
  /// 内容页宽，tooltip 兜底用例锁定该宽）。
  Future<AppProvider> pumpView(
    WidgetTester tester, {
    bool showHeader = true,
    double listWidth = 240,
    void Function(AppProvider app)? seed,
  }) async {
    final app = AppProvider();
    // 初始化文档目录（load 空文件安全），使删除路径的文件操作可用。
    await tester.runAsync(() => app.aiPanel.aiConversationService.load());
    seed?.call(app);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
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
                width: listWidth,
                child: SessionListView(showHeader: showHeader),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  /// 走完 AiSessionManager 的 500ms 防抖持久化 Timer（flutter_test 的
  /// pending-timer 不变量会在测试结束时拦截未走完的 Timer）。
  Future<void> drainPersistDebounce(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
  }

  group('头栏参数化（showHeader）', () {
    testWidgets('showHeader=true：头栏标题 + 新建钮渲染', (tester) async {
      await pumpView(tester, showHeader: true);

      expect(find.text('Sessions'), findsOneWidget, reason: '头栏标题');
      expect(
        find.byKey(const ValueKey('workbench_new_session_button')),
        findsOneWidget,
        reason: '新建入口随头栏（舞台 tab 形态补收窄态新建缺口）',
      );

      await drainPersistDebounce(tester);
    });

    testWidgets('showHeader=false：无头栏无新建钮；列表体仍渲染（空态文案）',
        (tester) async {
      await pumpView(tester, showHeader: false);

      expect(find.text('Sessions'), findsNothing, reason: '头栏标题不渲染');
      expect(
        find.byKey(const ValueKey('workbench_new_session_button')),
        findsNothing,
        reason: '新建钮随头栏隐藏',
      );
      expect(find.text('No sessions'), findsOneWidget, reason: '列表体仍在');

      await drainPersistDebounce(tester);
    });

    testWidgets('新建钮 → createSession + recordSession 统计（语义自 rail 保留）',
        (tester) async {
      final app = await pumpView(tester);
      final service = app.aiPanel.aiConversationService;
      expect(service.sessions, isEmpty);

      await tester.tap(find.byKey(const ValueKey('workbench_new_session_button')));
      await tester.pumpAndSettle();

      expect(service.sessions.length, 1, reason: '新建会话入账（经典同源）');
      expect(service.currentSession, isNotNull);
      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      final sessions = export.weeklySessions.values.fold<int>(0, (a, b) => a + b);
      expect(sessions, 1, reason: '新建按钮路径记一次 session 统计');

      await drainPersistDebounce(tester);
    });
  });

  group('会话管理语义（共享组件保留）', () {
    testWidgets('切换：点击条目 → switchSession', (tester) async {
      final app = await pumpView(
        tester,
        seed: (app) {
          final service = app.aiPanel.aiConversationService;
          final now = DateTime.now();
          service.restoreSession(sessionOf('s1', 'session one', now));
          service.restoreSession(sessionOf('s2', 'session two', now));
        },
      );
      final service = app.aiPanel.aiConversationService;

      await tester.tap(find.text('session two'));
      await tester.pumpAndSettle();
      expect(service.currentSession?.id, 's2');

      await drainPersistDebounce(tester);
    });

    testWidgets('删除即时 + 撤销恢复（经典回调语义）', (tester) async {
      final app = await pumpView(
        tester,
        seed: (app) {
          app.aiPanel.aiConversationService.restoreSession(
            sessionOf('doomed', 'doomed session', DateTime.now()),
          );
        },
      );
      final service = app.aiPanel.aiConversationService;

      await tester.tap(find.byKey(const ValueKey('workbench_session_menu_doomed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        service.sessions.where((s) => s.id == 'doomed'),
        isEmpty,
        reason: '删除即时生效',
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        service.sessions.where((s) => s.id == 'doomed'),
        isNotEmpty,
        reason: '撤销恢复（restoreSession 语义）',
      );

      await drainPersistDebounce(tester);
    });

    testWidgets('改名：菜单 → 对话框输入 → updateSessionTitle', (tester) async {
      final app = await pumpView(
        tester,
        seed: (app) {
          app.aiPanel.aiConversationService.restoreSession(
            sessionOf('r1', 'old title', DateTime.now()),
          );
        },
      );
      final service = app.aiPanel.aiConversationService;

      await tester.tap(find.byKey(const ValueKey('workbench_session_menu_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'renamed title');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        service.sessions.firstWhere((s) => s.id == 'r1').title,
        'renamed title',
      );

      await drainPersistDebounce(tester);
    });

    testWidgets('归档会话不出现在列表', (tester) async {
      await pumpView(
        tester,
        seed: (app) {
          final service = app.aiPanel.aiConversationService;
          service.restoreSession(sessionOf('a1', 'active one', DateTime.now()));
          service.restoreSession(sessionOf('a2', 'archived one', DateTime.now()));
          service.archiveSession('a2');
        },
      );

      expect(find.text('active one'), findsOneWidget);
      expect(find.text('archived one'), findsNothing);

      await drainPersistDebounce(tester);
    });
  });

  group('196 窄列（v2 A2 tooltip 兜底）', () {
    testWidgets('长标题：ellipsis + Tooltip 承载全文（196 宽约束）', (tester) async {
      const longTitle =
          'a very long session title that must truncate inside the 196 rail column';
      await pumpView(
        tester,
        listWidth: 196,
        seed: (app) {
          app.aiPanel.aiConversationService.restoreSession(
            sessionOf('long', longTitle, DateTime.now()),
          );
        },
      );

      final title = tester.widget<Text>(find.text(longTitle));
      expect(title.overflow, TextOverflow.ellipsis);
      expect(title.maxLines, 1);
      // tooltip 兜底：被截断的全文可读（§0.4 惯例）。
      expect(find.byTooltip(longTitle), findsOneWidget);

      await drainPersistDebounce(tester);
    });
  });
}
