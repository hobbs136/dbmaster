import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/audit_sql_sanitizer.dart';

void main() {
  group('AuditSqlSanitizer', () {
    test('returns empty string for empty input', () {
      expect(AuditSqlSanitizer.sanitize(''), equals(''));
    });

    test('masks password in single quotes', () {
      const sql = "SET PASSWORD = 'secret123'";
      expect(AuditSqlSanitizer.sanitize(sql), equals("SET PASSWORD = '***'"));
    });

    test('masks password in double quotes', () {
      const sql = 'SET PASSWORD = "secret123"';
      expect(AuditSqlSanitizer.sanitize(sql), equals('SET PASSWORD = "***"'));
    });

    test('masks secret keyword with equals', () {
      const sql = "UPDATE config SET secret = 'my-api-secret'";
      expect(
        AuditSqlSanitizer.sanitize(sql),
        equals("UPDATE config SET secret = '***'"),
      );
    });

    test('masks token keyword with equals', () {
      const sql = "UPDATE users SET token = 'bearer-xyz'";
      expect(
        AuditSqlSanitizer.sanitize(sql),
        equals("UPDATE users SET token = '***'"),
      );
    });

    test('masks api_key keyword with equals', () {
      const sql = "UPDATE settings SET api_key = 'key-12345'";
      expect(
        AuditSqlSanitizer.sanitize(sql),
        equals("UPDATE settings SET api_key = '***'"),
      );
    });

    test('masks apikey keyword (no underscore) with equals', () {
      const sql = "SET apikey = 'value'";
      expect(AuditSqlSanitizer.sanitize(sql), equals("SET apikey = '***'"));
    });

    test('masks api_secret keyword with equals', () {
      const sql = "SET api_secret = 'shh'";
      expect(AuditSqlSanitizer.sanitize(sql), equals("SET api_secret = '***'"));
    });

    test('masks auth keyword with equals', () {
      const sql = "SET auth = 'basic-auth-value'";
      expect(AuditSqlSanitizer.sanitize(sql), equals("SET auth = '***'"));
    });

    test('masks credential keyword with equals', () {
      const sql = "SET credential = 'admin-pass'";
      expect(AuditSqlSanitizer.sanitize(sql), equals("SET credential = '***'"));
    });

    test('masks JSON style double quote value', () {
      const sql = '{"password": "secret", "user": "admin"}';
      expect(
        AuditSqlSanitizer.sanitize(sql),
        equals('{"password": "***", "user": "admin"}'),
      );
    });

    test('masks JSON style single quote value', () {
      const sql = "{\"password\": 'secret', \"user\": 'admin'}";
      expect(
        AuditSqlSanitizer.sanitize(sql),
        equals("{\"password\": '***', \"user\": 'admin'}"),
      );
    });

    test('is case insensitive', () {
      const sql = "SET Password = 'Secret', TOKEN = 'Xyz'";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, equals("SET Password = '***', TOKEN = '***'"));
    });

    test('leaves non-sensitive SQL unchanged', () {
      const sql = "SELECT * FROM users WHERE id = 123 AND name = 'John'";
      expect(AuditSqlSanitizer.sanitize(sql), equals(sql));
    });

    test('handles multiple sensitive keywords in one statement', () {
      const sql =
          "UPDATE config SET password = 'p1', secret = 's1', token = 't1'";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, contains("password = '***'"));
      expect(result, contains("secret = '***'"));
      expect(result, contains("token = '***'"));
    });

    test('preserves SQL structure around masked value', () {
      const sql = "ALTER USER 'admin' IDENTIFIED BY 'oldpass'";
      final result = AuditSqlSanitizer.sanitize(sql);
      // 'password' is not in this SQL, so it should remain unchanged
      expect(result, equals(sql));
    });

    test('does not mask keyword inside string value', () {
      const sql = "SELECT * FROM secret_table WHERE name = 'public'";
      // 'secret' is in table name but not followed by =, so unchanged
      expect(AuditSqlSanitizer.sanitize(sql), equals(sql));
    });

    test('masks multiple occurrences of same keyword', () {
      const sql = "SET password = 'old', password = 'new'";
      final result = AuditSqlSanitizer.sanitize(sql);
      expect(result, equals("SET password = '***', password = '***'"));
    });
  });
}
