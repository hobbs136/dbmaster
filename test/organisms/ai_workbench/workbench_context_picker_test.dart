// AI 工作台上下文选择器测试（design-ai-workbench §4.2 R2 修订，T18）。
//
// 覆盖 AC-R2 可测项：
//   R2-2 选连接+库 → lock==(connId,dbName) 且 selected 同步、芯片转锁定态；
//   R2-4 跟随态改选转锁定；R2-7 无连接空态引导 + 新建入口在 picker 内；
//   R2-8 密码取消/连接失败零写入且 picker 保持；R2-9 库加载失败内联错误+重试；
//   R2-10 三态取消零变化；R2-11 键盘全程；R2-12 1024×768 几何；
//   R2-13 重复选择 metadata 键唯一覆盖；R2-14 新组件零 Colors.xxx 硬编码；
//   分区语义（未分组在前/组头不可点/孤儿分组按未分组）。
//
// R2-1（未设置主按钮开 picker 非 ConnectionDialog）在
// workbench_context_chip_test.dart 的迁移用例覆盖。
// R2-3（真库守卫解除）按任务书登记待补（与 T15 同批，测试服务器阻塞）。
//
// 组件级纪律：真实 AppProvider + DatabaseService；连接状态用
// registerConnectedAdapterForTest 测试钩子注入（本组件为纯结构/交互面，
// 数据修改路径不在此层——真库守卫链路由 T13/R2-3 覆盖）。
import 'dart:io';

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
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/organisms/connection/connection_dialog.dart';
import 'package:dbmaster/organisms/connection/password_prompt_dialog.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart';
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/database_abstract.dart';

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

const ValueKey _launcherKey = ValueKey('picker_test_launcher');

DbServer serverOf(
  String id,
  String name, {
  DatabaseType type = DatabaseType.sqlite,
  String? database,
  String? groupId,
  String? host,
  int port = 0,
}) => DbServer(
  id: id,
  name: name,
  type: type,
  host: host ?? 'localhost',
  port: port,
  username: 'root',
  password: null,
  database: database,
  groupId: groupId,
);

