// ConnectFailureDialog widget 测试（连接失败 UX 重构 T5）。
//
// 组件与 provider 解耦（回调注入），测试只 pump MaterialApp + ThemeProvider，
// 平台通道仅 mock Clipboard（验证复制 payload）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  String? clipboardPayload;
  setUp(() {
    clipboardPayload = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>?;
        clipboardPayload = args?['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  ConnectionFailure failureFixture({
    ConnectionFailureKind kind = ConnectionFailureKind.fileLocked,
    String errorCode = '5',
    String? offendingStatement = 'PRAGMA journal_mode = DELETE',
    String? target = 'C:/data/chinook.db',
    String rawMessage = 'database is locked (5)',
  }) {
    return ConnectionFailure(
      kind: kind,
      errorCode: errorCode,
      offendingStatement: offendingStatement,
      target: target,
      rawMessage: rawMessage,
      occurredAt: DateTime(2026, 1, 1),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required ConnectionFailure failure,
    required Future<bool> Function() onRetry,
    VoidCallback? onChooseFile,
    ConnectionFailure? Function()? latestFailure,
    String? environmentLabel,
  }) async {
    final themeProvider = ThemeProvider();
    await themeProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ConnectFailureDialog.show(
                context,
                failure: failure,
                onRetry: onRetry,
                onChooseFile: onChooseFile,
                latestFailure: latestFailure,
                environmentLabel: environmentLabel,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder selectableContaining(String text) => find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data?.contains(text) ?? false),
      );

  Finder selectableExact(String text) => find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == text,
      );

  bool primaryFocusIsInside(WidgetTester tester, Finder finder) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final target = tester.element(finder);
    if (identical(focusContext, target)) return true;
    var found = false;
    (focusContext as Element).visitAncestorElements((element) {
      if (identical(element, target)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  group('ConnectFailureDialog', () {
    testWidgets(
        'fileLocked: plain-language reason, collapsed technical details, copy button',
        (tester) async {
      await openDialog(tester, failure: failureFixture(), onRetry: () async => true);

      expect(find.text('Connection Failed'), findsOneWidget);
      expect(
        selectableContaining('The file is locked by another program'),
        findsOneWidget,
      );
      // 路径/语句只进技术详情：默认折叠时不可见。
      expect(selectableContaining('PRAGMA journal_mode = DELETE'), findsNothing);
      expect(selectableContaining('chinook.db'), findsNothing);
      expect(find.text('Technical Details'), findsOneWidget);
      expect(find.text('Copy Details'), findsOneWidget);

      // 展开后：出错语句 + 错误码 + 原始异常键值行可见。
      await tester.tap(find.text('Technical Details'));
      await tester.pumpAndSettle();
      expect(
        selectableContaining('PRAGMA journal_mode = DELETE'),
        findsOneWidget,
      );
      expect(selectableExact('5'), findsOneWidget);
      expect(selectableContaining('database is locked (5)'), findsOneWidget);
      expect(find.text('Error Code'), findsOneWidget);
      expect(find.text('Statement'), findsOneWidget);
      expect(find.text('Raw Error'), findsOneWidget);
    });

    testWidgets('initial focus on primary action; Enter triggers retry',
        (tester) async {
      var retryCount = 0;
      final retry = Completer<bool>();
      await openDialog(tester, failure: failureFixture(), onRetry: () {
        retryCount++;
        return retry.future;
      });

      expect(primaryFocusIsInside(tester, find.byType(FilledButton)), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(retryCount, 1);

      retry.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(ConnectFailureDialog), findsNothing);
    });

    testWidgets('Esc closes the dialog', (tester) async {
      await openDialog(tester, failure: failureFixture(), onRetry: () async => true);
      expect(find.byType(ConnectFailureDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ConnectFailureDialog), findsNothing);
    });

    testWidgets('retry failure updates content in place; retry success closes',
        (tester) async {
      var result = false;
      final updated = ConnectionFailure(
        kind: ConnectionFailureKind.corrupt,
        errorCode: '11',
        rawMessage: 'file is not a database',
        occurredAt: DateTime(2026, 1, 2),
      );
      await openDialog(
        tester,
        failure: failureFixture(),
        onRetry: () async => result,
        latestFailure: () => updated,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // 单实例原地更新：恒为 1 且内容刷新为新 failure。
      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      expect(
        selectableContaining('The database file appears to be corrupted'),
        findsOneWidget,
      );
      expect(
        selectableContaining('The file is locked by another program'),
        findsNothing,
      );

      result = true;
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectFailureDialog), findsNothing);
    });

    testWidgets(
        'retry failure with latestFailure returning null keeps old content',
        (tester) async {
      await openDialog(
        tester,
        failure: failureFixture(),
        onRetry: () async => false,
        latestFailure: () => null,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      expect(
        selectableContaining('The file is locked by another program'),
        findsOneWidget,
      );
    });

    testWidgets('pending retry disables primary action with loading indicator',
        (tester) async {
      final retry = Completer<bool>();
      await openDialog(tester, failure: failureFixture(), onRetry: () => retry.future);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      retry.complete(false);
      await tester.pumpAndSettle();
      // 失败且无 latestFailure → 沿用旧 failure，dialog 保持打开。
      expect(find.byType(ConnectFailureDialog), findsOneWidget);
    });

    testWidgets(
        'onRetry throwing shows unknown failure in place without closing',
        (tester) async {
      await openDialog(tester, failure: failureFixture(), onRetry: () async {
        throw Exception('boom: driver exploded');
      });

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectFailureDialog), findsOneWidget);
      expect(
        selectableContaining('Could not connect to the database'),
        findsOneWidget,
      );

      await tester.tap(find.text('Technical Details'));
      await tester.pumpAndSettle();
      expect(selectableContaining('boom: driver exploded'), findsOneWidget);
    });

    testWidgets(
        'fileNotFound with onChooseFile: primary action is choose file, closes on tap',
        (tester) async {
      var chosen = false;
      await openDialog(
        tester,
        failure: failureFixture(kind: ConnectionFailureKind.fileNotFound),
        onRetry: () async => true,
        onChooseFile: () => chosen = true,
      );

      expect(find.text('Choose Another File'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await tester.tap(find.text('Choose Another File'));
      await tester.pumpAndSettle();
      expect(chosen, isTrue);
      expect(find.byType(ConnectFailureDialog), findsNothing);
    });

    testWidgets('fileNotFound without onChooseFile falls back to retry',
        (tester) async {
      var retryCount = 0;
      await openDialog(
        tester,
        failure: failureFixture(kind: ConnectionFailureKind.fileNotFound),
        onRetry: () async {
          retryCount++;
          return true;
        },
      );

      expect(find.text('Choose Another File'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retryCount, 1);
      expect(find.byType(ConnectFailureDialog), findsNothing);
    });

    testWidgets(
        'copy details payload contains plain message, error code, statement, raw error',
        (tester) async {
      await openDialog(tester, failure: failureFixture(), onRetry: () async => true);

      await tester.tap(find.text('Copy Details'));
      await tester.pump();

      final payload = clipboardPayload ?? '';
      expect(payload, contains('The file is locked by another program'));
      expect(payload, contains('Error Code: 5'));
      expect(payload, contains('Statement: PRAGMA journal_mode = DELETE'));
      expect(payload, contains('File: C:/data/chinook.db'));
      expect(payload, contains('Raw Error: database is locked (5)'));
    });

    testWidgets('display and copy payload redact secrets', (tester) async {
      await openDialog(
        tester,
        failure: failureFixture(rawMessage: 'connect failed: pwd=secret123'),
        onRetry: () async => true,
      );

      await tester.tap(find.text('Copy Details'));
      await tester.pump();
      final payload = clipboardPayload ?? '';
      expect(payload.contains('secret123'), isFalse);
      expect(payload, contains('***'));

      // 展示路径同样脱敏。
      await tester.tap(find.text('Technical Details'));
      await tester.pumpAndSettle();
      expect(selectableContaining('secret123'), findsNothing);
    });

    testWidgets(
        'redacted diagnostics report uses frozen environment label literal (D-2)',
        (tester) async {
      // B-06-R 冻结：「环境标签: production | testing | development」（跨
      // 语言稳定可 grep）。调用方现行为传本地化显示名（home_screen 等
      // `_connectFailureEnvironmentLabel` 产物）——报告行须解析回冻结
      // 字面值，不得随 UI 语言变。
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await openDialog(
        tester,
        failure: failureFixture(),
        onRetry: () async => true,
        environmentLabel: l10n.environmentProduction,
      );
      await tester.tap(find.text('Copy redacted diagnostics'));
      await tester.pump();
      final payload = clipboardPayload ?? '';
      expect(payload, contains('- 环境标签: production'));
      expect(
        payload.contains(l10n.environmentProduction),
        isFalse,
        reason: '本地化显示名不得进报告（随 UI 语言变为冻结违约）',
      );

      // 枚举 name 直传同样落冻结字面值（参数语义=枚举值或本地化名皆可）。
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await openDialog(
        tester,
        failure: failureFixture(),
        onRetry: () async => true,
        environmentLabel: 'testing',
      );
      await tester.tap(find.text('Copy redacted diagnostics'));
      await tester.pump();
      expect(clipboardPayload ?? '', contains('- 环境标签: testing'));
    });

    testWidgets('authFailed: gateway-specific plain message, not fallback',
        (tester) async {
      // T12c：网关稳定码 AUTH_DENIED 分型 → 专属文案（非 unknown 兜底）。
      await openDialog(
        tester,
        failure: failureFixture(
          kind: ConnectionFailureKind.authFailed,
          errorCode: 'AUTH_DENIED',
          offendingStatement: null,
          target: '192.168.3.128:3306',
          rawMessage: 'Access denied for user',
        ),
        onRetry: () async => true,
      );

      expect(
        selectableContaining('Authentication failed'),
        findsOneWidget,
      );
      expect(
        selectableContaining('Could not connect to the database'),
        findsNothing,
      );
    });

    testWidgets('unreachable: gateway-specific plain message, not fallback',
        (tester) async {
      // T12c：网关稳定码 UNREACHABLE 分型 → 专属文案（非 unknown 兜底）。
      await openDialog(
        tester,
        failure: failureFixture(
          kind: ConnectionFailureKind.unreachable,
          errorCode: 'UNREACHABLE',
          offendingStatement: null,
          target: '192.168.3.128:6379',
          rawMessage: 'connection refused',
        ),
        onRetry: () async => true,
      );

      expect(
        selectableContaining('Could not reach the server'),
        findsOneWidget,
      );
      expect(
        selectableContaining('Could not connect to the database'),
        findsNothing,
      );
    });
  });

  // ── UI35-411~416（批4 T8 红测）：主按钮映射 + 建议组 + Raw 折叠限高 ──
  //
  // 断言依据：任务书「目标契约」逐字冻结（B-05 / P5-1.2 / P5-1.3 / UI35-416），
  // 文本 = lib/l10n/app_en.arb 已就绪键值（T0d 交付）。红态来源：
  // networkTimeout/sslHandshake 枚举值与对话框新分支尚未实现。
  group('UI35-41x（批4 T8 红测）：主按钮映射与建议组', () {
    // 建议条目可能以 Text 或 SelectableText 渲染（实现自由度），断言器同时
    // 匹配两种组件的 data 精确相等——文本值仍逐字精确，不做 contains 弱断言。
    Finder exactTextAnywhere(String text) => find.byWidgetPredicate(
          (widget) =>
              (widget is Text && widget.data == text) ||
              (widget is SelectableText && widget.data == text),
        );

    testWidgets('UI35-411: authFailed 主按钮 = Re-enter password',
        (tester) async {
      await openDialog(
        tester,
        failure: failureFixture(
          kind: ConnectionFailureKind.authFailed,
          errorCode: 'AUTH_DENIED',
          offendingStatement: null,
          target: '192.168.3.128:3306',
          rawMessage: 'Access denied for user',
        ),
        onRetry: () async => true,
      );

      expect(find.text('Re-enter password'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('UI35-412: 稳定码 TIMEOUT 主按钮 = Check host & proxy',
        (tester) async {
      // 经网关稳定码构造（B-05 映射 + P5-1.3 按钮映射复合断言）：
      // 实现前 kind 落 unknown → 主按钮 Retry，红；实现后转绿。
      final failure = gatewayEnvelopeFailure(
        code: 'TIMEOUT',
        message: 'pool timed out',
        target: '192.168.3.128:5432',
      );
      await openDialog(tester, failure: failure, onRetry: () async => true);

      expect(find.text('Check host & proxy'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('UI35-413: 稳定码 SSL_HANDSHAKE 主按钮 = Switch SSL & retry',
        (tester) async {
      final failure = gatewayEnvelopeFailure(
        code: 'SSL_HANDSHAKE',
        message: 'invalid peer certificate',
        target: '192.168.3.128:5432',
      );
      await openDialog(tester, failure: failure, onRetry: () async => true);

      expect(find.text('Switch SSL & retry'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('UI35-414: unreachable 主按钮保持既有 Retry（回归）',
        (tester) async {
      await openDialog(
        tester,
        failure: failureFixture(
          kind: ConnectionFailureKind.unreachable,
          errorCode: 'UNREACHABLE',
          offendingStatement: null,
          target: '192.168.3.128:6379',
          rawMessage: 'connection refused',
        ),
        onRetry: () async => true,
      );

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
        'UI35-415: networkTimeout 呈现恢复标题 + 专属 3 条建议 + 通用尾 3 条',
        (tester) async {
      final failure = gatewayEnvelopeFailure(
        code: 'TIMEOUT',
        message: 'pool timed out',
        target: '192.168.3.128:5432',
      );
      await openDialog(tester, failure: failure, onRetry: () async => true);

      expect(find.text('Try this first'), findsOneWidget);
      expect(
        exactTextAnywhere('Check the host name, port and DNS resolution.'),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere('Check proxy, VPN, firewall and security group rules.'),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere(
          'Confirm the server accepts remote connections (bind-address / pg_hba).',
        ),
        findsOneWidget,
      );
      // 通用尾建议（每 kind 面板固定 3 条）。
      expect(
        exactTextAnywhere(
          'Run the test again to confirm the failure is reproducible.',
        ),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere(
          'Expand Raw Driver Message to read the driver-level error.',
        ),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere(
          'Copy the redacted diagnostics for your DBA or provider.',
        ),
        findsOneWidget,
      );
      // 每 kind 恰 3 条：他组专属建议不出现。
      expect(
        exactTextAnywhere('Switch SSL mode (require / prefer / disable) and retry.'),
        findsNothing,
      );
    });

    testWidgets('UI35-415: authFailed 建议组 3 条', (tester) async {
      await openDialog(
        tester,
        failure: failureFixture(
          kind: ConnectionFailureKind.authFailed,
          errorCode: 'AUTH_DENIED',
          offendingStatement: null,
          target: '192.168.3.128:3306',
          rawMessage: 'Access denied for user',
        ),
        onRetry: () async => true,
      );

      expect(find.text('Try this first'), findsOneWidget);
      expect(
        exactTextAnywhere(
          'Re-check the username and password (case-sensitive; no trailing spaces).',
        ),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere(
          'Confirm this account may log in from the current host (GRANT / host rule).',
        ),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere(
          'If an SSH tunnel is used, verify the jump host and port forwarding.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('UI35-415: sslHandshake 建议组 3 条', (tester) async {
      final failure = gatewayEnvelopeFailure(
        code: 'SSL_HANDSHAKE',
        message: 'invalid peer certificate',
        target: '192.168.3.128:5432',
      );
      await openDialog(tester, failure: failure, onRetry: () async => true);

      expect(find.text('Try this first'), findsOneWidget);
      expect(
        exactTextAnywhere(
          'Switch SSL mode (require / prefer / disable) and retry.',
        ),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere(
          'Verify the CA certificate and host-name check (verify-full → verify-ca).',
        ),
        findsOneWidget,
      );
      expect(
        exactTextAnywhere(
          'Confirm the server TLS version and certificate expiry.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('UI35-416: Raw 默认折叠；展开后承载区限高恰 160', (tester) async {
      // UI35-416 探针记录（2026-10-27，临时探针测试实测）：现实现 Raw 经
      // 'Technical Details' 折叠头 + ActionableError 详情区承载——默认折叠
      // 成立（回归护栏），展开后 Raw 文本本征高 2224px、祖先唯一限高容器
      // 为 ActionableError._buildDetails 的 maxHeight=120。红点 = 承载区
      // 限高 120 ≠ 目标契约 160。
      final longRaw = 'raw-line ${'x' * 4000}';
      await openDialog(
        tester,
        failure: failureFixture(
          errorCode: '5',
          offendingStatement: null,
          target: null,
          rawMessage: longRaw,
        ),
        onRetry: () async => true,
      );

      // Raw 驱动消息默认折叠：全文不可见。
      expect(selectableContaining(longRaw), findsNothing);

      // 展开触发沿用现实现 'Technical Details' 折叠头（既有用例回归护栏
      // 保证其存续；若实现批为 Raw 引入独立折叠节头，本触发行需同步调整，
      // 已在汇报标注）。
      await tester.tap(find.text('Technical Details'));
      await tester.pumpAndSettle();
      expect(selectableContaining(longRaw), findsOneWidget);

      // 展开后限高 160（ConstrainedBox/maxHeight 形态，任务书目标契约）。
      final cappedAncestor = find.ancestor(
        of: selectableContaining(longRaw),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox && widget.constraints.maxHeight == 160,
        ),
      );
      expect(cappedAncestor, findsWidgets);
    });
  });
}
