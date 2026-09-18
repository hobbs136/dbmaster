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
}
