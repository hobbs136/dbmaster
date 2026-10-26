// AI 工作台会话栏 T11 组件测试（design-ai-workbench §11.1 R2 + NF3.1 组件面）。
//
// 覆盖：今天/昨天/更早分组 / 新建会话 + recordSession 统计 / 切换会话
// （AC2.2 组件面）/ 删除即时 + 撤销恢复（经典回调语义）/ 改名 /
// 归档会话过滤 / 收窄纯活动条 44（NF3.1 + v2 先行批 A1）/ 收窄态点会话
// 图标 → stageController.openSessions（v2 A2 R6 接缝）/ 1024 宽壳内
// rail 240 不破版（NF3.1 组件面）。会话列表本体已抽取为共享
// SessionListView（v2 A2），本文件经 rail 承载其回归网，零语义变化。
// v2 A3 起承载历史页 / A4 保存的查询页：活动条图标终态序
// （会话/保存的查询/历史，v2 §7-7）+ 两页展开态切换与收窄态路由。
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
import 'package:dbmaster/organisms/ai_workbench/workbench_query_history_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_saved_query_list_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_session_list_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_activity_bar.dart'
    show WorkbenchRailPage;
import 'package:dbmaster/organisms/ai_workbench/workbench_session_rail.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';
import 'package:dbmaster/theme/design_system.dart';

/// 批3 UI35-310 harness：模拟 shell 侧页态持有（currentPage + 展开覆写
/// ——收窄态点活动条 = 展开覆写 + 切页，生产逻辑在 shell，此处只复刻装配）。
class _RailHost extends StatefulWidget {
  const _RailHost({required this.collapsed, required this.stageController});

  final bool collapsed;
  final WorkbenchStageController stageController;

  @override
  State<_RailHost> createState() => _RailHostState();
}

class _RailHostState extends State<_RailHost> {
  WorkbenchRailPage _page = WorkbenchRailPage.sessions;
  bool _forceExpanded = false;

