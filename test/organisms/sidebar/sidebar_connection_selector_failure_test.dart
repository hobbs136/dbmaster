// SidebarConnectionSelector 未处置失败态测试（连接失败 UX 重构 T10 + P1-3）。
//
// 覆盖：
//   1. 独占锁真实 SQLite 文件（dart:io LockFileEx）→ openSqliteFile 失败、
//      保存保留（recentSqliteFiles/savedConnections 含该文件）、选择器条目
//      error 状态点 + 人话 tooltip；点击重试 → ConnectFailureDialog 弹出
//      1 次；释放锁后再重试 → 连接成功 + 失败态清除（P1-3 验收）。
//   2. 树根状态点 error 态：意外断连（事件注入）→ error tooltip；处置后
//      回归既有连接态；正常连接/断开两态 tooltip 不变。
//
// 真实链路纪律：真实 AppProvider + DatabaseService + SQLite adapter +
// 真实临时文件（仅 mock 平台通道，不 mock 数据库服务）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_connection_selector.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// 真实文件 IO / sqlite FFI 完成于真实事件循环：runAsync 让出 FakeAsync
/// 轮询真实完成，再 settle 帧；长期不满足则显式失败（参照 T8 harness）。
Future<void> waitUntilSettled(
  WidgetTester tester,
  bool Function() done,
) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }
  await tester.pumpAndSettle();
  expect(done(), isTrue, reason: '等待条件 3s 内未满足');
}

