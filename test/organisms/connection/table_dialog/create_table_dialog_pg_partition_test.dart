// ============================================================================
// DBT-T19（W-16）· CreatePostgresTableDialog 分区接线 Widget Tests
//
// 断言面（任务书 T19 验收①②）：
//   - 分区节渲染：PG 连接下策略/分区键/分区行可见（死线断点①修复锚定）；
//   - MySQL/Doris 对话框（CreateTableDialog）不渲染 PG 分区节（零泄漏，
//     Doris 分区路径零回归的反向锚定——既有 doris 测试为正向锚定）；
//   - PK 硬校验拒绝：PK 不含分区键 → 表单报错 + 零执行（不出半成品 SQL）；
//   - DDL 预览门：预览 SQL 与 adapter 同源构造逐字一致；取消 = 零执行；
//   - 确认后：tableCreator 收到逐字 options（协议锁定）+ 审计成功落账
//     （注入缝计数断言）；readonly 入口拦截。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:dbmaster/organisms/connection/table_dialog/create_table_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/postgresql_gateway_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// 泵对话框（沿 create_table_dialog_doris_test 先例：注入目标类型连接，
  /// 不真正连库）。
  Future<AppProvider> pumpDialog(
    WidgetTester tester, {
    required Widget dialog,
    required DatabaseType databaseType,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final appProvider = AppProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(context: context, builder: (_) => dialog),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    appProvider.connection.setCurrentServer(
      DbServer(
        id: 'pg_test',
        name: 'PG Test',
        type: databaseType,
        host: 'localhost',
        port: 5432,
        username: 'postgres',
        database: 'test_db',
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return appProvider;
  }

  group('CreatePostgresTableDialog 分区节渲染（死线断点①）', () {
    testWidgets('PG 连接：分区节可见（标题/策略/分区键/加分区按钮）', (tester) async {
      await pumpDialog(
        tester,
        dialog: const CreatePostgresTableDialog(dbName: 'test_db'),
        databaseType: DatabaseType.postgresql,
      );

      expect(find.text('Partitioning'), findsOneWidget);
      expect(find.text('Strategy'), findsOneWidget);
      expect(find.text('Partition Key Column'), findsOneWidget);
      expect(find.text('Add partition'), findsOneWidget);
      // 策略下拉缺省 RANGE。
      expect(find.text('RANGE'), findsOneWidget);
    });

    testWidgets('MySQL 连接（CreateTableDialog）：不渲染 PG 分区节（零泄漏）',
        (tester) async {
      await pumpDialog(
        tester,
        dialog: const CreateTableDialog(dbName: 'test_db'),
        databaseType: DatabaseType.mysql,
      );

      expect(find.text('Partitioning'), findsNothing);
      expect(find.text('Partition Key Column'), findsNothing);
    });

    testWidgets('Doris 连接（CreateTableDialog）：Doris 分区路径原样（零回归锚定）',
        (tester) async {
      await pumpDialog(
        tester,
        dialog: const CreateTableDialog(dbName: 'test_db'),
        databaseType: DatabaseType.doris,
      );

      // Doris 表模型 + 分区节按既有条件渲染（既有 doris 测试为正向锚定，
      // 此处补 PG 分区节不出现的反向断言）。
      expect(find.text('Partitioning'), findsNothing);
      expect(find.text('Partition column'), findsOneWidget);
    });
  });

  group('CreatePostgresTableDialog 分区提交（死线断点②③）', () {
    Future<CreatePostgresTableDialog> pumpWithSeams(
      WidgetTester tester, {
      required List<Map<String, dynamic?>> calls,
      required List<({bool success, String? errorMessage, String sql})> audits,
      bool readOnly = false,
    }) async {
      final dialog = CreatePostgresTableDialog(
        dbName: 'test_db',
        tableCreator: (db, table, columns,
            {comment, engine, options}) async {
          calls.add({'db': db, 'table': table, 'options': options});
          return true;
        },
        partitionAuditor: (rec) async {
          audits.add((
            success: rec.success,
            errorMessage: rec.errorMessage,
            sql: rec.sql,
          ));
        },
      );
      final provider = await pumpDialog(
        tester,
        dialog: dialog,
        databaseType: DatabaseType.postgresql,
      );
      if (readOnly) {
        // setCurrentServer 同 id 不生效（ConnectionProvider 语义）——RO
        // 连接用不同 id 真正切换 currentServer。
        provider.connection.setCurrentServer(
          DbServer(
            id: 'pg_test_ro',
            name: 'PG Test RO',
            type: DatabaseType.postgresql,
            host: 'localhost',
            port: 5432,
            username: 'postgres',
            database: 'test_db',
            readOnly: true,
          ),
        );
      }
      return dialog;
    }

    /// 填两列（id PK / amt PK）+ 分区键 amt + 两分区（p0→10 / p1→20）。
    Future<void> fillPartitionedForm(WidgetTester tester) async {
      // 表名（首个 TextFormField）。
      await tester.enterText(find.byType(TextFormField).at(0), 'sales');
      // 列 0：id（PK 勾选 = 首个 Checkbox）。
      await tester.enterText(find.byType(TextFormField).at(2), 'id');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pump();
      // 列 1：amt（Add Column 后出现；列行含 name+default 两个输入框，
      // col1.name = 第 5 个 TextFormField；PK 勾选 = 第三个 Checkbox）。
      await tester.tap(find.text('Add Column'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(4), 'amt');
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      // 分区键列下拉 → amt（T17 先例：tap 内层 DropdownButton<String?>）。
      await tester.tap(find.byType(DropdownButton<String?>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('amt').last);
      await tester.pumpAndSettle();
      // 两分区行。
      await tester.tap(find.text('Add partition'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pg_partition_name_0')),
        'p0',
      );
      await tester.enterText(
        find.byKey(const Key('pg_partition_bound_0')),
        '10',
      );
      await tester.tap(find.text('Add partition'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pg_partition_name_1')),
        'p1',
      );
      await tester.enterText(
        find.byKey(const Key('pg_partition_bound_1')),
        '20',
      );
      await tester.pump();
    }

    testWidgets('PK 硬校验拒绝：PK 不含分区键 → 报错 + 零执行', (tester) async {
      final calls = <Map<String, dynamic?>>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpWithSeams(tester, calls: calls, audits: audits);

      await tester.enterText(find.byType(TextFormField).at(0), 'bad_pk');
      // 列 0：id PK；列 1：region 不进 PK。
      await tester.enterText(find.byType(TextFormField).at(2), 'id');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pump();
      await tester.tap(find.text('Add Column'));
      await tester.pumpAndSettle();
      // col1.name = 第 5 个 TextFormField（列行含 name+default 两框）。
      await tester.enterText(find.byType(TextFormField).at(4), 'region');
      // 让 onChanged 触发的重建帧落地（分区键下拉 items 才含 region）。
      await tester.pump();
      // 分区键 = region（不在 PK 内）。
      await tester.tap(find.byType(DropdownButton<String?>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('region').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 前置拦截：pgPartitionNeedsPk 文案 + 零执行零审计 + 对话框保持。
      expect(
        find.textContaining('must include the partition key column'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      expect(audits, isEmpty);
      expect(find.byType(CreatePostgresTableDialog), findsOneWidget);
    });

    testWidgets('readonly 连接：提交被入口拦截（fail-closed UX 收口）', (
      tester,
    ) async {
      final calls = <Map<String, dynamic?>>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpWithSeams(
        tester,
        calls: calls,
        audits: audits,
        readOnly: true,
      );

      await fillPartitionedForm(tester);
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('read-only mode'), findsOneWidget);
      expect(calls, isEmpty);
      expect(audits, isEmpty);
    });

    testWidgets('分区边界含语句分隔符/注释串 = 拒绝（注入面防御）', (tester) async {
      final calls = <Map<String, dynamic?>>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpWithSeams(tester, calls: calls, audits: audits);

      await fillPartitionedForm(tester);
      await tester.enterText(
        find.byKey(const Key('pg_partition_bound_1')),
        '20); DROP TABLE x --',
      );
      await tester.pump();

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, isEmpty);
      expect(audits, isEmpty);
      expect(find.byType(CreatePostgresTableDialog), findsOneWidget);
    });

    testWidgets('DDL 预览门：预览与 adapter 同源逐字一致；取消 = 零执行', (
      tester,
    ) async {
      final calls = <Map<String, dynamic?>>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpWithSeams(tester, calls: calls, audits: audits);
      await fillPartitionedForm(tester);

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 预览门出现；预览文本 = adapter 同一构造函数输出（逐字断言）。
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      final expected = PostgreSQLAdapter.buildPgPartitionDdl(
        'public.sales',
        [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'amt', type: 'INTEGER', isPrimaryKey: true),
        ],
        strategy: 'RANGE',
        column: 'amt',
        partitions: const [(name: 'p0', values: '10'), (name: 'p1', values: '20')],
      ).join(';\n');
      final preview = tester.widget<SelectableText>(
        find.byKey(const Key('pg_partition_ddl_preview')),
      );
      expect(preview.data, expected);
      expect(expected, contains('PARTITION BY RANGE ("amt")'));

      // 取消 = 零执行零审计，对话框保持。
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(audits, isEmpty);
      expect(find.byType(CreatePostgresTableDialog), findsOneWidget);
    });

    testWidgets('确认后：options 协议逐字传递 + 审计成功落账 + 成功关窗', (
      tester,
    ) async {
      final calls = <Map<String, dynamic?>>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpWithSeams(tester, calls: calls, audits: audits);
      await fillPartitionedForm(tester);

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // options 序列化协议锁定（死线断点②③贯通：dialog 读分区 → options →
      // adapter 消费协议）。
      expect(calls, hasLength(1));
      expect(calls.first['db'], 'test_db');
      expect(calls.first['table'], 'public.sales');
      expect(calls.first['options'], {
        'pgPartition': {
          'strategy': 'RANGE',
          'column': 'amt',
          'partitions': [
            {'name': 'p0', 'values': '10'},
            {'name': 'p1', 'values': '20'},
          ],
        },
      });
      // 审计成功态（成功路径落账；SQL = 预览同源）。
      expect(audits, hasLength(1));
      expect(audits.first.success, isTrue);
      expect(audits.first.errorMessage, isNull);
      expect(audits.first.sql, contains('PARTITION BY RANGE'));
      // 成功 → 关窗 + 成功 SnackBar。
      expect(find.byType(CreatePostgresTableDialog), findsNothing);
      expect(find.text('Success'), findsOneWidget);
    });

    testWidgets('未选分区键 → options null（既有裸建表路径零变化）', (
      tester,
    ) async {
      final calls = <Map<String, dynamic?>>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpWithSeams(tester, calls: calls, audits: audits);

      await tester.enterText(find.byType(TextFormField).at(0), 'plain');
      await tester.enterText(find.byType(TextFormField).at(2), 'id');
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.first['options'], isNull);
      // 非分区路径零审计（既有行为）。
      expect(audits, isEmpty);
      expect(find.byType(CreatePostgresTableDialog), findsNothing);
    });
  });
}
