import 'package:dbmaster/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归测试：错误 SQL 回显的用户数据（含关键字如 "connection"）不得被误判为
/// "连接丢失"（曾导致普通 SQL 错误误触发 SQLite 连接断开）。
void main() {
  group('DatabaseService.isConnectionLostError', () {
    // 回归 —— 用户报告的真实错误（NOT NULL 约束违反 + INSERT 数据含
    // JSON key "connection"）。修复前（整串匹配 'connection'）会返回 true 并误断开。
    test('SQL error echoing "connection" in data is NOT connection-lost', () {
      const err =
          'Exception: 查询执行失败: SqfliteFfiException(sqlite_error: 1299, , '
          'SqliteException(1299): while executing, NOT NULL constraint failed: '
          'products.created_at, constraint failed (code 1299)\n'
          '  Causing statement: INSERT INTO "products" VALUES '
          "(..., '{\"connection\":\"蓝牙5.3\",\"storage\":\"256GB\"}', ...) "
          "sql 'INSERT INTO \"products\" ...' {details: {database: {path: "
          'test.db, id: 1, readOnly: false}}}';
      expect(DatabaseService.isConnectionLostError(err), isFalse);
    });

    test('SQL error echoing "closed"/"timeout"/"network" in data is NOT lost', () {
      const err =
          'SqliteException(1): near "x": syntax error\n'
          '  Causing statement: UPDATE logs SET network = 1, timeout = 5, '
          "status = 'closed' sql 'UPDATE logs SET ...' {details: {}}";
      expect(DatabaseService.isConnectionLostError(err), isFalse);
    });

    test('plain SQL error (no keywords) is NOT connection-lost', () {
      const err =
          'Exception: 查询执行失败: SqfliteFfiException(sqlite_error: 1, , '
          'SqliteException(1): near "SELEC": syntax error, SQL logic error '
          '(code 1)';
      expect(DatabaseService.isConnectionLostError(err), isFalse);
    });

    test('genuine connection errors ARE detected', () {
      expect(
        DatabaseService.isConnectionLostError('Connection refused'),
        isTrue,
      );
      expect(
        DatabaseService.isConnectionLostError(
          'Lost connection to MySQL server during query',
        ),
        isTrue,
      );
      expect(
        DatabaseService.isConnectionLostError('Connection reset by peer'),
        isTrue,
      );
      expect(
        DatabaseService.isConnectionLostError('broken pipe'),
        isTrue,
      );
      expect(
        DatabaseService.isConnectionLostError('Not connected to database'),
        isTrue,
      );
    });
  });
}