Future<void> pumpSelector(WidgetTester tester, AppProvider provider) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>.value(
          value: ThemeProvider()..load(),
        ),
        ChangeNotifierProvider<ServerConnectionProvider>.value(
          value: ServerConnectionProvider(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              SidebarConnectionSelector(onManageConnections: () {}),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SidebarConnectionSelector)))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // openSqliteFile → saveConnection 会经 SecureStorageService 读写凭据
    // 保险箱；flutter_tester 无插件实现会挂起，按项目测试约定 mock 为空。
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

  testWidgets('P1-3：独占锁文件 → 失败态 + 对话框；解锁后经选择器重试成功',
      (tester) async {
    final dbFile = File(
      '${Directory.systemTemp.absolute.path}'
      '${Platform.pathSeparator}dbmaster_t10_sel_'
      '${DateTime.now().millisecondsSinceEpoch}.db',
    );
    dbFile.writeAsStringSync(''); // 0 字节 = 合法空 SQLite 库
    addTearDown(() {
      try {
        if (dbFile.existsSync()) dbFile.deleteSync();
      } on FileSystemException {
        // 连接句柄未释放时删除失败不影响测试结论
      }
    });

    final app = AppProvider();
    await pumpSelector(tester, app);
    final l10n = _l10nOf(tester);

    // 1) dart:io 独占锁（range 覆盖 sqlite 锁区 0x40000000+）。
    final raf = dbFile.openSync(mode: FileMode.append);
    raf.lockSync(FileLock.exclusive, 0, 1 << 31);
    // 尽力而为释放（Windows 要求解锁范围与加锁范围精确一致；重复解锁报
    // errno 158，忽略之，不影响测试结论）。
    void unlockQuietly() {
      try {
        raf.unlockSync(0, 1 << 31);
        raf.closeSync();
      } on FileSystemException {
        // ignore
      }
    }

    addTearDown(unlockQuietly);

    // 2) 拖拽等价入口 openSqliteFile：保存保留 + 连接失败。
    var opened = false;
    await tester.runAsync(() async {
      opened = await app.connection.openSqliteFile(dbFile.path);
    });
    await tester.pumpAndSettle();
    expect(opened, isFalse);

    final conn = ConnectionProvider.findExistingSqlite(
      app.connection.savedConnections,
      ConnectionProvider.normalizeSqlitePath(dbFile.path),
    );
    expect(conn, isNotNull, reason: '失败连接保存策略 = 保留保存');
    expect(
      app.connection.recentSqliteFiles.map((s) => s.id),
      contains(conn!.id),
    );
    final failure = app.connection.lastFailureFor(conn.id);
    expect(failure, isNotNull);

    // 3) 选择器条目呈现失败态：error 状态点 + 人话 tooltip。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    final dotFinder = find.byKey(ValueKey('selector_failure_dot_${conn.id}'));
    expect(dotFinder, findsOneWidget);
    // key 挂在 Tooltip 本体上，直接取 widget 校验 message。
    final tooltip = tester.widget<Tooltip>(dotFinder);
    expect(
      tooltip.message,
      l10n.connectFailureLatestTooltip(
        SidebarConnectionSelector.failurePlainMessage(l10n, failure!.kind),
      ),
    );

    // 4) 点击重试 → 仍失败 → ConnectFailureDialog 单实例弹出。
    await tester.tap(find.text(conn.name));
    await waitUntilSettled(
      tester,
      () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
    );
    expect(find.byType(ConnectFailureDialog), findsOneWidget);

    // 5) 关闭对话框 → 释放锁。
    await tester.tap(find.widgetWithText(TextButton, l10n.commonClose));
    await tester.pumpAndSettle();
    unlockQuietly();

    // 6) 再经选择器重试 → 成功 + 失败态清除。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(conn.name));
    await waitUntilSettled(
      tester,
      () => app.connection.isConnectionConnected(conn.id),
    );

    expect(app.connection.lastFailureFor(conn.id), isNull);
    expect(app.connection.hasUnacknowledgedFailures, isFalse);
    expect(find.byType(ConnectFailureDialog), findsNothing);
    expect(
      find.byKey(ValueKey('selector_failure_dot_${conn.id}')),
      findsNothing,
    );

    // 收尾断开，释放文件句柄供 tearDown 删除。
    await tester.runAsync(() => app.connection.disconnectAllConnections());
    await tester.pumpAndSettle();
  });

  testWidgets('树根：意外断连 → error 态 tooltip；处置/断开两态回归不变',
      (tester) async {
    final app = AppProvider();
    final dbFile = File(
      '${Directory.systemTemp.absolute.path}'
      '${Platform.pathSeparator}dbmaster_t10_tree_'
      '${DateTime.now().millisecondsSinceEpoch}.db',
    );
    dbFile.writeAsStringSync(''); // 0 字节 = 合法空 SQLite 库
    addTearDown(() {
      try {
        if (dbFile.existsSync()) dbFile.deleteSync();
      } on FileSystemException {
        // 连接句柄未释放时删除失败不影响测试结论
      }
    });
    final server = DbServer(
      id: 't10_tree_1',
      name: 'TreeConn',
      type: DatabaseType.sqlite,
      host: dbFile.path,
      port: 0,
      username: null,
      password: null,
      database: null,
      useSSL: false,
      timeoutSeconds: 30,
      autoReconnect: false,
    );
    app.connection.addSavedServerForTest(server);

    // 真实连接（真实事件循环完成），再挂树。
    await tester.runAsync(() async {
      expect(await app.connection.connectToServer(server), isTrue);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<ServerConnectionProvider>.value(
            value: ServerConnectionProvider(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SidebarTree(
              expandedItems: const {},
              expandedDatabases: const {},
              expandedTables: const {},
              loadingDatabases: const {},
              loadedTableSchemas: const {},
              loadedTableForeignKeys: const {},
              loadingTableSchemas: const {},
              onToggleExpand: (_) {},
              onToggleDatabase: (_) {},
              onToggleTable: (_) {},
              onLoadDatabaseInfo: (a, b) async {},
              onShowConnectionManager: () {},
              onShowSettings: () {},
              onShowERDiagram: () {},
              onShowStoredProcedures: () {},
              onShowTriggers: () {},
              tableRowCounts: const {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SidebarTree)),
    )!;

    // 正常连接态回归不变：树根连接行 isActive 随 isConnected 传入，
    // tooltip = connectionCurrent。
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == l10n.connectionCurrent,
      ),
      findsOneWidget,
    );

    // 注入意外断连事件（无主动断开标记）→ 失败条目 + error 态 tooltip。
    app.connection.dbService.addEventForTest(
      ConnectionDisconnected(server.id, server),
    );
    await tester.pump();
    await tester.pump();

    expect(app.connection.lastFailureFor(server.id), isNotNull);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            w.message ==
            l10n.connectFailureLatestTooltip(
              SidebarConnectionSelector.failurePlainMessage(
                l10n,
                app.connection.lastFailureFor(server.id)!.kind,
              ),
            ),
      ),
      findsOneWidget,
    );

    // 处置后回归既有连接态 tooltip（无失败 → 原 current/connected 逻辑）。
    app.connection.acknowledgeFailure(server.id);
    await tester.pump();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == l10n.connectionCurrent,
      ),
      findsOneWidget,
    );

    // 真实断开（用户主动）→ 断开态 tooltip 回归 + 不产生失败态。
    await tester.runAsync(
      () => app.connection.disconnectConnection(connectionId: server.id),
    );
    // 断开后无 currentServer/活动 tab，侧栏选中锚点让树继续渲染该连接的
    // 断开态根行（单实例树只渲染当前连接）。
    app.sidebar.selectConnection(server.id);
    await tester.pump();
    await tester.pump();
    expect(app.connection.lastFailureFor(server.id), isNull);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == l10n.connectionDisconnect,
      ),
      findsOneWidget,
    );
  });
}
