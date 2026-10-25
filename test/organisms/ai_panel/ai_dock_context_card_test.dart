// UIRV-A1 · AI dock 上下文卡：跟随 + 手动改选（widget 层）。
//
// 从任务书验收条款直译（tasks-ui-review-fixes.md §UIRV-A1，编号 = ACn）：
// AC1 FOLLOW 卡显示连接名 + 类型徽章 + 库/表路径 + 来源徽章（实际命中级）；
// AC2 表路径来自活动 browse tab，无表显示占位不阻塞；
// AC3 手动改选 → MANUAL 态 + 「恢复跟随」→ 回 FOLLOW 头部即时更新；
// AC4 手动覆盖不被连接级事件冲掉；被覆盖连接删除后回退 FOLLOW；
// AC5 三级全空才 EMPTY（不再「有连接显示 No Connection」）；
// AC6 浏览/改选手势零 switchToConnection；
// AC7 发送路径生效值 = 卡上生效值（Provider 层文件覆盖）；
// AC8 主题 token——按项目约定 widget 测试不断言颜色，静态自查覆盖。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';

/// connectToServer 计数 spy（AC6b 建连断言基座：connect 经
/// `provider.connection.connectToServer` 走 ConnectionProvider，须注入层拦）。
class _ConnectSpyConnectionProvider extends ConnectionProvider {
  int connectCalls = 0;

  @override
  Future<bool> connectToServer(
    DbServer server, {
    bool switchToConnection = true,
  }) async {
    connectCalls++;
    return true;
  }
}

/// switchToConnection 计数 spy（AC6 断言基座，
/// multi_connection_tree_test 同款模式）。
class _SwitchSpyProvider extends AppProvider {
  _SwitchSpyProvider() : super(connectionProvider: _ConnectSpyConnectionProvider());

  int get switchCalls => _switchCalls;
  int _switchCalls = 0;

  int get connectCalls =>
      (connection as _ConnectSpyConnectionProvider).connectCalls;

  @override
  Future<bool> switchToConnection(String connectionId) async {
    _switchCalls++;
    return true;
  }
}

DbServer _server(String id, String name) => DbServer(
      id: id,
      name: name,
      type: DatabaseType.mysql,
      host: '127.0.0.1',
      port: 3306,
      username: 'root',
    );

Future<void> _seedConnections(AppProvider app, {required bool connected}) {
  app.connection.addSavedServerForTest(_server('conn_a', 'Chinook Alpha'));
  // conn_b 预置内存密码：ensurePassword 直返（免弹窗交互），建连走 spy。
  app.connection.addSavedServerForTest(
    _server('conn_b', 'Chinook Beta').copyWith(password: 'preset'),
  );
  if (connected) {
    // 内联库下拉数据源：conn_b 预置 per-tab 库列表（AC3/AC4 的手动态断言用）。
    app.connection.setConnectionDatabasesForTest(
      'conn_b',
      ['main', 'shop'],
      ['main', 'shop'],
    );
  }
  return Future.value();
}

