// AI 工作台上下文芯片 T11 组件测试（design-ai-workbench §5.1/§7.3 + §11.1 R3）。
//
// 覆盖：AC3.1 连接名+库名 / AC3.2 来源标识（活动 tab / 侧栏）/
// AC3.4 未锁定跟随更新（tab 与侧栏双源）+ 同步写生效上下文 /
// AC3.5 锁定不随切换变、解锁恢复、锁定随会话走 / AC3.6 未设置态引导
// 不阻塞输入 / §7.3 连接名 id 兜底 / 同步写仅限工作台可见期间（§5.1）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_chip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_picker.dart';
import 'package:dbmaster/providers/app_provider.dart';

import '../../helpers/fake_pro_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeProModule fakePro;

  DbServer serverOf(String id, String name, {String? database}) => DbServer(
    id: id,
    name: name,
    type: DatabaseType.sqlite,
    host: 'localhost',
    port: 0,
    username: 'root',
    password: null,
    database: database,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'read':
          case 'write':
          case 'delete':
          case 'deleteAll':
            return null;
          case 'readAll':
            return <String, String>{};
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    fakePro.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  /// 泵独立芯片（组件面）。[visible] 控制工作台可见性门（同步写的前提）。
  Future<AppProvider> pumpChip(
    WidgetTester tester, {
    bool visible = true,
    Future<void> Function(AppProvider app)? seed,
  }) async {
    fakePro = FakeProModule(isPro: true);
    final app = AppProvider(proModule: fakePro);
    if (seed != null) {
      await seed(app);
    }
    if (visible) {
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
    }
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Column(
              children: [
                const WorkbenchContextChip(
                  key: ValueKey('workbench_context_chip_slot'),
                ),
                // 伴随输入面：断言芯片各态（尤其未设置态）不阻塞输入。
                const TextField(
                  key: ValueKey('chip_test_companion_input'),
                ),
              ],
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

  group('跟随态（AC3.1/AC3.2）', () {
    testWidgets('显示连接名 + 库名 + 「活动 tab」来源徽标 + 锁定动作', (tester) async {
      await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_1', 'MySQL 主库'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_1',
            databaseName: 'db_from_tab',
          );
        },
      );

      expect(find.text('MySQL 主库'), findsOneWidget);
      expect(find.text('· db_from_tab'), findsOneWidget);
      expect(find.text('Active tab'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench_context_chip_lock_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workbench_context_chip_unlock_button')),
        findsNothing,
      );
    });

    testWidgets('无 tab 上下文、侧栏选中 → 「Sidebar」徽标；切换侧栏选中芯片跟随', (tester) async {
      await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_2', '分析库', database: 'db_on_server'),
          );
          await app.connection.saveConnection(
            serverOf('conn_3', '报表库', database: 'db_report'),
          );
          app.sidebar.selectConnection('conn_2');
        },
      );

      expect(find.text('分析库'), findsOneWidget);
      expect(find.text('· db_on_server'), findsOneWidget);
      expect(find.text('Sidebar'), findsOneWidget);

      // AC3.4 侧栏源：切换侧栏选中 → 芯片跟随更新。
      tester
          .element(find.byType(WorkbenchContextChip))
          .read<AppProvider>()
          .sidebar
          .selectConnection('conn_3');
      await tester.pumpAndSettle();
      expect(find.text('报表库'), findsOneWidget);
      expect(find.text('· db_report'), findsOneWidget);
    });
  });

  group('锁定态（AC3.5）', () {
    testWidgets('锁定后不随 tab 切换变、来源徽标消失；解锁恢复跟随', (tester) async {
      final app = await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_locked', '锁定目标库'),
          );
          await app.connection.saveConnection(
            serverOf('conn_other', '其他库'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_locked',
            databaseName: 'locked_db',
          );
          app.aiPanel.ensureSession();
        },
      );

      // 锁定当前上下文。
      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_lock_button')),
      );
      await tester.pumpAndSettle();

      final lock = app.aiPanel.workbenchContextLock;
      expect(lock, isNotNull);
      expect(lock?.connectionId, 'conn_locked');
      expect(lock?.databaseName, 'locked_db');

      // 锁定态：锁定徽标 + 解锁动作；来源徽标不渲染（T08 契约：
      // 锁定时 effectiveWorkbenchContext.source 不可用于来源徽标）。
      expect(
        find.byKey(const ValueKey('workbench_context_chip_locked_badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workbench_context_chip_unlock_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workbench_context_chip_source_badge')),
        findsNothing,
      );

      // 切换活动 tab → 芯片保持锁定值不变（AC3.5 前半）。
      await app.tab.openQueryTab(
        connectionId: 'conn_other',
        databaseName: 'other_db',
      );
      await tester.pumpAndSettle();
      expect(find.text('锁定目标库'), findsOneWidget, reason: '锁定不跟随 tab 切换');
      expect(find.text('· locked_db'), findsOneWidget);
      expect(find.text('· other_db'), findsNothing);
      // 同步写以锁定值为准（生效上下文 = 锁定快照）。
      expect(app.aiPanel.selectedConnectionId, 'conn_locked');

      // 解锁 → 恢复跟随当前 tab（AC3.5 后半）。
      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_unlock_button')),
      );
      await tester.pumpAndSettle();
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(find.text('其他库'), findsOneWidget);
      expect(find.text('Active tab'), findsOneWidget);
      expect(app.aiPanel.selectedConnectionId, 'conn_other');

      await drainPersistDebounce(tester);
    });

    testWidgets('锁定随会话走：切换会话各带各的锁定（AC3.5 会话粒度）', (tester) async {
      final app = await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_a', '连接 A'),
          );
          await app.connection.saveConnection(
            serverOf('conn_b', '连接 B'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_b',
            databaseName: 'db_b',
          );
          app.aiPanel.ensureSession();
        },
      );
      final service = app.aiPanel.aiConversationService;

      // 会话 1 锁定到 conn_b（当前跟随值）。
      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_lock_button')),
      );
      await tester.pumpAndSettle();
      final lockedSessionId = service.currentSession?.id;

      // 新建会话（无锁定）→ 芯片恢复跟随 tab。
      app.aiPanel.aiConversationService.createSession();
      await tester.pumpAndSettle();
      expect(find.text('连接 B'), findsOneWidget, reason: '新会话无锁定，恢复跟随');
      expect(app.aiPanel.selectedConnectionId, 'conn_b');

      // 切回会话 1 → 锁定快照恢复生效。
      app.aiPanel.switchSession(lockedSessionId!);
      await tester.pumpAndSettle();
      expect(app.aiPanel.workbenchContextLock, isNotNull);
      expect(app.aiPanel.workbenchContextLock?.connectionId, 'conn_b');

      await drainPersistDebounce(tester);
    });
  });

  group('未设置态与错误路径（AC3.6 / §7.3）', () {
    testWidgets('无任何上下文：未设置 + 设置引导，不阻塞输入', (tester) async {
      await pumpChip(tester);

      expect(find.text('Not set'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench_context_chip_setup')),
        findsOneWidget,
      );
      // 不显示错误连接名（无 context 名可显示）。
      expect(find.text('MySQL 主库'), findsNothing);

      // R2 迁移（T18）：设置出口 = 上下文选择器（选择已有连接为主，
      // 新建为次），不再是 ConnectionDialog。
      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_setup')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);
    });

    testWidgets('未设置态不阻塞输入：伴随输入框可正常录入', (tester) async {
      await pumpChip(tester);

      await tester.enterText(
        find.byKey(const ValueKey('chip_test_companion_input')),
        'free chat without context',
      );
      await tester.pump();

      expect(
        find.text('free chat without context'),
        findsOneWidget,
        reason: 'AC3.6：未设置态芯片存在时输入仍可用',
      );
    });

    testWidgets('§7.3 错误路径：connectionId 不在 savedConnections → 名字以 id 兜底', (tester) async {
      await pumpChip(
        tester,
        seed: (app) async {
          await app.tab.openQueryTab(
            connectionId: 'ghost_conn',
            databaseName: 'db_x',
          );
        },
      );

      expect(find.text('ghost_conn'), findsOneWidget, reason: 'id 兜底，不显示 null');
      expect(find.text('· db_x'), findsOneWidget);
    });
  });

  group('R2 主体出口（T18）：三态主体均可点开 picker', () {
    testWidgets('跟随态：主体点击开 picker（key workbench_context_chip_body）',
        (tester) async {
      await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_body', '主体库'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_body',
            databaseName: 'body_db',
          );
        },
      );

      expect(find.byType(WorkbenchContextPicker), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_body')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsNothing);
    });

    testWidgets('锁定态：主体点击开 picker', (tester) async {
      final app = await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_locked_body', '锁定主体库'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_locked_body',
            databaseName: 'locked_body_db',
          );
          app.aiPanel.ensureSession();
        },
      );
      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_lock_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workbench_context_chip_locked_badge')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_body')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Esc 只关 picker，不碰锁定。
      expect(app.aiPanel.workbenchContextLock, isNotNull);

      await drainPersistDebounce(tester);
    });

    testWidgets('未设置态：主体（非 setup 按钮）点击开 picker', (tester) async {
      await pumpChip(tester);

      await tester.tap(find.text('Not set'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);
    });

    testWidgets('键盘可达：Tab 聚焦主体 → Enter 开 picker', (tester) async {
      await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_kb', '键盘库'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_kb',
            databaseName: 'kb_db',
          );
        },
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byType(WorkbenchContextPicker),
        findsOneWidget,
        reason: 'R2：主体 FocusableActionDetector Enter/Space 激活',
      );
    });
  });

  group('生效上下文同步（design §5.1）', () {
    testWidgets('工作台可见期间：effective 上下文经 setSelected 写入', (tester) async {
      final app = await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_sync', '同步目标库', database: 'sync_db'),
          );
          app.sidebar.selectConnection('conn_sync');
        },
      );

      expect(app.aiPanel.selectedConnectionId, 'conn_sync');
      expect(app.aiPanel.selectedDatabaseName, 'sync_db');
    });

    testWidgets('工作台不可见期间：不写入（Offstage 保活期间芯片停写）', (tester) async {
      final app = await pumpChip(
        tester,
        visible: false,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_hidden', '隐藏库'),
          );
        },
      );

      await app.tab.openQueryTab(
        connectionId: 'conn_hidden',
        databaseName: 'hidden_db',
      );
      await tester.pumpAndSettle();

      expect(app.aiPanel.selectedConnectionId, isNull, reason: '不可见期间不写');
      expect(app.aiPanel.selectedDatabaseName, isNull);

      // 重新进入工作台 → 同步恢复。
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
      await tester.pumpAndSettle();
      expect(app.aiPanel.selectedConnectionId, 'conn_hidden');
      expect(app.aiPanel.selectedDatabaseName, 'hidden_db');
    });
  });
}
