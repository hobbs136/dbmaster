import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('DiffType', () {
    test('应有 4 个值', () {
      expect(DiffType.values.length, 4);
    });

    test('应包含所有预期值', () {
      expect(
        DiffType.values,
        containsAll([
          DiffType.added,
          DiffType.removed,
          DiffType.modified,
          DiffType.unchanged,
        ]),
      );
    });
  });

  group('TableDiff', () {
    test('hasChanges 应为 false 当所有无变化', () {
      final diff = TableDiff(
        name: 'users',
        type: DiffType.unchanged,
        columnDiffs: [ColumnDiff(name: 'id', type: DiffType.unchanged)],
        indexDiffs: [IndexDiff(name: 'pk_id', type: DiffType.unchanged)],
      );
      expect(diff.hasChanges, isFalse);
    });

    test('hasChanges 应为 true 当表类型变化', () {
      final diff = TableDiff(name: 'users', type: DiffType.added);
      expect(diff.hasChanges, isTrue);
    });

    test('hasChanges 应为 true 当有列变化', () {
      final diff = TableDiff(
        name: 'users',
        type: DiffType.unchanged,
        columnDiffs: [ColumnDiff(name: 'email', type: DiffType.added)],
      );
      expect(diff.hasChanges, isTrue);
    });

    test('hasChanges 应为 true 当有索引变化', () {
      final diff = TableDiff(
        name: 'users',
        type: DiffType.unchanged,
        indexDiffs: [IndexDiff(name: 'idx_email', type: DiffType.removed)],
      );
      expect(diff.hasChanges, isTrue);
    });

    test('changeCount 应统计所有变化', () {
      final diff = TableDiff(
        name: 'users',
        type: DiffType.modified,
        columnDiffs: [
          ColumnDiff(name: 'id', type: DiffType.unchanged),
          ColumnDiff(name: 'email', type: DiffType.added),
          ColumnDiff(name: 'age', type: DiffType.modified),
        ],
        indexDiffs: [
          IndexDiff(name: 'pk_id', type: DiffType.unchanged),
          IndexDiff(name: 'idx_email', type: DiffType.added),
        ],
      );
      // 1 (table) + 2 (columns) + 1 (index) = 4
      expect(diff.changeCount, 4);
    });
  });

  group('SchemaDiffReport', () {
    test('计数器应正确统计', () {
      final report = SchemaDiffReport(
        sourceConnection: 'src',
        targetConnection: 'tgt',
        sourceDatabase: 'db1',
        targetDatabase: 'db2',
        generatedAt: DateTime.now(),
        tableDiffs: [
          TableDiff(name: 't1', type: DiffType.added),
          TableDiff(name: 't2', type: DiffType.removed),
          TableDiff(name: 't3', type: DiffType.modified),
          TableDiff(name: 't4', type: DiffType.unchanged),
        ],
      );
      expect(report.addedTables, 1);
      expect(report.removedTables, 1);
      expect(report.modifiedTables, 1);
      expect(report.unchangedTables, 1);
      expect(report.totalTableChanges, 3);
    });

    test('hasChanges 应为 false 当无变化', () {
      final report = SchemaDiffReport(
        sourceConnection: 'src',
        targetConnection: 'tgt',
        sourceDatabase: 'db1',
        targetDatabase: 'db2',
        generatedAt: DateTime.now(),
      );
      expect(report.hasChanges, isFalse);
    });

    test('hasChanges 应为 true 当有视图变化', () {
      final report = SchemaDiffReport(
        sourceConnection: 'src',
        targetConnection: 'tgt',
        sourceDatabase: 'db1',
        targetDatabase: 'db2',
        generatedAt: DateTime.now(),
        viewDiffs: [ViewDiff(name: 'v1', type: DiffType.added)],
      );
      expect(report.hasChanges, isTrue);
    });

    test('totalColumnChanges 应统计所有列变化', () {
      final report = SchemaDiffReport(
        sourceConnection: 'src',
        targetConnection: 'tgt',
        sourceDatabase: 'db1',
        targetDatabase: 'db2',
        generatedAt: DateTime.now(),
        tableDiffs: [
          TableDiff(
            name: 't1',
            type: DiffType.unchanged,
            columnDiffs: [
              ColumnDiff(name: 'c1', type: DiffType.added),
              ColumnDiff(name: 'c2', type: DiffType.removed),
            ],
          ),
        ],
      );
      expect(report.totalColumnChanges, 2);
    });
  });

  group('SyncOperation', () {
    test('copyWith 应复制所有字段', () {
      final op = SyncOperation(
        id: 'op_1',
        description: 'Test',
        sql: 'SELECT 1',
        type: DiffType.added,
        targetTable: 'users',
      );
      final copy = op.copyWith();
      expect(copy.id, op.id);
      expect(copy.description, op.description);
      expect(copy.sql, op.sql);
      expect(copy.isExecuted, op.isExecuted);
    });

    test('copyWith 应允许覆盖字段', () {
      final op = SyncOperation(
        id: 'op_1',
        description: 'Test',
        sql: 'SELECT 1',
        type: DiffType.added,
        targetTable: 'users',
      );
      final copy = op.copyWith(isExecuted: true, error: 'failed');
      expect(copy.isExecuted, isTrue);
      expect(copy.error, 'failed');
      expect(copy.id, op.id); // 未覆盖的字段保持不变
    });
  });

  group('SyncPlan', () {
    test('空计划应正确计算', () {
      final plan = SyncPlan(
        sourceSnapshot: 'src/db',
        targetSnapshot: 'tgt/db',
        operations: [],
      );
      expect(plan.totalOperations, 0);
      expect(plan.executedCount, 0);
      expect(plan.failedCount, 0);
      expect(plan.isComplete, isTrue);
    });

    test('应统计已执行操作', () {
      final plan = SyncPlan(
        sourceSnapshot: 'src/db',
        targetSnapshot: 'tgt/db',
        operations: [
          SyncOperation(
            id: 'op_1',
            description: 'D1',
            sql: 'S1',
            type: DiffType.added,
            targetTable: 't1',
            isExecuted: true,
          ),
          SyncOperation(
            id: 'op_2',
            description: 'D2',
            sql: 'S2',
            type: DiffType.added,
            targetTable: 't2',
          ),
        ],
      );
      expect(plan.totalOperations, 2);
      expect(plan.executedCount, 1);
      expect(plan.isComplete, isFalse);
    });

    test('应统计失败操作', () {
      final plan = SyncPlan(
        sourceSnapshot: 'src/db',
        targetSnapshot: 'tgt/db',
        operations: [
          SyncOperation(
            id: 'op_1',
            description: 'D1',
            sql: 'S1',
            type: DiffType.added,
            targetTable: 't1',
            error: 'Syntax error',
          ),
        ],
      );
      expect(plan.failedCount, 1);
      expect(plan.hasAllAttempted, isTrue);
    });
  });

  group('SchemaSnapshot', () {
    test('toJson/fromJson 应正确序列化', () {
      final snapshot = SchemaSnapshot(
        connectionId: 'conn1',
        connectionName: 'MySQL Local',
        databaseName: 'test_db',
        capturedAt: DateTime(2024, 1, 15, 10, 30),
        tables: [
          DbTable(
            name: 'users',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
              DbColumn(name: 'name', type: 'VARCHAR(50)', isNullable: true),
            ],
            indexes: [
              DbIndex(name: 'pk_users', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        views: ['active_users'],
        procedures: ['get_user_count'],
        createStatements: {'users': 'CREATE TABLE users (id INT PRIMARY KEY)'},
        captureErrors: [],
      );

      final json = snapshot.toJson();
      final restored = SchemaSnapshot.fromJson(json);

      expect(restored.connectionId, snapshot.connectionId);
      expect(restored.connectionName, snapshot.connectionName);
      expect(restored.databaseName, snapshot.databaseName);
      expect(restored.tables.length, 1);
      expect(restored.tables.first.name, 'users');
      expect(restored.tables.first.columns.length, 2);
      expect(restored.tables.first.columns.first.name, 'id');
      expect(restored.tables.first.indexes.first.name, 'pk_users');
      expect(restored.views, ['active_users']);
      expect(restored.procedures, ['get_user_count']);
    });

    test('fromJson 应处理空列表', () {
      final json = {
        'connectionId': 'c1',
        'connectionName': 'Test',
        'databaseName': 'db',
        'capturedAt': '2024-01-15T10:30:00.000Z',
        'tables': [],
      };
      final snapshot = SchemaSnapshot.fromJson(json);
      expect(snapshot.tables, isEmpty);
      expect(snapshot.views, isEmpty);
      expect(snapshot.procedures, isEmpty);
    });
  });
}
