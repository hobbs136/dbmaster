// DBT-T8 · PgLocksDialog widget 测试（W-10 锁分析面板，只读）——
// mock loader 注入（ProcessManagerDialog 测试缝先例）：数据渲染（含
// granted=false 等待行）/ 空态 / 失败态 / 手动刷新重取。只读面无 terminate
// 动作（无按钮即无写路径，任务书约束）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/dialogs/pg_locks_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget _wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
      );

  List<PgLockEntry> _sampleLocks() => const [
        PgLockEntry(
          locktype: 'relation',
          pid: 101,
          mode: 'RowShareLock',
          granted: true,
          waitingQuery: 'SELECT pg_sleep(15) FROM t WHERE id = 1 FOR UPDATE',
          durationSeconds: 3,
        ),
        PgLockEntry(
          locktype: 'transactionid',
          pid: 202,
          mode: 'ExclusiveLock',
          granted: false,
          waitingQuery: 'UPDATE t SET v = v + 1 WHERE id = 1',
          durationSeconds: 2,
        ),
      ];

  testWidgets('渲染聚合行：列头 + granted 双态 + 等待查询 + 时长', (tester) async {
    await tester.pumpWidget(_wrap(PgLocksDialog(
      connectionId: 'c1',
      loader: (_) async => _sampleLocks(),
    )));
    await tester.pumpAndSettle();

    // 列头（l10n：pgLocksCol*）。
    expect(find.text('Lock Type'), findsOneWidget);
    expect(find.text('PID'), findsOneWidget);
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Granted'), findsOneWidget);
    expect(find.text('Waiting Query'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);

    // 行数据：持锁行 + 等待行（granted 双态）。
    expect(find.text('relation'), findsOneWidget);
    expect(find.text('transactionid'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);
    expect(find.text('202'), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
    expect(find.text('false'), findsOneWidget);
    expect(find.textContaining('UPDATE t SET v = v + 1'), findsOneWidget);
    expect(find.text('3s'), findsOneWidget);
    expect(find.text('2s'), findsOneWidget);
  });

  testWidgets('空态：无锁显示 pgLocksEmpty', (tester) async {
    await tester.pumpWidget(_wrap(PgLocksDialog(
      connectionId: 'c1',
      loader: (_) async => const <PgLockEntry>[],
    )));
    await tester.pumpAndSettle();

    expect(find.text('No locks'), findsOneWidget);
  });

  testWidgets('失败态：loader 抛错展示错误原文', (tester) async {
    await tester.pumpWidget(_wrap(PgLocksDialog(
      connectionId: 'c1',
      loader: (_) async => throw StateError('connection lost'),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('connection lost'), findsOneWidget);
  });

  testWidgets('手动刷新重新调用 loader（计数断言）', (tester) async {
    var loadCount = 0;
    await tester.pumpWidget(_wrap(PgLocksDialog(
      connectionId: 'c1',
      loader: (_) async {
        loadCount++;
        return _sampleLocks();
      },
    )));
    await tester.pumpAndSettle();
    expect(loadCount, 1, reason: 'initState 首载');

    await tester.tap(find.byIcon(LucideIcons.refreshCw));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(loadCount, 2, reason: '手动刷新重取');
    // 刷新后行数据仍在。
    expect(find.text('transactionid'), findsOneWidget);
  });

  test("PgLockEntry.fromRow 归一化（网关 bool/'t'/数值字符串形态）", () {
    final entry = PgLockEntry.fromRow(const {
      'locktype': 'transactionid',
      'pid': 42,
      'mode': 'ShareLock',
      'granted': 't',
      'waiting_query': 'SELECT 1',
      'duration_seconds': '7',
    });
    expect(entry.granted, isTrue, reason: "'t' 字符串形态归一为 true");
    expect(entry.pid, 42);
    expect(entry.durationSeconds, 7);
    final nullDuration = PgLockEntry.fromRow(const {
      'locktype': 'virtualxid',
      'pid': null,
      'mode': 'ExclusiveLock',
      'granted': 'f',
      'waiting_query': '',
      'duration_seconds': null,
    });
    expect(nullDuration.granted, isFalse);
    expect(nullDuration.pid, isNull);
    expect(nullDuration.durationSeconds, isNull);
  });
}
