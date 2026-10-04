// 2b.1 observe 内容壳测试（任务书 §6.1 步骤 3）。
//
// 覆盖：
// - 未锁空态（workbenchObserveNoConnection + hint，零按钮零写手势）；
// - 引擎分段（R13）：mysql → 进程列表/引擎状态两段；redis → 内存分析；
//   其它引擎 → 不支持空态；
// - 锁切换换内容（mysql → redis 段导航按新引擎重建）；
// - 时间戳（R2）：失败不更新（恒 Not loaded yet）/ 成功更新为 Last updated；
// - 手动刷新调用计数 + 零轮询（静置不再加载）；
// - escalation 回调断言（收到正确 connectionId，不真执行切换）+ 内置 R3 三连；
// - 三态：加载中（首载 spinner）/ 空数据 commonNoData / 失败 + 重试；
// - Redis 段：Top-N 表格 / Doctor / Stats 三子视图切换 / 空态 / adapter 缺失
//   防御。
//
// 组件级纪律：真实 AppProvider + 注入 _CountingConnectionProvider（计数 +
// 失败模拟）+ dbService 测试钩子注册假 adapter（AGENTS.md §5.4 同款），
// 不 mock 数据语义本身（loadProcessList 经真实 ConnectionProvider facade
// 落缓存 → getProcessList 读缓存 = 生产同路径）。savedConnections 经
// SharedPreferences 'saved_connections' 键种子 + loadSavedConnections 载入
// （绕开 saveConnection 的网关注册——mysql 族 GatewayBacking.persistConnection
// 在无 server 会话的 widget 测试中必然失败）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_content.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_engine_status_segment.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_process_list_segment.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_redis_segment.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';

/// 计数 + 失败模拟的 ConnectionProvider（2b.1 测试注入面：AppProvider
/// 构造注入 connectionProvider，生产路径 = 真实 ConnectionProvider）。
class _CountingConnectionProvider extends ConnectionProvider {
  _CountingConnectionProvider(DatabaseService dbService)
    : super(dbService: dbService);

  int processListLoads = 0;
  int engineStatusLoads = 0;
  bool failProcessList = false;
  bool failEngineStatus = false;

  /// R3 内置链路探针：记录 switchToConnection 调用（不触真实锚定链——其
  /// 成功语义由既有 connection provider 测试覆盖；widget 测试只验证三连
  /// 接线与参数）。
  final List<String> switchToConnectionCalls = [];

  @override
  Future<bool> switchToConnection(String connectionId) async {
    switchToConnectionCalls.add(connectionId);
    return true;
  }

  @override
  Future<void> loadProcessList(String connectionId) async {
    processListLoads++;
    if (failProcessList) return; // 模拟失败：不落缓存
    await super.loadProcessList(connectionId);
  }

  @override
  Future<void> loadEngineStatus(String connectionId) async {
    engineStatusLoads++;
    if (failEngineStatus) return; // 模拟失败：不落缓存
    await super.loadEngineStatus(connectionId);
  }
}

/// MySQL 假 adapter：进程列表（ProcessListAdapter 能力路由）+ SHOW ENGINE
/// INNODB STATUS（executeQuery）+ getDatabases（R3 内置链路活性验证）。
class _FakeMysqlAdapter implements DatabaseAdapter, ProcessListAdapter {
  _FakeMysqlAdapter({
    this.processes = const <ProcessInfo>[],
    this.engineStatus = 'InnoDB engine running',
  });

  List<ProcessInfo> processes;
  String engineStatus;

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getDatabases() async => const ['seed'];

  /// saveConnection 链路（toggleReadOnly）触达的既有 concrete 方法——
  /// `implements DatabaseAdapter` 不继承默认实现，显式覆写为 no-op。
  @override
  void updateReadOnly(bool value) {}

  /// switchToConnection 活性验证/元数据链路的触达面。
  @override
  Future<void> useDatabase(String dbName) async {}

  @override
  Future<List<ProcessInfo>> getProcessList() async => processes;

