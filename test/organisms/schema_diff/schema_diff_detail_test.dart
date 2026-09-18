import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/organisms/connection/schema_diff/schema_diff_detail.dart';

/// SchemaDiffDetail widget 测试：空状态 / 表 / 视图 / 存储过程 / 未找到。
void main() {
  testWidgets('selectedObjectKey 为 null 时显示空状态', (tester) async {
    await _pump(tester, SchemaDiffDetail(report: _report(), selectedObjectKey: null));
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('Select an object from the tree'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('选中表时显示列差异与 DDL 对比', (tester) async {
    await _pump(tester, SchemaDiffDetail(report: _report(), selectedObjectKey: 'table:users'));
    expect(find.text('users'), findsWidgets);
    expect(find.text('Columns'), findsOneWidget);
    expect(find.text('email'), findsOneWidget);
    expect(find.text('DDL Comparison'), findsOneWidget);
  });

  testWidgets('选中不存在的表时显示 not found', (tester) async {
    await _pump(tester, SchemaDiffDetail(report: _report(), selectedObjectKey: 'table:missing'));
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('not found in diff report'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('选中视图时显示 CREATE VIEW', (tester) async {
    await _pump(tester, SchemaDiffDetail(report: _report(), selectedObjectKey: 'view:v1'));
    expect(find.text('CREATE VIEW'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is SelectableText && (w.data ?? '').contains('SELECT 1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('选中存储过程时显示 CREATE STATEMENT', (tester) async {
    await _pump(tester, SchemaDiffDetail(report: _report(), selectedObjectKey: 'proc:p1'));
    expect(find.text('CREATE STATEMENT'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

SchemaDiffReport _report() => SchemaDiffReport(
      sourceConnection: 's',
      targetConnection: 't',
      sourceDatabase: 'src',
      targetDatabase: 'tgt',
      generatedAt: DateTime(2024, 1, 1),
      tableDiffs: [
        TableDiff(
          name: 'users',
          type: DiffType.modified,
          columnDiffs: [
            ColumnDiff(
              name: 'email',
              type: DiffType.added,
              sourceColumn: DbColumn(name: 'email', type: 'VARCHAR(255)'),
            ),
          ],
          sourceCreateSql: 'CREATE TABLE users (id INT);',
          targetCreateSql: 'CREATE TABLE users (id INT, email VARCHAR(255));',
        ),
      ],
      viewDiffs: [
        ViewDiff(
          name: 'v1',
          type: DiffType.added,
          createStatement: 'CREATE VIEW v1 AS SELECT 1',
        ),
      ],
      procedureDiffs: [
        ProcedureDiff(
          name: 'p1',
          type: DiffType.added,
          createStatement: 'CREATE PROCEDURE p1() BEGIN END',
        ),
      ],
    );
