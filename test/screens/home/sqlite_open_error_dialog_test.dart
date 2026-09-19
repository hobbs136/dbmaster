// T8（连接失败 UX 重构）：home_screen SQLite 打开失败接线回归。
//
// 验证 _connectSqlitePath 失败分支从固定文案 snackbar 升级为结构化
// ConnectFailureDialog：
//   1. 拖入坏 SQLite 文件（垃圾字节）→ notADatabase 对话框出现 1 次、无 SnackBar；
//   2. 重试仍失败（同路径换成目录占位 → fileNotFound）→ 对话框原地更新、不叠开；
//   3. 文件修复（截断为 0 字节 = 合法空库）后重试 → 对话框关闭 + 侧栏选中该连接；
//   4. 非 SQLite 扩展名拖入 → firstSqlitePath 过滤，不弹任何提示。
//
// 真实链路纪律：真实 AppProvider + 真实 DatabaseService + 真实 SQLite adapter
// + 真实临时文件（不 mock 数据库服务）；仅 mock 会挂起 flutter_tester 的
// 平台通道（SharedPreferences / FlutterSecureStorage），desktop_drop 用
// 通道注入模拟拖拽放下。
//
// harness 参照 ai_fullscreen_e2e_test.dart（真实 HomeScreen）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/approval_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/health_check_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/providers/workspace_provider.dart';
import 'package:dbmaster/screens/home_screen.dart';

/// 在系统临时目录写一个唯一命名的文件（同步 IO，避开 FakeAsync）。
File _writeTempFile(String tag, String extension, {String content = ''}) {
  final file = File(
    '${Directory.systemTemp.absolute.path}'
    '${Platform.pathSeparator}dbmaster_t8_${tag}_'
    '${DateTime.now().millisecondsSinceEpoch}.$extension',
  );
  file.writeAsStringSync(content);
  return file;
}

/// 按路径真实类型清理临时文件/目录（用例中途可能把同一路径换成了目录）。
void _deleteQuietly(FileSystemEntity entity) {
  try {
    final type = FileSystemEntity.typeSync(entity.path);
    if (type == FileSystemEntityType.directory) {
      Directory(entity.path).deleteSync(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      File(entity.path).deleteSync();
    }
  } on FileSystemException {
    // 临时文件清理尽力而为，不影响测试结论
  }
}

/// 注入 desktop_drop 平台事件模拟拖拽放下。
///
/// DropTarget 只在 enter 态 + 落点入界时触发 onDragDone，故先发 entered
/// （坐标为物理像素，test 环境 dpr=3，(300,300) 映射入界逻辑位）。
Future<void> dropPaths(WidgetTester tester, List<String> paths) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> send(MethodCall call) => messenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(call),
        (data) {},
      );
  await send(const MethodCall('entered', <double>[300, 300]));
  await tester.pump();
  await send(MethodCall('performOperation', paths));
  await tester.pump();
}

/// 真实文件 IO / sqlite FFI 完成于真实事件循环：runAsync 让出 FakeAsync
/// 轮询真实完成，再以固定步进推进帧；[done] 长期不满足则显式失败。
///
/// 固定小步 pump 而非 pumpAndSettle：连接成功后工作区可能存在常驻动画
/// （pumpAndSettle 会永不停歇超时）。fake 步长压在 10ms，是为了让单个
/// 用例累计 fake 时间远离连接保活心跳的 10s 周期边界（跨界会触发心跳
/// 回调，其内部真实异步会让 FakeAsync elapse 挂死）。
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