  @override
  Future<bool> killProcess(int processId) async => true;

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async =>
      QueryResult(
        columns: const ['Engine', 'Status'],
        rows: [
          {'Engine': 'InnoDB', 'Status': engineStatus},
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Redis 假 adapter（extends 真 RedisAdapter：getRedisAdapter 的
/// `is RedisAdapter` 判定通过，仅覆写三数据方法，零网络）。
class _FakeRedisAdapter extends RedisAdapter {
  _FakeRedisAdapter({this.topKeys = const <Map<String, dynamic>>[]});

  List<Map<String, dynamic>> topKeys;
  String doctorText = 'DOCTOR OK';
  String statsText = 'STATS OK';
  int topNLoads = 0;
  int doctorLoads = 0;
  int statsLoads = 0;

  @override
  Future<List<Map<String, dynamic>>> getTopKeysByMemory({
    int limit = 20,
  }) async {
    topNLoads++;
    return topKeys;
  }

  @override
  Future<String> memoryDoctor() async {
    doctorLoads++;
    return doctorText;
  }

  @override
  Future<dynamic> memoryStats() async {
    statsLoads++;
    return statsText;
  }
}

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

ProcessInfo _proc({int id = 1, int time = 0, String info = 'SELECT 1'}) =>
    ProcessInfo(
      id: id,
      user: 'root',
      host: 'localhost',
      database: 'mydb',
      command: 'Query',
      time: time,
      state: 'executing',
      info: info,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService dbService;
  late _CountingConnectionProvider connection;
  late AppProvider app;
  final List<DbServer> seededServers = [];

  setUp(() {
    seededServers.clear();
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
    dbService = DatabaseService();
    connection = _CountingConnectionProvider(dbService);
    app = AppProvider(connectionProvider: connection);
  });

  tearDown(() {
    app.dispose();
  });

  Future<void> seedServers(List<DbServer> servers) async {
    // 累积式种子（多引擎并存用例：mysql + redis 同表）。
    seededServers.addAll(servers);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_connections',
      jsonEncode(seededServers.map((s) => s.toJson()).toList()),
    );
    await app.connection.loadSavedConnections();
  }

  Future<void> seedMysql({
    List<ProcessInfo> processes = const [],
    String engineStatus = 'InnoDB engine running',
  }) async {
    final server = DbServer(
      id: 'conn_mysql',
      name: 'Local MySQL',
      type: DatabaseType.mysql,
      host: 'localhost',
      port: 3306,
      username: 'root',
    );
    dbService.registerConnectedServerForTest(server);
    dbService.registerConnectedAdapterForTest(
      server.id,
      _FakeMysqlAdapter(processes: processes, engineStatus: engineStatus),
    );
    await seedServers([server]);
  }

  Future<void> seedRedis(_FakeRedisAdapter adapter) async {
    final server = DbServer(
      id: 'conn_redis',
      name: 'Local Redis',
      type: DatabaseType.redis,
      host: 'localhost',
      port: 6379,
      password: 'x',
    );
    dbService.registerConnectedServerForTest(server);
    dbService.registerConnectedAdapterForTest(server.id, adapter);
    await seedServers([server]);
  }

  void lock(String connectionId) {
    app.aiPanel.ensureSession();
    app.aiPanel.lockWorkbenchContext(connectionId, null);
  }

  Future<void> pumpObserve(
    WidgetTester tester, {
    void Function(String connectionId)? onManageInClassic,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: app,
        child: _wrap(
          WorkbenchObserveContent(onManageInClassic: onManageInClassic),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 冲刷 ensureSession 的 500ms persist 防抖 Timer（否则测试末尾
    // pending timer 触发 flutter_test 不变量断言）。
    await tester.pump(const Duration(seconds: 1));
  }

  group('2b.1 observe 内容壳', () {
    group('未锁 / 不支持空态（v2 §8-8）', () {
      testWidgets('未锁连接 → 空态（标题 + hint + 零按钮零写手势）', (tester) async {
        app.aiPanel.ensureSession();
        await pumpObserve(tester);

        expect(
          find.byKey(WorkbenchObserveContent.noConnectionKey),
          findsOneWidget,
        );
        expect(find.text('No connection locked'), findsOneWidget);
        expect(
          find.text('Lock a connection to observe its health'),
          findsOneWidget,
        );
        expect(
          find.byKey(WorkbenchObserveContent.refreshButtonKey),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('非 mysql/redis 引擎 → 不支持空态', (tester) async {
        final server = DbServer(
          id: 'conn_pg',
          name: 'Local PG',
          type: DatabaseType.postgresql,
          host: 'localhost',
          port: 5432,
          username: 'postgres',
        );
        dbService.registerConnectedServerForTest(server);
        dbService.registerConnectedAdapterForTest(
          server.id,
          _FakeMysqlAdapter(),
        );
        await seedServers([server]);
        lock('conn_pg');
        await pumpObserve(tester);

        expect(
          find.byKey(WorkbenchObserveContent.unsupportedKey),
          findsOneWidget,
        );
        expect(find.text('No observe panels for this engine'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('引擎分段与锁切换（R1/R13）', () {
      testWidgets('MySQL → 进程列表/引擎状态两段导航 + 默认激活进程列表', (tester) async {
        await seedMysql(processes: [_proc()]);
        lock('conn_mysql');
        await pumpObserve(tester);

        expect(
          find.byKey(const ValueKey('workbench_observe_segment_processList')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('workbench_observe_segment_engineStatus')),
          findsOneWidget,
        );
        expect(find.byType(WorkbenchObserveProcessListSegment), findsOneWidget);
        // 引擎状态段位于 IndexedStack 非激活槽（offstage，保活构建）。
        expect(
          find.byType(WorkbenchObserveEngineStatusSegment, skipOffstage: false),
          findsOneWidget,
        );
        // 激活段（进程列表）内容可见：八列行渲染。
        expect(find.text('SELECT 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('锁切换 → 段导航按新引擎重建（mysql → redis）', (tester) async {
        await seedMysql(processes: [_proc()]);
        await seedRedis(
          _FakeRedisAdapter(
            topKeys: [
              {'key': 'bigkey', 'bytes': 2048},
            ],
          ),
        );
        lock('conn_mysql');
        await pumpObserve(tester);
        expect(find.byType(WorkbenchObserveProcessListSegment), findsOneWidget);

        // 切换锁到 redis：段导航按新引擎重建 + 内容换 Redis 段。
        app.aiPanel.lockWorkbenchContext('conn_redis', null);
        await tester.pumpAndSettle();

        expect(find.byType(WorkbenchObserveProcessListSegment), findsNothing);
        expect(find.byType(WorkbenchObserveRedisSegment), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workbench_observe_segment_memory')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('workbench_observe_segment_processList')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('段导航点击切换激活段（引擎状态内容可见）', (tester) async {
        await seedMysql(processes: [_proc()]);
        lock('conn_mysql');
        await pumpObserve(tester);

        await tester.tap(
          find.byKey(const ValueKey('workbench_observe_segment_engineStatus')),
        );
        await tester.pumpAndSettle();

        // 引擎状态 mono 文本可见（引擎状态段激活）。
        expect(
          find.byKey(WorkbenchObserveEngineStatusSegment.textKey),
          findsOneWidget,
        );
        final text = tester.widget<SelectableText>(
          find.byKey(WorkbenchObserveEngineStatusSegment.textKey),
        );
        expect(text.data, 'InnoDB engine running');
        expect(tester.takeException(), isNull);
      });
    });

    group('时间戳（R2）', () {
      testWidgets('加载失败时间戳不更新（恒 Not loaded yet）+ 段内错误态 + 重试', (tester) async {
        connection.failProcessList = true;
        connection.failEngineStatus = true;
        await seedMysql(processes: [_proc()]);
        lock('conn_mysql');
        await pumpObserve(tester);

        // 失败不更新时间戳（R2 锁定）：恒「尚未加载」。
        expect(find.text('Not loaded yet'), findsOneWidget);
        // 激活段（进程列表）错误态 + 重试。
        expect(find.text('Failed to load data'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        // 重试 = 手动刷新同义：恢复后重试成功 → 数据可见 + 时间戳更新。
        connection.failProcessList = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('SELECT 1'), findsOneWidget);
        final ts = tester.widget<Text>(
          find.byKey(WorkbenchObserveContent.timestampKey),
        );
        expect(ts.data, startsWith('Last updated: '));
        expect(tester.takeException(), isNull);
      });

      testWidgets('成功加载后时间戳更新为 Last updated（HH:mm:ss）', (tester) async {
        await seedMysql(processes: [_proc()]);
        lock('conn_mysql');
        await pumpObserve(tester);

        final ts = tester.widget<Text>(
          find.byKey(WorkbenchObserveContent.timestampKey),
        );
        expect(ts.data, startsWith('Last updated: '));
        // HH:mm:ss 格式（8 字符时间尾巴）。
        expect(
          RegExp(r'Last updated: \d{2}:\d{2}:\d{2}$').hasMatch(ts.data ?? ''),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('手动刷新与零轮询（R2）', () {
      testWidgets('mount 首载两段各自动拉取一次；手动刷新各 +1；静置零重载', (tester) async {
        await seedMysql(processes: [_proc()]);
        lock('conn_mysql');
        await pumpObserve(tester);

        // R2：mount 首载自动拉取一次（两段各 1）。
        expect(connection.processListLoads, 1);
        expect(connection.engineStatusLoads, 1);

        // 零轮询：静置（推进假时钟）不再加载。
        await tester.pump(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 10));
        expect(connection.processListLoads, 1);
        expect(connection.engineStatusLoads, 1);

        // 此后仅手动刷新：点刷新钮 → 两段各 +1。
        await tester.tap(find.byKey(WorkbenchObserveContent.refreshButtonKey));
        await tester.pumpAndSettle();
        expect(connection.processListLoads, 2);
        expect(connection.engineStatusLoads, 2);
        expect(tester.takeException(), isNull);
      });
    });

    group('三态（加载中 / 空数据 / 失败）', () {
      testWidgets('首载缓存 null = 加载中（spinner）', (tester) async {
        await seedMysql(processes: [_proc()]);
        lock('conn_mysql');
        await tester.pumpWidget(
          ChangeNotifierProvider<AppProvider>.value(
            value: app,
            child: _wrap(const WorkbenchObserveContent()),
          ),
        );
        // 首帧：加载在途（缓存 null）→ 激活段 spinner（引擎状态段 offstage
        // 被默认 skipOffstage 排除）。
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Not loaded yet'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // 冲刷 persist 防抖 Timer（本用例不走 pumpObserve 的尾部冲刷）。
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });

      testWidgets('空进程列表 = commonNoData', (tester) async {
        await seedMysql(processes: const []);
        lock('conn_mysql');
        await pumpObserve(tester);

        expect(find.text('No Data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('escalation（R3）', () {
      testWidgets('行尾 Manage in classic → 回调收到正确 connectionId'
          '（不真执行切换）', (tester) async {
        await seedMysql(processes: [_proc(time: 12)]); // 慢行（Time>5s）
        lock('conn_mysql');
        final received = <String>[];
        await pumpObserve(tester, onManageInClassic: received.add);

        await tester.tap(find.text('Manage in classic'));
        expect(received, ['conn_mysql']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('内置 R3 三连：退出全屏 + switchToConnection 锚定 + '
          '请求展开 \$id:performance', (tester) async {
        await seedMysql(processes: [_proc()]);
        lock('conn_mysql');
        app.setAiPanelOpen(true);
        app.setAiPanelFullscreen(true);
        await pumpObserve(tester); // 不注入回调 → 内置 R3 实现

        await tester.tap(find.text('Manage in classic'));
        await tester.pumpAndSettle();

        expect(app.aiPanelFullscreen, isFalse);
        // switchToConnection 收到锁定连接 id（探针计数，不真执行锚定链）。
        expect(connection.switchToConnectionCalls, ['conn_mysql']);
        // 展开请求信号 = 经典进程面板挂载键（SidebarWidget 消费后清除）。
        expect(app.sidebar.sidebarExpandRequest, 'conn_mysql:performance');
        expect(tester.takeException(), isNull);
      });
    });

    group('Redis 内存分析段（R4）', () {
      testWidgets('Top-N 表格 + Doctor/Stats 三子视图切换 + 手动刷新重载当前子视图', (
        tester,
      ) async {
        final adapter = _FakeRedisAdapter(
          topKeys: [
            {'key': 'bigkey', 'bytes': 2048},
          ],
        );
        await seedRedis(adapter);
        lock('conn_redis');
        await pumpObserve(tester);

        // Top-N（默认激活）：VirtualizedDataTable 经典同款。
        expect(find.byType(VirtualizedDataTable), findsOneWidget);
        expect(adapter.topNLoads, 1);

        // Doctor：mono 文本。
        await tester.tap(
          find.byKey(WorkbenchObserveRedisSegment.viewSwitchKey(1)),
        );
        await tester.pumpAndSettle();
        expect(adapter.doctorLoads, 1);
        final doctor = tester.widget<SelectableText>(
          find.byKey(WorkbenchObserveRedisSegment.textKey),
        );
        expect(doctor.data, 'DOCTOR OK');

        // Stats：mono 文本。
        await tester.tap(
          find.byKey(WorkbenchObserveRedisSegment.viewSwitchKey(2)),
        );
        await tester.pumpAndSettle();
        expect(adapter.statsLoads, 1);
        final stats = tester.widget<SelectableText>(
          find.byKey(WorkbenchObserveRedisSegment.textKey),
        );
        expect(stats.data, 'STATS OK');

        // 手动刷新重载当前子视图（Stats +1，Doctor/TopN 不变）。
        await tester.tap(find.byKey(WorkbenchObserveContent.refreshButtonKey));
        await tester.pumpAndSettle();
        expect(adapter.statsLoads, 2);
        expect(adapter.doctorLoads, 1);
        expect(adapter.topNLoads, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Top-N 空数据 = workbenchObserveRedisNoKeys', (tester) async {
        await seedRedis(_FakeRedisAdapter(topKeys: const []));
        lock('conn_redis');
        await pumpObserve(tester);

        expect(find.text('No keys with memory data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('adapter 缺失（防御）→ commonError', (tester) async {
        // redis 类型连接但注册的是非 Redis adapter → getRedisAdapter null。
        final server = DbServer(
          id: 'conn_redis',
          name: 'Local Redis',
          type: DatabaseType.redis,
          host: 'localhost',
          port: 6379,
          password: 'x',
        );
        dbService.registerConnectedServerForTest(server);
        dbService.registerConnectedAdapterForTest(
          server.id,
          _FakeMysqlAdapter(),
        );
        await seedServers([server]);
        lock('conn_redis');
        await pumpObserve(tester);

        expect(
          find.byKey(WorkbenchObserveRedisSegment.adapterMissingKey),
          findsOneWidget,
        );
        expect(find.text('Error'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
