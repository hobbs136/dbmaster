import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/molecules/actionable_error.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认未处理 Clipboard 平台通道，setData 会永久挂起。
  // 这里用内存映射 mock Clipboard.setData/GetData。
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? clipText;

  setUp(() {
    clipText = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          clipText = args?['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipText == null ? null : <String, dynamic>{'text': clipText};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('renders message as SelectableText + Copy button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ActionableError(message: 'boom error')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.byIcon(LucideIcons.copy), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('tap Copy writes redacted payload to clipboard', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ActionableError(
          message: 'Password=secret123 failed',
          sql: 'SELECT 1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.copy));
    await tester
        .pump(); // 让 Clipboard.setData + setState 完成（不 pumpAndSettle，避免等 2s 复位定时器）
    final data = await Clipboard.getData('text/plain');
    expect(data?.text, isNotNull);
    expect(data!.text, contains('***')); // password 已脱敏
    expect(data.text, contains('SELECT 1'));
  });

  testWidgets('Retry button appears only when onRetry provided', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ActionableError(message: 'x')));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.refreshCw), findsNothing);

    await tester.pumpWidget(
      _wrap(ActionableError(message: 'x', onRetry: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
  });

  testWidgets(
    'Analyze button appears only when onAnalyze provided and fires on tap',
    (tester) async {
      await tester.pumpWidget(_wrap(const ActionableError(message: 'x')));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.sparkles), findsNothing);

      var tapped = 0;
      await tester.pumpWidget(
        _wrap(ActionableError(message: 'x', onAnalyze: () => tapped++)),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.sparkles));
      expect(tapped, 1);
    },
  );

  testWidgets('details null or empty renders no detail region', (tester) async {
    await tester.pumpWidget(_wrap(const ActionableError(message: 'x')));
    await tester.pumpAndSettle();
    expect(find.text('Host'), findsNothing);

    await tester.pumpWidget(
      _wrap(const ActionableError(message: 'x', details: [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Host'), findsNothing);
  });

  testWidgets('details render label+value rows and copy redacted payload', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ActionableError(
          message: 'Connection refused',
          details: [
            ErrorDetail(label: 'Host', value: '192.168.3.128'),
            ErrorDetail(label: 'Password', value: 'Password=hunter2'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('192.168.3.128'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // details 值同样过 redactSecrets：明文不出现在 UI。
    expect(find.textContaining('hunter2'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.copy));
    await tester.pump(); // 不 pumpAndSettle，避免等 2s 复位定时器
    final data = await Clipboard.getData('text/plain');
    expect(data?.text, isNotNull);
    expect(data!.text, contains('Host: 192.168.3.128'));
    expect(data.text, contains('Password: ***'));
    expect(data.text, isNot(contains('hunter2')));
  });

  testWidgets('style=body vs compact differ in message fontSize (12 vs 11)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ActionableError(
          message: 'boom',
          style: ActionableErrorStyle.body,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bodyWidget = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(bodyWidget.data, 'boom');
    expect(bodyWidget.style?.fontSize, 12);

    await tester.pumpWidget(
      _wrap(
        const ActionableError(
          message: 'boom',
          style: ActionableErrorStyle.compact,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final compactWidget = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(compactWidget.data, 'boom');
    expect(compactWidget.style?.fontSize, 11);
  });

  testWidgets('custom actions render after the Retry button', (tester) async {
    const actionKey = Key('custom-action');
    await tester.pumpWidget(
      _wrap(
        ActionableError(
          message: 'x',
          onRetry: () {},
          actions: [
            TextButton(
              key: actionKey,
              onPressed: () {},
              child: const Text('Diagnose'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Diagnose'), findsOneWidget);
    final retryRect = tester.getRect(find.byIcon(LucideIcons.refreshCw));
    final actionRect = tester.getRect(find.byKey(actionKey));
    expect(actionRect.left, greaterThan(retryRect.right));
  });

  testWidgets('detail with empty value renders empty string row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ActionableError(
          message: 'x',
          details: [ErrorDetail(label: 'Empty', value: '')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Empty'), findsOneWidget);
  });

  testWidgets('very long detail value stays inside scrollable container', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ActionableError(
          message: 'x',
          details: [ErrorDetail(label: 'Detail', value: 'v' * 2000)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