Widget _host(AppProvider app) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<LayoutPreferencesProvider>(
        create: (_) => LayoutPreferencesProvider(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: AiPanelWidget()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  testWidgets('AC1 FOLLOW：侧栏选中 → 卡显示连接名 + 来源徽章（侧栏），'
      '不再出现「No Connection」', (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(find.text('Chinook Alpha'), findsWidgets,
        reason: '卡显示锚定连接名（欢迎区 badge 可能复现同名，用 findsWidgets）');
    expect(find.text('Auto-follow · current context'), findsOneWidget);
    expect(find.text('Sidebar'), findsOneWidget, reason: '来源徽章 = 实际命中级');
    expect(find.text('Manual select'), findsOneWidget);
    expect(find.text('No Connection'), findsNothing,
        reason: '有活动上下文时不再显示 No Connection');
  });

  testWidgets('AC1 侧栏选中不可解析（指向已删连接）时降级活动 tab 级并标注来源',
      (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    await app.tab.openQueryTab(connectionId: 'conn_b', databaseName: 'main');
    // 选中指向不存在连接 → activeContextConnection 跳过侧栏级命中 tab 级。
    app.sidebar.selectConnection('ghost');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(find.text('Chinook Beta'), findsWidgets);
    expect(find.text('Active tab'), findsOneWidget);
  });

  testWidgets('AC2 活动浏览 tab 的表对象进入路径行；无表时显示占位',
      (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    await app.tab.openQueryTab(connectionId: 'conn_a', databaseName: 'main');
    final tabId = app.tab.activeTab?.id;
    if (tabId != null) {
      app.tab.setBrowseTarget(tabId, 'Album');
    }
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(find.text('main'), findsWidgets,
        reason: '库路径进入卡（欢迎区/其它位置可能复现同名，用 findsWidgets）');
    expect(find.text('Album'), findsOneWidget);
    expect(find.text('Current table'), findsOneWidget);
  });

  testWidgets('AC2b 无浏览目标 → 「未指定表」占位，不阻塞输入区', (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(find.text('No table specified'), findsOneWidget);
    expect(find.byType(AiInputArea), findsOneWidget, reason: '占位不阻塞输入');
  });

  testWidgets('AC3 手动改选 → MANUAL 态 + 恢复跟随入口；恢复后回 FOLLOW',
      (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinook Beta').last);
    await tester.pumpAndSettle();

    expect(find.text('Manually selected'), findsOneWidget);
    expect(find.text('Restore follow'), findsWidgets);
    expect(find.text('Chinook Beta'), findsWidgets);

    await tester.tap(find.text('Restore follow').first);
    await tester.pumpAndSettle();

    expect(find.text('Auto-follow · current context'), findsOneWidget);
    expect(find.text('Chinook Alpha'), findsWidgets,
        reason: '恢复后头部即时更新为跟随锚定');
    expect(app.aiPanel.manualContextOverride, isFalse);
  });

  testWidgets('AC4 手动覆盖不被树选中/tab 激活冲掉；被覆盖连接删除后回退 FOLLOW',
      (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    // 手动改选到 conn_b
    await tester.tap(find.text('Manual select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinook Beta').last);
    await tester.pumpAndSettle();
    expect(find.text('Manually selected'), findsOneWidget);

    // 连接级事件 1：树选中 conn_a
    app.sidebar.selectConnection('conn_a');
    await tester.pumpAndSettle();
    expect(find.text('Manually selected'), findsOneWidget,
        reason: '树选中不冲掉手动覆盖');
    expect(find.text('Chinook Beta'), findsWidgets);

    // 连接级事件 2：激活绑定 conn_a 的 tab
    await app.tab.openQueryTab(connectionId: 'conn_a', databaseName: 'main');
    await tester.pumpAndSettle();
    expect(find.text('Manually selected'), findsOneWidget,
        reason: 'tab 激活不冲掉手动覆盖');
    expect(find.text('Chinook Beta'), findsWidgets);

    // 被覆盖连接从已保存列表删除 → 回退 FOLLOW
    await app.connection.deleteConnection('conn_b');
    await tester.pumpAndSettle();

    expect(app.aiPanel.manualContextOverride, isFalse,
        reason: '被覆盖连接删除后自动解除覆盖（T25 删除降级先例）');
    expect(find.text('Auto-follow · current context'), findsOneWidget);
    expect(find.text('Chinook Alpha'), findsWidgets);
  });

  testWidgets('AC5 三级全空 → EMPTY 态（未设置连接 + 选择入口）；选择入口可达',
      (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    // 无任何连接级锚点（侧栏/tab/currentServer 全空）。

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(find.text('No connection set'), findsOneWidget);
    expect(find.text('Choose a connection'), findsOneWidget);
    expect(find.text('No Connection'), findsNothing,
        reason: 'EMPTY 走新空态文案，旧「No Connection」退役');
  });

  testWidgets('AC6 浏览/改选手势零 switchToConnection', (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    // 手动改选（改选不再触发 connectToServer——UIRV-A1 自决）
    await tester.tap(find.text('Manual select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinook Beta').last);
    await tester.pumpAndSettle();

    // 树选中（连接级事件）
    app.sidebar.selectConnection('conn_a');
    await tester.pumpAndSettle();

    expect(app.switchCalls, 0, reason: '浏览/改选手势零 switchToConnection（红线只锁 switch，conn_b 无密码弹窗待输入时 connectCalls 恒 0）');
  });

  testWidgets('AC6b 选中未连接连接 → 恢复「选择即建连」（connectToServer 恰一次）', (
    tester,
  ) async {
    // 打回修复回归锁：手动改选恢复旧下拉等价行为——未连接连接被选中时
    // 经 ensurePassword（_seedConnections 预置密码直返，免弹窗）+
    // connectToServer 建连；零 switchToConnection 不变。
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinook Beta').last);
    await tester.pumpAndSettle();

    expect(app.connectCalls, 1, reason: '选中未连接连接发起建连（恰一次）');
    expect(app.switchCalls, 0, reason: '建连路径仍零 switchToConnection');
    expect(find.text('Manually selected'), findsOneWidget,
        reason: '覆盖语义不变：上下文先写、建连不冲掉手动态');
  });
}
