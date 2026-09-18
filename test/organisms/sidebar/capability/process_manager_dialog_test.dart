// C15 · 进程管理对话框单测：loader 注入渲染 / 空态 / kill 确认与反馈 /
// loader 异常态。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/sidebar/capability/process_manager_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<List<ProcessListEntry>> Function(String) loader,
    required Future<bool> Function(String, int) onKill,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: ProcessManagerDialog(
            connectionId: 'c1',
            loader: loader,
            onKill: onKill,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染 loader 返回的归一化行（慢进程 >5s 高亮路径不崩溃）', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      loader: (_) async => const [
        ProcessListEntry(
          id: 7,
          user: 'root',
          command: 'Query',
          timeSeconds: 42,
          info: 'SELECT SLEEP(60)',
        ),
        ProcessListEntry(id: 8, user: 'app', command: 'Sleep', timeSeconds: 1),
      ],
      onKill: (_, _) async => true,
    );

    expect(find.textContaining('[7] root'), findsOneWidget);
    expect(find.textContaining('[8] app'), findsOneWidget);
    // 每行一个 Kill 按钮
    expect(find.text('Kill Query'), findsNWidgets(2));
  });

  testWidgets('空列表渲染空态文案', (tester) async {
    await pumpDialog(
      tester,
      loader: (_) async => const [],
      onKill: (_, _) async => true,
    );

    expect(find.text('No active processes'), findsOneWidget);
  });

  testWidgets('loader 抛错渲染错误态（不静默空列表）', (tester) async {
    await pumpDialog(
      tester,
      loader: (_) async => throw Exception('boom'),
      onKill: (_, _) async => true,
    );

    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('Kill：确认后调 onKill 并刷新（行消失）', (tester) async {
    var killed = <int>[];
    var round = 0;
    await pumpDialog(
      tester,
      loader: (_) async => round++ == 0
          ? const [
              ProcessListEntry(id: 9, user: 'u', command: 'Query',
                  timeSeconds: 2),
            ]
          : const [],
      onKill: (cid, pid) async {
        killed.add(pid);
        return true;
      },
    );

    await tester.tap(find.text('Kill Query'));
    await tester.pumpAndSettle();
    // 确认对话框
    expect(find.text('Kill Query'), findsNWidgets(2)); // 行按钮 + 确认按钮
    await tester.tap(find.widgetWithText(TextButton, 'Kill Query').last);
    await tester.pumpAndSettle();

    expect(killed, [9]);
    // kill 成功后刷新 → 空态
    expect(find.text('No active processes'), findsOneWidget);
  });
}
