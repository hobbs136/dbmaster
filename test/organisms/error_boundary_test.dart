import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/connection/error_boundary.dart';

Widget _harness({required Widget child}) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认未处理 Clipboard 平台通道，setData 会挂起；这里 mock。
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

  testWidgets('showErrorSnackBar Copy action writes redacted message to clipboard',
      (tester) async {
    await tester.pumpWidget(_harness(
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => AppErrorHandler.showErrorSnackBar(
            ctx,
            'connect failed: Password=secret123',
          ),
          child: const Text('trigger'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget); // SnackBar Copy action
    await tester.tap(find.text('Copy'));
    await tester.pump();
    final data = await Clipboard.getData('text/plain');
    expect(data?.text, isNotNull);
    expect(data!.text, contains('***'));
    expect(data.text, isNot(contains('secret123'))); // 原始密钥不得进剪贴板
  });
}
