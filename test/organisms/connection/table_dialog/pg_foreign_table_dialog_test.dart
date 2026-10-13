// ============================================================================
// DBT-T19（W-16）· PgForeignTableDialog Widget Tests
//
// 断言面（任务书 T19 验收①）：
//   - servers 下拉渲染 / 空态提示（pg_foreign_server 空 → 不内嵌建 server）；
//   - DDL 生成逐字断言（列定义 / OPTIONS 值单引号转义 / 零列合法）；
//   - DDL 预览门：取消 = 零执行（执行计数）；确认 = executor 一次 + 逐字
//     SQL + 审计成功落账；失败路径 = 审计失败 + 引擎错误原文展示；
//   - readonly = 入口禁用；
//   - OPTIONS 键非法词法 = 表单校验拒绝。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:dbmaster/organisms/connection/table_dialog/pg_foreign_table_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<String> servers,
    required List<String> executed,
    required List<({bool success, String? errorMessage, String sql})> audits,
    bool readOnly = false,
    bool executeFails = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final provider = AppProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  // readonly 解析：保存清单命中（T18 addSavedServerForTest 同面）。
                  if (readOnly) {
                    provider.connection.addSavedServerForTest(
                      DbServer(
                        id: 'pg1',
                        name: 'pg',
                        type: DatabaseType.postgresql,
                        host: 'localhost',
                        port: 5432,
                        readOnly: true,
                      ),
                    );
                  }
                  showDialog<void>(
                    context: context,
                    builder: (_) => PgForeignTableDialog(
                      connectionId: 'pg1',
                      databaseName: 'test_db',
                      // 注入缝（生产默认经 dbService 只读/执行面）。
                      serverLoader: (_) async => servers,
                      executor: (_, __, ___, ddl) async {
                        executed.add(ddl);
                        if (executeFails) {
                          throw StateError('engine boom');
                        }
                      },
                      auditor: (rec) async => audits.add((
                        success: rec.success,
                        errorMessage: rec.errorMessage,
                        sql: rec.sql,
                      )),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// 列 remote_id + 一条 OPTIONS（schema=public）→ 提交到预览门。
  Future<void> fillToGate(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('pgft_table_field')),
      'ext_contacts',
    );
    await tester.tap(find.byKey(const Key('pgft_col_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('pgft_col_name_0')),
      'remote_id',
    );
    await tester.tap(find.byKey(const Key('pgft_opt_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pgft_opt_key_0')), 'schema');
    await tester.enterText(
      find.byKey(const Key('pgft_opt_value_0')),
      'public',
    );
    await tester.tap(find.byKey(const Key('pgft_create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('PgForeignTableDialog 渲染与边界', () {
    testWidgets('servers 下拉渲染 + 空态提示（不内嵌建 server）', (tester) async {
      await pumpDialog(
        tester,
        servers: ['dbt_srv', 'other_srv'],
        executed: [],
        audits: [],
      );

      // 下拉缺省选中首个 server（未展开只渲染选中值）。
      expect(find.text('dbt_srv'), findsOneWidget);
      // 展开后全量可见。
      await tester.tap(find.byKey(const Key('pgft_server_field')));
      await tester.pumpAndSettle();
      expect(find.text('other_srv'), findsOneWidget);
      // 标题带库名。
      expect(find.textContaining('Foreign Table · test_db'), findsOneWidget);
    });

    testWidgets('无 foreign server → 提示 + 创建禁用', (tester) async {
      await pumpDialog(tester, servers: [], executed: [], audits: []);

      expect(
        find.textContaining('No foreign servers found'),
        findsOneWidget,
      );
      final createBtn = tester.widget<TextButton>(
        find.byKey(const Key('pgft_create')),
      );
      expect(createBtn.onPressed, isNull);
    });

    testWidgets('readonly 连接 = 创建入口禁用', (tester) async {
      await pumpDialog(
        tester,
        servers: ['dbt_srv'],
        executed: [],
        audits: [],
        readOnly: true,
      );

      expect(find.textContaining('read-only mode'), findsOneWidget);
      final createBtn = tester.widget<TextButton>(
        find.byKey(const Key('pgft_create')),
      );
      expect(createBtn.onPressed, isNull);
    });
  });

  group('PgForeignTableDialog DDL 生成与执行链', () {
    testWidgets('DDL 逐字断言：列 + OPTIONS 值单引号转义；取消 = 零执行', (
      tester,
    ) async {
      final executed = <String>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpDialog(
        tester,
        servers: ['dbt_srv'],
        executed: executed,
        audits: audits,
      );

      await tester.enterText(
        find.byKey(const Key('pgft_table_field')),
        'ext_contacts',
      );
      // 列：remote_id INTEGER（dropdown 缺省 INTEGER）。
      await tester.tap(find.byKey(const Key('pgft_col_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pgft_col_name_0')),
        'remote_id',
      );
      // OPTIONS：schema = public，值含单引号（转义断言）。
      await tester.tap(find.byKey(const Key('pgft_opt_add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pgft_opt_key_0')), 'schema');
      await tester.enterText(
        find.byKey(const Key('pgft_opt_value_0')),
        "pub'lic",
      );

      // 提交 → 预览门（DDL 逐字断言）。
      await tester.tap(find.byKey(const Key('pgft_create')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      final expected =
          'CREATE FOREIGN TABLE "public"."ext_contacts" (\n'
          '  "remote_id" INTEGER\n'
          ')\n'
          'SERVER "dbt_srv"\n'
          "OPTIONS (schema 'pub''lic')";
      final preview = tester.widget<SelectableText>(
        find.byKey(const Key('pgft_ddl_preview')),
      );
      expect(preview.data, expected);

      // 取消 = 零执行零审计。
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(executed, isEmpty);
      expect(audits, isEmpty);
      expect(find.byType(PgForeignTableDialog), findsOneWidget);
    });

    testWidgets('零列合法（无列清单的 CREATE FOREIGN TABLE）+ 确认执行一次 + 审计成功',
        (tester) async {
      final executed = <String>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpDialog(
        tester,
        servers: ['dbt_srv'],
        executed: executed,
        audits: audits,
      );

      await tester.enterText(
        find.byKey(const Key('pgft_table_field')),
        'ext_nocols',
      );
      await tester.tap(find.byKey(const Key('pgft_create')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      final preview = tester.widget<SelectableText>(
        find.byKey(const Key('pgft_ddl_preview')),
      );
      expect(
        preview.data,
        'CREATE FOREIGN TABLE "public"."ext_nocols"\nSERVER "dbt_srv"',
      );

      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(executed, [
        'CREATE FOREIGN TABLE "public"."ext_nocols"\nSERVER "dbt_srv"',
      ]);
      expect(audits, hasLength(1));
      expect(audits.first.success, isTrue);
      expect(audits.first.sql, executed.first);
      expect(find.byType(PgForeignTableDialog), findsNothing);
      expect(find.text('Success'), findsOneWidget);
    });

    testWidgets('失败路径：审计 success=false + 引擎错误原文展示（不关窗）', (
      tester,
    ) async {
      final executed = <String>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpDialog(
        tester,
        servers: ['dbt_srv'],
        executed: executed,
        audits: audits,
        executeFails: true,
      );
      await fillToGate(tester);
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(executed, hasLength(1));
      expect(audits, hasLength(1));
      expect(audits.first.success, isFalse);
      expect(audits.first.errorMessage, contains('engine boom'));
      // 引擎错误原文展示 + 对话框保持（不假成功）。
      expect(find.textContaining('engine boom'), findsOneWidget);
      expect(find.byType(PgForeignTableDialog), findsOneWidget);
    });

    testWidgets('OPTIONS 键非法词法 = 表单校验拒绝（不出预览门）', (tester) async {
      final executed = <String>[];
      final audits = <({bool success, String? errorMessage, String sql})>[];
      await pumpDialog(
        tester,
        servers: ['dbt_srv'],
        executed: executed,
        audits: audits,
      );

      await tester.enterText(
        find.byKey(const Key('pgft_table_field')),
        'ext_bad',
      );
      await tester.tap(find.byKey(const Key('pgft_opt_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pgft_opt_key_0')),
        'bad key;',
      );
      await tester.enterText(
        find.byKey(const Key('pgft_opt_value_0')),
        'v',
      );

      await tester.tap(find.byKey(const Key('pgft_create')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 校验拒绝：无预览门、零执行。
      expect(find.byType(DestructiveConfirmDialog), findsNothing);
      expect(executed, isEmpty);
      expect(audits, isEmpty);
    });
  });
}
