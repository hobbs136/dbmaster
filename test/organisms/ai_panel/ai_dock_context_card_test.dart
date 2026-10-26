// UIRV-A1 · AI dock 上下文卡：跟随 + 手动改选（widget 层）。
//
// 从任务书验收条款直译（tasks-ui-review-fixes.md §UIRV-A1 + 2026-10-25
// 真机走查修订，编号 = ACn）：
// AC1 FOLLOW 卡显示连接名 + 类型徽章 + 恒显 chevron + 第 1 行实际来源；
//     连接行整行可点直接打开已保存连接菜单；
// AC2 表路径来自活动 browse tab，有表才显示 `/ 表名` + 「当前表」徽章；
// AC2b 无表时整棵树不存在 `/` 与表占位文本（全尺寸）；
// AC3 MANUAL 态连接行可直接改选（无需先恢复跟随）；「恢复跟随」回 FOLLOW；
// AC4 手动覆盖不被连接级事件冲掉；被覆盖连接删除后回退 FOLLOW；
// AC5 三级全空才 EMPTY，连接行可直接开菜单选择；
// AC6 浏览/改选手势零 switchToConnection；AC6b 选择即建连（AC6b）；
// AC7 发送路径生效值 = 卡上生效值（Provider 层文件覆盖）；
// AC8 主题 token——按项目约定 widget 测试不断言颜色，静态自查覆盖；
// N1 MANUAL 直接连选换连接仍是 MANUAL；N2 恢复跟随不弹连接菜单；
// N3 紧凑态无表不渲染表段；N4 紧凑 280px + 长连接名 + MANUAL 无 overflow；
// N5 键盘：聚焦触发器 → Enter 开菜单 → Esc 关闭且焦点回触发器。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_dock_context_card.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_picker.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart'
    show AiDockContextSource;
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';

/// getDatabases / 库限定 getTables 假适配器（workbench_context_picker_test
/// 同款最小桩；表模式用例需要表清单）。
class _FakeDbAdapter
    implements DatabaseAdapter, DatabaseQualifiedTablesAdapter {
  _FakeDbAdapter(
    this.dbs, {
    this.tablesByDb = const <String, List<String>>{},
  });

  final List<String> dbs;
  final Map<String, List<String>> tablesByDb;

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getDatabases() async => dbs;

  @override
  Future<List<String>> getTables({String? database, String? schemaName}) async {
    return tablesByDb[database] ?? const <String>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  _SwitchSpyProvider()
    : super(connectionProvider: _ConnectSpyConnectionProvider());

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

/// 标记连接已连接并注入库/表清单（表模式 picker 直接载入的数据源）。
void _registerTableSource(
  AppProvider app,
  DbServer server, {
  List<String> dbs = const <String>['main'],
  Map<String, List<String>> tablesByDb = const <String, List<String>>{
    'main': <String>['Album'],
  },
}) {
  app.connection.dbService.registerConnectedServerForTest(server);
  app.connection.dbService.registerConnectedAdapterForTest(
    server.id,
    _FakeDbAdapter(dbs, tablesByDb: tablesByDb),
  );
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

/// 纯卡直泵（紧凑态/溢出/无表结构断言用；ThemeColors 无 Provider 时安全回退）。
Widget _cardHost({
  required WidgetTester tester,
  DbServer? connection,
  String? databaseName,
  String? tableName,
  bool isManual = false,
  AiDockContextSource? followSource,
  bool compact = false,
  double width = 280,
  ValueChanged<DbServer>? onManualSelect,
}) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: AiDockContextCard(
            connection: connection,
            databaseName: databaseName,
            tableName: tableName,
            isManual: isManual,
            followSource: followSource,
            connections: [
              _server('conn_b', 'A Very Long Connection Name For Overflow'),
            ],
            onManualSelect: onManualSelect ?? (_) {},
            onRestoreFollow: () {},
            compact: compact,
          ),
        ),
      ),
    ),
  );
}

