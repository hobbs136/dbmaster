// T10（DBT）· MongoDB currentOp/killOp dialog widget 测试：
// 列表渲染五列 / opid 双形态映射（数值保数值、分片串保串）/ 空态 / 失败态 /
// kill 确认门文案（opid 明示）/ **取消 = 零执行零审计**（计数断言）/
// 确认 → 执行 + 审计成功落账 + 复查刷新（目标行消失）/ 执行器失败 →
// 审计失败落账 + 失败文案 / 审计写失败不阻塞 UI / secs 降序排序。
//
// 真库全链路（$function 长操作 → currentOp 出现 → killOp 实杀 → 行消失）
// 在 integration_test/mongodb_currentop_killop_e2e_test.dart（连 WSL）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/dialogs/mongo_process_dialog.dart';

const MongoOpEntry _numericOp = MongoOpEntry(
  opId: 123,
  namespace: 'dbmaster_test.orders',
  operation: 'command',
  secsRunning: 8,
  client: '127.0.0.1:51000',
  active: true,
  commandJson: '{"find":"orders","filter":{}}',
  commandSummary: 'find: orders',
);

const MongoOpEntry _shardedOp = MongoOpEntry(
  opId: 'rs0:456',
  namespace: 'dbmaster_test.logs',
  operation: 'getmore',
  secsRunning: 2,
  client: '127.0.0.1:51001',
  active: true,
);

