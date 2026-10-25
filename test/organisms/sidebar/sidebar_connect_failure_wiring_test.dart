// UIRV-A2（UI 审查修复批）：侧栏树连接入口失败面统一接线测试。
//
// 任务书验收条款直译（.specs/tasks-ui-review-fixes.md §UIRV-A2）：
//   1. 树上连接入口（根行单击/双击/右键 Connect/收藏·最近重连）失败只弹
//      一个 ConnectFailureDialog：人话原因 + 目标 + 恢复动作；无 SnackBar、
//      无通用 Error 模态叠开。
//   2. connectToServer / openSqliteFile / 打开前置校验的 typed 失败不再写
//      errorMessage 兼容面（_onProviderChange 不再触发通用模态）。
//   3. 重试闭包 = 对应入口的同一连接调用（真实 provider.connectToServer
//      重发）；重试仍失败 → 对话框原地更新、不叠窗。
//
// 真实链路纪律：真实 AppProvider + 真实 DatabaseService + 真实 SQLite
// adapter；失败用垃圾字节临时文件构造（不 mock 数据库服务）；仅 mock
// flutter_tester 会挂起的平台通道（SharedPreferences / SecureStorage）。
import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// 谎报已连接的最小 stub（树装配判定用；本组连接入口全部走真实失败链路，
/// 不触达其余 adapter 方法）。
class _FakeTreeAdapter extends Fake implements DatabaseAdapter {
  @override
  bool get isConnected => true;
}

DbServer _failingSqliteServer(String id, String garbagePath) => DbServer(
  id: id,
  name: id,
  type: DatabaseType.sqlite,
  host: garbagePath,
  port: 0,
  username: null,
  // 密码非空 → PasswordPromptDialog.ensurePassword 不弹窗直接放行。
  password: 'x',
);

Widget _buildTestApp(AppProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: provider),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider()..load(),
      ),
      ChangeNotifierProvider<ServerConnectionProvider>(
        create: (_) => ServerConnectionProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 1200,
          child: SidebarTree(
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
}

AppLocalizations _l10nOf(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(SidebarTree)),
)!;

