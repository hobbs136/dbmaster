import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/error_event.dart';
import 'package:dbmaster/organisms/execution_center/execution_center_panel.dart';
import 'package:dbmaster/providers/execution_center_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';

Widget _wrap(
  Widget child, {
  required ExecutionCenterProvider ec,
  required TaskProvider tp,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MultiProvider(
        providers: [
          ChangeNotifierProvider<ExecutionCenterProvider>.value(value: ec),
          ChangeNotifierProvider<TaskProvider>.value(value: tp),
        ],
        child: SizedBox(width: 600, height: 400, child: child),
      ),
    ),
  );
}

ErrorEvent _ev(String id, [String msg = 'err']) => ErrorEvent(
      id: id,
      timestamp: DateTime.now(),
      severity: ErrorSeverity.error,
      message: '$msg $id',
    );

void main() {
  testWidgets('renders header + Tasks tab by default', (tester) async {
    final ec = ExecutionCenterProvider();
    final tp = TaskProvider();
    await tester.pumpWidget(_wrap(const ExecutionCenterPanel(), ec: ec, tp: tp));
    await tester.pumpAndSettle();
    expect(find.text('Execution Center'), findsOneWidget);
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('Errors'), findsOneWidget);
  });

  testWidgets('switching to Errors tab lists captured errors', (tester) async {
    final ec = ExecutionCenterProvider();
    final tp = TaskProvider();
    ec.addError(_ev('e1', 'boom'));
    await tester.pumpWidget(_wrap(const ExecutionCenterPanel(), ec: ec, tp: tp));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Errors'));
    await tester.pumpAndSettle();
    expect(find.textContaining('boom'), findsWidgets);
  });

  testWidgets('dismiss removes the error row', (tester) async {
    final ec = ExecutionCenterProvider();
    final tp = TaskProvider();
    ec.addError(_ev('e1', 'boom'));
    await tester.pumpWidget(_wrap(const ExecutionCenterPanel(), ec: ec, tp: tp));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Errors'));
    await tester.pumpAndSettle();
    expect(find.textContaining('boom'), findsWidgets);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('boom'), findsNothing);
  });
}