/// 经连接选择器改选（新版整行触发器，点开菜单选目标连接）。
Future<void> _selectConnection(WidgetTester tester, String targetName) async {
  await tester.tap(find.byKey(kAiDockContextConnectionTrigger));
  await tester.pumpAndSettle();
  await tester.tap(find.text(targetName).last);
  await tester.pumpAndSettle();
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

  testWidgets('AC1 FOLLOW：侧栏选中 → 连接行（名+徽章+chevron）整行可点开菜单，'
      '第 1 行显示实际来源（侧栏）', (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(
      find.text('Chinook Alpha'),
      findsWidgets,
      reason: '卡显示锚定连接名（欢迎区 badge 可能复现同名，用 findsWidgets）',
    );
    expect(find.text('Auto-follow'), findsOneWidget, reason: '第 1 行 = 自动跟随');
    expect(find.text('Sidebar'), findsOneWidget, reason: '第 1 行附实际命中级来源');
    expect(find.text('Manual select'), findsNothing, reason: '原右上角小链接已删除');
    // 整行触发器直接开菜单（不再两跳）。
    await tester.tap(find.byKey(kAiDockContextConnectionTrigger));
    await tester.pumpAndSettle();
    expect(find.text('Chinook Beta'), findsOneWidget, reason: '菜单列出候选');
    await tester.tap(find.text('Chinook Beta'));
    await tester.pumpAndSettle();
    expect(find.text('Manually set AI context'), findsOneWidget);
  });

  testWidgets('AC1 侧栏选中不可解析（指向已删连接）时降级活动 tab 级并标注来源', (tester) async {
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

  testWidgets('AC2 活动浏览 tab 的表对象进入路径行并显示当前表徽章', (tester) async {
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

    expect(
      find.text('main'),
      findsWidgets,
      reason: '库路径进入卡（欢迎区/其它位置可能复现同名，用 findsWidgets）',
    );
    expect(find.text('Album'), findsOneWidget);
    expect(find.text('Current table'), findsOneWidget);
  });

  testWidgets('AC2b 无浏览目标 → 整棵树不存在「/」分隔与表占位文本；占位不阻塞输入', (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(
      find.text('No table specified'),
      findsNothing,
      reason: '表占位文本退役：无表时隐藏整个表段',
    );
    expect(find.text('/'), findsNothing, reason: '无表时不渲染库/表分隔符（不暗示可点选）');
    expect(find.byType(AiInputArea), findsOneWidget, reason: '不阻塞输入');
  });

  testWidgets('AC3 MANUAL 态连接行直接改选；「恢复跟随」后回 FOLLOW 头部即时更新', (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    await _selectConnection(tester, 'Chinook Beta');

    expect(find.text('Manually set AI context'), findsOneWidget);
    expect(find.text('Restore follow'), findsWidgets);
    expect(find.text('Chinook Beta'), findsWidgets);

    await tester.tap(find.text('Restore follow').first);
    await tester.pumpAndSettle();

    expect(find.text('Auto-follow'), findsOneWidget);
    expect(find.text('Chinook Alpha'), findsWidgets, reason: '恢复后头部即时更新为跟随锚定');
    expect(app.aiPanel.manualContextOverride, isFalse);
  });

  testWidgets('AC4 手动覆盖不被树选中/tab 激活冲掉；被覆盖连接删除后回退 FOLLOW', (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    // 手动改选到 conn_b（直接点连接行，无需先恢复）
    await _selectConnection(tester, 'Chinook Beta');
    expect(find.text('Manually set AI context'), findsOneWidget);

    // 连接级事件 1：树选中 conn_a
    app.sidebar.selectConnection('conn_a');
    await tester.pumpAndSettle();
    expect(
      find.text('Manually set AI context'),
      findsOneWidget,
      reason: '树选中不冲掉手动覆盖',
    );
    expect(find.text('Chinook Beta'), findsWidgets);

    // 连接级事件 2：激活绑定 conn_a 的 tab
    await app.tab.openQueryTab(connectionId: 'conn_a', databaseName: 'main');
    await tester.pumpAndSettle();
    expect(
      find.text('Manually set AI context'),
      findsOneWidget,
      reason: 'tab 激活不冲掉手动覆盖',
    );
    expect(find.text('Chinook Beta'), findsWidgets);

    // 被覆盖连接从已保存列表删除 → 回退 FOLLOW
    await app.connection.deleteConnection('conn_b');
    await tester.pumpAndSettle();

    expect(
      app.aiPanel.manualContextOverride,
      isFalse,
      reason: '被覆盖连接删除后自动解除覆盖（T25 删除降级先例）',
    );
    expect(find.text('Auto-follow'), findsOneWidget);
    expect(find.text('Chinook Alpha'), findsWidgets);
  });

  testWidgets('AC5 三级全空 → EMPTY 态；EMPTY 连接行可直接开菜单选择', (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    // 无任何连接级锚点（侧栏/tab/currentServer 全空）。

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(find.text('No connection set'), findsOneWidget);
    expect(
      find.text('Choose a connection'),
      findsNothing,
      reason: 'EMPTY 入口并入连接行触发器，独立小链接退役',
    );
    expect(
      find.text('No Connection'),
      findsNothing,
      reason: 'EMPTY 走新空态文案，旧「No Connection」退役',
    );

    // EMPTY 态点连接行 → 菜单直接可达并可选择。
    await tester.tap(find.byKey(kAiDockContextConnectionTrigger));
    await tester.pumpAndSettle();
    expect(find.text('Chinook Beta'), findsOneWidget, reason: '菜单列出候选');
    await tester.tap(find.text('Chinook Beta'));
    await tester.pumpAndSettle();
    expect(find.text('Manually set AI context'), findsOneWidget);
    expect(find.text('Chinook Beta'), findsWidgets);
  });

  testWidgets('AC6 浏览/改选手势零 switchToConnection', (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    // 手动改选（选择即建连：未连接连接经 ensurePassword + connectToServer；
    // 红线仍只锁 switchToConnection——UIRV-A1 评审打回修复口径）。
    await _selectConnection(tester, 'Chinook Beta');

    // 树选中（连接级事件）
    app.sidebar.selectConnection('conn_a');
    await tester.pumpAndSettle();

    expect(
      app.switchCalls,
      0,
      reason:
          '浏览/改选手势零 switchToConnection（建连走既有 connectToServer 链路，不计入 switch）',
    );
  });

  testWidgets('AC6b 选中未连接连接 → 恢复「选择即建连」（connectToServer 恰一次）', (tester) async {
    // 打回修复回归锁：手动改选恢复旧下拉等价行为——未连接连接被选中时
    // 经 ensurePassword（_seedConnections 预置密码直返，免弹窗）+
    // connectToServer 建连；零 switchToConnection 不变。
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    await _selectConnection(tester, 'Chinook Beta');

    expect(app.connectCalls, 1, reason: '选中未连接连接发起建连（恰一次）');
    expect(app.switchCalls, 0, reason: '建连路径仍零 switchToConnection');
    expect(
      find.text('Manually set AI context'),
      findsOneWidget,
      reason: '覆盖语义不变：上下文先写、建连不冲掉手动态',
    );
  });

  testWidgets('N1 MANUAL 态直接点连接行换到另一连接（无需先恢复），换选后仍是 MANUAL', (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    // 第一次改选：FOLLOW → MANUAL（Beta；未连接选择即建连 → connectCalls=1）
    await _selectConnection(tester, 'Chinook Beta');
    expect(find.text('Manually set AI context'), findsOneWidget);
    expect(app.connectCalls, 1, reason: '选择未连接连接发起建连（AC6b）');

    // 第二次改选：MANUAL 态直接点连接行（不点恢复跟随）→ 换 Alpha，仍是 MANUAL
    await _selectConnection(tester, 'Chinook Alpha');
    expect(
      find.text('Manually set AI context'),
      findsOneWidget,
      reason: '直接换选不退出手动态',
    );
    expect(app.aiPanel.manualContextOverride, isTrue);
    // 建连计数不锁精确值（加载库列表的已连接判定由 Provider 层管）；
    // 红线只锁 switch：直接换选零 switchToConnection。
    expect(app.switchCalls, 0);
  });

  testWidgets('N2 MANUAL 态点「恢复跟随」不弹连接菜单，直接回 FOLLOW', (tester) async {
    final app = _SwitchSpyProvider();
    await _seedConnections(app, connected: true);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    await _selectConnection(tester, 'Chinook Beta');
    expect(find.text('Manually set AI context'), findsOneWidget);
    final connectsAfterSelect = app.connectCalls;

    await tester.tap(find.text('Restore follow').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Chinook Beta'),
      findsNothing,
      reason: '恢复跟随不弹菜单（Beta 只在菜单中出现，恢复后不可见）',
    );
    expect(find.text('Auto-follow'), findsOneWidget, reason: '直接回 FOLLOW');
    expect(app.connectCalls, connectsAfterSelect, reason: '恢复跟随零额外副作用');
  });

  testWidgets('N3 紧凑态无表 → 只保留连接/库分隔符，无表段分隔与占位文本',
      (tester) async {
    await tester.pumpWidget(
      _cardHost(
        tester: tester,
        connection: _server('conn_a', 'Chinook Alpha'),
        databaseName: 'main',
        tableName: null,
        compact: true,
      ),
    );
    await tester.pumpAndSettle();

    // UI35-123 起紧凑行 2 = 连接名 / 库名（无表时表段整体隐藏）：
    // 仅剩连接/库之间的一个「/」。
    expect(find.text('/'), findsOneWidget,
        reason: '仅连接/库分隔符；表段分隔符随表段隐藏');
    expect(find.text('No table specified'), findsNothing);
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('N4 紧凑态 280px 宽 + 长连接名 + MANUAL 恢复链接无 overflow', (tester) async {
    final longServer = _server(
      'conn_b',
      'A Very Long Connection Name For Overflow',
    );
    await tester.pumpWidget(
      _cardHost(
        tester: tester,
        connection: longServer,
        databaseName: 'main',
        tableName: 'Album',
        isManual: true,
        compact: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: '280px 宽 + 长连接名 + MANUAL 恢复链接不产生 RenderFlex overflow',
    );
    expect(find.text('Restore follow'), findsOneWidget);
    expect(find.byKey(kAiDockCompactContextTrigger), findsOneWidget);
  });

  testWidgets('N5 键盘：聚焦连接触发器 → Enter 开菜单 → Esc 关闭且焦点回触发器', (tester) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    final triggerFinder = find.byKey(kAiDockContextConnectionTrigger);
    final triggerElement = tester.element(triggerFinder);

    // 聚焦触发器：Tab 遍历直到主焦点落在触发器子树（PopupMenuButton 内部
    // Focus 节点不外露，用遍历聚焦与真实键盘路径一致）。
    bool focusedOnTrigger() {
      bool inside = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        if (e == triggerElement) {
          inside = true;
          return false;
        }
        return true;
      });
      return inside;
    }

    for (var i = 0; i < 40 && !focusedOnTrigger(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedOnTrigger(), isTrue, reason: 'Tab 可达连接触发器');

    // Enter 开菜单。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Chinook Beta'), findsOneWidget, reason: 'Enter 打开连接菜单');

    // Esc 关闭且焦点回触发器。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Chinook Beta'), findsNothing, reason: 'Esc 关闭菜单');
    expect(focusedOnTrigger(), isTrue, reason: '焦点回连接触发器');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // v0.3.5 批1 T2 · UI35-121~133：44px 紧凑上下文卡改版
  // 行 1（18px）= ● Auto-follow / ▲ Manual（+ 右端 Restore follow）；
  // 行 2（24px）= [库图标] 连接名 / 库名 / 表名 ▾，整行触发级联选择器；
  // 截断优先级：表名 > 库名 > 连接名。
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('UI35-121 紧凑 FOLLOW：行1 = ● Auto-follow（无恢复链接）', (tester) async {
    await tester.pumpWidget(
      _cardHost(
        tester: tester,
        connection: _server('conn_a', 'Chinook Alpha'),
        databaseName: 'main',
        tableName: null,
        compact: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Auto-follow'),
      findsOneWidget,
      reason: '紧凑行 1 = 状态点 + Auto-follow',
    );
    expect(find.text('Restore follow'), findsNothing, reason: 'FOLLOW 态无恢复链接');
    expect(
      find.byKey(const Key('aiDockCompactContextTrigger')),
      findsOneWidget,
      reason: '行 2 触发器存在',
    );
  });

  testWidgets('UI35-122 紧凑 MANUAL：行1 = ▲ Manual + 右端 Restore follow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardHost(
        tester: tester,
        connection: _server('conn_a', 'Chinook Alpha'),
        databaseName: 'main',
        tableName: null,
        isManual: true,
        compact: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Manually set AI context'),
      findsOneWidget,
      reason: '紧凑行 1 = 警示标识 + Manual 态标签',
    );
    expect(
      find.text('Restore follow'),
      findsOneWidget,
      reason: 'MANUAL 右端保留恢复跟随入口',
    );
    expect(
      find.byKey(const Key('aiDockCompactContextTrigger')),
      findsOneWidget,
    );
  });

  testWidgets('UI35-123 紧凑行2 = [库图标] 连接名 / 库名 / 表名 + chevron（整行触发器）', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardHost(
        tester: tester,
        connection: _server('conn_a', 'Chinook Alpha'),
        databaseName: 'main',
        tableName: 'Album',
        compact: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chinook Alpha'), findsOneWidget, reason: '行 2 显示连接名');
    expect(find.text('main'), findsOneWidget, reason: '行 2 显示库名');
    expect(
      find.text('Album'),
      findsOneWidget,
      reason: '行 2 显示表名（表选择入口，本批只要求存在）',
    );
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
  });

  testWidgets('UI35-124 截断优先级：长连接名中间省略（…），库名/表名完整', (tester) async {
    await tester.pumpWidget(
      _cardHost(
        tester: tester,
        connection: _server(
          'conn_b',
          'A Very Long Connection Name For Overflow',
        ),
        databaseName: 'main',
        tableName: 'Album',
        compact: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('…'),
      findsOneWidget,
      reason: '连接名中间省略（预算 ~100px）',
    );
    expect(
      find.textContaining('A Very Long Connection Name'),
      findsNothing,
      reason: '长连接名不再原样显示',
    );
    expect(find.text('main'), findsOneWidget, reason: '库名不省略');
    expect(find.text('Album'), findsOneWidget, reason: '表名不省略');
  });

  testWidgets('UI35-125 极窄 dock（280px）：无 overflow，表名仍完整', (tester) async {
    await tester.pumpWidget(
      _cardHost(
        tester: tester,
        connection: _server('conn_b', 'Chinook Beta'),
        databaseName: 'a_long_database_name_here',
        tableName: 'Album',
        compact: true,
        width: 280,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: '极窄卡不产生 RenderFlex overflow',
    );
    expect(find.text('Album'), findsOneWidget, reason: '表名仍完整（截断优先级最高）');
  });

  testWidgets('UI35-126/127 紧凑态点行 2 → 打开 WorkbenchContextPicker 级联选择器', (
    tester,
  ) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    // 1400x400 → totalHeight < 420 → 紧凑头生效。
    expect(
      find.byKey(const Key('aiDockCompactContextTrigger')),
      findsOneWidget,
      reason: '矮面板走紧凑上下文卡',
    );

    await tester.tap(find.byKey(const Key('aiDockCompactContextTrigger')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('workbench_context_picker_content')),
      findsOneWidget,
      reason: '复用 WorkbenchContextPicker（左列连接/库，右列库表级联）',
    );
    expect(find.text('Set AI context'), findsOneWidget);

    // 关闭（零状态变化路径）。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workbench_context_picker_content')),
      findsNothing,
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // v0.3.5 批1 返工 T2b：紧凑卡行 2 打开 picker 的写入面 = dock 手动上下文
  // （setManualDockContext），不是工作台锁定（lockWorkbenchContext）。
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('T2b 紧凑卡行2 picker 表模式选表 → 写 dock 手动上下文三元组，工作台零锁定', (
    tester,
  ) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    // conn_b 标记已连接 + 注入库/表清单：picker 免建连直装库与表。
    app.connection.dbService.registerConnectedServerForTest(
      _server('conn_b', 'Chinook Beta'),
    );
    app.connection.dbService.registerConnectedAdapterForTest(
      'conn_b',
      _FakeDbAdapter(
        ['main'],
        tablesByDb: const <String, List<String>>{
          'main': <String>['Album'],
        },
      ),
    );
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('aiDockCompactContextTrigger')),
      findsOneWidget,
      reason: '矮面板走紧凑上下文卡',
    );
    await tester.tap(find.byKey(const Key('aiDockCompactContextTrigger')));
    await tester.pumpAndSettle();

    // 选连接 → 装库 → 点库钻取表清单 → 点表确认（scope 到 picker Dialog，
    // 避开侧栏树同名）。
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Chinook Beta'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('main')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Album')),
    );
    await tester.pumpAndSettle();

    // picker 关闭。
    expect(
      find.byKey(const ValueKey('workbench_context_picker_content')),
      findsNothing,
    );

    // dock 手动上下文三元组已写（B-03 原子写入）。
    expect(app.aiPanel.manualContextOverride, isTrue);
    expect(app.aiPanel.selectedConnectionId, 'conn_b');
    expect(app.aiPanel.selectedDatabaseName, 'main');
    expect(app.aiPanel.selectedManualTable, 'Album');
    expect(app.aiPanel.contextBuilder.currentTable, 'Album');

    // 工作台零锁定（承载字段 = 会话 metadata workbench.contextLock →
    // workbenchContextLock getter 必须为 null）。
    expect(
      app.aiPanel.workbenchContextLock,
      isNull,
      reason: '紧凑卡路径只写 dock 上下文，不得写工作台锁定',
    );
  });

  testWidgets('T2b 紧凑卡行2 picker 空表清单 → 表模式引导空态 + 零写入（无仅连接出口）', (
    tester,
  ) async {
    final app = AppProvider();
    await _seedConnections(app, connected: false);
    app.connection.dbService.registerConnectedServerForTest(
      _server('conn_b', 'Chinook Beta'),
    );
    app.connection.dbService.registerConnectedAdapterForTest(
      'conn_b',
      _FakeDbAdapter(['main']),
    );
    app.sidebar.selectConnection('conn_a');

    await tester.binding.setSurfaceSize(const Size(1400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(app));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('aiDockCompactContextTrigger')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Chinook Beta'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('main')),
    );
    await tester.pumpAndSettle();

    // 表模式空表清单 = 引导空态行；无「仅连接」出口（B-04）。
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(AppLocalizationsEn().uirvDockContextPickerHint),
      ),
      findsOneWidget,
    );
    expect(find.text('Use connection only'), findsNothing);

    // 未提交 → 逐项零写入；picker 保持打开。
    expect(app.aiPanel.manualContextOverride, isFalse);
    expect(app.aiPanel.selectedManualTable, isNull);
    expect(app.aiPanel.workbenchContextLock, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workbench_context_picker_content')),
      findsNothing,
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // v0.3.5 批2 T5 · B-04 上下文卡第 3 行拉通 + 手动表契约（UI35-201~206）
  // FOLLOW 完整卡第 3 行 = 整行命中区（hover 底色 + 尾部 ▾ + tooltip），
  // 点击打开表模式 picker（初始 = 当前生效连接/库）；选表后转 MANUAL 且
  // 表名渲染自 selectedManualTable；手动态无表整段隐藏。
  // ══════════════════════════════════════════════════════════════════════════
  group('T5 上下文卡第 3 行 + 手动表契约', () {
    testWidgets('UI35-201 FOLLOW 第 3 行整行命中区：tooltip + 尾部 ▾ + 点击开表模式 picker',
        (tester) async {
      final app = _SwitchSpyProvider();
      await _seedConnections(app, connected: false);
      _registerTableSource(app, _server('conn_a', 'Chinook Alpha'));
      await app.tab.openQueryTab(
        connectionId: 'conn_a',
        databaseName: 'main',
      );
      app.sidebar.selectConnection('conn_a');

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(app));
      await tester.pumpAndSettle();

      final trigger = find.byKey(kAiDockContextScopeTrigger);
      expect(trigger, findsOneWidget, reason: '完整卡第 3 行是整行命中区');
      expect(
        find.byTooltip(AppLocalizationsEn().uirvDockContextChangeScopeTooltip),
        findsOneWidget,
        reason: 'tooltip = uirvDockContextChangeScopeTooltip',
      );
      expect(
        find.descendant(
          of: trigger,
          matching: find.byIcon(LucideIcons.chevronDown),
        ),
        findsOneWidget,
        reason: '尾部 ▾',
      );

      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(
        find.byType(WorkbenchContextPicker),
        findsOneWidget,
        reason: '点击打开表模式 picker',
      );
      expect(
        find.text('Album'),
        findsOneWidget,
        reason: '初始库已定 → 直接呈表清单（只选表）',
      );
      expect(app.switchCalls, 0, reason: '卡片全程零 switchToConnection');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('UI35-202/203 选表 → 宿主三元组落 provider → 卡片转 MANUAL 且表名来自 selectedManualTable',
        (tester) async {
      final app = _SwitchSpyProvider();
      await _seedConnections(app, connected: false);
      _registerTableSource(app, _server('conn_a', 'Chinook Alpha'));
      await app.tab.openQueryTab(
        connectionId: 'conn_a',
        databaseName: 'main',
      );
      app.sidebar.selectConnection('conn_a');

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAiDockContextScopeTrigger));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Album')),
      );
      await tester.pumpAndSettle();

      // provider 三元组（B-03 原子写入）。
      expect(app.aiPanel.manualContextOverride, isTrue);
      expect(app.aiPanel.selectedConnectionId, 'conn_a');
      expect(app.aiPanel.selectedDatabaseName, 'main');
      expect(app.aiPanel.selectedManualTable, 'Album');

      // 卡片转 MANUAL（warning 语义 + 恢复入口可见），表名来自手动表。
      expect(find.text('Manually set AI context'), findsOneWidget);
      expect(find.text('Restore follow'), findsWidgets);
      expect(find.text('Album'), findsOneWidget);
      expect(
        find.text('Current table'),
        findsNothing,
        reason: 'MANUAL 表段不渲染当前表徽标（批1 手动态本就不渲染表段，零视觉回归）',
      );
      expect(app.switchCalls, 0, reason: '选表/卡片手势零 switchToConnection');
    });

    testWidgets('UI35-205 手动态无表：表段与「/」分隔符整段隐藏（完整卡）',
        (tester) async {
      final app = AppProvider();
      await _seedConnections(app, connected: true);
      app.aiPanel.setManualDockContext('conn_b', databaseName: 'main');

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(app));
      await tester.pumpAndSettle();

      expect(find.text('Manually set AI context'), findsOneWidget);
      expect(find.text('/'), findsNothing, reason: '无表时不渲染 / 分隔符');
      expect(find.text('Current table'), findsNothing);
      expect(find.text('main'), findsWidgets, reason: '库段仍在（宿主注入下拉）');
    });

    testWidgets('UI35-205b 手动态无表：紧凑卡同样隐藏表段（仅连接/库分隔符）',
        (tester) async {
      await tester.pumpWidget(
        _cardHost(
          tester: tester,
          connection: _server('conn_a', 'Chinook Alpha'),
          databaseName: 'main',
          tableName: null,
          isManual: true,
          compact: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('/'), findsOneWidget, reason: '仅连接/库分隔符');
      expect(find.text('No table specified'), findsNothing);
      expect(find.text('Current table'), findsNothing);
    });

    testWidgets('UI35-207 MANUAL 有表 + 280px 宽：表名段不 overflow',
        (tester) async {
      await tester.pumpWidget(
        _cardHost(
          tester: tester,
          connection: _server(
            'conn_b',
            'A Very Long Connection Name For Overflow',
          ),
          databaseName: 'a_long_database_name_here',
          tableName: 'a_very_long_table_name_here',
          isManual: true,
          width: 280,
        ),
      );
      await tester.pumpAndSettle();

      final Object? overflow = tester.takeException();
      expect(
        overflow,
        isNull,
        reason:
            '窄卡 MANUAL 表名段 + Current table 徽标不产生 RenderFlex overflow'
            '${overflow is FlutterError ? '\n${overflow.toStringDeep()}' : ''}',
      );
      expect(find.byKey(kAiDockContextScopeTrigger), findsOneWidget);
      expect(find.text('a_very_long_table_name_here'), findsOneWidget);
    });

    testWidgets('UI35-206 紧凑行2 表模式选表 → 同一 setManualDockContext 三元组',
        (tester) async {
      final app = _SwitchSpyProvider();
      await _seedConnections(app, connected: false);
      _registerTableSource(app, _server('conn_b', 'Chinook Beta'));
      await app.tab.openQueryTab(
        connectionId: 'conn_b',
        databaseName: 'main',
      );
      app.sidebar.selectConnection('conn_b');

      await tester.binding.setSurfaceSize(const Size(1400, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(app));
      await tester.pumpAndSettle();

      expect(
        find.byKey(kAiDockCompactContextTrigger),
        findsOneWidget,
        reason: '矮面板走紧凑上下文卡',
      );
      await tester.tap(find.byKey(kAiDockCompactContextTrigger));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Album')),
      );
      await tester.pumpAndSettle();

      expect(app.aiPanel.selectedConnectionId, 'conn_b');
      expect(app.aiPanel.selectedDatabaseName, 'main');
      expect(app.aiPanel.selectedManualTable, 'Album');
      expect(app.aiPanel.workbenchContextLock, isNull);
      expect(app.switchCalls, 0, reason: '紧凑入口零 switchToConnection');

      // 紧凑行 2 显示表名（MANUAL 表名渲染源）。
      expect(find.text('Album'), findsOneWidget);
    });
  });
}
