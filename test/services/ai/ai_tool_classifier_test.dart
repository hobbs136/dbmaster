import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/ai_tool_classifier.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';

void main() {
  group('AiToolClassifier.isWriteSql', () {
    group('只读语句（返回 false）', () {
      test('SELECT 开头', () {
        expect(AiToolClassifier.isWriteSql('SELECT * FROM users'), isFalse);
      });

      test('SHOW 开头', () {
        expect(AiToolClassifier.isWriteSql('SHOW TABLES'), isFalse);
      });

      test('DESCRIBE 开头', () {
        expect(AiToolClassifier.isWriteSql('DESCRIBE users'), isFalse);
      });

      test('EXPLAIN 开头', () {
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN SELECT * FROM users'),
          isFalse,
        );
      });

      test('小写输入', () {
        expect(AiToolClassifier.isWriteSql('select * from users'), isFalse);
        expect(AiToolClassifier.isWriteSql('show databases'), isFalse);
        expect(AiToolClassifier.isWriteSql('describe users'), isFalse);
        expect(AiToolClassifier.isWriteSql('explain select 1'), isFalse);
      });

      test('混合大小写', () {
        expect(AiToolClassifier.isWriteSql('SeLeCt * FrOm users'), isFalse);
        expect(AiToolClassifier.isWriteSql('ShOw TaBlEs'), isFalse);
        expect(AiToolClassifier.isWriteSql('DeScRiBe users'), isFalse);
        expect(AiToolClassifier.isWriteSql('ExPlAiN SeLeCt 1'), isFalse);
      });

      test('前后空格（含换行与制表符）', () {
        expect(AiToolClassifier.isWriteSql('  SELECT * FROM users  '), isFalse);
        expect(AiToolClassifier.isWriteSql('\n\t SHOW TABLES \t\n'), isFalse);
        expect(AiToolClassifier.isWriteSql('\r\nDESCRIBE users'), isFalse);
      });
    });

    group('写语句（返回 true）', () {
      test('常见写关键字开头', () {
        expect(
          AiToolClassifier.isWriteSql('INSERT INTO users VALUES (1)'),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql("UPDATE users SET name = 'a'"),
          isTrue,
        );
        expect(AiToolClassifier.isWriteSql('DELETE FROM users'), isTrue);
        expect(AiToolClassifier.isWriteSql('DROP TABLE users'), isTrue);
        expect(AiToolClassifier.isWriteSql('CREATE TABLE t (id INT)'), isTrue);
        expect(
          AiToolClassifier.isWriteSql('ALTER TABLE t ADD COLUMN c INT'),
          isTrue,
        );
        expect(AiToolClassifier.isWriteSql('TRUNCATE TABLE users'), isTrue);
        expect(
          AiToolClassifier.isWriteSql('REPLACE INTO users VALUES (1)'),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql('GRANT SELECT ON db.* TO u'),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql('REVOKE SELECT ON db.* FROM u'),
          isTrue,
        );
      });

      test('小写写语句', () {
        expect(
          AiToolClassifier.isWriteSql('insert into users values (1)'),
          isTrue,
        );
        expect(AiToolClassifier.isWriteSql('drop table users'), isTrue);
      });

      test('写语句带前后空格', () {
        expect(AiToolClassifier.isWriteSql('  DROP TABLE users  '), isTrue);
        expect(AiToolClassifier.isWriteSql('\tdelete from users\n'), isTrue);
      });

      test('空串视为写（不匹配任何只读前缀）', () {
        expect(AiToolClassifier.isWriteSql(''), isTrue);
      });

      test('纯空白字符串视为写', () {
        expect(AiToolClassifier.isWriteSql('   '), isTrue);
        expect(AiToolClassifier.isWriteSql('\n\t'), isTrue);
      });

      test('只读关键字不在开头视为写（前缀语义）', () {
        expect(AiToolClassifier.isWriteSql('-- comment\nSELECT 1'), isTrue);
        expect(
          AiToolClassifier.isWriteSql('WITH cte AS (SELECT 1) SELECT 1'),
          isTrue,
        );
      });
    });

    group('EXPLAIN ANALYZE / DESCRIBE 后随写关键字特判（F3，仅公开包装层）', () {
      test('EXPLAIN ANALYZE + 写语句 → 判写（PG/MySQL 真实执行写）', () {
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN ANALYZE DELETE FROM t'),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN ANALYZE UPDATE t SET a = 1'),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql(
            'EXPLAIN ANALYZE INSERT INTO t VALUES (1)',
          ),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN ANALYZE DROP TABLE t'),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql(
            'EXPLAIN ANALYZE CREATE TABLE t (id INT)',
          ),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN ANALYZE TRUNCATE TABLE t'),
          isTrue,
        );
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN ANALYZE GRANT ALL ON db.* TO u'),
          isTrue,
        );
      });

      test('EXPLAIN ANALYSE（PG 拼写变体）→ 判写', () {
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN ANALYSE DELETE FROM t'),
          isTrue,
        );
      });

      test('EXPLAIN 只读形态不受特判影响', () {
        expect(AiToolClassifier.isWriteSql('EXPLAIN SELECT 1'), isFalse);
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN ANALYZE SELECT * FROM t'),
          isFalse,
          reason: 'EXPLAIN ANALYZE 只读语句仍只读',
        );
      });

      test('空白/换行/大小写变体', () {
        expect(
          AiToolClassifier.isWriteSql('explain analyze  delete from t'),
          isTrue,
          reason: '多空格',
        );
        expect(
          AiToolClassifier.isWriteSql('EXPLAIN\tANALYZE\nDELETE FROM t'),
          isTrue,
          reason: '制表符与换行',
        );
        expect(
          AiToolClassifier.isWriteSql('  ExPlAiN aNaLyZe DeLeTe FROM t  '),
          isTrue,
          reason: '混合大小写 + 首尾空白',
        );
      });

      test('词边界：表名含写关键字前缀不误命中', () {
        expect(
          AiToolClassifier.isWriteSql('DESCRIBE deleted_users'),
          isFalse,
          reason: '表名 deleted_users 的 DELETE 非独立关键字（词边界）',
        );
        expect(
          AiToolClassifier.isWriteSql('DESCRIBE updates_table'),
          isFalse,
          reason: '表名 updates_table 的 UPDATE 非独立关键字',
        );
        expect(AiToolClassifier.isWriteSql('DESCRIBE users'), isFalse);
      });

      test('DESC 缩写维持基线语义：不在 _isWriteSql 只读白名单（判写）', () {
        // T06 约束：私有 _isWriteSql 本体不动——它只放行完整 DESCRIBE 前缀，
        // DESC 缩写自始判写。特判只可能把 DESCRIBE/DESC + 写关键字判写，
        // 不存在把既有只读改判写的方向。
        expect(
          AiToolClassifier.isWriteSql('DESC users'),
          isTrue,
          reason: '既有语义：DESC 缩写不被只读前缀放行',
        );
      });
    });
  });

  group('AiToolClassifier.opClassOf（统计三分类，design §6.4 / P1-2）', () {
    test('只读 → queryGen', () {
      expect(
        AiToolClassifier.opClassOf('SELECT * FROM t'),
        WorkbenchOpClass.queryGen,
      );
      expect(
        AiToolClassifier.opClassOf('SHOW TABLES'),
        WorkbenchOpClass.queryGen,
      );
      expect(
        AiToolClassifier.opClassOf('DESCRIBE t'),
        WorkbenchOpClass.queryGen,
      );
      expect(
        AiToolClassifier.opClassOf('EXPLAIN SELECT 1'),
        WorkbenchOpClass.queryGen,
      );
    });

    test('DML 写 → bulkMaint（含 REPLACE 与 CTE 内嵌形态）', () {
      expect(
        AiToolClassifier.opClassOf('INSERT INTO t VALUES (1)'),
        WorkbenchOpClass.bulkMaint,
      );
      expect(
        AiToolClassifier.opClassOf('UPDATE t SET a = 1'),
        WorkbenchOpClass.bulkMaint,
      );
      expect(
        AiToolClassifier.opClassOf('DELETE FROM t'),
        WorkbenchOpClass.bulkMaint,
      );
      expect(
        AiToolClassifier.opClassOf('REPLACE INTO t VALUES (1)'),
        WorkbenchOpClass.bulkMaint,
      );
      expect(
        AiToolClassifier.opClassOf(
          'WITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x',
        ),
        WorkbenchOpClass.bulkMaint,
        reason: 'CTE 内嵌 DML 同计（_isWriteQuery 同口径）',
      );
    });

    test('DDL/权限类 → ddlPerm', () {
      expect(
        AiToolClassifier.opClassOf('CREATE TABLE t (id INT)'),
        WorkbenchOpClass.ddlPerm,
      );
      expect(
        AiToolClassifier.opClassOf('DROP TABLE t'),
        WorkbenchOpClass.ddlPerm,
      );
      expect(
        AiToolClassifier.opClassOf('ALTER TABLE t ADD c INT'),
        WorkbenchOpClass.ddlPerm,
      );
      expect(
        AiToolClassifier.opClassOf('TRUNCATE TABLE t'),
        WorkbenchOpClass.ddlPerm,
      );
      expect(
        AiToolClassifier.opClassOf('RENAME TABLE a TO b'),
        WorkbenchOpClass.ddlPerm,
      );
      expect(
        AiToolClassifier.opClassOf('GRANT SELECT ON db.* TO u'),
        WorkbenchOpClass.ddlPerm,
      );
      expect(
        AiToolClassifier.opClassOf('REVOKE SELECT ON db.* FROM u'),
        WorkbenchOpClass.ddlPerm,
      );
    });

    test('EXPLAIN ANALYZE 写形态经 F3 特判不落 queryGen', () {
      expect(
        AiToolClassifier.opClassOf('EXPLAIN ANALYZE DELETE FROM t'),
        WorkbenchOpClass.bulkMaint,
      );
    });
  });
}