  @override
  Widget build(BuildContext context) {
    return WorkbenchSessionRail(
      collapsed: widget.collapsed && !_forceExpanded,
      currentPage: _page,
      onPageSelected: (page) => setState(() {
        _forceExpanded = true;
        _page = page;
      }),
      stageController: widget.stageController,
    );
  }
}

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

  AiConversationSession sessionOf(
    String id,
    String title,
    DateTime updatedAt,
  ) => AiConversationSession(
    id: id,
    title: title,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    messageIds: const [],
  );

  /// 泵独立会话栏（组件面）。restoreSession 逐条 insert(0)：
  /// 按 (更早, 昨天, 今天) 顺序恢复后列表头为今天组。
  /// 批3 UI35-310：页态上提调用方（[currentPage] / [onPageSelected]——
  /// 生产由 shell 持有；本 harness 以本地 State 模拟）。
  Future<AppProvider> pumpRail(
    WidgetTester tester, {
    bool collapsed = false,
    void Function(AppProvider app)? seed,
    WorkbenchStageController? stageController,
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
            body: _RailHost(
              collapsed: collapsed,
              stageController: stageController ?? WorkbenchStageController(),
            ),
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
          service.restoreSession(
            sessionOf(
              'old',
              'ancient chat',
              today.subtract(const Duration(days: 10)),
            ),
          );
          service.restoreSession(
            sessionOf(
              'yest',
              'yesterday chat',
              today.subtract(const Duration(days: 1)),
            ),
          );
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

    testWidgets('新建会话按钮 → createSession + recordSession 统计（§6.4 字段 2）', (
      tester,
    ) async {
      final app = await pumpRail(tester);
      final service = app.aiPanel.aiConversationService;
      expect(service.sessions, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('workbench_new_session_button')),
      );
      await tester.pumpAndSettle();

      expect(service.sessions.length, 1, reason: '新建会话入账（经典可见，AC2.3 同源）');
      expect(service.currentSession, isNotNull);
      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      final sessions = export.weeklySessions.values.fold<int>(
        0,
        (a, b) => a + b,
      );
      expect(sessions, 1, reason: '新建按钮路径记一次 session 统计');

      await drainPersistDebounce(tester);
    });

    testWidgets('AC2.2 组件面：点击条目 → switchSession（消息加载由 chat view 承担）', (
      tester,
    ) async {
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

      await tester.tap(
        find.byKey(const ValueKey('workbench_session_menu_doomed')),
      );
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
          service.restoreSession(
            sessionOf('a2', 'archived one', DateTime.now()),
          );
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
    testWidgets('collapsed rail：活动条渲染 + 会话图标存在（逐会话图标列随 A1 下线）', (tester) async {
      await pumpRail(
        collapsed: true,
        tester,
        seed: (app) {
          final service = app.aiPanel.aiConversationService;
          final now = DateTime.now();
          service.restoreSession(sessionOf('c1', 'collapsed one', now));
          service.restoreSession(sessionOf('c2', 'collapsed two', now));
        },
      );

      expect(find.text('collapsed one'), findsNothing, reason: '收窄态不渲染标题');
      expect(find.text('Sessions'), findsNothing);
      expect(
        find.byKey(const ValueKey('workbench_activity_sessions')),
        findsOneWidget,
        reason: '收窄态 = 纯活动条（v2 A1）',
      );
      expect(
        find.byIcon(LucideIcons.messageCircle),
        findsOneWidget,
        reason: '会话页图标存在（活动条唯一入口，与会话数无关）',
      );
      expect(
        find.byKey(const ValueKey('workbench_session_icon_c2')),
        findsNothing,
        reason: '逐会话图标列已下线（A1；点击行为由下方 A2 路由用例断言）',
      );
      expect(
        find.byKey(const ValueKey('workbench_new_session_button')),
        findsNothing,
        reason: '收窄态新建入口随旧列下线（已知中间态，A2 舞台 tab 头栏补齐）',
      );

      await drainPersistDebounce(tester);
    });

    testWidgets(
      '收窄态点会话图标 → 展开 rail 至 196 会话抽屉（批3 UI35-310，不开舞台）',
      (tester) async {
        final stageController = WorkbenchStageController();
        await pumpRail(
          tester,
          collapsed: true,
          stageController: stageController,
        );

        expect(stageController.stageVisible, isFalse, reason: '前置：舞台不可见');
        expect(stageController.tabs, isEmpty);

        await tester.tap(
          find.byKey(const ValueKey('workbench_activity_sessions')),
        );
        await tester.pumpAndSettle();

        // 批3：点击 = 展开 rail 抽屉（会话页），不开舞台 tab。
        expect(find.byType(SessionListView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workbench_new_session_button')),
          findsOneWidget,
          reason: '展开后新建入口随会话页头栏出现',
        );
        expect(stageController.stageVisible, isFalse, reason: '不开舞台');
        expect(stageController.tabs, isEmpty, reason: '零舞台 tab');

        await drainPersistDebounce(tester);
      },
    );

    testWidgets('1024 宽：rail 保持 240 token 宽、无 overflow', (tester) async {
      await pumpShellAt(tester, const Size(1024, 768));

      final railSize = tester.getSize(
        find.byKey(const ValueKey('workbench_session_rail_slot')),
      );
      expect(
        railSize.width,
        AppDesignSystem.workbenchSessionListWidth,
        reason:
            'design §8【二】1024 校验：900−240=660 为收起态 region 全域最坏（AI-CW 批文档口径）；'
            '本例 1024 档 = 1024−240=784，rail 不收窄',
      );
      expect(tester.takeException(), isNull, reason: 'NF3.1 无 overflow');
    });

    testWidgets('<900 宽：rail 收窄 44、无 overflow', (tester) async {
      await pumpShellAt(tester, const Size(800, 600));

      final railSize = tester.getSize(
        find.byKey(const ValueKey('workbench_session_rail_slot')),
      );
      expect(railSize.width, AppDesignSystem.workbenchRailActivityBarWidth);
      expect(tester.takeException(), isNull, reason: 'NF3.1 无 overflow');
    });
  });

  group('v2 A3 历史页（活动条图标 / 页切换 / 收窄态路由）', () {
    testWidgets('活动条三图标存在 + 终态序 会话→保存的查询→历史（v2 §7-7，A4 要点 ⑥）', (tester) async {
      await pumpRail(tester);

      expect(
        find.byKey(const ValueKey('workbench_activity_history')),
        findsOneWidget,
        reason: '历史图标随 A3 上线',
      );
      expect(find.byIcon(LucideIcons.history), findsOneWidget);
      final sessionsCenter = tester.getCenter(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      final savedQueriesCenter = tester.getCenter(
        find.byKey(const ValueKey('workbench_activity_savedQueries')),
      );
      final historyCenter = tester.getCenter(
        find.byKey(const ValueKey('workbench_activity_history')),
      );
      expect(
        sessionsCenter.dy,
        lessThan(savedQueriesCenter.dy),
        reason: '终态图标序第 1/2 位 = 会话/保存的查询（A4 插入第二位，v2 §7-7）',
      );
      expect(
        savedQueriesCenter.dy,
        lessThan(historyCenter.dy),
        reason: '终态图标序第 2/3 位 = 保存的查询/历史（波间中间态已收敛）',
      );

      await drainPersistDebounce(tester);
    });

    testWidgets('展开态点历史图标 → 内容页切到 QueryHistoryListView（同源组件）', (tester) async {
      await pumpRail(tester);

      expect(find.byType(SessionListView), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_history')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QueryHistoryListView), findsOneWidget);
      expect(find.byType(SessionListView), findsNothing);
      expect(
        find.byKey(const ValueKey('workbench_history_search')),
        findsOneWidget,
        reason: '顶行搜索框随页渲染',
      );

      // 切回会话页（页切换可逆）。
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionListView), findsOneWidget);

      await drainPersistDebounce(tester);
    });

    testWidgets('收窄态点历史图标 → 展开 rail 历史抽屉（批3 UI35-310，不开舞台）', (
      tester,
    ) async {
      final stageController = WorkbenchStageController();
      await pumpRail(tester, collapsed: true, stageController: stageController);

      expect(stageController.stageVisible, isFalse, reason: '前置：舞台不可见');

      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_history')),
      );
      await tester.pumpAndSettle();

      // 批3：点击 = 展开 rail 抽屉（历史页），不开舞台 tab。
      expect(find.byType(QueryHistoryListView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench_history_search')),
        findsOneWidget,
        reason: '历史页搜索框随抽屉渲染',
      );
      expect(stageController.stageVisible, isFalse);
      expect(stageController.tabs, isEmpty);

      await drainPersistDebounce(tester);
    });
  });

  group('v2 A4 保存的查询页（页切换 / 收窄态路由）', () {
    testWidgets('展开态点保存的查询图标 → 内容页切到 SavedQueryListView（同源组件）', (tester) async {
      await pumpRail(tester);

      expect(find.byType(SessionListView), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_savedQueries')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SavedQueryListView), findsOneWidget);
      expect(find.byType(SessionListView), findsNothing);
      expect(
        find.byKey(const ValueKey('workbench_saved_queries_empty')),
        findsOneWidget,
        reason: '本地空态随页渲染（§8-8 本地空态）',
      );

      // 切回会话页（页切换可逆）。
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionListView), findsOneWidget);

      await drainPersistDebounce(tester);
    });

    testWidgets(
      '收窄态点保存的查询图标 → 展开 rail 保存查询抽屉（批3 UI35-310，不开舞台）',
      (tester) async {
        final stageController = WorkbenchStageController();
        await pumpRail(
          tester,
          collapsed: true,
          stageController: stageController,
        );

        expect(stageController.stageVisible, isFalse, reason: '前置：舞台不可见');

        await tester.tap(
          find.byKey(const ValueKey('workbench_activity_savedQueries')),
        );
        await tester.pumpAndSettle();

        // 批3：点击 = 展开 rail 抽屉（保存的查询页），不开舞台 tab。
        expect(find.byType(SavedQueryListView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workbench_saved_queries_empty')),
          findsOneWidget,
          reason: '本地空态随抽屉渲染',
        );
        expect(stageController.stageVisible, isFalse);
        expect(stageController.tabs, isEmpty);

        await drainPersistDebounce(tester);
      },
    );
  });

  // 批3 评审 P1#2 补覆盖：抽屉「载入编辑器槽」动线端到端（rail 页
  // onLoadIntoEditor 绑 stageController.openEditorSlot——
  // workbench_session_rail.dart 内容页三抽屉装配）。旧 stage_test A3/A4
  // 载入用例随舞台抽屉退役删除，本组接住该动线回归网。
  group('抽屉载入编辑器槽动线（onLoadIntoEditor → openEditorSlot）', () {
    testWidgets('历史抽屉条目 Enter → 舞台 sqlStudio 容器 tab（edit 子态）'
        '装载该条 SQL', (tester) async {
      final stageController = WorkbenchStageController();
      final app = await pumpRail(tester, stageController: stageController);
      expect(stageController.tabs, isEmpty, reason: '前置：舞台无 tab');

      // 播种一条历史（沿被删 A3 用例：provider 公有 API）。
      await app.queryHistory.addQueryHistory(
        sql: 'SELECT 7 AS seven',
        connectionId: 'conn_history',
        connectionName: 'Local MySQL',
      );
      await tester.pumpAndSettle();

      // 切到「查询历史」抽屉。
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_history')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QueryHistoryListView), findsOneWidget);

      // 载入动线（沿 openEditorSlot AC5.5 既有断言先例）：单击行（聚焦，
      // 双击判别窗 ≈300ms，pump 越窗）→ Enter（历史条目主动作）。
      await tester.tap(find.text('SELECT 7 AS seven'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final tab = stageController.activeTab;
      expect(
        tab?.container,
        WorkbenchStageContainerKind.sqlStudio,
        reason: '载入 = 舞台 sqlStudio 容器 tab（接线断则此处静默空）',
      );
      expect(tab?.subKind, SqlStudioSubKind.edit, reason: 'edit 子态（编辑器槽）');
      expect(
        tab?.initialSql,
        'SELECT 7 AS seven',
        reason: '编辑器槽装载该条目 SQL（AC5.2 载入不执行）',
      );
      expect(stageController.stageVisible, isTrue);
      expect(stageController.tabs, hasLength(1));

      await drainPersistDebounce(tester);
    });
    // 保存的查询抽屉同构：SavedQueryListView.onLoadIntoEditor 与历史抽屉
    // 绑同一 openEditorSlot（rail 装配处相邻三行），交互面一致（单击聚焦 +
    // Enter/双击载入），不重复覆盖。
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

  // 批3 T7-R 红测先行（UI35-310，.specs/tasks-v3.5-ui.md §3-B01 + §4-P3）：
  // sessionList/history/savedQueries 退出舞台枚举——收窄态活动条点击从
  // 「开舞台单例 tab」（R6 接缝，上方既有用例断言的现行为）改为
  // 「rail 收窄 44 → 展开 rail 至 196 内容页切对应抽屉」；rail 已展开时
  // 点另一图标 = 切抽屉页。全程文本/几何断言，不引用新枚举类型名。
  // 上方「收窄态点 xx 图标 → stageController.openXxx 被调」三用例断言的
  // 是被替换的旧行为，实现批落地时随之适配（本组为其红态对偶）。
  group('UI35-310 收窄态活动条点击 = 展开 rail 抽屉（不开舞台 tab）', () {
    /// 泵整壳（带 LayoutPreferencesProvider：本组路径会开舞台，
    /// shell 舞台布局段消费对话列持久化宽度；手法沿
    /// ai_workbench_shell_test.dart pumpShell 装配）。
    Future<AppProvider> pumpShellWithLayoutAt(
      WidgetTester tester,
      Size surface,
    ) async {
      final app = AppProvider();
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
      await tester.binding.setSurfaceSize(surface);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppProvider>.value(value: app),
            ChangeNotifierProvider<LayoutPreferencesProvider>(
              create: (_) => LayoutPreferencesProvider()..load(),
            ),
          ],
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

    testWidgets('收窄态点「会话」→ rail 展开至 240（活动条 44 + 内容 196）+ '
        '抽屉出现 + 不开舞台', (tester) async {
      await pumpShellWithLayoutAt(tester, const Size(800, 600));
      // 800 < 900（stage 不可见分支断点）→ rail 收窄 44。
      expect(
        tester.getSize(find.byKey(const ValueKey('workbench_session_rail_slot'))).width,
        AppDesignSystem.workbenchRailActivityBarWidth,
        reason: '前置：收窄态',
      );
      expect(find.byType(WorkbenchStage), findsNothing, reason: '前置：舞台隐藏');

      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();

      // 展开至 196 内容页（总宽 = workbenchSessionListWidth 240）。
      expect(
        tester.getSize(find.byKey(const ValueKey('workbench_session_rail_slot'))).width,
        AppDesignSystem.workbenchSessionListWidth,
        reason: 'UI35-310：点击 → rail 展开至 240（44 + 196），不再保持 44',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workbench_session_rail_slot')),
          matching: find.byType(SessionListView),
        ),
        findsOneWidget,
        reason: '会话抽屉在 rail 内容页出现',
      );
      // 不开舞台：舞台仍隐藏（旧行为 = sessionList 单例 tab 开舞台，红）。
      expect(
        find.byType(WorkbenchStage),
        findsNothing,
        reason: 'UI35-310：点击不开舞台 tab（sessionList 退出舞台枚举）',
      );
      expect(find.byType(SessionListView), findsOneWidget);

      await drainPersistDebounce(tester);
    });

    testWidgets('rail 已展开时点另一图标 = 切抽屉页（不开舞台）', (tester) async {
      await pumpShellWithLayoutAt(tester, const Size(800, 600));
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_history')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workbench_session_rail_slot')),
          matching: find.byType(QueryHistoryListView),
        ),
        findsOneWidget,
        reason: '切到历史抽屉页',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workbench_session_rail_slot')),
          matching: find.byType(SessionListView),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('workbench_session_rail_slot'))).width,
        AppDesignSystem.workbenchSessionListWidth,
        reason: '切抽屉不改变 rail 展开宽度',
      );
      expect(
        find.byType(WorkbenchStage),
        findsNothing,
        reason: '切抽屉不开舞台（history 退出舞台枚举）',
      );

      await drainPersistDebounce(tester);
    });
  });
}
