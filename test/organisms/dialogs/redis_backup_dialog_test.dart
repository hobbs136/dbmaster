// T20（W-17）· Redis 备份与持久化 dialog widget 测试：
// 状态区渲染 / 空态 / 失败态 / 刷新 / 确认门文案（明示目标实例）/
// 取消 = 零执行（触发计数断言）/ 审计两态（mock 接缝）/ 成功后状态区刷新 /
// readonly = BGSAVE 入口禁用 + CONFIG 子区隐藏 / BGSAVE 进行中 = 触发禁用。
//
// 真库全链路（INFO persistence 真数据、BGSAVE 真触发 LASTSAVE 前移、
// 取消路径状态不变）在 integration_test/redis_backup_e2e_test.dart。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/atoms/app_loading.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/dialogs/redis_backup_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';

/// 可写连接缺省种子（readonly 用例另建）。
DbServer _seedServer({bool readOnly = false}) => DbServer(
      id: 'rd_conn',
      name: 'RD-Local',
      type: DatabaseType.redis,
      host: '127.0.0.1',
      port: 6379,
      readOnly: readOnly,
    );

Map<String, String> _sampleInfo({String changes = '42', bool inProgress = false}) =>
    {
      'rdb_last_save_time': '1760000000',
      'rdb_last_bgsave_status': 'ok',
      'rdb_last_bgsave_time_sec': '3',
      'rdb_changes_since_last_save': changes,
      'rdb_bgsave_in_progress': inProgress ? '1' : '0',
      'lastsave': '1760000000',
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required AppProvider provider,
    RedisPersistenceLoader? loadInfo,
    RedisConfigLoader? loadConfig,
    RedisBgsaveTrigger? trigger,
    RedisBackupAuditor? audit,
    String connectionId = 'rd_conn',
  }) async {
    final home = Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => RedisBackupDialog(
            provider: provider,
            connectionId: connectionId,
            loadInfo: loadInfo,
            loadConfig: loadConfig,
            trigger: trigger,
            audit: audit,
          ),
        ),
        child: const Text('Open'),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          // Scaffold 必备：真实 app 中 dialog 下恒有 Scaffold（成功/失败
          // snackbar 经 ScaffoldMessenger 呈现）。
          home: Scaffold(body: home),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  AppProvider seededProvider({bool readOnly = false}) {
    final provider = AppProvider();
    provider.connection.addSavedServerForTest(_seedServer(readOnly: readOnly));
    return provider;
  }

  testWidgets('状态区渲染：LASTSAVE 格式化 + BGSAVE 状态耗时 + 变更数 + CONFIG 子区', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async => _sampleInfo(),
      loadConfig: (_) async => {
        'save': '3600 1 300 100',
        'dir': '/data',
        'dbfilename': 'dump.rdb',
        'maxmemory': '0', // 非 CONFIG 子区三键 → 不渲染
      },
      audit: (_) async {},
    );

    expect(find.text('Backup & Persistence'), findsOneWidget);
    // 目标实例明示（名称 + host:port，无凭据）。
    expect(find.text('RD-Local (127.0.0.1:6379)'), findsOneWidget);
    // LASTSAVE unix 秒 1760000000 → 2025-10-09（断言用日期前缀，规避时区）。
    expect(find.textContaining('Last save: 2025-10-09'), findsOneWidget);
    expect(find.text('Last BGSAVE: ok (3s)'), findsOneWidget);
    expect(find.text('Changes since last save: 42'), findsOneWidget);
    // CONFIG 子区（可选增强）：标题 + 白名单键；非三键不渲染。
    expect(find.text('Save Policy (CONFIG)'), findsOneWidget);
    expect(find.textContaining('dump.rdb'), findsOneWidget);
    expect(find.textContaining('maxmemory'), findsNothing);
  });

  testWidgets('空态：INFO/LASTSAVE 锚定空 Map → No data', (tester) async {
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async => {},
      audit: (_) async {},
    );
    expect(find.text('No data'), findsOneWidget);
    expect(find.textContaining('Last save:'), findsNothing);
  });

  testWidgets('失败态：加载抛错 → 错误原文（不吞错）', (tester) async {
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async => throw Exception('connection reset'),
      audit: (_) async {},
    );
    expect(find.textContaining('connection reset'), findsOneWidget);
  });

  testWidgets('刷新：手动刷新重新取数（loader 计数 + 新数据渲染；零轮询）', (tester) async {
    var loadCount = 0;
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async {
        loadCount++;
        return _sampleInfo(changes: loadCount == 1 ? '42' : '0');
      },
      audit: (_) async {},
    );
    expect(loadCount, 1, reason: '首帧取数一次（零 Timer/零轮询）');
    expect(find.text('Changes since last save: 42'), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(loadCount, 2, reason: '手动刷新再取一次');
    expect(find.text('Changes since last save: 0'), findsOneWidget);
  });

  testWidgets('确认门文案：fork 影响说明 + 明示目标实例 + 当前变更数', (tester) async {
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async => _sampleInfo(),
      audit: (_) async {},
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Trigger BGSAVE'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'BGSAVE forks the server process and may temporarily double memory '
        'usage. On production instances, run during off-peak hours. Continue?',
      ),
      findsOneWidget,
    );
    expect(find.text('Backup & Persistence: RD-Local (127.0.0.1:6379)'),
        findsOneWidget);
    expect(find.text('Changes since last save: 42'), findsNWidgets(2));
  });

  testWidgets('取消 = 零执行：触发计数 0、审计 0、无成功反馈', (tester) async {
    var triggerCount = 0;
    final audits = <RedisBackupAuditRecord>[];
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async => _sampleInfo(),
      trigger: (_) async {
        triggerCount++;
        return 'Background saving started';
      },
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Trigger BGSAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(triggerCount, 0, reason: '取消确认门后不得有任何触发');
    expect(audits, isEmpty, reason: '取消路径不落审计');
    expect(find.text('BGSAVE triggered'), findsNothing);
  });

  testWidgets('确认执行成功：触发 1 次 + 审计 success:true + snackbar + 状态区刷新', (
    tester,
  ) async {
    var triggerCount = 0;
    var loadCount = 0;
    final audits = <RedisBackupAuditRecord>[];
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async {
        loadCount++;
        return _sampleInfo(changes: loadCount == 1 ? '42' : '0');
      },
      trigger: (_) async {
        triggerCount++;
        return 'Background saving started';
      },
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Trigger BGSAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoadingButton, 'Trigger BGSAVE'));
    await tester.pumpAndSettle();

    expect(triggerCount, 1);
    expect(loadCount, 2, reason: '成功后状态区自动刷新');
    expect(audits, hasLength(1));
    expect(audits.single.connectionId, 'rd_conn');
    expect(audits.single.sql, 'BGSAVE');
    expect(audits.single.success, isTrue);
    expect(audits.single.errorMessage, isNull);
    expect(find.text('BGSAVE triggered'), findsOneWidget, reason: '成功 snackbar');
    expect(find.text('Changes since last save: 0'), findsOneWidget);
  });

  testWidgets('触发失败：错误原文 + 审计失败落账（success:false）', (tester) async {
    final audits = <RedisBackupAuditRecord>[];
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async => _sampleInfo(),
      trigger: (_) async => throw Exception('Out of memory: fork failed'),
      audit: (r) async => audits.add(r),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Trigger BGSAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LoadingButton, 'Trigger BGSAVE'));
    await tester.pumpAndSettle();

    expect(audits, hasLength(1));
    expect(audits.single.success, isFalse);
    expect(audits.single.errorMessage, contains('Out of memory: fork failed'));
    expect(find.text('Failed to trigger BGSAVE'), findsOneWidget);
  });

  testWidgets('readonly 连接：BGSAVE 入口禁用 + CONFIG 子区隐藏 + 只读提示', (
    tester,
  ) async {
    var configLoads = 0;
    await pumpDialog(
      tester,
      provider: seededProvider(readOnly: true),
      loadInfo: (_) async => _sampleInfo(),
      loadConfig: (_) async {
        configLoads++;
        return {'save': '3600 1'};
      },
      audit: (_) async {},
    );

    // 入口禁用：按钮置灰不可点。
    final triggerButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Trigger BGSAVE'),
    );
    expect(triggerButton.onPressed, isNull, reason: 'readonly 连接触发入口禁用');
    // CONFIG 子区隐藏（readonly 不发起 dangerous 级命令）。
    expect(configLoads, 0, reason: 'readonly 连接不发起 CONFIG GET');
    expect(find.text('Save Policy (CONFIG)'), findsNothing);
    // 只读提示 + 主状态区不受影响（INFO/LASTSAVE safe 级照常渲染）。
    expect(find.textContaining('read-only mode'), findsOneWidget);
    expect(find.textContaining('Last save: 2025-10-09'), findsOneWidget);

    // 点击无效（确认门都不出现）。
    await tester.tap(find.widgetWithText(FilledButton, 'Trigger BGSAVE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('double memory'), findsNothing);
  });

  testWidgets('BGSAVE 进行中：触发禁用 + 进行中提示', (tester) async {
    var triggerCount = 0;
    await pumpDialog(
      tester,
      provider: seededProvider(),
      loadInfo: (_) async => _sampleInfo(inProgress: true),
      trigger: (_) async {
        triggerCount++;
        return 'Background saving started';
      },
      audit: (_) async {},
    );

    final triggerButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Trigger BGSAVE'),
    );
    expect(triggerButton.onPressed, isNull, reason: 'BGSAVE 进行中触发禁用');
    expect(find.text('BGSAVE in progress'), findsWidgets);
    expect(triggerCount, 0);
  });
}
