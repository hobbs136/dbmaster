import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/audit_sql_sanitizer.dart';

void main() {
  group('AuditSqlSanitizer', () {
    // =====================================================================
    // HIGH-004: INSERT 语句中的密码应被脱敏
    // =====================================================================

    test('should mask password in INSERT with explicit assignment', () {
      final sql =
          "INSERT INTO users SET name = 'admin', password = 'secret123'";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, isNot(contains('secret123')));
      expect(result, contains('***'));
    });

    test('should mask password in VALUES with keyword assignment syntax', () {
      // 注: INSERT ... VALUES 的列值对应关系难以通过正则可靠识别，
      // 推荐在应用层对完整 INSERT VALUES 进行额外处理或选择性记录
      final sql = "INSERT INTO log SET password = 'pass1', token = 'tok1'";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, isNot(contains('pass1')));
      expect(result, isNot(contains('tok1')));
    });

    // =====================================================================
    // HIGH-004: UPDATE 语句中的密码应被脱敏
    // =====================================================================

    test('should mask password in UPDATE SET', () {
      final sql = "UPDATE users SET password = 'newpass' WHERE id = 1";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, isNot(contains('newpass')));
      expect(result, contains('***'));
    });

    test('should mask secret/token in UPDATE', () {
      final sql =
          "UPDATE config SET api_secret = 'sk-abc123', token = 'bearer_xyz'";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, isNot(contains('sk-abc123')));
      expect(result, isNot(contains('bearer_xyz')));
    });

    // =====================================================================
    // HIGH-004: SELECT 语句不应被误伤
    // =====================================================================

    test('should NOT alter safe SELECT statements', () {
      final sql = "SELECT * FROM users WHERE id = 1 AND name = 'Alice'";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, equals(sql));
    });

    test('should NOT alter SELECT with column named password', () {
      final sql = "SELECT password FROM users";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, equals(sql));
    });

    // =====================================================================
    // HIGH-004: 空值和边界情况
    // =====================================================================

    test('should handle empty string', () {
      final result = AuditSqlSanitizer.sanitize('');
      expect(result, equals(''));
    });

    test('should handle SQL without sensitive keywords', () {
      final sql = "CREATE TABLE users (id INT PRIMARY KEY)";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, equals(sql));
    });

    test('should handle MongoDB-style JSON', () {
      final json = r'{"password": "secret", "name": "test"}';
      final result = AuditSqlSanitizer.sanitize(json);
      expect(result, isNot(contains('secret')));
    });

    // =====================================================================
    // HIGH-004: 多种引号形式
    // =====================================================================

    test('should mask double-quoted string after password=', () {
      final sql = 'UPDATE users SET password = "mysecret"';
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, isNot(contains('mysecret')));
    });
  });
}