Future<AppProvider> pumpHome(WidgetTester tester) async {
  final app = AppProvider();
  // 表面加宽：连接激活后 StatusBarWidget 的连接信息 Row 在测试字体（Ahem，
  // 字宽约为真实字体 2 倍）下会溢出（1400 宽时溢出 ~107px）——与
  // home_layers_test.dart 规避 SidebarHeader 溢出同类，属测试字体产物。
  await tester.binding.setSurfaceSize(const Size(2200, 1100));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ChangeNotifierProvider<AppProvider>.value(value: app),
        ChangeNotifierProvider<TaskProvider>.value(value: TaskProvider()),
        ChangeNotifierProvider<ServerConnectionProvider>.value(
          value: ServerConnectionProvider(),
        ),
        ChangeNotifierProvider<HealthCheckProvider>.value(
          value: HealthCheckProvider(),
        ),
        ChangeNotifierProvider<ApprovalProvider>.value(
          value: ApprovalProvider(),
        ),
        ChangeNotifierProvider<WorkspaceProvider>.value(
          value: WorkspaceProvider(),
        ),
        ChangeNotifierProvider<ThemeProvider>.value(
          value: ThemeProvider()..load(),
        ),
        ChangeNotifierProvider<LocaleProvider>.value(
          value: LocaleProvider()..load(),
        ),
        ChangeNotifierProvider<LayoutPreferencesProvider>.value(
          value: LayoutPreferencesProvider()..load(),
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
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

AppLocalizations _l10nOfHome(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;

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

  testWidgets('拖入坏 SQLite 文件：结构化对话框出现 1 次，无 SnackBar',
      (tester) async {
    final garbage =
        _writeTempFile('bad', 'db', content: 'not a database at all');
    addTearDown(() => _deleteQuietly(garbage));

    final app = await pumpHome(tester);
    final l10n = _l10nOfHome(tester);

    await dropPaths(tester, <String>[garbage.path]);
    await waitUntilSettled(
      tester,
      () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
    );

    expect(find.byType(ConnectFailureDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    // P0 闭环：errorMessage 兼容面的遗留通用错误弹窗不得叠开盖住结构化对话框。
    expect(find.byType(AlertDialog), findsOneWidget);
    // 结构化分型生效：垃圾字节 → notADatabase 人话原因（非原始异常文本）。
    expect(find.text(l10n.connectFailureNotADatabase), findsOneWidget);
    expect(
      app.connection.lastConnectFailure?.kind,
      ConnectionFailureKind.notADatabase,
    );
  });

  testWidgets('重试仍失败：对话框原地更新内容，不叠开第二个', (tester) async {
    final garbage = _writeTempFile('retry_fail', 'db', content: 'garbage v1');
    addTearDown(() => _deleteQuietly(garbage));

    final app = await pumpHome(tester);
    final l10n = _l10nOfHome(tester);

    await dropPaths(tester, <String>[garbage.path]);
    await waitUntilSettled(
      tester,
      () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
    );
    expect(find.text(l10n.connectFailureNotADatabase), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400)); // 入场动画走完再点

    // 同路径换成目录占位后重试：sqlite CANTOPEN → 失败分型原地更新为
    // fileNotFound（目录占位也让 sqlite 的 CREATE 语义建不出文件）。
    garbage.deleteSync();
    Directory(garbage.path).createSync();

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.connectFailureRetry),
    );
    await waitUntilSettled(
      tester,
      () =>
          find.text(l10n.connectFailureFileNotFound).evaluate().isNotEmpty,
    );

    expect(
      find.byType(ConnectFailureDialog),
      findsOneWidget,
      reason: '仍失败时应原地更新单实例，不叠开第二个对话框',
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(
      app.connection.lastConnectFailure?.kind,
      ConnectionFailureKind.fileNotFound,
    );
  });

  testWidgets('文件修复后重试：对话框关闭且侧栏选中该连接', (tester) async {
    final garbage = _writeTempFile('retry_ok', 'db', content: 'garbage v1');
    addTearDown(() => _deleteQuietly(garbage));

    final app = await pumpHome(tester);
    final l10n = _l10nOfHome(tester);

    await dropPaths(tester, <String>[garbage.path]);
    await waitUntilSettled(
      tester,
      () => find.byType(ConnectFailureDialog).evaluate().isNotEmpty,
    );

    // 修复路径：截断为 0 字节（SQLite 合法空库），重试应成功。
    await tester.pump(const Duration(milliseconds: 400)); // 入场动画走完再点
    garbage.writeAsStringSync('');
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.connectFailureRetry),
    );
    await waitUntilSettled(
      tester,
      () => find.byType(ConnectFailureDialog).evaluate().isEmpty,
    );

    expect(find.byType(ConnectFailureDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // 成功分支既有行为回归：定位刚保存/复用的连接并在侧栏选中。
    final conn = ConnectionProvider.findExistingSqlite(
      app.connection.savedConnections,
      ConnectionProvider.normalizeSqlitePath(garbage.path),
    );
    expect(conn, isNotNull);
    expect(app.sidebar.selectedConnectionId, conn!.id);

    // 断开清理：连接成功路径会启动保活类 Timer，测试结束前断开，避免
    // 「Timer is still pending」不变量（与 T3 provider 测试同一处理）。
    // sqflite 关闭是真实异步，须经 runAsync 在真实事件循环完成——直接
    // await 会在 FakeAsync 下永不完成。
    await tester.runAsync(() => app.connection.disconnectConnection());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('拖入非 SQLite 扩展名：firstSqlitePath 过滤，不弹对话框',
      (tester) async {
    final txt = _writeTempFile('txt', 'txt', content: 'plain text');
    addTearDown(() => _deleteQuietly(txt));

    final app = await pumpHome(tester);

    await dropPaths(tester, <String>[txt.path]);
    await waitUntilSettled(tester, () => true);

    expect(find.byType(ConnectFailureDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(app.connection.lastConnectFailure, isNull);
    expect(app.connection.savedConnections, isEmpty);
  });
}
