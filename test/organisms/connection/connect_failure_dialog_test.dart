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
}
