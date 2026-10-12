// T5（DBT）· SQLite 维护三件 dialog widget 测试：
// 三动作渲染 / 逐动作确认门文案 / 取消 = 零执行（执行计数断言）/
// 成功失败结果行（含耗时、引擎错误原文）/ 审计调用断言（mock 接缝）/
// 审计写失败不阻塞 UI / 只读连接 fail-closed（默认执行器 readonly 守卫）。
//
// 真库全链路（VACUUM→integrity_check、ANALYZE→sqlite_stat1、REINDEX、
// 取消前后库内容一致）在 integration_test/sqlite_maintenance_e2e_test.dart。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/dialogs/sqlite_maintenance_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    SqliteMaintenanceExecutor? execute,
    SqliteMaintenanceAuditor? audit,
    AppProvider? provider,
  }) async {
    // 动作行在确认后读 AppProvider（默认执行器锚定连接）。dialog 路由挂在
    // Navigator 之下 → provider 必须在 MaterialApp 之上（app 真实拓扑）。
    final effectiveProvider = provider ?? AppProvider();
    final home = Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => SqliteMaintenanceDialog(
            connectionId: 'lt_conn',
            databaseName: 'C:/tmp/test.db',
            execute: execute,
            audit: audit,
          ),
        ),
        child: const Text('Open'),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: effectiveProvider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('三动作渲染：标题 + 库路径 + 三个动作按钮', (tester) async {
    await pumpDialog(
      tester,
      execute: (_, _, _) async {},
      audit: (_) async {},
    );

    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('C:/tmp/test.db'), findsOneWidget);
    expect(find.text('VACUUM'), findsOneWidget);
    expect(find.text('ANALYZE'), findsOneWidget);
    expect(find.text('REINDEX'), findsOneWidget);
  });

  testWidgets('逐动作确认门：VACUUM 带参确认文案（Run {action} on this database?）', (tester) async {
    await pumpDialog(
      tester,
      execute: (_, _, _) async {},
      audit: (_) async {},
    );

    await tester.tap(find.text('VACUUM'));
    await tester.pumpAndSettle();

    expect(find.text('Run VACUUM on this database?'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('确认取消 = 零执行：执行计数为 0、无结果行、无审计', (tester) async {
    final calls = <String>[];
    final audits = <SqliteMaintenanceAuditRecord>[];
    await pumpDialog(
      tester,
      execute: (_, _, sql) async => calls.add(sql),
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.text('VACUUM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, isEmpty, reason: '取消确认门后不得有任何执行');
    expect(audits, isEmpty, reason: '取消路径不落审计');
    expect(find.textContaining('VACUUM completed'), findsNothing);
    expect(find.textContaining('VACUUM failed'), findsNothing);
    // 动作按钮回到可用态（可再次发起）
    expect(find.text('VACUUM'), findsOneWidget);
  });

  testWidgets('确认执行成功：结果行（completed + 耗时）+ 审计成功落账', (tester) async {
    final calls = <String>[];
    final audits = <SqliteMaintenanceAuditRecord>[];
    await pumpDialog(
      tester,
      execute: (_, _, sql) async => calls.add(sql),
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.text('REINDEX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(calls, ['REINDEX']);
    expect(find.textContaining('REINDEX completed'), findsOneWidget);
    expect(find.textContaining(' ms'), findsOneWidget, reason: '成功行需展示耗时');
    expect(audits, hasLength(1));
    expect(audits.single.sql, 'REINDEX');
    expect(audits.single.success, isTrue);
    expect(audits.single.errorMessage, isNull);
    expect(audits.single.connectionId, 'lt_conn');
  });

  testWidgets('执行失败：失败结果行展示引擎错误原文 + 审计失败落账', (tester) async {
    final audits = <SqliteMaintenanceAuditRecord>[];
    await pumpDialog(
      tester,
      execute: (_, _, _) async =>
          throw Exception('database is locked (SQLITE_BUSY)'),
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.text('ANALYZE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ANALYZE failed'), findsOneWidget);
    // 引擎错误原文展示（不吞错、不崩溃；失败后按钮恢复 = 重试入口）
    expect(find.textContaining('database is locked'), findsOneWidget);
    expect(audits, hasLength(1));
    expect(audits.single.sql, 'ANALYZE');
    expect(audits.single.success, isFalse);
    expect(audits.single.errorMessage, contains('database is locked'));
    expect(find.text('ANALYZE'), findsOneWidget, reason: '失败后动作按钮恢复可用（重试）');
  });

  testWidgets('执行中展示 Running 状态文案', (tester) async {
    final gate = Completer<void>();
    await pumpDialog(
      tester,
      execute: (_, _, _) => gate.future,
      audit: (_) async {},
    );

    await tester.tap(find.text('VACUUM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump();

    expect(find.textContaining('Running VACUUM'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('VACUUM completed'), findsOneWidget);
  });

  testWidgets('审计写失败不阻塞 UI：结果行仍为成功态', (tester) async {
    await pumpDialog(
      tester,
      execute: (_, _, _) async {},
      audit: (_) async => throw Exception('prefs write failed'),
    );

    await tester.tap(find.text('VACUUM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('VACUUM completed'), findsOneWidget);
    expect(find.textContaining('VACUUM failed'), findsNothing);
  });

  testWidgets('只读连接 fail-closed：默认执行器拦截维护命令（readOnlyModeBlocked）', (tester) async {
    final provider = AppProvider();
    provider.connection.addSavedServerForTest(
      DbServer(
        id: 'lt_conn',
        name: 'LT',
        type: DatabaseType.sqlite,
        host: 'C:/tmp/test.db',
        port: 0,
        readOnly: true,
      ),
    );

    // 不注入 execute（走默认执行器 = provider 既有面 + readonly 守卫）；
    // 审计注入 no-op（默认审计器的 persist 防抖 Timer 会超出用例生命周期，
    // 且本用例验证点是执行器守卫，非审计落账）。
    await pumpDialog(tester, provider: provider, audit: (_) async {});

    await tester.tap(find.text('VACUUM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('VACUUM failed'), findsOneWidget);
    expect(
      find.textContaining('read-only mode'),
      findsOneWidget,
      reason: '只读连接的维护命令需映射到 readOnlyModeBlocked 文案',
    );
  });
}
