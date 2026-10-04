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
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_chip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_picker.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart';
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';

import '../../helpers/fake_pro_module.dart';

/// isRunning 可控的 runner 桩（T6 提示用例）：isRunning 为本组唯一触达面；
/// 会话切换路径触达的 ledger 给真实实现（clearAll 零副作用）、复位桩为
/// no-op，其余成员 noSuchMethod 兜底（AGENTS §5.4 内部服务桩惯例）。
class _StubAgentRunner implements AgentLoopRunner {
  _StubAgentRunner({this.running = false});

  final bool running;

  @override
  bool get isRunning => running;

  @override
  final AgentPermissionLedger ledger = AgentPermissionLedger();

  @override
  void resetForSessionSwitch() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// aiPanel getter 覆盖为注入桩 runner 的独立 AiPanelProvider（AppProvider
/// 的 aiPanel 为 late final，组件树级无法替换默认 runner——
/// workbench_chat_view_agent_test.dart 头注同款约束；除 agentRunner 外
/// 面板装配全部真实，仅服务「run 活跃」提示用例）。
class _RunnerStubAppProvider extends AppProvider {
  _RunnerStubAppProvider({required this.stubPanel, required super.proModule});

  final AiPanelProvider stubPanel;

  @override
  AiPanelProvider get aiPanel => stubPanel;
}

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
  /// [appBuilder] 供「run 活跃」用例注入桩 runner 面板（默认真实 AppProvider）。
  Future<AppProvider> pumpChip(
    WidgetTester tester, {
    bool visible = true,
    AppProvider Function(FakeProModule proModule)? appBuilder,
    Future<void> Function(AppProvider app)? seed,
  }) async {
    fakePro = FakeProModule(isPro: true);
    final app = appBuilder != null
        ? appBuilder(fakePro)
        : AppProvider(proModule: fakePro);
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

  group('T6 未选库标记（E2E 缺陷①显示面）', () {
    testWidgets('跟随态：有连接但未选库 → 库名槽位显示标记；有库 → 现状不变',
        (tester) async {
      await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_nodb', '无库连接'),
          );
          await app.connection.saveConnection(
            serverOf('conn_db', '有库连接', database: 'db_present'),
          );
          app.sidebar.selectConnection('conn_nodb');
        },
      );

      expect(find.text('无库连接'), findsOneWidget);
      expect(find.text('· No database'), findsOneWidget);

      // 切到有库连接 → 「· 库名」现状不变，标记消失。
      tester
          .element(find.byType(WorkbenchContextChip))
          .read<AppProvider>()
          .sidebar
          .selectConnection('conn_db');
      await tester.pumpAndSettle();
      expect(find.text('· db_present'), findsOneWidget);
      expect(find.text('· No database'), findsNothing);
    });

    testWidgets('锁定态：连接级锁（databaseName null）→ 同槽位同款标记',
        (tester) async {
      final app = await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_lock_nodb', '锁定无库连接'),
          );
          app.aiPanel.ensureSession();
          // 「仅锁定连接」同款连接级锁（_lockConnectionOnly 落锁形态）。
          app.aiPanel.lockWorkbenchContext('conn_lock_nodb', null);
        },
      );

      expect(app.aiPanel.workbenchContextLock, isNotNull);
      expect(
        find.byKey(const ValueKey('workbench_context_chip_locked_badge')),
        findsOneWidget,
      );
      expect(find.text('锁定无库连接'), findsOneWidget);
      expect(find.text('· No database'), findsOneWidget);

      await drainPersistDebounce(tester);
    });

    testWidgets('未设置态：现状不变，无标记', (tester) async {
      await pumpChip(tester);

      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('· No database'), findsNothing);
    });
  });

  group('T6 运行中改选提示（D15 快照契约显示面）', () {
    testWidgets('run 活跃：解锁上下文 → 「下次运行生效」提示 snackbar',
        (tester) async {
      final app = await pumpChip(
        tester,
        appBuilder: (proModule) => _RunnerStubAppProvider(
          proModule: proModule,
          stubPanel: AiPanelProvider(
            agentRunner: _StubAgentRunner(running: true),
          ),
        ),
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_unlock', '解锁目标库', database: 'db_unlock'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_unlock',
            databaseName: 'db_unlock',
          );
          app.aiPanel.ensureSession();
          app.aiPanel.lockWorkbenchContext('conn_unlock', 'db_unlock');
        },
      );

      expect(
        find.byKey(const ValueKey('workbench_context_chip_unlock_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_unlock_button')),
      );
      await tester.pumpAndSettle();

      // 解锁回跟随（锁定语义零改动）+ run 活跃提示在。
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(
        find.text(AppLocalizationsEn().workbenchContextChangeWhileRunning),
        findsOneWidget,
      );

      // snackbar 到期 + 退出动画（清 pending timer，防不变量拦截）。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await drainPersistDebounce(tester);
    });

    testWidgets('run 空闲：解锁上下文 → 零提示（现状不变）', (tester) async {
      final app = await pumpChip(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_unlock_idle', '空闲解锁库', database: 'db_idle'),
          );
          await app.tab.openQueryTab(
            connectionId: 'conn_unlock_idle',
            databaseName: 'db_idle',
          );
          app.aiPanel.ensureSession();
          app.aiPanel.lockWorkbenchContext('conn_unlock_idle', 'db_idle');
        },
      );

      await tester.tap(
        find.byKey(const ValueKey('workbench_context_chip_unlock_button')),
      );
      await tester.pumpAndSettle();

      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(find.byType(SnackBar), findsNothing);
      await drainPersistDebounce(tester);
    });
  });
}