/// getDatabases 假适配器（仅 isConnected + getDatabases 会被触达）。
class _FakeAdapter implements DatabaseAdapter {
  final List<String> dbs;
  _FakeAdapter(this.dbs);

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getDatabases() async => dbs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 首次 getDatabases 抛错、之后恢复的假适配器（R2-9 重试路径）。
class _FlakyAdapter implements DatabaseAdapter {
  int calls = 0;

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getDatabases() async {
    calls++;
    if (calls == 1) throw Exception('boom');
    return <String>['recovered_db'];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void registerConnected(AppProvider app, DbServer server, List<String> dbs) {
  app.connection.dbService.registerConnectedServerForTest(server);
  app.connection.dbService.registerConnectedAdapterForTest(
    server.id,
    _FakeAdapter(dbs),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FakeProModule? fakePro;

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
    // 纯静态断言用例不创建 fakePro；置空防双 dispose。
    fakePro?.dispose();
    fakePro = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  /// 泵宿主：芯片（同步管道在位）+ launcher。工作台可见门打开。
  /// [appBuilder] 供「run 活跃」用例注入桩 runner 面板（默认真实 AppProvider）。
  Future<AppProvider> pumpHost(
    WidgetTester tester, {
    AppProvider Function(FakeProModule proModule)? appBuilder,
    Future<void> Function(AppProvider app)? seed,
  }) async {
    fakePro = FakeProModule(isPro: true);
    final pro = fakePro!;
    final app = appBuilder != null
        ? appBuilder(pro)
        : AppProvider(proModule: pro);
    if (seed != null) {
      await seed(app);
    }
    app.setAiPanelOpen(true);
    app.setAiPanelFullscreen(true);
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
                const WorkbenchContextChip(),
                Builder(
                  builder: (launcherContext) => TextButton(
                    key: _launcherKey,
                    onPressed: () =>
                        WorkbenchContextPicker.show(launcherContext),
                    child: const Text('open picker'),
                  ),
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

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byKey(_launcherKey));
    await tester.pumpAndSettle();
  }

  /// 走完 AiSessionManager 的持久化防抖 Timer（与芯片测试同一纪律）。
  Future<void> drainPersistDebounce(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
  }

  group('结构（R2-1/布局/分区语义）', () {
    testWidgets('双栏 master-detail：栏头/连接行/库提示态/footer 次出口',
        (tester) async {
      await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_a', '连接 A'));
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      expect(find.text('Set AI context'), findsOneWidget);
      // 栏头（scope 到 picker 内；未设置态芯片主按钮 label 同为
      // aiPanelSelectConnection，是芯片侧既有语义）。
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Select Connection'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Select Database'),
        ),
        findsOneWidget,
      );
      expect(find.text('连接 A'), findsOneWidget);
      // 右栏初始提示态；footer 常驻次出口。
      expect(find.text('Connect to list databases'), findsOneWidget);
      expect(find.text('New connection'), findsOneWidget);
    });

    testWidgets('分区语义：未分组在前、组头不可点、孤儿分组按未分组',
        (tester) async {
      await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.addConnectionGroup(
            ConnectionGroup(id: 'g1', name: '生产'),
          );
          await app.connection.saveConnection(
            serverOf('conn_free', '自由连接'),
          );
          await app.connection.saveConnection(
            serverOf('conn_g1', '组内连接', groupId: 'g1'),
          );
          // groupId 指向已删组 = 孤儿 → 按未分组。
          await app.connection.saveConnection(
            serverOf('conn_orphan', '孤儿连接', groupId: 'ghost_group'),
          );
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      // 未分组（含孤儿）在分组头之前；分组头文本存在。
      expect(find.text('生产'), findsOneWidget);
      expect(find.text('自由连接'), findsOneWidget);
      expect(find.text('孤儿连接'), findsOneWidget);
      expect(find.text('组内连接'), findsOneWidget);

      final finderFree = tester.getRect(find.text('自由连接'));
      final finderOrphan = tester.getRect(find.text('孤儿连接'));
      final finderHeader = tester.getRect(find.text('生产'));
      final finderMember = tester.getRect(find.text('组内连接'));
      expect(finderFree.top, lessThan(finderHeader.top),
          reason: '未分组连接在组头之前');
      expect(finderOrphan.top, lessThan(finderHeader.top),
          reason: '孤儿分组连接按未分组处理');
      expect(finderHeader.top, lessThan(finderMember.top),
          reason: '组头在其成员之前');

      // 组头不可点：点击组头不触发任何连接激活（右栏仍为提示态）。
      await tester.tap(find.text('生产'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Connect to list databases'), findsOneWidget);
    });
  });

  group('选择即锁定（R2-2/R2-4/R2-13）', () {
    testWidgets('已连接连接：选连接 → 库列表进右栏 → 点库落锁 + 关闭 + selected 同步 + 芯片转锁定',
        (tester) async {
      final app = await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_a', '连接 A'));
          await app.connection.saveConnection(serverOf('conn_b', '连接 B'));
          registerConnected(app, serverOf('conn_a', '连接 A'),
              <String>['alpha', 'beta']);
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      // 点连接行 → 右栏装库。
      await tester.tap(find.text('连接 A'));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      // 装库只写共享缓存，不落锁、不写 selected（取消纪律）。
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(app.aiPanel.selectedConnectionId, isNull);

      // 点库行 → lock + 关闭。
      await tester.tap(find.text('beta'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsNothing);

      final lock = app.aiPanel.workbenchContextLock;
      expect(lock, isNotNull);
      expect(lock?.connectionId, 'conn_a');
      expect(lock?.databaseName, 'beta');
      // R2-2：芯片同步管道把生效上下文写入 selected。
      expect(app.aiPanel.selectedConnectionId, 'conn_a');
      expect(app.aiPanel.selectedDatabaseName, 'beta');
      // 芯片转锁定态：锁定徽标在、来源徽标不在。
      expect(
        find.byKey(const ValueKey('workbench_context_chip_locked_badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workbench_context_chip_source_badge')),
        findsNothing,
      );

      await drainPersistDebounce(tester);
    });

    testWidgets('跟随态改选 → 转锁定到新目标（R2-4）+ 打开预选当前跟随值',
        (tester) async {
      final app = await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_a', '连接 A'));
          await app.connection.saveConnection(
            serverOf('conn_b', '连接 B', database: 'db_follow'),
          );
          registerConnected(app, serverOf('conn_a', '连接 A'),
              <String>['alpha']);
          registerConnected(app, serverOf('conn_b', '连接 B'),
              <String>['follow_db']);
          await app.tab.openQueryTab(
            connectionId: 'conn_b',
            databaseName: 'db_follow',
          );
          app.aiPanel.ensureSession();
        },
      );
      expect(app.aiPanel.workbenchContextLock, isNull);

      await openPicker(tester);
      // 预选 = 当前跟随值：初始焦点在连接栏，Enter 直接激活预选行（连接 B）。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('follow_db'), findsOneWidget,
          reason: '打开即预选当前跟随上下文对应的连接');

      // ↑ 改选连接 A → Enter 装库 → Tab 到库栏 → Enter 落锁（改选转锁定）。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final lock = app.aiPanel.workbenchContextLock;
      expect(lock?.connectionId, 'conn_a');
      expect(lock?.databaseName, 'alpha');
      expect(app.aiPanel.selectedConnectionId, 'conn_a');
      expect(app.aiPanel.selectedDatabaseName, 'alpha');

      await drainPersistDebounce(tester);
    });

    testWidgets('重复选择：metadata 键唯一覆盖（R2-13）', (tester) async {
      final app = await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_a', '连接 A'));
          await app.connection.saveConnection(serverOf('conn_b', '连接 B'));
          registerConnected(app, serverOf('conn_a', '连接 A'),
              <String>['alpha']);
          registerConnected(app, serverOf('conn_b', '连接 B'), <String>['delta']);
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);
      await tester.tap(find.text('连接 A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      // 第二轮：conn_b / delta 覆盖。
      await openPicker(tester);
      await tester.tap(find.text('连接 B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('delta'));
      await tester.pumpAndSettle();

      final metadata = app.aiPanel.aiConversationService.currentSession?.metadata;
      expect(metadata, isNotNull);
      final lockKeys = metadata!.keys
          .where((k) => k == 'workbench.contextLock')
          .toList();
      expect(lockKeys.length, 1, reason: '重复选择只保留一个锁定键');
      final lock = app.aiPanel.workbenchContextLock;
      expect(lock?.connectionId, 'conn_b');
      expect(lock?.databaseName, 'delta');

      await drainPersistDebounce(tester);
    });

    testWidgets('库列表为空 → 空态 + 「仅锁定连接」落 conn 级锁', (tester) async {
      final app = await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_empty', '空库连接'));
          registerConnected(app, serverOf('conn_empty', '空库连接'), <String>[]);
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);
      await tester.tap(find.text('空库连接'));
      await tester.pumpAndSettle();

      expect(find.text('No database list for this connection'), findsOneWidget);
      await tester.tap(find.text('Use connection only'));
      await tester.pumpAndSettle();

      final lock = app.aiPanel.workbenchContextLock;
      expect(lock?.connectionId, 'conn_empty');
      expect(lock?.databaseName, isNull);

      await drainPersistDebounce(tester);
    });
  });

  group('空态与失败路径（R2-7/R2-8/R2-9）', () {
    testWidgets('无任何已保存连接：居中引导 + 新建入口在 picker 内（R2-7）', (tester) async {
      await pumpHost(
        tester,
        seed: (app) async {
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      expect(
        find.text('No connections yet. Create one to get started.'),
        findsOneWidget,
      );
      // 「新建连接」双出口都在 picker 内：空态主出口 + footer 常驻次出口。
      expect(find.text('New connection'), findsNWidgets(2));
      // 空态主出口按钮 → ConnectionDialog（picker 保持打开）。
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionDialog), findsOneWidget);
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);
    });

    testWidgets('密码取消：零写入、picker 保持（R2-8 前半）', (tester) async {
      final app = await pumpHost(
        tester,
        seed: (app) async {
          // redis：非 SQL 库不触发 embedded 网关镜像（saveConnection 只写
          // keychain），且无密码 + 非 sqlite → ensurePassword 仍弹密码框。
          await app.connection.saveConnection(
            serverOf(
              'conn_auth',
              '需要密码',
              type: DatabaseType.redis,
              host: '192.0.2.9',
              port: 6379,
            ),
          );
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      await tester.tap(find.text('需要密码'));
      await tester.pumpAndSettle();
      expect(find.byType(PasswordPromptDialog), findsOneWidget);

      // 取消密码 → picker 保持打开，零写入。
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);
      expect(find.byType(PasswordPromptDialog), findsNothing);
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(app.aiPanel.selectedConnectionId, isNull);
      expect(find.text('Connect to list databases'), findsOneWidget,
          reason: '右栏回提示态');
    });

    testWidgets('连接失败：ConnectFailureDialog + picker 保持 + 零写入（R2-8 后半）',
        (tester) async {
      // 真实链路：独占锁 SQLite 文件 → 连接必败（T10 同款手法）。
      // dart:io 的 open/lock 是真实 IO，必须经 runAsync（FakeAsync 区内
      // 真实 IO future 永不完成）。
      final dbFile = File(
        '${Directory.systemTemp.absolute.path}'
        '${Platform.pathSeparator}dbmaster_t18_picker_'
        '${DateTime.now().millisecondsSinceEpoch}.db',
      );
      dbFile.writeAsStringSync('');
      RandomAccessFile? lockHandle;
      await tester.runAsync(() async {
        lockHandle = await dbFile.open();
        await lockHandle!.lock(FileLock.exclusive);
      });
      addTearDown(() {
        try {
          lockHandle?.unlockSync();
          lockHandle?.closeSync();
        } on FileSystemException {
          // 清理尽力而为。
        }
        try {
          if (dbFile.existsSync()) dbFile.deleteSync();
        } on FileSystemException {
          // 同上。
        }
      });

      final app = await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_locked_file', '锁文件连接', host: dbFile.path),
          );
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      await tester.tap(find.text('锁文件连接'));
      // 真实文件 IO 完成于真实事件循环：runAsync 让出轮询（T10 harness 模式）。
      // 连接期间行尾是无界 loading 圈，此测试全程禁用 pumpAndSettle。
      var failureShown = false;
      for (var i = 0; i < 240 && !failureShown; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        failureShown = find.byType(ConnectFailureDialog).evaluate().isNotEmpty;
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(failureShown, isTrue, reason: '连接失败对话框应在 12s 内弹出');

      // picker 保持打开、零写入。
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(app.aiPanel.selectedConnectionId, isNull);

      // 关闭失败对话框 → picker 仍在。
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectFailureDialog), findsNothing);
      expect(find.byType(WorkbenchContextPicker), findsOneWidget);
    });

    testWidgets('库加载失败：右栏内联错误 + 重试恢复，无全局 snackbar（R2-9）',
        (tester) async {
      await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_flaky', '抖动连接'));
          app.connection.dbService
              .registerConnectedServerForTest(serverOf('conn_flaky', '抖动连接'));
          app.connection.dbService.registerConnectedAdapterForTest(
            'conn_flaky',
            _FlakyAdapter(),
          );
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      await tester.tap(find.text('抖动连接'));
      await tester.pumpAndSettle();

      // 内联错误行（非全局 snackbar）。
      expect(find.text('Unable to load databases'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // 重试 → 恢复列表。
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('recovered_db'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('取消与键盘（R2-10/R2-11）', () {
    testWidgets('三态 Esc 取消零变化（R2-10）', (tester) async {
      // (a) 未设置态。
      final app = await pumpHost(
        tester,
        seed: (app) async {
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsNothing);
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(app.aiPanel.selectedConnectionId, isNull);

      // (b) 跟随态（tab 绑定）。
      await app.connection.saveConnection(
        serverOf('conn_f', '跟随连接', database: 'db_follow'),
      );
      await app.tab.openQueryTab(
        connectionId: 'conn_f',
        databaseName: 'db_follow',
      );
      await tester.pumpAndSettle();
      await openPicker(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(app.aiPanel.selectedConnectionId, 'conn_f');
      expect(app.aiPanel.selectedDatabaseName, 'db_follow');

      // (c) 锁定态。
      app.aiPanel.lockWorkbenchContext('conn_f', 'db_follow');
      await tester.pumpAndSettle();
      await openPicker(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final lock = app.aiPanel.workbenchContextLock;
      expect(lock?.connectionId, 'conn_f');
      expect(lock?.databaseName, 'db_follow');

      // (d) 解锁回跟随态后，浏览过连接（装库已写缓存）再取消 → 仍零落锁。
      app.aiPanel.unlockWorkbenchContext();
      await tester.pumpAndSettle();
      registerConnected(app, serverOf('conn_f', '跟随连接'), <String>['db_follow']);
      await openPicker(tester);
      // 芯片（跟随态）同样渲染「跟随连接」，tap 需 scope 到 picker。
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('跟随连接')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('db_follow')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.aiPanel.workbenchContextLock, isNull);

      await drainPersistDebounce(tester);
    });

    testWidgets('键盘全程：初始焦点在连接栏，↑↓/Enter/Tab 环形（R2-11）',
        (tester) async {
      final app = await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_a', '连接 A'));
          await app.connection.saveConnection(serverOf('conn_b', '连接 B'));
          registerConnected(app, serverOf('conn_a', '连接 A'),
              <String>['alpha', 'beta']);
          registerConnected(app, serverOf('conn_b', '连接 B'), <String>['gamma']);
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);

      // 初始焦点落连接栏当前选中行：直接 Enter 提交连接 A。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget, reason: '初始焦点在连接栏，Enter 激活预选行');

      // Tab → 库栏；↓ 移动选中；Enter 提交库。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchContextPicker), findsNothing);
      expect(app.aiPanel.workbenchContextLock?.databaseName, 'beta');
      expect(app.aiPanel.workbenchContextLock?.connectionId, 'conn_a');

      // Tab 环形：Tab×2 落 footer，Enter 打开 ConnectionDialog；
      // 再 Tab 回绕到连接栏（Enter 激活连接 A 装库证明回绕成功）。
      await openPicker(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionDialog), findsOneWidget,
          reason: 'Tab×2 后焦点在 footer，Enter 触发新建连接次出口');

      // 清掉 ConnectionDialog（焦点回 footer），Tab 一次即环形回绕到连接栏；
      // Enter 激活连接 A 装库 = 回绕成功的可观察证据。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionDialog), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget,
          reason: 'Tab 从 footer 环形回绕到连接栏，Enter 激活连接 A');

      await drainPersistDebounce(tester);
    });
  });

  group('几何与静态纪律（R2-12/R2-14）', () {
    testWidgets('1024×768：内容区 440 / 连接栏 200 / 长列表内滚无溢出（R2-12）',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final databases = List<String>.generate(15, (i) => 'db_$i');
      await pumpHost(
        tester,
        seed: (app) async {
          await app.connection.saveConnection(serverOf('conn_big', '大库连接'));
          registerConnected(app, serverOf('conn_big', '大库连接'), databases);
          app.aiPanel.ensureSession();
        },
      );
      await openPicker(tester);
      await tester.tap(find.text('大库连接'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '15 库 + 320 上限内滚不应溢出');
      final contentSize = tester.getSize(
        find.byKey(const ValueKey('workbench_context_picker_content')),
      );
      expect(contentSize.width, 440, reason: '内容区总宽 440（R2 布局 token）');
      final connRow = tester.getSize(
        find.byKey(const ValueKey('workbench_context_picker_conn_conn_big')),
      );
      expect(connRow.width, 200, reason: '连接栏固定宽');
    });

    test('新组件零 Colors.xxx 硬编码 + 布局 token 落位（R2-14）', () {
      final pickerSource = File(
        '${Directory.current.path}/lib/organisms/ai_workbench/'
        'workbench_context_picker.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'\bColors\.').allMatches(pickerSource),
        isEmpty,
        reason: 'NF3.4/R2-14：picker 禁止 Colors.xxx 硬编码，取色走 themeColors',
      );

      final designSource = File(
        '${Directory.current.path}/lib/theme/design_system.dart',
      ).readAsStringSync();
      expect(
        designSource.contains(
          'static const double workbenchContextPickerWidth = 440.0;',
        ),
        isTrue,
      );
      expect(
        designSource.contains(
          'static const double workbenchContextPickerConnListWidth = 200.0;',
        ),
        isTrue,
      );
      expect(
        designSource.contains(
          'static const double workbenchContextPickerItemHeight = 32.0;',
        ),
        isTrue,
      );
      expect(
        designSource.contains(
          'static const double workbenchContextPickerListMaxHeight = 320.0;',
        ),
        isTrue,
      );
    });
  });

  group('运行中改选提示（T6，D15 快照契约显示面）', () {
    /// 注入桩 runner 的宿主（run 活跃面）：除 agentRunner 外装配全真实，
    /// 选择即锁定语义（R2）零改动。
    Future<AppProvider> pumpWithStubRunner(
      WidgetTester tester, {
      required bool running,
      required List<String> dbs,
    }) {
      return pumpHost(
        tester,
        appBuilder: (proModule) => _RunnerStubAppProvider(
          proModule: proModule,
          stubPanel: AiPanelProvider(
            agentRunner: _StubAgentRunner(running: running),
          ),
        ),
        seed: (app) async {
          await app.connection.saveConnection(
            serverOf('conn_t6', 'T6 连接'),
          );
          registerConnected(app, serverOf('conn_t6', 'T6 连接'), dbs);
          app.aiPanel.ensureSession();
        },
      );
    }

    testWidgets('run 活跃：选库提交 → 落锁语义不变 + 「下次运行生效」snackbar',
        (tester) async {
      final app = await pumpWithStubRunner(
        tester,
        running: true,
        dbs: <String>['run_db'],
      );
      await openPicker(tester);
      await tester.tap(find.text('T6 连接'));
      await tester.pumpAndSettle();
      expect(find.text('run_db'), findsOneWidget);

      await tester.tap(find.text('run_db'));
      await tester.pumpAndSettle();

      // picker 已关 + 落锁（R2 选择即锁定零改动）；run 活跃提示在。
      expect(find.byType(WorkbenchContextPicker), findsNothing);
      expect(app.aiPanel.workbenchContextLock?.connectionId, 'conn_t6');
      expect(app.aiPanel.workbenchContextLock?.databaseName, 'run_db');
      expect(
        find.text(AppLocalizationsEn().workbenchContextChangeWhileRunning),
        findsOneWidget,
      );

      // snackbar 到期 + 退出动画（清 pending timer，防不变量拦截）。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await drainPersistDebounce(tester);
    });

    testWidgets('run 空闲：选库提交 → 落锁但零提示（现状不变）', (tester) async {
      final app = await pumpWithStubRunner(
        tester,
        running: false,
        dbs: <String>['idle_db'],
      );
      await openPicker(tester);
      await tester.tap(find.text('T6 连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('idle_db'));
      await tester.pumpAndSettle();

      expect(app.aiPanel.workbenchContextLock?.databaseName, 'idle_db');
      expect(find.byType(SnackBar), findsNothing);
      await drainPersistDebounce(tester);
    });

    testWidgets('run 活跃：「仅锁定连接」提交 → 「下次运行生效」snackbar',
        (tester) async {
      final app = await pumpWithStubRunner(
        tester,
        running: true,
        dbs: <String>[],
      );
      await openPicker(tester);
      await tester.tap(find.text('T6 连接'));
      await tester.pumpAndSettle();

      expect(find.text('No database list for this connection'), findsOneWidget);
      await tester.tap(find.text('Use connection only'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkbenchContextPicker), findsNothing);
      expect(app.aiPanel.workbenchContextLock?.connectionId, 'conn_t6');
      expect(app.aiPanel.workbenchContextLock?.databaseName, isNull);
      expect(
        find.text(AppLocalizationsEn().workbenchContextChangeWhileRunning),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await drainPersistDebounce(tester);
    });
  });
}
