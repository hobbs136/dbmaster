// DBT-T8 R4-d（reviewer P3#10）· MySQL 表维护聚合入口运行中关闭收紧——
// 动作执行中 PopScope（canPop:false）拦 Esc/屏障（两路径同走 maybePop）。
// 新建文件（沿 T3 既有 mysql_sidebar_plugin_test 的 dialog 组模式；该文件
// 属 T3 任务族不在本任务清单，PopScope 用例落本新建文件——R4 验收③允许）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/dialogs/mysql_table_maintenance_entry_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('执行中 Esc/屏障不关，完成后 Cancel 可关（PopScope）', (
    tester,
  ) async {
    final executorGate = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MysqlTableMaintenanceEntryDialog(
                  connectionId: 'c1',
                  loadDatabases: (_) async => ['chinook'],
                  loadTables: (_, __) async => ['Artist'],
                  runMaintenance: (_, __, ___, ____) => executorGate.future,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget);

    // 勾表 → Confirm → 逐表确认门 → 门内确认 → runMaintenance 挂起（_running）。
    await tester.tap(find.text('Artist'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget,
        reason: '执行中态（runMaintenance 挂起）');

    // 执行中：Esc 与屏障点击都不关。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget,
        reason: '执行中不可 Esc/屏障关闭（PopScope canPop:false）');

    // 放行 → 结果 dialog 出现（_running 期间旋转指示器不收敛，定长推进）。
    executorGate.complete(const <Map<String, dynamic>>[]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget);
    // 关结果 dialog → 逐表循环走完 → _running 复位（此后可 settle）。
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    // 空闲态 Cancel 正常关闭（canPop 复位）。
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(MysqlTableMaintenanceEntryDialog), findsNothing);
  });
}
