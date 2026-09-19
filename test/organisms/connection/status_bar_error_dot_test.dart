// StatusBarWidget 未处置连接失败指示点测试（连接失败 UX 重构 T10）。
//
// 覆盖：无失败不可见；connect 失败（真实 SQLite 坏路径）→ 指示点可见且
// tooltip 为最新人话；点击 = 打开执行中心 + 处置全部 + 指示点消失；
// 与 _ErrorBadge（执行中心错误计数）并存互不干扰。
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
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/error_event.dart';
import 'package:dbmaster/organisms/connection/status_bar_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';

const _dotKey = ValueKey('status_bar_connection_failure_dot');

DbServer _sqliteServer(String id, String host) => DbServer(
  id: id,
  name: id,
  type: DatabaseType.sqlite,
  host: host,
  port: 0,
  username: null,
  password: null,
  database: null,
  useSSL: false,
  timeoutSeconds: 30,
  autoReconnect: false,
);

Future<void> pumpStatusBar(WidgetTester tester, AppProvider provider) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<TaskProvider>.value(value: TaskProvider()),
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
        home: const Scaffold(body: StatusBarWidget()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(StatusBarWidget)))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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

  testWidgets('无未处置失败 → 指示点不可见', (tester) async {
    final app = AppProvider();
    await pumpStatusBar(tester, app);

    expect(find.byKey(_dotKey), findsNothing);
  });

  testWidgets('connect 失败 → 指示点可见且 tooltip 含最新人话', (tester) async {
    final app = AppProvider();
    final garbage = File(
      '${Directory.systemTemp.absolute.path}'
      '${Platform.pathSeparator}dbmaster_t10_sb_'
      '${DateTime.now().millisecondsSinceEpoch}.db',
    );
    garbage.writeAsStringSync('not a database at all');
    addTearDown(() {
      try {
        if (garbage.existsSync()) garbage.deleteSync();
      } on FileSystemException {}
    });

    // 真实 connect 失败在真实事件循环完成：runAsync 让出 FakeAsync。
    await tester.runAsync(() async {
      await app.connection.connectToServer(_sqliteServer('t10_sb_1', garbage.path));
    });

    await pumpStatusBar(tester, app);
    final l10n = _l10nOf(tester);

    expect(find.byKey(_dotKey), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(_dotKey),
        matching: find.byType(Tooltip),
      ),
    );
    expect(
      tooltip.message,
      l10n.connectFailureLatestTooltip(l10n.connectFailureNotADatabase),
    );
  });

  testWidgets('点击 → 执行中心打开 + 全部处置 + 指示点消失', (tester) async {
    final app = AppProvider();
    final garbage = File(
      '${Directory.systemTemp.absolute.path}'
      '${Platform.pathSeparator}dbmaster_t10_sb2_'
      '${DateTime.now().millisecondsSinceEpoch}.db',
    );
    garbage.writeAsStringSync('not a database at all');
    addTearDown(() {
      try {
        if (garbage.existsSync()) garbage.deleteSync();
      } on FileSystemException {}
    });

    await tester.runAsync(() async {
      await app.connection.connectToServer(_sqliteServer('t10_sb_2', garbage.path));
    });

    await pumpStatusBar(tester, app);
    expect(app.connection.hasUnacknowledgedFailures, isTrue);
    expect(app.executionCenter.isOpen, isFalse);

    await tester.tap(find.byKey(_dotKey));
    await tester.pumpAndSettle();

    expect(app.executionCenter.isOpen, isTrue, reason: '点击应打开执行中心');
    expect(app.connection.hasUnacknowledgedFailures, isFalse, reason: '点击应处置全部失败');
    expect(find.byKey(_dotKey), findsNothing);
  });

  testWidgets('与 _ErrorBadge 并存互不干扰（两 widget 同时可见）', (tester) async {
    final app = AppProvider();
    final garbage = File(
      '${Directory.systemTemp.absolute.path}'
      '${Platform.pathSeparator}dbmaster_t10_sb3_'
      '${DateTime.now().millisecondsSinceEpoch}.db',
    );
    garbage.writeAsStringSync('not a database at all');
    addTearDown(() {
      try {
        if (garbage.existsSync()) garbage.deleteSync();
      } on FileSystemException {}
    });

    await tester.runAsync(() async {
      await app.connection.connectToServer(_sqliteServer('t10_sb_3', garbage.path));
    });
    // 独立注入执行中心错误（_ErrorBadge 的数据源，与失败指示点无交集）。
    app.executionCenter.addError(
      ErrorEvent(
        id: 't10_exec_1',
        timestamp: DateTime.now(),
        severity: ErrorSeverity.error,
        message: 'execution center error',
      ),
    );

    await pumpStatusBar(tester, app);

    // 各自存在：失败指示点 + 错误计数徽标「1」。
    expect(find.byKey(_dotKey), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