/// 真实文件 IO / sqlite FFI 完成于真实事件循环：runAsync 让出 FakeAsync
/// 轮询真实完成，再以固定步进推进帧（与 sqlite_open_error_dialog_test 同款
/// harness；固定小步 fake 时间远离保活心跳周期边界）。
Future<void> waitUntilSettled(
  WidgetTester tester,
  bool Function() done,
) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pump(const Duration(milliseconds: 100));
  expect(done(), isTrue, reason: '等待条件 3s 内未满足');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = Directory.systemTemp.createTempSync('dbmaster_uirv_a2_');
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
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // 连接句柄占用时尽力而为
    }
  });

  /// 写垃圾字节 SQLite 文件（连接必失败 → notADatabase 分型）。
  File writeGarbage(String tag) {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}$tag.db',
    )..writeAsStringSync('not a database at all');
    return file;
  }

  group('UIRV-A2 · 树连接失败只弹 ConnectFailureDialog', () {
    testWidgets('树根行单击连接失败 → 结构化对话框出现一次，无 SnackBar',
        (tester) async {
      final garbage = writeGarbage('root_tap');
      final app = AppProvider();
      final server = _failingSqliteServer('a2_root', garbage.path);
      app.connection.addSavedServerForTest(server);

      await tester.pumpWidget(_buildTestApp(app));
      await tester.pumpAndSettle();
      final l10n = _l10nOf(tester);

      await tester.tap(find.text(server.name).first);
      await waitUntilSettled(
        tester,
        () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
      );

      // 验收 1：只弹一个结构化面。
      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // 分型生效：人话原因（notADatabase），非原始异常文本。
      expect(find.text(l10n.connectFailureNotADatabase), findsOneWidget);
      // 验收 2：连接类失败不再写 errorMessage 兼容面。
      expect(app.connection.errorMessage, isNull);
      // 结构化失败与失败结果同生共死（T3 契约保持）。
      expect(
        app.connection.lastFailureFor(server.id)?.kind,
        ConnectionFailureKind.notADatabase,
      );
    });

    testWidgets('树根行双击连接失败 → 同一结构化面（无 SnackBar）', (tester) async {
      final garbage = writeGarbage('root_dbl');
      final app = AppProvider();
      final server = _failingSqliteServer('a2_dbl', garbage.path);
      app.connection.addSavedServerForTest(server);

      await tester.pumpWidget(_buildTestApp(app));
      await tester.pumpAndSettle();
      final l10n = _l10nOf(tester);

      await tester.tap(find.text(server.name).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text(server.name).first, warnIfMissed: false);
      await waitUntilSettled(
        tester,
        () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
      );

      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(l10n.connectFailureNotADatabase), findsOneWidget);
    });

    testWidgets('右键菜单 Connect 失败 → 结构化对话框（无 SnackBar）',
        (tester) async {
      final garbage = writeGarbage('ctx');
      final app = AppProvider();
      final server = _failingSqliteServer('a2_ctx', garbage.path);
      app.connection.addSavedServerForTest(server);

      await tester.pumpWidget(_buildTestApp(app));
      await tester.pumpAndSettle();
      final l10n = _l10nOf(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text(server.name).first),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.connectionConnect));
      await waitUntilSettled(
        tester,
        () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
      );

      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(l10n.connectFailureNotADatabase), findsOneWidget);
    });

    testWidgets('最近表重连失败（收藏/最近护栏入口）→ 结构化对话框', (tester) async {
      final garbage = writeGarbage('recent');
      final app = AppProvider();
      final server = _failingSqliteServer('a2_recent', garbage.path);
      app.connection.addSavedServerForTest(server);
      // 最近表条目指向未连接连接 → 点击走 _switchAndOpenTableQuery 重连护栏。
      await app.recentTables.recordTableAccess(
        connectionId: server.id,
        databaseName: 'main',
        tableName: 'Album',
      );

      await tester.pumpWidget(_buildTestApp(app));
      await tester.pumpAndSettle();
      final l10n = _l10nOf(tester);

      // 顶区最近表行（'连接名 · 表名' 前缀既有）。
      final recentLabel = find.textContaining(server.name).first;
      await tester.tap(recentLabel);
      await waitUntilSettled(
        tester,
        () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
      );

      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(l10n.connectFailureNotADatabase), findsOneWidget);
    });

    testWidgets('重试仍失败：同一连接调用重发，对话框原地更新不叠窗', (tester) async {
      final garbage = writeGarbage('retry');
      final app = AppProvider();
      final server = _failingSqliteServer('a2_retry', garbage.path);
      app.connection.addSavedServerForTest(server);

      await tester.pumpWidget(_buildTestApp(app));
      await tester.pumpAndSettle();
      final l10n = _l10nOf(tester);

      await tester.tap(find.text(server.name).first);
      await waitUntilSettled(
        tester,
        () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
      );
      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      final firstFailure = app.connection.lastFailureFor(server.id);
      final firstOccurredAt = firstFailure!.occurredAt;

      // 同一目标重试（闭包 = provider.connectToServer 同一调用）：
      // 仍打同一垃圾文件 → 再次失败。occurredAt 推进证明第二次真实连接调用发生。
      await tester.pump(const Duration(milliseconds: 400)); // 入场动画走完再点
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.connectFailureRetry),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await waitUntilSettled(
        tester,
        () => app.connection.lastFailureFor(server.id)!.occurredAt
            .isAfter(firstOccurredAt),
      );

      expect(find.byType(ConnectFailureDialog), findsOneWidget,
          reason: '仍失败时原地更新单实例，不叠开第二个对话框');
      expect(find.byType(SnackBar), findsNothing);
      final secondFailure = app.connection.lastFailureFor(server.id);
      expect(secondFailure, isNotNull);
      expect(
        secondFailure!.occurredAt.isAfter(firstOccurredAt),
        isTrue,
        reason: '重试闭包应重发同一 provider.connectToServer 调用（失败时间戳推进）',
      );
    });

    testWidgets('重试成功后（文件修复）：对话框关闭', (tester) async {
      final garbage = writeGarbage('retry_ok');
      final app = AppProvider();
      final server = _failingSqliteServer('a2_retry_ok', garbage.path);
      app.connection.addSavedServerForTest(server);

      await tester.pumpWidget(_buildTestApp(app));
      await tester.pumpAndSettle();
      final l10n = _l10nOf(tester);

      await tester.tap(find.text(server.name).first);
      await waitUntilSettled(
        tester,
        () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
      );
      expect(find.byType(ConnectFailureDialog), findsOneWidget);

      // 修复路径：截断为 0 字节（SQLite 合法空库），重试成功。
      await tester.pump(const Duration(milliseconds: 400));
      garbage.writeAsStringSync('');
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.connectFailureRetry),
      );
      await waitUntilSettled(
        tester,
        () => find.byType(ConnectFailureDialog).evaluate().isEmpty,
      );

      expect(find.byType(ConnectFailureDialog), findsNothing);
      // 成功后失败条目清除（T10 同生共死）。
      expect(app.connection.lastFailureFor(server.id), isNull);
      // 成功清理：关闭保活 Timer。sqflite 关闭是真实异步，须经 runAsync
      // 在真实事件循环完成——直接 await 会在 FakeAsync 下永不完成。
      await tester.runAsync(
        () => app.connection.disconnectConnection(connectionId: server.id),
      );
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('UIRV-A2 · errorMessage 兼容面退役边界', () {
    test('connectToServer typed 失败不写 errorMessage；结构化失败照常', () async {
      final provider = AppProvider();
      final garbage = writeGarbage('prov');

      final result = await provider.connection.connectToServer(
        _failingSqliteServer('a2_prov', garbage.path),
      );

      expect(result, isFalse);
      // 验收 2：连接类失败不再写 _errorMessage（_onProviderChange 不再触发
      // 通用模态的结构性保证）。
      expect(provider.connection.errorMessage, isNull);
      expect(
        provider.connection.lastConnectFailure?.kind,
        ConnectionFailureKind.notADatabase,
      );
      expect(
        provider.connection.lastFailureFor('a2_prov')?.kind,
        ConnectionFailureKind.notADatabase,
      );
    });

    test('openSqliteFile 非法扩展名（打开前置校验）不写 errorMessage', () async {
      final provider = AppProvider();

      final result = await provider.connection.openSqliteFile(
        'not_a_sqlite_file.txt',
      );

      expect(result, isFalse);
      expect(provider.connection.errorMessage, isNull);
      expect(
        provider.connection.lastConnectFailure?.kind,
        ConnectionFailureKind.unknown,
      );
      expect(
        provider.connection.lastConnectFailure?.rawMessage,
        contains('Not a supported SQLite file'),
      );
    });

    test('保存类失败（非连接类）仍写 errorMessage（口径保留）', () async {
      final provider = AppProvider();
      final server = _failingSqliteServer('a2_save', '${tempDir.path}/x.db');

      // SecureStorage 写入失败（保险箱异常被 saveConnection 内层捕获 →
      // 「凭据未能安全保存」 errorMessage，非连接类口径）。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => throw PlatformException(
          code: 'secure_store_failed',
          message: 'keychain denied',
        ),
      );
      try {
        await provider.connection.saveConnection(server);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel(
            'plugins.it_nomads.com/flutter_secure_storage',
          ),
          (call) async => null,
        );
      }

      // 保存失败 ≠ 连接失败：旧通用面口径保留，errorMessage 非空、
      // 结构化连接失败仍为 null（不串味）。
      expect(provider.connection.errorMessage, isNotNull);
      expect(provider.connection.lastConnectFailure, isNull);
    });
  });
}
