import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/organisms/connection/schema_diff/schema_diff_ddl_preview.dart';

/// SchemaDiffDdlPreview widget 测试：为选中对象生成的迁移 DDL。
void main() {
  testWidgets('无选中对象时显示空状态', (tester) async {
    await _pump(tester, const SchemaDiffDdlPreview());
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('Select an object to view its migration DDL'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('新增表生成 CREATE TABLE', (tester) async {
    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedTableDiff: TableDiff(
          name: 'users',
          type: DiffType.added,
          sourceCreateSql: 'CREATE TABLE users (id INT);',
        ),
      ),
    );
    expect(find.text('CREATE TABLE'), findsOneWidget);
  });

  testWidgets('删除表生成 DROP TABLE', (tester) async {
    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedTableDiff: TableDiff(name: 'users', type: DiffType.removed),
      ),
    );
    expect(find.text('DROP TABLE'), findsOneWidget);
  });

  testWidgets('修改表生成列与索引 DDL', (tester) async {
    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedTableDiff: TableDiff(
          name: 'users',
          type: DiffType.modified,
          columnDiffs: [
            ColumnDiff(
              name: 'email',
              type: DiffType.added,
              sourceColumn: DbColumn(name: 'email', type: 'VARCHAR(255)'),
            ),
            ColumnDiff(name: 'legacy', type: DiffType.removed),
          ],
          indexDiffs: [
            IndexDiff(
              name: 'idx_email',
              type: DiffType.added,
              sourceIndex: DbIndex(name: 'idx_email', columns: ['email']),
            ),
          ],
        ),
      ),
    );
    expect(find.text('ADD COLUMN'), findsOneWidget);
    expect(find.text('DROP COLUMN'), findsOneWidget);
    expect(find.text('CREATE INDEX'), findsOneWidget);
  });

  testWidgets('未变化的表显示 No DDL changes needed', (tester) async {
    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedTableDiff: TableDiff(name: 'users', type: DiffType.unchanged),
      ),
    );
    expect(find.text('No DDL changes needed'), findsOneWidget);
  });

  testWidgets('视图新增/删除 DDL', (tester) async {
    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedViewDiff: ViewDiff(
          name: 'v1',
          type: DiffType.added,
          createStatement: 'CREATE VIEW v1 AS SELECT 1',
        ),
      ),
    );
    expect(find.text('CREATE VIEW'), findsOneWidget);

    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedViewDiff: ViewDiff(name: 'v1', type: DiffType.removed),
      ),
    );
    expect(find.text('DROP VIEW'), findsOneWidget);
  });

  testWidgets('存储过程新增/删除 DDL', (tester) async {
    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedProcedureDiff: ProcedureDiff(
          name: 'p1',
          type: DiffType.added,
          createStatement: 'CREATE PROCEDURE p1() BEGIN END',
        ),
      ),
    );
    expect(find.text('CREATE PROCEDURE/FUNCTION'), findsOneWidget);

    await _pump(
      tester,
      SchemaDiffDdlPreview(
        selectedProcedureDiff: ProcedureDiff(name: 'p1', type: DiffType.removed),
      ),
    );
    expect(find.text('DROP PROCEDURE/FUNCTION'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}
