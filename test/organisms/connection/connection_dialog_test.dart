// UIRV-B2 · 新建连接先测后存（软门）——表单状态机 widget 测试。
//
// 从任务书验收条款 1~7 直译：
// 1. 初始 dirty：Test 为主样式（accentBlue），Save 次样式但可点；
// 2. testing：主动作 loading 禁点防重，测试请求只发一次（计数断言）；
// 3. tested：成功摘要条含 host:port，Save 变主样式、Test 变「重新测试」次样式；
// 4. 影响连接的字段变更（host）→ 回 dirty（摘要条清除、Test 回主样式）；
// 5. Save 始终可用（testing 中仍可点），保存成功 pop 回连接（契约不变）；
// 6. 失败走 ConnectFailureDialog 结构化面，无失败 snackbar、无摘要条；
// 7. footer「Provided by plugin」提示在状态切换前后始终存在（零改动回归）。
//
// provider 经 AppProvider 子类注入桩（testConnection 可门控 + 计数、
// saveConnection 捕获），不触真库/平台通道——纯呈现层（任务书约束）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/atoms/app_loading.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/organisms/connection/connection_dialog.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

class _StubAppProvider extends AppProvider {
  int testCalls = 0;
  final List<DbServer> saved = [];

  /// 非 null 时 testConnection 挂起直到 complete（防重计数用）。
  Completer<String?>? testGate;
  String? nextTestResult;

  @override
  Future<String?> testConnection(DbServer server) {
    testCalls++;
    final gate = testGate;
    if (gate != null && !gate.isCompleted) return gate.future;
    return Future<String?>.value(nextTestResult);
  }

  @override
  Future<void> saveConnection(DbServer server) async {
    saved.add(server);
  }
}

/// 承载 dialog 的宿主页：showDialog 推入 + pop 结果回调（Save pop 契约用）。
class _DialogHost extends StatefulWidget {
  const _DialogHost({required this.onResult});