void main() {
  setUp(() {
    // 默认审计器经 AuditLogService 落账（initialize → SharedPreferences）；
    // 平台通道不 mock 会挂起（AGENTS §5.4 陷阱）。
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required MongoCurrentOpLoader loadOps,
    required MongoKillOpExecutor killOp,
    MongoKillOpAuditor? audit,
  }) async {
    // 直接构造 widget（audit seam 注入；生产入口 MongoProcessDialog.show 由
    // 插件调用，e2e 连真库覆盖）。Scaffold 承载结果 snackbar（生产 dialog
    // 恒开在 home Scaffold 之上）。
    final home = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => MongoProcessDialog(
                connectionId: 'mg_conn',
                loadOps: loadOps,
                killOp: killOp,
                audit: audit,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('列表渲染：标题 + 五列头 + 数据行（secs 降序 = 长操作在前）', (tester) async {
    await pumpDialog(
      tester,
      loadOps: (_) async => [_numericOp, _shardedOp],
      killOp: (_, _) async => true,
    );

    expect(find.text('Current Operations'), findsOneWidget);
    expect(find.text('Op ID'), findsOneWidget);
    expect(find.text('Namespace'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Seconds'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
    // 行数据（opid 双形态均以显示串呈现）。
    expect(find.text('123'), findsOneWidget);
    expect(find.text('rs0:456'), findsOneWidget);
    expect(find.text('dbmaster_test.orders'), findsOneWidget);
    expect(find.text('command find: orders'), findsOneWidget);
    expect(find.text('8s'), findsOneWidget);
    // Kill 动作列逐行一枚（不做批量全杀）。
    expect(find.widgetWithText(TextButton, 'Kill Query'), findsNWidgets(2));
  });

  testWidgets('空态：mongoCurrentOpEmpty 文案', (tester) async {
    await pumpDialog(
      tester,
      loadOps: (_) async => [],
      killOp: (_, _) async => true,
    );

    expect(find.text('Current Operations'), findsOneWidget);
    expect(find.text('No active operations'), findsOneWidget);
  });

  testWidgets('失败态：loader 抛错 → 错误态展示不崩溃', (tester) async {
    await pumpDialog(
      tester,
      loadOps: (_) async => throw StateError('gateway unreachable'),
      killOp: (_, _) async => true,
    );

    expect(find.text('Current Operations'), findsOneWidget);
    expect(find.textContaining('gateway unreachable'), findsOneWidget);
    expect(find.text('No active operations'), findsNothing);
  });

  testWidgets('kill 确认门：opid 明示 + 行上下文；Cancel = 零执行零审计', (tester) async {
    final kills = <Object>[];
    final audits = <MongoKillOpAuditRecord>[];
    await pumpDialog(
      tester,
      loadOps: (_) async => [_numericOp],
      killOp: (cid, opId) async {
        kills.add(opId);
        return true;
      },
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Kill Query'));
    await tester.pumpAndSettle();

    // 确认门文案：opid 明示 + 目标行上下文（ns · op · client）。
    expect(find.text('Kill operation 123?'), findsOneWidget);
    expect(
      find.textContaining('dbmaster_test.orders'),
      findsWidgets,
    );
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(kills, isEmpty, reason: '取消确认门后不得有任何 killOp 执行');
    expect(audits, isEmpty, reason: '取消路径不落审计');
    expect(find.textContaining('killed'), findsNothing);
  });

  testWidgets('确认 kill 成功：opid 原生类型直传 + 审计成功落账 + 复查刷新行消失', (tester) async {
    final entries = <MongoOpEntry>[_numericOp];
    final kills = <Object>[];
    final audits = <MongoKillOpAuditRecord>[];
    var loadCount = 0;
    await pumpDialog(
      tester,
      loadOps: (_) async {
        loadCount++;
        return List<MongoOpEntry>.of(entries);
      },
      killOp: (cid, opId) async {
        kills.add(opId);
        entries.removeWhere((e) => e.opId == opId);
        return true;
      },
      audit: (r) async => audits.add(r),
    );
    expect(loadCount, 1, reason: '初始加载一次');

    await tester.tap(find.widgetWithText(TextButton, 'Kill Query'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kill Query').last);
    await tester.pumpAndSettle();

    // wire 原生类型直传（数值 opid 不经字符串往返）。
    expect(kills, hasLength(1));
    expect(kills.single, isA<int>(), reason: 'opid 保 wire 原生类型');
    // 审计：成功 + sql 明示 opid + admin 库 + isWriteQuery 口径（recordQuery）。
    expect(audits, hasLength(1));
    expect(audits.single.success, isTrue);
    expect(audits.single.sql, 'killOp {op: 123}');
    expect(audits.single.databaseName, 'admin');
    expect(audits.single.connectionId, 'mg_conn');
    // 成功 snackbar（fire-and-forget：ok=1 即受理）。
    expect(find.text('Operation 123 killed'), findsOneWidget);
    // 复查刷新：目标行消失（列表重新加载）。
    expect(loadCount, 2, reason: 'kill 后复查刷新一次');
    expect(find.text('dbmaster_test.orders'), findsNothing);
  });

  testWidgets('kill 执行失败：审计失败落账（errorMessage）+ 失败文案', (tester) async {
    final audits = <MongoKillOpAuditRecord>[];
    await pumpDialog(
      tester,
      loadOps: (_) async => [_shardedOp],
      killOp: (_, _) async => throw Exception('Unauthorized'),
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Kill Query'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kill Query').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to kill operation rs0:456'),
      findsOneWidget,
    );
    expect(audits, hasLength(1));
    expect(audits.single.success, isFalse);
    expect(audits.single.errorMessage, contains('Unauthorized'));
    expect(audits.single.sql, 'killOp {op: rs0:456}');
  });

  testWidgets('审计写失败不阻塞 UI：结果 snackbar 仍出、列表照常刷新', (tester) async {
    final kills = <Object>[];
    await pumpDialog(
      tester,
      loadOps: (_) async => [_numericOp],
      killOp: (cid, opId) async {
        kills.add(opId);
        return true;
      },
      audit: (_) async => throw Exception('audit storage broken'),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Kill Query'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kill Query').last);
    await tester.pumpAndSettle();

    expect(kills, hasLength(1));
    expect(find.text('Operation 123 killed'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '审计失败不得崩溃');
  });

  group('MongoOpEntry 映射（currentOp inprog → 条目）', () {
    test('数值 opid 保数值、分片串 opid 保字符串（wire 原生类型不解析）', () {
      final numeric = MongoOpEntry.fromOpDoc({
        'opid': 321,
        'ns': 'a.b',
        'op': 'command',
        'secs_running': 4,
        'client': '127.0.0.1:1',
        'active': true,
      });
      expect(numeric.opId, isA<int>());
      expect(numeric.opId, 321);

      final sharded = MongoOpEntry.fromOpDoc({
        'opid': 'shard01:99',
        'ns': 'a.c',
        'op': 'getmore',
        'client': '127.0.0.1:2',
      });
      expect(sharded.opId, isA<String>());
      expect(sharded.opId, 'shard01:99');
      // 缺省容错：secs_running 归零、op 归 '-'、active 归 false。
      expect(sharded.secsRunning, 0);
      expect(sharded.active, isFalse);
      expect(sharded.operation, 'getmore');
    });

    test('listFromCurrentOp：secs_running 降序 + 非 List inprog 容错', () {
      final entries = MongoOpEntry.listFromCurrentOp({
        'inprog': [
          {'opid': 1, 'secs_running': 1},
          {'opid': 2, 'secs_running': 30},
          {'opid': 3}, // 缺 secs_running → 0
        ],
      });
      expect(entries.map((e) => e.opId).toList(), [2, 1, 3]);

      expect(MongoOpEntry.listFromCurrentOp({'ok': 1}), isEmpty);
    });

    test('command 摘要构造期派生（标量值内联，复杂值仅键名）', () {
      final entry = MongoOpEntry.fromOpDoc({
        'opid': 9,
        'command': {
          'find': 'orders',
          'filter': {'status': 1},
        },
      });
      expect(entry.commandSummary, 'find: orders');
      expect(entry.commandJson, contains('"filter"'));
    });
  });
}
