// AI 工作台会话栏 T11 组件测试（design-ai-workbench §11.1 R2 + NF3.1 组件面）。
//
// 覆盖：今天/昨天/更早分组 / 新建会话 + recordSession 统计 / 切换会话
// （AC2.2 组件面）/ 删除即时 + 撤销恢复（经典回调语义）/ 改名 /
// 归档会话过滤 / 收窄 44 rail（NF3.1）/ 1024 宽壳内 rail 240 不破版
// （NF3.1 组件面）。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_conversation_session.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_session_rail.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';
import 'package:dbmaster/theme/design_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkbenchUsageStatsService.instance.resetForTesting();
    tempDir = Directory.systemTemp.createTempSync('workbench_rail_test_');
    // deleteSession 的文件清理（_deleteSessionFiles）需要文档目录；
    // 指向临时目录（mock 手法沿 test/services/backup_service_test.dart）。
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

  /// 泵独立会话栏（组件面）。restoreSession 逐条 insert(0)：
  /// 按 (更早, 昨天, 今天) 顺序恢复后列表头为今天组。
  Future<AppProvider> pumpRail(
    WidgetTester tester, {
    bool collapsed = false,
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
            body: WorkbenchSessionRail(collapsed: collapsed),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  /// 泵整壳（NF3.1 断点面；手法沿 ai_workbench_shell_test.dart）。
  Future<AppProvider> pumpShellAt(WidgetTester tester, Size surface) async {
    final app = AppProvider();
    app.setAiPanelOpen(true);
    app.setAiPanelFullscreen(true);
    await tester.binding.setSurfaceSize(surface);
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


  /// 走完 AiSessionManager 的 500ms 防抖持久化 Timer（flutter_test 的
  /// pending-timer 不变量会在测试结束时拦截未走完的 Timer）。
  Future<void> drainPersistDebounce(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
  }

  group('展开态（240 列表）', () {
    testWidgets('今天/昨天/更早分组头与会话条目按组渲染', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      await pumpRail(
        tester,
        seed: (app) {
          final service = app.aiPanel.aiConversationService;
          // restoreSession insert(0)：按时间正序恢复 → 列表头为最新。
          service.restoreSession(sessionOf('old', 'ancient chat', today.subtract(const Duration(days: 10))));
          service.restoreSession(sessionOf('yest', 'yesterday chat', today.subtract(const Duration(days: 1))));
          service.restoreSession(sessionOf('tdy', 'todays chat', today));
        },
      );

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);
      expect(find.text('todays chat'), findsOneWidget);
      expect(find.text('yesterday chat'), findsOneWidget);
      expect(find.text('ancient chat'), findsOneWidget);

      await drainPersistDebounce(tester);
    });

    testWidgets('新建会话按钮 → createSession + recordSession 统计（§6.4 字段 2）', (tester) async {
      final app = await pumpRail(tester);
      final service = app.aiPanel.aiConversationService;
      expect(service.sessions, isEmpty);

      await tester.tap(find.byKey(const ValueKey('workbench_new_session_button')));
      await tester.pumpAndSettle();

      expect(service.sessions.length, 1, reason: '新建会话入账（经典可见，AC2.3 同源）');
      expect(service.currentSession, isNotNull);
      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      final sessions = export.weeklySessions.values.fold<int>(0, (a, b) => a + b);
      expect(sessions, 1, reason: '新建按钮路径记一次 session 统计');

      await drainPersistDebounce(tester);
    });

    testWidgets('AC2.2 组件面：点击条目 → switchSession（消息加载由 chat view 承担）', (tester) async {
      final app = await pumpRail(
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

      await tester.tap(find.text('session one'));
      await tester.pumpAndSettle();
      expect(service.currentSession?.id, 's1');

      await drainPersistDebounce(tester);
    });

    testWidgets('删除：菜单删除即时生效 + 撤销恢复（经典回调语义）', (tester) async {
      final app = await pumpRail(
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
      final app = await pumpRail(
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
      await pumpRail(
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

    testWidgets('空会话：占位文案', (tester) async {
      await pumpRail(tester);
      expect(find.text('No sessions'), findsOneWidget);
    });
  });

  group('收窄态与断点（NF3.1 组件面）', () {
    testWidgets('collapsed rail：无标题文本、图标条目可切换会话', (tester) async {
      final app = await pumpRail(
        collapsed: true,
        tester,
        seed: (app) {
          final service = app.aiPanel.aiConversationService;
          final now = DateTime.now();
          service.restoreSession(sessionOf('c1', 'collapsed one', now));
          service.restoreSession(sessionOf('c2', 'collapsed two', now));
        },
      );
      final service = app.aiPanel.aiConversationService;

      expect(find.text('collapsed one'), findsNothing, reason: '收窄态不渲染标题');
      expect(find.text('Sessions'), findsNothing);
      expect(
        find.byIcon(LucideIcons.messageCircle),
        findsNWidgets(2),
        reason: '每会话一枚图标条目',
      );

      await tester.tap(find.byKey(const ValueKey('workbench_session_icon_c2')));
      await tester.pumpAndSettle();
      expect(service.currentSession?.id, 'c2', reason: '收窄态仍可切换会话');

      await drainPersistDebounce(tester);
    });

    testWidgets('1024 宽：rail 保持 240 token 宽、无 overflow', (tester) async {
      await pumpShellAt(tester, const Size(1024, 768));

      final railSize = tester.getSize(
        find.byKey(const ValueKey('workbench_session_rail_slot')),
      );
      expect(
        railSize.width,
        AppDesignSystem.workbenchSessionListWidth,
        reason: 'design §8【二】1024 校验：1024−240=784≥760，rail 不收窄',
      );
      expect(tester.takeException(), isNull, reason: 'NF3.1 无 overflow');
    });

    testWidgets('<900 宽：rail 收窄 44、无 overflow', (tester) async {
      await pumpShellAt(tester, const Size(800, 600));

      final railSize = tester.getSize(
        find.byKey(const ValueKey('workbench_session_rail_slot')),
      );
      expect(railSize.width, WorkbenchSessionRail.collapsedWidth);
      expect(tester.takeException(), isNull, reason: 'NF3.1 无 overflow');
    });
  });

  group('Scrollbar controller 回归（Windows 桌面断言）', () {
    testWidgets(
      'Windows：Scrollbar.controller 非空且与 CustomScrollView 同实例、hasClients',
      (tester) async {
        // 桌面平台下 ScrollView 不继承 PrimaryScrollController，无显式
        // controller 的 Scrollbar(thumbVisibility: true) 会在 debug 抛
        // 「Scrollbar's ScrollController has no ScrollPosition attached」；
        // 测试默认平台（android）因继承不触发。平台覆写经 variant 注入，
        // 结束时自动复位（复位先于 binding 不变量校验）。
        await pumpRail(
          tester,
          seed: (app) {
            app.aiPanel.aiConversationService.restoreSession(
              sessionOf('w1', 'windows session', DateTime.now()),
            );
          },
        );

        final scrollbar = tester.widget<Scrollbar>(
          // Windows 下 MaterialScrollBehavior 会给纵向 ScrollView 自动注入
          // 一颗 Scrollbar（thumbVisibility 为 null），显式 Scrollbar 用
          // thumbVisibility: true 精确定位。
          find.byWidgetPredicate(
            (widget) => widget is Scrollbar && widget.thumbVisibility == true,
          ),
        );
        final scrollView = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        final controller = scrollbar.controller;
        expect(
          controller,
          isNotNull,
          reason: '桌面 thumbVisibility=true 必须显式 controller',
        );
        expect(
          controller,
          same(scrollView.controller),
          reason: 'Scrollbar 与会话列表共用同一 controller',
        );
        expect(controller!.hasClients, isTrue, reason: 'controller 已挂上会话列表');

        await drainPersistDebounce(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });
}
