import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/theme/design_system.dart';

List<Map<String, dynamic>> _rows(int count) =>
    List.generate(count, (i) => <String, dynamic>{'id': i, 'name': 'row_$i'});

void main() {
  group('WorkbenchSqlCardPayload', () {
    test('toJson → fromJson 往返一致', () {
      const payload = WorkbenchSqlCardPayload(
        sql: 'SELECT * FROM users',
        statementType: 'SELECT',
        isWrite: false,
        connectionId: 'conn_1',
        databaseName: 'db_1',
      );

      final restored = WorkbenchSqlCardPayload.fromJson(payload.toJson());

      expect(restored, isNotNull);
      expect(restored!.sql, payload.sql);
      expect(restored.statementType, payload.statementType);
      expect(restored.isWrite, payload.isWrite);
      expect(restored.connectionId, payload.connectionId);
      expect(restored.databaseName, payload.databaseName);
    });

    test('kind 值为对外锁定键名 sql_card', () {
      expect(WorkbenchSqlCardPayload.kind, 'sql_card');
      expect(
        WorkbenchSqlCardPayload.fromJson({
          'kind': WorkbenchSqlCardPayload.kind,
        }),
        isNull,
        reason: 'kind 匹配但缺关键字段 → null（不抛异常）',
      );
    });

    test('fromJson 对 kind 不匹配返回 null（分发防串）', () {
      expect(WorkbenchSqlCardPayload.fromJson({'kind': 'result_card'}), isNull);
      expect(WorkbenchSqlCardPayload.fromJson({'sql': 'x'}), isNull);
    });

    test('fromJson 关键字段畸形返回 null，未知键忽略（C-2 向前兼容）', () {
      final restored = WorkbenchSqlCardPayload.fromJson({
        'kind': 'sql_card',
        'sql': 'DELETE FROM t',
        'statementType': 'DELETE',
        'isWrite': true,
        'approval': {'state': 'pending'}, // C-2：M2 未知键不报错
      });

      expect(restored, isNotNull);
      expect(restored!.isWrite, isTrue);
      expect(
        WorkbenchSqlCardPayload.fromJson({
          'kind': 'sql_card',
          'statementType': 'SELECT',
        }),
        isNull,
        reason: '缺 sql 视为无效',
      );
    });
  });

  group('WorkbenchResultCardPayload 快照 ≤ N（take 语义）', () {
    test('行数超过 N 时快照截断到 toolCardSnapshotRows，isTruncated 为真', () {
      final rows = _rows(50);
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT * FROM big_table',
        rowCount: 50,
        durationMs: 42,
        columns: const ['id', 'name'],
        rows: rows,
      );

      expect(
        payload.snapshotRows.length,
        AppDesignSystem.toolCardSnapshotRows,
        reason: '快照上限唯一来源 = toolCardSnapshotRows 常量',
      );
      expect(payload.rowCount, 50, reason: '完整行数 M 保留');
      expect(payload.isTruncated, isTrue);
      expect(payload.isEmpty, isFalse);
    });

    test('行数 ≤ N 时全量入快照，无截断提示', () {
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT 1',
        rowCount: 5,
        durationMs: 3,
        columns: const ['id'],
        rows: _rows(5),
      );

      expect(payload.snapshotRows.length, 5);
      expect(payload.isTruncated, isFalse);
    });

    test('0 行 → isEmpty 空态（AC5.6）', () {
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT * FROM empty_table',
        rowCount: 0,
        durationMs: 12,
        columns: const ['id'],
        rows: const [],
      );

      expect(payload.isEmpty, isTrue);
      expect(payload.snapshotRows, isEmpty);
      expect(payload.isTruncated, isFalse);
    });

    test('take 保留行 Map 原引用（不复制值）', () {
      final rows = _rows(AppDesignSystem.toolCardSnapshotRows + 5);
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT * FROM t',
        rowCount: rows.length,
        durationMs: 1,
        columns: const ['id', 'name'],
        rows: rows,
      );

      for (var i = 0; i < payload.snapshotRows.length; i++) {
        expect(
          identical(payload.snapshotRows[i], rows[i]),
          isTrue,
          reason: '第 $i 行应为执行结果原引用',
        );
      }
    });

    test('rowCount 与 rows.length 不一致时以 rowCount 判定截断', () {
      // 调用方只传部分行（如流式分页场景）：M=100、行=10 → 快照 10、截断为真。
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT * FROM t',
        rowCount: 100,
        durationMs: 1,
        columns: const ['id'],
        rows: _rows(10),
      );

      expect(payload.snapshotRows.length, 10);
      expect(payload.isTruncated, isTrue);
    });
  });

  group('WorkbenchResultCardPayload 往返一致', () {
    test('toJson → fromJson 字段逐一一致（含 columnTypes）', () {
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT id, name FROM users',
        rowCount: 2,
        durationMs: 42,
        columns: const ['id', 'name'],
        rows: _rows(2),
        columnTypes: const {'id': 'INT', 'name': 'VARCHAR'},
      );

      final restored = WorkbenchResultCardPayload.fromJson(payload.toJson());

      expect(restored, isNotNull);
      expect(restored!.sql, payload.sql);
      expect(restored.rowCount, 2);
      expect(restored.durationMs, 42);
      expect(restored.columns, ['id', 'name']);
      expect(restored.snapshotRows, [
        {'id': 0, 'name': 'row_0'},
        {'id': 1, 'name': 'row_1'},
      ]);
      expect(restored.columnTypes, {'id': 'INT', 'name': 'VARCHAR'});
      expect(restored.isTruncated, isFalse);
      expect(restored.isEmpty, isFalse);
    });

    test('columnTypes 为 null 时可往返且不出现该键', () {
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT 1',
        rowCount: 1,
        durationMs: 1,
        columns: const ['1'],
        rows: [
          {'1': 1},
        ],
      );

      final json = payload.toJson();
      expect(json.containsKey('columnTypes'), isFalse);

      final restored = WorkbenchResultCardPayload.fromJson(json);
      expect(restored!.columnTypes, isNull);
    });

    test('截断卡往返后 isTruncated/rowCount 保留', () {
      final payload = WorkbenchResultCardPayload(
        sql: 'SELECT * FROM big',
        rowCount: 50,
        durationMs: 42,
        columns: const ['id', 'name'],
        rows: _rows(50),
      );

      final restored = WorkbenchResultCardPayload.fromJson(payload.toJson());

      expect(restored!.rowCount, 50);
      expect(
        restored.snapshotRows.length,
        AppDesignSystem.toolCardSnapshotRows,
      );
      expect(restored.isTruncated, isTrue);
    });

    test('fromJson 对 kind 不匹配 / 关键字段畸形返回 null', () {
      expect(WorkbenchResultCardPayload.fromJson({'kind': 'sql_card'}), isNull);
      expect(
        WorkbenchResultCardPayload.fromJson({
          'kind': 'result_card',
          'rowCount': 1,
          'durationMs': 1,
        }),
        isNull,
        reason: '缺 sql 视为无效',
      );
    });

    test('历史快照按落盘原样恢复，不做 N 再裁剪（AC2.2 当初快照）', () {
      // 模拟旧会话文件：写入时 N 更大（探针复跑后常量可能变小）。
      final legacyRows = _rows(AppDesignSystem.toolCardSnapshotRows + 5);
      final legacyJson = <String, dynamic>{
        'kind': WorkbenchResultCardPayload.kind,
        'sql': 'SELECT * FROM t',
        'rowCount': legacyRows.length,
        'durationMs': 10,
        'columns': ['id', 'name'],
        'snapshotRows': legacyRows,
        'isTruncated': false,
        'isEmpty': false,
      };

      final restored = WorkbenchResultCardPayload.fromJson(legacyJson);

      expect(
        restored!.snapshotRows.length,
        legacyRows.length,
        reason: '历史卡片所见 = 当初快照，读取侧不再按当前 N 裁剪',
      );
      expect(restored.isTruncated, isFalse, reason: '落盘标记按原样恢复，不按当前 N 重算');
    });
  });

  group('WorkbenchCardKind 枚举面（design §4.4 契约预留）', () {
    test('两值齐备', () {
      expect(
        WorkbenchCardKind.values,
        containsAll([WorkbenchCardKind.sqlCard, WorkbenchCardKind.resultCard]),
      );
    });
  });
}
