// DBT-T18 · MySQL 事件设计器 widget 测试：
// 列表渲染/空态/错误态 + 调度器 OFF 提示 / DDL 生成与 SHOW CREATE EVENT
// 反解析（纯函数逐字断言）/ 表单必填校验 / DDL 预览与执行逐字一致 /
// 确认门取消 = 零执行（执行计数）/ DROP typed confirmation / 审计两态 /
// 审计写失败不阻塞 / 只读连接入口禁用。
//
// 真库全链路（CREATE→IS 断言→ALTER→SHOW CREATE 反解析→DROP→消失、取消路径
// 零变化、readonly 服务层拦截）在 integration_test/mysql_events_designer_e2e_test.dart。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:dbmaster/organisms/dialogs/mysql_events_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _sampleShowCreate =
    "CREATE DEFINER=`root`@`%` EVENT `mydb`.`ev_cleanup` ON SCHEDULE "
    "EVERY 15 MINUTE STARTS '2026-10-12 10:00:00' ENDS '2026-12-31 23:59:59' "
    "ON COMPLETION NOT PRESERVE DISABLE COMMENT 'purge logs' "
    "DO DELETE FROM `logs` WHERE `created_at` < NOW() - INTERVAL 7 DAY";

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── 纯函数：DDL 生成（预览与执行同源）────────────────────────────
  group('MysqlEventDdl 生成', () {
    test('buildCreate：EVERY + STARTS/ENDS + definer + comment + NOT PRESERVE', () {
      final sql = MysqlEventDdl.buildCreate(const MysqlEventFormInput(
        name: 'ev_cleanup',
        definer: 'root@localhost',
        status: 'DISABLE',
        everyValue: '15',
        everyUnit: 'MINUTE',
        starts: '2026-10-12 10:00:00',
        ends: '2026-12-31 23:59:59',
        comment: "purge 'logs'",
        doBody: 'DELETE FROM `logs`',
      ));
      expect(
        sql,
        'CREATE DEFINER=`root`@`localhost` EVENT `ev_cleanup`\n'
        "  ON SCHEDULE EVERY 15 MINUTE STARTS '2026-10-12 10:00:00' "
        "ENDS '2026-12-31 23:59:59'\n"
        '  ON COMPLETION NOT PRESERVE\n'
        '  DISABLE\n'
        "  COMMENT 'purge ''logs'''\n"
        '  DO\n'
        'DELETE FROM `logs`',
      );
    });

    test('buildCreate：AT 一次性 + 无 definer/comment 省略子句', () {
      final sql = MysqlEventDdl.buildCreate(const MysqlEventFormInput(
        name: 'ev_once',
        recurring: false,
        atTime: '2026-11-01 00:00:00',
        preserve: true,
        doBody: 'SELECT 1',
      ));
      expect(
        sql,
        'CREATE EVENT `ev_once`\n'
        "  ON SCHEDULE AT '2026-11-01 00:00:00'\n"
        '  ON COMPLETION PRESERVE\n'
        '  ENABLE\n'
        '  DO\n'
        'SELECT 1',
      );
    });

    // R1-P1（注入面修复）：MySQL 串内反斜杠是转义字符——COMMENT/STARTS/
    // ENDS/AT 全部经 escapeMySqlString（先 `\`→`\\` 再 `'`→`''`）。
    test('buildCreate：COMMENT 含反斜杠 → 反斜杠双写 + 引号双写', () {
      final sql = MysqlEventDdl.buildCreate(const MysqlEventFormInput(
        name: 'ev_c',
        everyValue: '1',
        everyUnit: 'DAY',
        comment: r"purge \logs 'x'",
        doBody: 'SELECT 1',
      ));
      expect(sql, contains(r"COMMENT 'purge \\logs ''x'''"));
    });

    test('buildAlter：COMMENT 含尾随反斜杠（naive 转义下会吞收尾引号）', () {
      final sql = MysqlEventDdl.buildAlter(
        const MysqlEventFormInput(
          name: 'ev_a',
          everyValue: '1',
          everyUnit: 'DAY',
          comment: 'backlash\\',
          doBody: 'SELECT 1',
        ),
        'ev_a',
      );
      // `\'` 会把收尾引号转义进数据（字符串不闭合）；`\\'` 才是字面反斜杠。
      expect(sql, contains(r"COMMENT 'backlash\\'"));
    });

    test('调度时间（AT/STARTS/ENDS）含反斜杠同样双写', () {
      final sql = MysqlEventDdl.buildCreate(const MysqlEventFormInput(
        name: 'ev_s',
        recurring: false,
        atTime: '2026-11-01 00:00:00\\',
        doBody: 'SELECT 1',
      ));
      expect(sql, contains(r"AT '2026-11-01 00:00:00\\'"));

      final recurring = MysqlEventDdl.buildCreate(const MysqlEventFormInput(
        name: 'ev_s',
        everyValue: '1',
        everyUnit: 'DAY',
        starts: '2026-11-01 00:00:00\\',
        ends: '2026-12-31 23:59:59\\',
        doBody: 'SELECT 1',
      ));
      expect(recurring, contains(r"STARTS '2026-11-01 00:00:00\\'"));
      expect(recurring, contains(r"ENDS '2026-12-31 23:59:59\\'"));
    });

    test('buildCreate：标识符反引号转义（含反引号的事件名）', () {
      final sql = MysqlEventDdl.buildCreate(const MysqlEventFormInput(
        name: 'a`b',
        everyValue: '1',
        everyUnit: 'DAY',
        doBody: 'SELECT 1',
      ));
      expect(sql.startsWith('CREATE EVENT `a``b`'), isTrue);
    });

    test('buildAlter：改名 → RENAME TO；COMMENT 恒输出（空串清除）', () {
      final sql = MysqlEventDdl.buildAlter(
        const MysqlEventFormInput(
          name: 'ev_renamed',
          everyValue: '1',
          everyUnit: 'HOUR',
          doBody: 'SELECT 2',
        ),
        'ev_orig',
      );
      expect(sql, contains('ALTER EVENT `ev_orig`'));
      expect(sql, contains('RENAME TO `ev_renamed`'));
      expect(sql, contains("COMMENT ''"));
      expect(sql, isNot(contains('RENAME TO `ev_orig`')));
    });

    test('buildAlter：同名不输出 RENAME', () {
      final sql = MysqlEventDdl.buildAlter(
        const MysqlEventFormInput(
          name: 'ev_same',
          everyValue: '1',
          everyUnit: 'HOUR',
          doBody: 'SELECT 2',
        ),
        'ev_same',
      );
      expect(sql, isNot(contains('RENAME')));
    });

    test('buildDrop：反引号转义', () {
      expect(MysqlEventDdl.buildDrop('ev_x'), 'DROP EVENT `ev_x`');
      expect(MysqlEventDdl.buildDrop('a`b'), 'DROP EVENT `a``b`');
    });
  });

  // ── 纯函数：SHOW CREATE EVENT 反解析（容错）──────────────────────
  group('MysqlEventDdl.parseShowCreate', () {
    test('典型 EVERY 输出全字段回填', () {
      final input = MysqlEventDdl.parseShowCreate(_sampleShowCreate);
      expect(input.name, 'ev_cleanup');
      expect(input.definer, 'root@%');
      expect(input.status, 'DISABLE');
      expect(input.recurring, isTrue);
      expect(input.everyValue, '15');
      expect(input.everyUnit, 'MINUTE');
      expect(input.starts, '2026-10-12 10:00:00');
      expect(input.ends, '2026-12-31 23:59:59');
      expect(input.preserve, isFalse);
      expect(input.comment, 'purge logs');
      expect(
        input.doBody,
        'DELETE FROM `logs` WHERE `created_at` < NOW() - INTERVAL 7 DAY',
      );
    });

    test('AT 一次性 + PRESERVE + DISABLE ON SLAVE', () {
      final input = MysqlEventDdl.parseShowCreate(
        "CREATE EVENT `mydb`.`ev_once` ON SCHEDULE AT '2026-11-01 00:00:00' "
        'ON COMPLETION PRESERVE DISABLE ON SLAVE DO TRUNCATE `t`',
      );
      expect(input.recurring, isFalse);
      expect(input.atTime, '2026-11-01 00:00:00');
      expect(input.preserve, isTrue);
      expect(input.status, 'DISABLE ON SLAVE');
      expect(input.doBody, 'TRUNCATE `t`');
    });

    test('不可解析输入 → 字段留默认（不抛异常）', () {
      final input = MysqlEventDdl.parseShowCreate('not a ddl at all');
      expect(input.name, isEmpty);
      expect(input.doBody, isEmpty);
      expect(input.status, 'ENABLE');
      expect(input.recurring, isTrue);
    });

    test('注释含 DO 关键字不误截 body（引号串跳过）', () {
      final input = MysqlEventDdl.parseShowCreate(
        "CREATE EVENT `e` ON SCHEDULE EVERY 1 DAY COMMENT 'runs DO stuff' "
        'DO SELECT 1',
      );
      expect(input.comment, 'runs DO stuff');
      expect(input.doBody, 'SELECT 1');
    });
  });

  // ── 表单校验（纯函数）───────────────────────────────────────────
  group('MysqlEventFormInput 校验', () {
    test('必填：名称/EVERY 数值/DO body/AT 时间/DEFINER 格式', () {
      const empty = MysqlEventFormInput();
      expect(empty.firstInvalidField(), 'name');

      const noEvery = MysqlEventFormInput(name: 'e', doBody: 'SELECT 1');
      expect(noEvery.firstInvalidField(), 'every');

      const badEvery = MysqlEventFormInput(
        name: 'e', everyValue: '0', doBody: 'SELECT 1');
      expect(badEvery.firstInvalidField(), 'every');

      const atMode = MysqlEventFormInput(
        name: 'e', recurring: false, doBody: 'SELECT 1');
      expect(atMode.firstInvalidField(), 'at');

      const noBody = MysqlEventFormInput(name: 'e', everyValue: '1');
      expect(noBody.firstInvalidField(), 'doBody');

      const badDefiner = MysqlEventFormInput(
        name: 'e', everyValue: '1', definer: 'no-at-sign', doBody: 'SELECT 1');
      expect(badDefiner.firstInvalidField(), 'definer');

      const valid = MysqlEventFormInput(
        name: 'e', everyValue: '1', definer: 'u@h', doBody: 'SELECT 1');
      expect(valid.firstInvalidField(), isNull);
    });
  });

  // ── Widget：对话框交互 ──────────────────────────────────────────
  group('MysqlEventsDialog widget', () {
    MysqlEventsSnapshot snapshot({
      List<MysqlEventEntry> events = const [],
      String schedulerState = 'ON',
    }) =>
        MysqlEventsSnapshot(events: events, schedulerState: schedulerState);

    final fixtureEvents = [
      const MysqlEventEntry(
        name: 'ev_cleanup',
        status: 'ENABLED',
        eventType: 'RECURRING',
        intervalValue: '15',
        intervalField: 'MINUTE',
        lastExecuted: '2026-10-12 10:15:00',
        definer: 'root@%',
      ),
      const MysqlEventEntry(
        name: 'ev_once',
        status: 'DISABLED',
        eventType: 'ONE TIME',
        executeAt: '2026-11-01 00:00:00',
        definer: 'root@%',
      ),
    ];

    Future<MysqlEventsDialog> pumpDialog(
      WidgetTester tester, {
      MysqlEventsLoader? loader,
      MysqlEventDdlFetcher? ddlFetcher,
      MysqlEventDdlExecutor? executor,
      MysqlEventAuditor? auditor,
      AppProvider? provider,
    }) async {
      final dialog = MysqlEventsDialog(
        connectionId: 'ev_conn',
        databaseName: 'mydb',
        loader: loader,
        ddlFetcher: ddlFetcher,
        executor: executor,
        auditor: auditor,
      );
      // 760px 宽 dialog 超默认 800x600 安全区——放大测试视口（金标准 e2e 同法）。
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final effectiveProvider = provider ?? AppProvider();
      final home = Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('Open'),
          ),
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
      return dialog;
    }

    testWidgets('列表渲染：行 + 列头 + 库名；LAST_EXECUTED null → —', (tester) async {
      await pumpDialog(
        tester,
        loader: (_, _) async => snapshot(events: [
          ...fixtureEvents,
          const MysqlEventEntry(
            name: 'ev_never',
            status: 'ENABLED',
            eventType: 'RECURRING',
            intervalValue: '1',
            intervalField: 'DAY',
          ),
        ]),
      );

      expect(find.text('Events · mydb'), findsOneWidget);
      expect(find.text('ev_cleanup'), findsOneWidget);
      expect(find.text('EVERY 15 MINUTE'), findsOneWidget);
      expect(find.text('AT 2026-11-01 00:00:00'), findsOneWidget);
      expect(find.textContaining('Name'), findsWidgets);
      // 3 处 —：ev_once.lastExecuted + ev_never.lastExecuted + ev_never.definer
      expect(find.text('—'), findsNWidgets(3), reason: '从未执行/无 definer → —');
      // 调度器 ON → 不出提示行
      expect(find.textContaining('event scheduler is OFF'), findsNothing);
    });

    testWidgets('调度器 OFF → 提示行可见', (tester) async {
      await pumpDialog(
        tester,
        loader: (_, _) async =>
            snapshot(events: fixtureEvents, schedulerState: 'OFF'),
      );
      expect(find.textContaining('event scheduler is OFF'), findsOneWidget);
    });

    // R1-P3-5：探测失败/空值（schedulerState 为空）不误报——仅确知非 ON
    // 才提示。
    testWidgets('调度器状态为空（探测失败）→ 不出提示行', (tester) async {
      await pumpDialog(
        tester,
        loader: (_, _) async =>
            snapshot(events: fixtureEvents, schedulerState: ''),
      );
      expect(find.textContaining('event scheduler is OFF'), findsNothing);
    });

    testWidgets('空态', (tester) async {
      await pumpDialog(tester, loader: (_, _) async => snapshot());
      expect(find.text('No events'), findsOneWidget);
    });

    testWidgets('加载失败 → 错误态 + Retry 重新取数', (tester) async {
      var fail = true;
      await pumpDialog(
        tester,
        loader: (_, _) {
          if (fail) throw Exception('connection lost');
          return Future.value(snapshot(events: fixtureEvents));
        },
      );
      expect(find.textContaining('Events failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('ev_cleanup'), findsOneWidget);
    });

    testWidgets('新建：必填校验拦截空表单（零执行零审计）', (tester) async {
      final executed = <String>[];
      final audits = <MysqlEventAuditRecord>[];
      await pumpDialog(
        tester,
        loader: (_, _) async => snapshot(),
        executor: (_, _, _, sql) async => executed.add(sql),
        auditor: (r) async => audits.add(r),
      );

      await tester.tap(find.text('New Event'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mysql_event_form_save')));
      await tester.pumpAndSettle();

      expect(executed, isEmpty);
      expect(audits, isEmpty);
      // 三处必填错误浮出（Name / Every / DO Body）
      expect(
        find.widgetWithText(TextField, 'Required'),
        findsNWidgets(3),
        reason: '名称、EVERY 数值、DO body 三个必填错误',
      );
    });

    testWidgets('新建：预览与执行逐字一致 + 取消 = 零执行', (tester) async {
      final executed = <String>[];
      final audits = <MysqlEventAuditRecord>[];
      await pumpDialog(
        tester,
        loader: (_, _) async => snapshot(),
        executor: (_, _, _, sql) async => executed.add(sql),
        auditor: (r) async => audits.add(r),
      );

      await tester.tap(find.text('New Event'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('mysql_event_field_name')),
        'ev_created',
      );
      await tester.enterText(
        find.byKey(const Key('mysql_event_field_every_value')),
        '5',
      );
      await tester.enterText(
        find.byKey(const Key('mysql_event_field_do_body')),
        'INSERT INTO `t` VALUES (1)',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('mysql_event_form_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // DDL 预览门：预览文本 = 生成函数输出
      final expected = MysqlEventDdl.buildCreate(const MysqlEventFormInput(
        name: 'ev_created',
        everyValue: '5',
        doBody: 'INSERT INTO `t` VALUES (1)',
      ));
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      expect(find.text(expected), findsOneWidget, reason: '预览即所执行（逐字）');

      // 取消 → 零执行零审计
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(executed, isEmpty);
      expect(audits, isEmpty);

      // 重新提交并确认 → 执行 SQL 与预览逐字一致 + 审计成功落账
      await tester.tap(find.byKey(const Key('mysql_event_form_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(executed, [expected]);
      expect(audits, hasLength(1));
      expect(audits.first.success, isTrue);
      expect(audits.first.sql, expected);
    });

    testWidgets('编辑：SHOW CREATE 反解析回填 + ALTER 预览', (tester) async {
      final executed = <String>[];
      await pumpDialog(
        tester,
        loader: (_, _) async => snapshot(events: fixtureEvents),
        ddlFetcher: (_, _, _) async => _sampleShowCreate,
        executor: (_, _, _, sql) async => executed.add(sql),
        auditor: (_) async {},
      );

      await tester.tap(find.byIcon(LucideIcons.pencil).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 回填断言（SHOW CREATE 反解析）
      expect(
        (tester.widget<TextField>(
          find.byKey(const Key('mysql_event_field_name')),
        ).controller?.text ?? ''),
        'ev_cleanup',
      );
      expect(
        (tester.widget<TextField>(
          find.byKey(const Key('mysql_event_field_every_value')),
        ).controller?.text ?? ''),
        '15',
      );
      // 编辑回填不预填 DEFINER（ALTER 省略 = 保持原值；原文见 sourceDdl）
      expect(
        (tester.widget<TextField>(
          find.byKey(const Key('mysql_event_field_definer')),
        ).controller?.text ?? ''),
        isEmpty,
      );
      expect(
        (tester.widget<TextField>(
          find.byKey(const Key('mysql_event_field_do_body')),
        ).controller?.text ?? ''),
        contains('DELETE FROM `logs`'),
      );
      // 原始 DDL 展示（以 DDL 为准手改提示）
      expect(find.textContaining('DEFINER=`root`@`%`'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mysql_event_form_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      // 反解析回填 round-trip：调度/状态进 ALTER；DEFINER 不回填（ALTER 省
      // 子句 = 保持原 definer，最小权限面）。
      expect(executed, hasLength(1));
      expect(executed.first, startsWith('ALTER EVENT `ev_cleanup`'));
      expect(executed.first, isNot(contains('DEFINER')));
      expect(executed.first, contains('  DISABLE\n'));
      expect(executed.first, isNot(contains('RENAME')));
    });

    testWidgets('删除：typed confirmation 错名禁用 / 取消零执行 / 正确执行', (tester) async {
      final executed = <String>[];
      final audits = <MysqlEventAuditRecord>[];
      await pumpDialog(
        tester,
        loader: (_, _) async => snapshot(events: fixtureEvents),
        executor: (_, _, _, sql) async => executed.add(sql),
        auditor: (r) async => audits.add(r),
      );

      // 行尾删除按钮（trash 图标）
      await tester.tap(find.byIcon(LucideIcons.trash2).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      expect(find.textContaining('Drop event ev_cleanup?'), findsOneWidget);

      // 错误输入 → 确认钮禁用
      await tester.enterText(find.byType(TextField), 'wrong_name');
      await tester.pump();
      final confirmBtn =
          tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
      expect(confirmBtn.onPressed, isNull, reason: 'typed 不匹配时确认禁用');

      // 取消 → 零执行
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(executed, isEmpty);
      expect(audits, isEmpty);

      // 正确输入 → 确认 → DROP + 审计成功
      await tester.tap(find.byIcon(LucideIcons.trash2).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'ev_cleanup');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(executed, ['DROP EVENT `ev_cleanup`']);
      expect(audits, hasLength(1));
      expect(audits.first.success, isTrue);
      expect(audits.first.sql, 'DROP EVENT `ev_cleanup`');
    });

    testWidgets('执行失败：引擎错误原文 + 审计失败态（success=false + errorMessage）',
        (tester) async {
      final audits = <MysqlEventAuditRecord>[];
      await pumpDialog(
        tester,
        loader: (_, _) async => snapshot(events: fixtureEvents),
        executor: (_, _, _, _) async =>
            throw Exception('ERROR 1064 (42000): parse error'),
        auditor: (r) async => audits.add(r),
      );

      await tester.tap(find.byIcon(LucideIcons.trash2).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'ev_cleanup');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(audits, hasLength(1));
      expect(audits.first.success, isFalse);
      expect(audits.first.errorMessage, contains('1064'));
      // 错误原文进 snackbar（不吞错）
      expect(find.textContaining('parse error'), findsOneWidget);
    });

    testWidgets('审计写失败不阻塞：执行仍完成（对话框不崩溃）', (tester) async {
      final executed = <String>[];
      await pumpDialog(
        tester,
        loader: (_, _) async => snapshot(events: fixtureEvents),
        executor: (_, _, _, sql) async => executed.add(sql),
        auditor: (_) async => throw Exception('prefs write failed'),
      );

      await tester.tap(find.byIcon(LucideIcons.trash2).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'ev_cleanup');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(executed, ['DROP EVENT `ev_cleanup`']);
    });

    testWidgets('只读连接：新建/编辑/删除入口全禁用（readOnlyModeBlocked 提示）',
        (tester) async {
      final provider = AppProvider();
      provider.connection.addSavedServerForTest(
        DbServer(
          id: 'ev_conn',
          name: 'RO',
          type: DatabaseType.mysql,
          host: 'h',
          port: 3306,
          readOnly: true,
        ),
      );
      await pumpDialog(
        tester,
        provider: provider,
        loader: (_, _) async => snapshot(events: fixtureEvents),
      );

      // 新建按钮禁用
      final newBtn =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'New Event'));
      expect(newBtn.onPressed, isNull);
      expect(find.textContaining('read-only mode'), findsOneWidget);

      // 行内编辑/删除按钮禁用（onPressed null，fixture 2 行取首行）；
      // 查看 DDL 仍可用（只读动作）。经 icon 定位 IconButton（tooltip 包装
      // 因版本而异，icon 查找稳定）。
      final editBtns = find.widgetWithIcon(IconButton, LucideIcons.pencil);
      expect(editBtns, findsNWidgets(2));
      expect(tester.widget<IconButton>(editBtns.first).onPressed, isNull);
      final dropBtns = find.widgetWithIcon(IconButton, LucideIcons.trash2);
      expect(dropBtns, findsNWidgets(2));
      expect(tester.widget<IconButton>(dropBtns.first).onPressed, isNull);
      final viewBtns = find.widgetWithIcon(IconButton, LucideIcons.eye);
      expect(viewBtns, findsNWidgets(2));
      expect(tester.widget<IconButton>(viewBtns.first).onPressed, isNotNull);
    });
  });
}