  final ValueChanged<Object?> onResult;

  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<DbServer>(
        context: context,
        builder: (_) => const ConnectionDialog(),
      ).then(widget.onResult);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('home')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_StubAppProvider> pumpDialog(
    WidgetTester tester, {
    bool viaHost = false,
    ValueChanged<Object?>? onResult,
  }) async {
    if (defaultPluginRegistry.pluginCount == 0) {
      registerDefaultUiPlugins(defaultPluginRegistry);
    }
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final provider = _StubAppProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: viaHost
              ? _DialogHost(
                  onResult: onResult ??
                      (Object? _) {},)
              : const Scaffold(body: ConnectionDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(
        tester.element(find.byType(ConnectionDialog)),
      )!;

  LoadingButton testButton(WidgetTester tester) => tester.widget<LoadingButton>(
        find.byKey(const ValueKey('connection-dialog-test-button')),
      );

  LoadingButton saveButton(WidgetTester tester) => tester.widget<LoadingButton>(
        find.byKey(const ValueKey('connection-dialog-save-button')),
      );

  group('UIRV-B2 · 先测后存软门（状态机）', () {
    testWidgets('B2-001 初始 dirty：Test 主样式、Save 次样式可点、脏态提示可见',
        (tester) async {
      final provider = await pumpDialog(tester);
      final ctx = tester.element(find.byType(ConnectionDialog));
      final colors = ctx.themeColors;

      expect(testButton(tester).backgroundColor, colors.accentBlue,
          reason: '验收1：dirty 态 Test 为主样式');
      expect(testButton(tester).isLoading, isFalse);
      expect(saveButton(tester).backgroundColor, colors.bgTertiary,
          reason: '验收1：dirty 态 Save 为次样式');
      expect(saveButton(tester).onPressed, isNotNull,
          reason: '验收1/5：Save 始终可点');

      final l10n = l10nOf(tester);
      expect(find.text(l10n.connectionTestPendingHint), findsOneWidget,
          reason: 'dirty 态显示未测试提示');
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsNothing,
          reason: '未测试无成功摘要条');
      expect(provider.testCalls, 0);
    });

    testWidgets('B2-002 testing：loading 禁点防重，测试请求只发一次', (tester) async {
      final provider = await pumpDialog(tester);
      provider.testGate = Completer<String?>();

      // 表单校验要求连接名非空（既有守卫，非本批改动面）
      await tester.enterText(find.byType(TextField).first, 'conn under test');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(provider.testCalls, 1, reason: '第一次点击发出一次测试请求');
      expect(testButton(tester).isLoading, isTrue, reason: 'testing 中主动作 loading');

      // testing 中 Save 仍可点（离线保存自由，不被测试态锁住）
      expect(saveButton(tester).onPressed, isNotNull, reason: '验收5：Save 始终可用');

      await tester.tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(provider.testCalls, 1, reason: '验收2：testing 中禁点防重，请求只发一次');

      provider.testGate!.complete(null);
      await tester.pumpAndSettle();
      expect(testButton(tester).isLoading, isFalse);
    });

    testWidgets('B2-003 tested：成功摘要条含 host:port，Save 主样式、Test 变重新测试',
        (tester) async {
      final provider = await pumpDialog(tester);
      final ctx = tester.element(find.byType(ConnectionDialog));
      final colors = ctx.themeColors;
      final l10n = l10nOf(tester);

      // 表单校验要求连接名非空（既有守卫，非本批改动面）
      await tester.enterText(find.byType(TextField).first, 'conn under test');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();

      expect(provider.testCalls, 1);
      expect(
        find.text(l10n.connectionTestPassedSummary('localhost:3306')),
        findsOneWidget,
        reason: '验收3：成功摘要条含目标 host:port（默认 MySQL localhost:3306）',
      );
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsOneWidget);
      expect(saveButton(tester).backgroundColor, colors.accentBlue,
          reason: '验收3：tested 后 Save 变主样式');
      expect(find.text(l10n.connectionRetest), findsOneWidget,
          reason: '验收3：Test 变「重新测试」');
      expect(testButton(tester).backgroundColor, colors.bgTertiary,
          reason: '验收3：重新测试为次样式');
      // footer 徽章零改动（验收7）
      expect(
        find.text(l10n.connectionFormProvidedBy('mysql-connection-plugin')),
        findsOneWidget,
      );
    });

    testWidgets('B2-004 影响连接的字段变更（host）→ 回 dirty，摘要条清除',
        (tester) async {
      final provider = await pumpDialog(tester);
      final ctx = tester.element(find.byType(ConnectionDialog));
      final colors = ctx.themeColors;
      final l10n = l10nOf(tester);

      // 表单校验要求连接名非空（既有守卫，非本批改动面）
      await tester.enterText(find.byType(TextField).first, 'conn under test');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsOneWidget);

      // 改 host（MySQL 表单 host 输入框，初始值 localhost）
      final hostField = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) => f.controller?.text == 'localhost');
      await tester.enterText(find.byWidget(hostField), 'db.example.com');
      await tester.pump();

      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsNothing,
          reason: '验收4：字段变更后旧测试态失效，摘要条清除');
      expect(find.text(l10n.connectionTestPendingHint), findsOneWidget,
          reason: '回 dirty 后重新显示未测试提示');
      expect(testButton(tester).backgroundColor, colors.accentBlue,
          reason: '验收4：回 dirty 后 Test 回主样式');
      expect(find.text(l10n.connectionRetest), findsNothing);
      expect(provider.testCalls, 1);
    });

    testWidgets('B2-005 测试失败：走 ConnectFailureDialog 结构化面，无 snackbar、无摘要',
        (tester) async {
      final provider = await pumpDialog(tester);
      provider.nextTestResult = 'Connection refused';

      await tester.enterText(find.byType(TextField).first, 'conn under test');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectFailureDialog), findsOneWidget,
          reason: '验收6：失败走结构化错误面');
      expect(find.byType(SnackBar), findsNothing,
          reason: '验收6：失败 snackbar 退役，不叠报');
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsNothing,
          reason: '失败无成功摘要条');

      // 关闭失败对话框后回 dirty：Test 回主样式
      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(ConnectionDialog));
      expect(testButton(tester).backgroundColor, ctx.themeColors.accentBlue);
    });

    testWidgets('B2-006 Save 始终可用且成功后 pop 连接（契约不变）', (tester) async {
      final provider = await pumpDialog(
        tester,
        viaHost: true,
        onResult: (result) {},
      );

      // testing 未完成时 Save 仍可点
      provider.testGate = Completer<String?>();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(saveButton(tester).onPressed, isNotNull, reason: '验收5：Save 始终可用');

      // 填连接名（保存校验必填）后点 Save
      await tester.enterText(find.byType(TextField).first, 'my conn');
      await tester.pump();
      provider.testGate!.complete(null);
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-save-button')));
      await tester.pumpAndSettle();

      expect(provider.saved, hasLength(1), reason: '保存走 provider.saveConnection');
      expect(provider.saved.first.name, 'my conn');
    });
  });
}
