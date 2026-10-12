// T14（J1-a）· 行级编辑 dialog widget 测试（任务书验收标准①）：
// 表单预填 / PK 只读 / 零变更确认钮禁用 / 预览 SQL 与执行 SQL 逐字一致
// （同一生成函数断言）/ 确认门取消 = 零执行（执行计数）/ 审计成功与失败
// 两态断言（mock 接缝）/ 影响 0 行 = 行已不存在 / 二进制列只读不进 SET /
// NULL 置位 / 数字非法输入阻断。
//
// 真库全链路（MySQL 8 + PG 17：写回断言/仅该行变化/取消前后一致/无 PK 表
// 与手写 SQL 网格不开放/readonly 禁用）在
// integration_test/mysql_row_edit_writeback_e2e_test.dart。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/results/row_edit_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  // MySQL 转义感知的字符串字面量剥离器（负测试断言面）：把 '...' 串内容
  // 挖空（处理 `\x` 跳读与 `''` 双写），留下的骨架若不含注入 token，即证明
  // 注入文本全部仍是字符串数据。
  String stripMySqlStringLiterals(String sql) {
    final out = StringBuffer();
    var i = 0;
    while (i < sql.length) {
      if (sql[i] == "'") {
        out.write("''");
        i++;
        while (i < sql.length) {
          if (sql[i] == r'\') {
            i += 2; // `\x` 转义对：内容整体跳过
            continue;
          }
          if (sql[i] == "'") {
            if (i + 1 < sql.length && sql[i + 1] == "'") {
              i += 2; // '' 双写引号：仍是内容
              continue;
            }
            break; // 收尾引号
          }
          i++;
        }
        i++; // 越过收尾引号
        continue;
      }
      out.write(sql[i]);
      i++;
    }
    return out.toString();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testColumns = <DbColumn>[
    DbColumn(name: 'id', type: 'int', isPrimaryKey: true, isNullable: false),
    DbColumn(name: 'name', type: 'varchar(100)', isNullable: false),
    DbColumn(name: 'age', type: 'int', isNullable: true),
  ];
  final testRow = <String, dynamic>{'id': 1, 'name': 'Alice', 'age': 30};

  /// UPDATE 期望串（与 dialog 内同一生成函数产出对照——铁律①断言面）。
  String expectedUpdate(Map<String, RowEditCellValue> changed) =>
      buildRowUpdateSql(
        qualifiedTableName: 'users',
        databaseType: DatabaseType.mysql,
        tableColumns: testColumns,
        rowValues: testRow,
        changedValues: changed,
      );

  Future<void> pumpDialog(
    WidgetTester tester, {
    RowEditExecutor? execute,
    RowEditAuditor? audit,
    List<DbColumn>? columns,
    Map<String, dynamic>? rowValues,
  }) async {
    // _confirm 执行段读 AppProvider（接缝注入后仅作 provider 存在性依赖）；
    // dialog 路由挂在 Navigator 之下 → provider 必须在 MaterialApp 之上。
    final home = Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => RowEditDialog(
            connectionId: 'conn1',
            databaseName: 'testdb',
            qualifiedTableName: 'users',
            tableColumns: columns ?? testColumns,
            rowValues: rowValues ?? testRow,
            databaseType: DatabaseType.mysql,
            execute: execute,
            audit: audit,
          ),
        ),
        child: const Text('Open'),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: AppProvider(),
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

  Future<void> changeNameTo(WidgetTester tester, String value) async {
    await tester.enterText(find.widgetWithText(TextField, 'Alice'), value);
    await tester.pumpAndSettle();
  }

  group('buildRowUpdateSql（纯函数）', () {
    test('MySQL 方言：反引号标识符 + 字符串转义 + 单 PK WHERE', () {
      final sql = buildRowUpdateSql(
        qualifiedTableName: 'users',
        databaseType: DatabaseType.mysql,
        tableColumns: testColumns,
        rowValues: testRow,
        changedValues: {
          'name': const RowEditCellValue("O'Brien"),
          'age': const RowEditCellValue('31'),
        },
      );
      expect(
        sql,
        "UPDATE `users` SET `name` = 'O''Brien', `age` = 31 WHERE `id` = 1",
      );
    });

    test('PG 方言：双引号标识符；schema 限定表名逐段转义', () {
      final sql = buildRowUpdateSql(
        qualifiedTableName: 'public.users',
        databaseType: DatabaseType.postgresql,
        tableColumns: testColumns,
        rowValues: testRow,
        changedValues: {'name': const RowEditCellValue('Bob')},
      );
      expect(
        sql,
        'UPDATE "public"."users" SET "name" = \'Bob\' WHERE "id" = 1',
      );
    });

    // ── R1-P1（注入面修复）：MySQL 族字符串字面量反斜杠双写 ──────────

    test('MySQL 方言：含反斜杠值 → 反斜杠双写 + 引号双写', () {
      final sql = buildRowUpdateSql(
        qualifiedTableName: 'users',
        databaseType: DatabaseType.mysql,
        tableColumns: [
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
          DbColumn(name: 'memo', type: 'varchar(100)'),
        ],
        rowValues: {'id': 1, 'memo': r'old\val'},
        changedValues: {'memo': const RowEditCellValue(r"a\b'c")},
      );
      // `\` → `\\`、`'` → `''`（先反斜杠后引号）。
      expect(
        sql,
        r"UPDATE `users` SET `memo` = 'a\\b''c' WHERE `id` = 1",
      );
    });

    test('MySQL 方言：PK WHERE 字符串值含反斜杠同样双写', () {
      final sql = buildRowUpdateSql(
        qualifiedTableName: 'users',
        databaseType: DatabaseType.mysql,
        tableColumns: [
          DbColumn(name: 'path', type: 'varchar(100)', isPrimaryKey: true),
          DbColumn(name: 'memo', type: 'varchar(100)'),
        ],
        rowValues: {'path': r'p\1', 'memo': 'x'},
        changedValues: {'memo': const RowEditCellValue('y')},
      );
      expect(sql, r"UPDATE `users` SET `memo` = 'y' WHERE `path` = 'p\\1'");
    });

    test('MySQL 方言：尾随反斜杠注入负测试——注入文本保持为数据', () {
      // 经典尾随反斜杠注入：值尾 `\'` 会把 naive 转义下的收尾引号吞进数据，
      // `, is_admin=1` 升格为 SQL 结构。修复后必须整体仍是字符串数据。
      final malicious = r"\', is_admin=1, c2='abc";
      final sql = buildRowUpdateSql(
        qualifiedTableName: 'users',
        databaseType: DatabaseType.mysql,
        tableColumns: [
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
          DbColumn(name: 'memo', type: 'varchar(200)'),
        ],
        rowValues: {'id': 1, 'memo': 'old'},
        changedValues: {'memo': RowEditCellValue(malicious)},
      );
      // 生成串逐字断言：值内 `'` 全部双写、`\` 双写，注入文本在引号内
      //（值以未闭合的 `c2='abc` 结尾——正是注入形态）。
      expect(
        sql,
        "UPDATE `users` SET `memo` = "
        "'\\\\'', is_admin=1, c2=''abc' WHERE `id` = 1",
      );
      // 结构断言：剥离字符串字面量（MySQL 转义感知）后，语句骨架不含任何
      // 注入 token——`, is_admin=1` 等只能留在串内（= 数据）。
      expect(
        stripMySqlStringLiterals(sql),
        "UPDATE `users` SET `memo` = '' WHERE `id` = 1",
      );
    });

    test('MySQL 族成员（doris/mariadb/tidb/oceanbase/starrocks）同 mysql 双写', () {
      for (final type in {
        DatabaseType.doris,
        DatabaseType.mariadb,
        DatabaseType.tidb,
        DatabaseType.oceanbase,
        DatabaseType.starrocks,
      }) {
        final sql = buildRowUpdateSql(
          qualifiedTableName: 't',
          databaseType: type,
          tableColumns: [
            DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
            DbColumn(name: 'memo', type: 'varchar(100)'),
          ],
          rowValues: {'id': 1, 'memo': 'x'},
          changedValues: {'memo': const RowEditCellValue('a\\')},
        );
        expect(
          sql,
          r"UPDATE `t` SET `memo` = 'a\\' WHERE `id` = 1",
          reason: '$type',
        );
      }
    });

    test('PG/SQLite 方言：反斜杠保持原样（仅引号双写，不回归）', () {
      // 字符串字面量口径两方言一致：反斜杠非串转义字符，只双写引号。
      // （表名标识符引号沿 canonical escapeQualifiedIdentifier：PG 双引号、
      // SQLite 落 default 反引号分支——SQLite 引擎接受反引号标识符。）
      final pg = buildRowUpdateSql(
        qualifiedTableName: 't',
        databaseType: DatabaseType.postgresql,
        tableColumns: [
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
          DbColumn(name: 'memo', type: 'text'),
        ],
        rowValues: {'id': 1, 'memo': 'x'},
        changedValues: {'memo': const RowEditCellValue(r"a\b'c")},
      );
      expect(pg, 'UPDATE "t" SET "memo" = \'a\\b\'\'c\' WHERE "id" = 1');

      final sqlite = buildRowUpdateSql(
        qualifiedTableName: 't',
        databaseType: DatabaseType.sqlite,
        tableColumns: [
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
          DbColumn(name: 'memo', type: 'text'),
        ],
        rowValues: {'id': 1, 'memo': 'x'},
        changedValues: {'memo': const RowEditCellValue(r"a\b'c")},
      );
      expect(
        sqlite,
        'UPDATE `t` SET "memo" = \'a\\b\'\'c\' WHERE "id" = 1',
      );
    });

    test('多 PK WHERE 以 AND 串联；布尔值归一 TRUE/FALSE', () {
      final cols = <DbColumn>[
        DbColumn(name: 'tenant', type: 'varchar(10)', isPrimaryKey: true),
        DbColumn(name: 'active', type: 'boolean', isPrimaryKey: true),
        DbColumn(name: 'score', type: 'int'),
      ];
      final row = <String, dynamic>{'tenant': 'a', 'active': true, 'score': 5};
      final sql = buildRowUpdateSql(
        qualifiedTableName: 't',
        databaseType: DatabaseType.mysql,
        tableColumns: cols,
        rowValues: row,
        changedValues: {'score': const RowEditCellValue('6')},
      );
      expect(
        sql,
        "UPDATE `t` SET `score` = 6 WHERE `tenant` = 'a' "
        "AND `active` = TRUE",
      );
    });

    test('SET 为空 = StateError（零变更不生成）', () {
      expect(
        () => buildRowUpdateSql(
          qualifiedTableName: 'users',
          databaseType: DatabaseType.mysql,
          tableColumns: testColumns,
          rowValues: testRow,
          changedValues: const {},
        ),
        throwsStateError,
      );
    });

    test('PK 原值为 null = StateError（入口应已禁用）', () {
      expect(
        () => buildRowUpdateSql(
          qualifiedTableName: 'users',
          databaseType: DatabaseType.mysql,
          tableColumns: testColumns,
          rowValues: {'id': null, 'name': 'x', 'age': 1},
          changedValues: {'name': const RowEditCellValue('y')},
        ),
        throwsStateError,
      );
    });

    test('未识别类型列进 SET = StateError（fail-closed）', () {
      expect(
        () => buildRowUpdateSql(
          qualifiedTableName: 'users',
          databaseType: DatabaseType.mysql,
          tableColumns: [
            DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
            DbColumn(name: 'payload', type: 'somefuturetype'),
          ],
          rowValues: {'id': 1, 'payload': 'x'},
          changedValues: {'payload': const RowEditCellValue('y')},
        ),
        throwsStateError,
      );
    });

    test('rowEditFieldKindFor：二进制/未知 fail-closed，常见类型可编辑', () {
      expect(rowEditFieldKindFor('BLOB'), RowEditFieldKind.readonlyLiteral);
      expect(
        rowEditFieldKindFor('varbinary(16)'),
        RowEditFieldKind.readonlyLiteral,
      );
      expect(rowEditFieldKindFor('bytea'), RowEditFieldKind.readonlyLiteral);
      expect(rowEditFieldKindFor('geometry'), RowEditFieldKind.readonlyLiteral);
      expect(
        rowEditFieldKindFor('totally_unknown'),
        RowEditFieldKind.readonlyLiteral,
      );
      expect(rowEditFieldKindFor('varchar(100)'), RowEditFieldKind.text);
      expect(rowEditFieldKindFor('double precision'), RowEditFieldKind.number);
      expect(rowEditFieldKindFor('timestamp'), RowEditFieldKind.text);
      expect(rowEditFieldKindFor('jsonb'), RowEditFieldKind.text);
      expect(rowEditFieldKindFor('boolean'), RowEditFieldKind.boolean);
    });
  });

  testWidgets('表单预填 + PK 列只读 + 零变更 Save 禁用与提示', (tester) async {
    await pumpDialog(
      tester,
      execute: (_, _, _, _) async => 1,
      audit: (_) async {},
    );

    expect(find.text('Edit Row — users'), findsOneWidget);
    // 预填：name/age 可编辑字段带原值。
    expect(find.widgetWithText(TextField, 'Alice'), findsOneWidget);
    expect(find.widgetWithText(TextField, '30'), findsOneWidget);
    // PK 列只读（enabled=false）。
    final pkField = tester.widget<TextField>(
      find.widgetWithText(TextField, '1'),
    );
    expect(pkField.enabled, isFalse, reason: 'PK 列必须只读展示');
    // 零变更：Save 禁用 + 提示文案。
    expect(find.text('No changes to save'), findsOneWidget);
    final save = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('预览 SQL 与执行 SQL 逐字一致（同一生成函数 + 执行捕获对照）', (tester) async {
    final executed = <String>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, sql) async {
        executed.add(sql);
        return 1;
      },
      audit: (_) async {},
    );

    await changeNameTo(tester, 'Bob');
    final expected = expectedUpdate({'name': const RowEditCellValue('Bob')});

    // 表单预览区即展示最终 SQL。
    expect(find.text(expected), findsOneWidget);

    // Save → 确认门（同一 SQL 展示）→ Confirm → 执行。
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    // 'UPDATE Preview' 两处：表单预览区小标题 + 确认门标题（同一 key 复用）。
    expect(find.text('UPDATE Preview'), findsWidgets);
    expect(
      find.text(expected),
      findsWidgets,
      reason: '确认门 extraContent 与表单预览同串',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(executed, [expected], reason: '执行 SQL 与预览 SQL 逐字一致（铁律①）');
  });

  testWidgets('确认门取消 = 零执行零审计（执行计数）', (tester) async {
    final executed = <String>[];
    final audits = <RowEditAuditRecord>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, sql) async {
        executed.add(sql);
        return 1;
      },
      audit: (r) async => audits.add(r),
    );

    await changeNameTo(tester, 'Bob');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();

    expect(executed, isEmpty, reason: '取消确认门后不得有任何执行');
    expect(audits, isEmpty, reason: '取消路径不落审计');
    // 表单仍在（可继续编辑或再取消）。
    expect(find.text('Edit Row — users'), findsOneWidget);
  });

  testWidgets('执行成功：审计成功落账 + dialog 关闭', (tester) async {
    final audits = <RowEditAuditRecord>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, _) async => 1,
      audit: (r) async => audits.add(r),
    );

    await changeNameTo(tester, 'Bob');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(audits, hasLength(1));
    expect(audits.first.success, isTrue);
    expect(
      audits.first.sql,
      expectedUpdate({'name': const RowEditCellValue('Bob')}),
    );
    expect(audits.first.connectionId, 'conn1');
    expect(find.text('Edit Row — users'), findsNothing, reason: '成功后关窗');
  });

  testWidgets('执行失败：错误态 + 引擎错误原文 + 审计失败落账 + 不关窗', (tester) async {
    final audits = <RowEditAuditRecord>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, _) async => throw Exception('Deadlock found'),
      audit: (r) async => audits.add(r),
    );

    await changeNameTo(tester, 'Bob');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(audits, hasLength(1));
    expect(audits.first.success, isFalse);
    expect(audits.first.errorMessage, contains('Deadlock'));
    expect(find.text('Update failed'), findsOneWidget);
    expect(find.textContaining('Deadlock found'), findsOneWidget);
    expect(find.text('Edit Row — users'), findsOneWidget, reason: '失败不关窗（可重试）');
  });

  testWidgets('影响 0 行 = 行已不存在（审计照落、不关窗）', (tester) async {
    final audits = <RowEditAuditRecord>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, _) async => 0,
      audit: (r) async => audits.add(r),
    );

    await changeNameTo(tester, 'Bob');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(audits.first.success, isTrue, reason: '语句成功（影响 0 行）审计照落');
    expect(find.text('The row no longer exists'), findsOneWidget);
    expect(find.text('Edit Row — users'), findsOneWidget);
  });

  testWidgets('二进制/未知类型列：只读展示 + 不进 SET + 顶部说明', (tester) async {
    final executed = <String>[];
    final columns = <DbColumn>[
      ...testColumns,
      DbColumn(name: 'avatar', type: 'blob'),
    ];
    await pumpDialog(
      tester,
      execute: (_, _, _, sql) async {
        executed.add(sql);
        return 1;
      },
      audit: (_) async {},
      columns: columns,
      rowValues: {...testRow, 'avatar': '<bytes>'},
    );

    expect(
      find.textContaining('Binary or unknown-type columns are read-only'),
      findsWidgets,
    );
    final blobField = tester.widget<TextField>(
      find.widgetWithText(TextField, '<bytes>'),
    );
    expect(blobField.enabled, isFalse);

    await changeNameTo(tester, 'Bob');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(executed.single, isNot(contains('avatar')), reason: '二进制列不进 SET');
  });

  testWidgets('NULL 置位：可空列勾选 NULL → SET 该列 = NULL', (tester) async {
    final executed = <String>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, sql) async {
        executed.add(sql);
        return 1;
      },
      audit: (_) async {},
    );

    // age 可空 → 勾选 NULL 置位。
    await tester.tap(find.text('NULL'));
    await tester.pumpAndSettle();

    final expected = expectedUpdate({'age': const RowEditCellValue.sqlNull()});
    expect(find.text(expected), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(executed, [expected]);
    expect(executed.single, contains('`age` = NULL'));
  });

  testWidgets('数字列非法输入：Save 禁用 + 告警行（列名）', (tester) async {
    final executed = <String>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, sql) async {
        executed.add(sql);
        return 1;
      },
      audit: (_) async {},
    );

    await tester.enterText(find.widgetWithText(TextField, '30'), 'abc');
    await tester.pumpAndSettle();

    expect(find.textContaining('Warning: age'), findsOneWidget);
    final save = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save'),
    );
    expect(save.onPressed, isNull, reason: '非法输入不得进预览与执行');
    expect(find.textContaining('UPDATE'), findsNothing);
    expect(executed, isEmpty);
  });

  testWidgets('审计写失败不阻塞 UI（AppLogger 吞掉，执行结果照常展示）', (tester) async {
    final executed = <String>[];
    await pumpDialog(
      tester,
      execute: (_, _, _, sql) async {
        executed.add(sql);
        return 1;
      },
      audit: (_) async => throw Exception('prefs broken'),
    );

    await changeNameTo(tester, 'Bob');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(executed, hasLength(1));
    expect(find.text('Edit Row — users'), findsNothing, reason: '审计失败不影响成功关窗');
  });
}
