// UIRV-B2（软门四态，UI35-221~227）· 先测后存 widget 测试。
//
// 从任务书验收条款直译，两组：
// ① UIRV-B2（既有组，按四态规格适配）：
// 1. 初始 dirty：Test 主样式（accentBlue），Save 次样式可点；
// 2. testing：主槽 = Testing… ×（可点 = 取消，不发第二次请求），Save 禁用；
// 3. tested：成功摘要条含 host:port，Save 主样式、Test 变「重新测试」次样式；
// 4. 白名单字段变更（host）→ reverted（warning 条、Test 回主样式）；
// 5. Save 语义：非 testing 可点、testing 禁用，保存成功 pop 回连接；
// 6. 失败走 ConnectFailureDialog 结构化面，无失败 snackbar、无摘要条；
// 7. footer「Provided by plugin」提示在状态切换前后始终存在（零改动回归）。
// ② UI35-221~227（新组）：四态渲染、按钮槽位不位移、testing 只读、
//    再测试成功/失败、Name/Env 不回退、白名单逐字段回退、取消 + 迟到结果丢弃。
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
import 'package:dbmaster/organisms/connection/forms/connection_form_fields.dart';
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

    testWidgets('B2-002 testing：主槽可点=取消测试（不发第二次请求），Save 禁用',
        (tester) async {
      final provider = await pumpDialog(tester);
      final l10n = l10nOf(tester);
      provider.testGate = Completer<String?>();

      // 表单校验要求连接名非空（既有守卫，非本批改动面）
      await tester.enterText(find.byType(TextField).first, 'conn under test');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(provider.testCalls, 1, reason: '第一次点击发出一次测试请求');
      expect(saveButton(tester).onPressed, isNull, reason: 'testing 中 Save 禁用');

      // testing 中主槽仍可点：点击 = 取消测试（非禁点防重）
      await tester.tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(provider.testCalls, 1, reason: '验收2：取消不发第二次请求');
      expect(find.text(l10n.connectionTestPendingHint), findsOneWidget,
          reason: '验收2：取消后立即回 dirty（脏态提示回归）');

      // 迟到的测试结果被忽略：不回 tested、无摘要条、无失败弹窗
      provider.testGate!.complete(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connection-test-summary')), findsNothing,
          reason: '验收6：取消后迟到结果不生效');
      expect(find.byType(ConnectFailureDialog), findsNothing);
      expect(saveButton(tester).onPressed, isNotNull);
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

    testWidgets('B2-004 host 变更（白名单）→ reverted：warning 条 + Test 回主样式',
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

      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget,
          reason: '验收4：host 变更 → reverted 态 warning 条');
      expect(find.text(l10n.connectionTestSettingsChanged), findsOneWidget,
          reason: 'reverted 条显示「设置已变更」提示');
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsNothing,
          reason: 'reverted 后摘要条清除');
      expect(testButton(tester).backgroundColor, colors.accentBlue,
          reason: '验收4：reverted 态 Test 回主样式');
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

    testWidgets('B2-006 Save 语义：非 testing 可点、testing 禁用、成功 pop 连接',
        (tester) async {
      final provider = await pumpDialog(
        tester,
        viaHost: true,
        onResult: (result) {},
      );

      // dirty 态 Save 可点
      expect(saveButton(tester).onPressed, isNotNull,
          reason: '验收7：非 testing 态 Save 可点');

      // testing 态 Save 禁用（表单校验需连接名非空，先填名）
      await tester.enterText(find.byType(TextField).first, 'my conn');
      await tester.pump();
      provider.testGate = Completer<String?>();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull, reason: '验收7：testing 中 Save 禁用');

      // 取消测试 → Save 恢复可点
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(saveButton(tester).onPressed, isNotNull);
      provider.testGate!.complete(null);
      await tester.pumpAndSettle();

      // 点 Save，成功 pop 回传连接
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-save-button')));
      await tester.pumpAndSettle();

      expect(provider.saved, hasLength(1), reason: '保存走 provider.saveConnection');
      expect(provider.saved.first.name, 'my conn');
    });
  });

  group('UI35-221~227 · 新建连接软门四态', () {
    testWidgets('UI35-221 四态渲染齐全：dirty/testing/tested/reverted 各自提示条',
        (tester) async {
      final provider = await pumpDialog(tester);
      final l10n = l10nOf(tester);

      // dirty：未测试弱提示
      expect(find.text(l10n.connectionTestPendingHint), findsOneWidget);

      // testing：accent tint 提示条含「Testing…」与取消入口
      provider.testGate = Completer<String?>();
      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-inprogress')),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('connection-test-inprogress')),
          matching: find.text(l10n.connectionTestInProgress),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.connectionTestCancel), findsOneWidget);

      // tested：success 摘要条
      provider.testGate!.complete(null);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsOneWidget);

      // reverted：warning 条
      final hostField = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) => f.controller?.text == 'localhost');
      await tester.enterText(find.byWidget(hostField), 'db.example.com');
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget);
      expect(find.text(l10n.connectionTestSettingsChanged), findsOneWidget);
    });

    testWidgets('UI35-222 按钮权重交接不位移：[Cancel][次槽][主槽] 三槽固定',
        (tester) async {
      final provider = await pumpDialog(tester);
      final l10n = l10nOf(tester);

      double dx(Key key) => tester.getCenter(find.byKey(key)).dx;
      final cancelDx =
          tester.getCenter(find.text(l10n.commonCancel)).dx;

      // dirty：Save 次 + Test 主
      expect(cancelDx < dx(const ValueKey('connection-dialog-save-button')),
          isTrue, reason: 'Cancel 在最左');
      expect(
          dx(const ValueKey('connection-dialog-save-button')) <
              dx(const ValueKey('connection-dialog-test-button')),
          isTrue,
          reason: 'dirty：Save 次、Test 主');

      // tested：Test 次 + Save 主（同三槽位置，仅权重互换）
      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(cancelDx < dx(const ValueKey('connection-dialog-test-button')),
          isTrue);
      expect(
          dx(const ValueKey('connection-dialog-test-button')) <
              dx(const ValueKey('connection-dialog-save-button')),
          isTrue,
          reason: 'tested：Test 次、Save 主');

      // testing：主槽 = 可点的 Testing… ×（点击即取消）
      provider.testGate = Completer<String?>();
      await tester.tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull, reason: 'testing：Save 禁用');
      expect(find.byType(OutlinedButton), findsOneWidget,
          reason: 'testing：主槽为 OutlinedButton（Testing… ×）');
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
        reason: 'testing：主槽 Testing… × 可点',
      );
      await tester.tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      // 此前 tested 建立已消耗 1 次请求 + 门控挂起的 1 次；取消不追加第 3 次
      expect(provider.testCalls, 2, reason: '主槽点击 = 取消，非二次请求');
      provider.testGate!.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('UI35-223 testing 态字段只读（IgnorePointer 锁定），他态可编辑',
        (tester) async {
      final provider = await pumpDialog(tester);

      bool locked() => tester
          .widgetList<IgnorePointer>(find.byType(IgnorePointer))
          .any((w) => w.ignoring);

      expect(locked(), isFalse, reason: 'dirty 态字段可编辑');

      provider.testGate = Completer<String?>();
      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(locked(), isTrue, reason: 'testing 态字段只读');

      await tester.tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(locked(), isFalse, reason: '取消后字段恢复可编辑');
    });

    testWidgets('UI35-224 tested → 再测试成功仍 tested；再测试失败回 dirty + 结构化面',
        (tester) async {
      final provider = await pumpDialog(tester);
      final ctx = tester.element(find.byType(ConnectionDialog));
      final l10n = l10nOf(tester);

      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsOneWidget);

      // 再测试成功：仍 tested，摘要条保留
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(provider.testCalls, 2);
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsOneWidget,
          reason: '再测试成功仍 tested');

      // 再测试失败：回 dirty + ConnectFailureDialog
      provider.nextTestResult = 'Connection refused';
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(provider.testCalls, 3);
      expect(find.byType(ConnectFailureDialog), findsOneWidget,
          reason: '失败走结构化面');
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsNothing);
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
      expect(testButton(tester).backgroundColor,
          ctx.themeColors.accentBlue, reason: '失败后回 dirty，Test 回主样式');
    });

    testWidgets('UI35-225 tested 后改 Name/Environment → 仍 tested（不回退）',
        (tester) async {
      final provider = await pumpDialog(tester);

      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();

      // 改 Name → 仍 tested
      await tester.enterText(find.byType(TextField).first, 'renamed conn');
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsOneWidget, reason: '改 Name 不回退，摘要条保留');
      expect(saveButton(tester).backgroundColor,
          tester.element(find.byType(ConnectionDialog)).themeColors.accentBlue,
          reason: 'Save 仍主样式');

      // 改 Environment → 仍 tested
      await tester.tap(find.byType(DropdownButton<ConnectionEnvironment?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Production').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsOneWidget, reason: '改 Environment 不回退，摘要条保留');
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsNothing);
      expect(provider.testCalls, 1);
    });

    testWidgets('UI35-226a 白名单文本字段（host/port/user/password/database/timeout）→ reverted',
        (tester) async {
      final cases = <(int, String)>[
        (1, 'host'), (2, 'port'), (3, 'username'),
        (4, 'password'), (5, 'database'),
      ];
      for (final (index, field) in cases) {
        final provider = await pumpDialog(tester);
        await tester.enterText(find.byType(TextField).first, 'conn');
        await tester.pump();
        await tester
            .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('connection-test-summary')),
            findsOneWidget,
            reason: 'pre-testCalls=${provider.testCalls} field=$field');

        await tester.enterText(find.byType(TextField).at(index), 'changed-$field');
        await tester.pump();
        expect(find.byKey(const ValueKey('connection-test-reverted')),
            findsOneWidget, reason: '$field 变更 → reverted');
        expect(find.byKey(const ValueKey('connection-test-summary')),
            findsNothing, reason: '$field 变更后摘要条清除');
        expect(provider.testCalls, 1);
        // 每轮完全拆树，避免上一轮残留树影响下一轮 pumpWidget
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }

      // timeout 在 advanced 折叠区：展开后编辑
      await pumpDialog(tester);
      final l10n = l10nOf(tester);
      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.connectionAdvancedOptions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.connectionAdvancedOptions));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField).at(6));
      await tester.enterText(find.byType(TextField).at(6), '60');
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget, reason: 'timeout 变更 → reverted');
    });

    testWidgets('UI35-226b SSL 开关（advanced）→ reverted', (tester) async {
      final provider = await pumpDialog(tester);
      final l10n = l10nOf(tester);
      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(l10n.connectionAdvancedOptions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.connectionAdvancedOptions));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.connectionUseSSL));
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate((w) =>
              w is ConnectionSwitchTile && w.title == l10n.connectionUseSSL),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget, reason: 'SSL 开关变更 → reverted');
      expect(provider.testCalls, 1);
    });

    testWidgets('UI35-226c SSH 隧道开关 + 隧道字段 → reverted', (tester) async {
      final provider = await pumpDialog(tester);
      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();

      // 开启 SSH 隧道（开关即白名单字段）
      await tester.ensureVisible(find.text('SSH Tunnel'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
              (w) => w is ConnectionSwitchTile && w.title == 'SSH Tunnel'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget, reason: 'SSH 隧道开关 → reverted');

      // 填 ssh host / ssh username（SSH 字段有必填校验：host/username）
      await tester.ensureVisible(find.byType(TextField).at(6));
      await tester.enterText(find.byType(TextField).at(6), 'jump.example.com');
      await tester.enterText(find.byType(TextField).at(8), 'deploy');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(provider.testCalls, 2, reason: 'SSH 字段齐备后重测发出请求');
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsOneWidget, reason: 'SSH 字段齐备后重测成功');

      // 再改 ssh host 字段 → 再次 reverted
      final sshHostField2 = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) => f.controller?.text == 'jump.example.com');
      await tester.enterText(find.byWidget(sshHostField2), 'jump2.example.com');
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget, reason: 'ssh host 变更 → reverted');
    });

    testWidgets('UI35-226c2 Database Type 切换（白名单）→ reverted',
        (tester) async {
      await pumpDialog(tester);
      final l10n = l10nOf(tester);
      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsOneWidget);

      // 左栏切到 SQLite（仅新建态可切）→ 旧测试结果失效
      await tester.tap(find.text('SQLite'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget, reason: '类型切换（白名单内）→ reverted');
      expect(find.text(l10n.connectionTestSettingsChanged), findsOneWidget);
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsNothing);
    });

    testWidgets('UI35-226d SQLite path → reverted（切类型后测试再改路径）',
        (tester) async {
      final provider = await pumpDialog(tester);
      final l10n = l10nOf(tester);

      // 左栏切到 SQLite（仅新建态可切）
      await tester.tap(find.text('SQLite'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'sqlite conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsOneWidget);

      // 改 path（SQLite path 输入框，controller 文本非空且非 name）
      final pathField = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) =>
              f != tester.widget<TextField>(find.byType(TextField).first) &&
              (f.controller?.text.isNotEmpty ?? false));
      await tester.enterText(find.byWidget(pathField), '/tmp/other.db');
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsOneWidget, reason: 'SQLite path 变更 → reverted');
      expect(find.text(l10n.connectionTestSettingsChanged), findsOneWidget);
      expect(provider.testCalls, 1);
    });

    testWidgets('UI35-228 testing 中点左栏另一类型：类型不切换，迟到结果不落跨类型 stale',
        (tester) async {
      final provider = await pumpDialog(tester);
      final l10n = l10nOf(tester);
      provider.testGate = Completer<String?>();

      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-inprogress')),
          findsOneWidget);

      // testing 中点左栏 PostgreSQL：导航锁定，类型不切换（验收 UI35-228 A）
      // （testing 中 spinner 常驻动画，只能 pump 不能 pumpAndSettle）
      await tester.tap(find.text('PostgreSQL'));
      await tester.pump();
      expect(find.byKey(const ValueKey('connection-test-inprogress')),
          findsOneWidget, reason: 'testing 中点类型无效果：仍在测试中');
      expect(provider.testCalls, 1, reason: '不触发二次请求');
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsNothing);
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsNothing);

      // 迟到结果落回：目标仍是 MySQL（localhost:3306），无「新类型表单 +
      // tested 摘要条」的跨类型 stale
      provider.testGate!.complete(null);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.connectionTestPassedSummary('localhost:3306')),
        findsOneWidget,
        reason: '摘要条目标仍是 MySQL localhost:3306（类型未切换）',
      );
      expect(
        find.text(l10n.connectionFormProvidedBy('mysql-connection-plugin')),
        findsOneWidget,
        reason: '表单仍是 MySQL 插件（类型未切换）',
      );
    });

    testWidgets('UI35-229 tested 后仅展开/收起高级选项 → 仍 tested；改 host → reverted',
        (tester) async {
      final provider = await pumpDialog(tester);
      final l10n = l10nOf(tester);

      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsOneWidget);

      // 展开 advanced（纯 UI 折叠，白名单外）→ 仍 tested，无 reverted 条
      await tester.ensureVisible(find.text(l10n.connectionAdvancedOptions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.connectionAdvancedOptions));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connection-test-summary')),
          findsOneWidget, reason: '展开 advanced 不回退，摘要条保留');
      expect(find.byKey(const ValueKey('connection-test-reverted')),
          findsNothing, reason: '纯 UI 折叠不触发「连接设置已变更」假警告');

      // 收起 advanced → 仍 tested
      await tester.tap(find.text(l10n.connectionAdvancedOptions));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connection-test-summary')), findsOneWidget,
          reason: '收起 advanced 不回退');
      expect(find.byKey(const Key('connection-test-reverted')), findsNothing);

      // 防漏字段：随后改 host 仍正确 reverted
      final hostField = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) => f.controller?.text == 'localhost');
      await tester.ensureVisible(find.byWidget(hostField));
      await tester.enterText(find.byWidget(hostField), 'db.example.com');
      await tester.pump();
      expect(find.byKey(const Key('connection-test-reverted')), findsOneWidget,
          reason: 'host 变更 → reverted（指纹方案不漏 host）');
      expect(find.byKey(const Key('connection-test-summary')), findsNothing);
      expect(provider.testCalls, 1);
    });

    testWidgets('UI35-227 testing 中取消：立即回 dirty + 字段解锁 + 迟到结果被忽略',
        (tester) async {
      final provider = await pumpDialog(tester);
      provider.testGate = Completer<String?>();

      await tester.enterText(find.byType(TextField).first, 'conn');
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(provider.testCalls, 1);

      // 点击主槽（Testing… ×）取消
      await tester
          .tap(find.byKey(const ValueKey('connection-dialog-test-button')));
      await tester.pump();
      expect(find.text(l10nOf(tester).connectionTestPendingHint),
          findsOneWidget, reason: 'UI 立即回 dirty');
      expect(saveButton(tester).onPressed, isNotNull, reason: '字段恢复可操作');

      // 迟到结果（成功）被忽略：不回 tested、无摘要条
      provider.testGate!.complete(null);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('connection-test-summary')), findsNothing,
          reason: '迟到成功结果被丢弃');
      expect(find.byType(ConnectFailureDialog), findsNothing);
      expect(provider.testCalls, 1, reason: '取消不发新请求');
    });
  });
}
