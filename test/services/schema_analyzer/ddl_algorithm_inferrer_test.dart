import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/schema_analyzer/ddl_algorithm.dart';
import 'package:dbmaster/services/schema_analyzer/ddl_algorithm_inferrer.dart';

/// DdlAlgorithmInferrer 纯单测（design-phase4.md §5 版本矩阵全覆盖）。
///
/// 覆盖：10 类 DDL × 3 版本区间（<8.0.12 / 8.0.12-8.0.28 / 8.0.29+）
/// × 显式 ALGORITHM= × 非 MySQL × MariaDB × 版本不可用。
void main() {
  group('DdlAlgorithmInferrer.infer', () {
    // ===== 非 MySQL 库（Doris 等仍 unknown；PG/SQLite 见各自专组）=====
    group('未实现的库 → unknown', () {
      test('Doris → unknown（不套用 MySQL/PG/SQLite 语义）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'doris',
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
      });

      test('ClickHouse → unknown', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c String',
          ddlType: 'ADD_COLUMN',
          databaseType: 'clickhouse',
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
      });
    });

    // ===== B4: PostgreSQL 锁语义 =====
    group('PostgreSQL（B4）', () {
      test('ALTER TABLE ADD/DROP/ALTER COLUMN → copy（ACCESS EXCLUSIVE 阻塞读写）', () {
        for (final ddlType in ['ADD_COLUMN', 'DROP_COLUMN', 'ALTER_COLUMN']) {
          final r = DdlAlgorithmInferrer.infer(
            ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
            ddlType: ddlType,
            databaseType: 'postgresql',
          );
          expect(r.algorithm, DdlAlgorithm.copy, reason: ddlType);
          expect(r.concurrencyImpact, ConcurrencyImpact.blocksDml);
        }
      });

      test('CREATE INDEX 普通 → copy（SHARE 锁阻塞写）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'CREATE INDEX idx ON t(c)',
          ddlType: 'CREATE_INDEX',
          databaseType: 'postgresql',
        );
        expect(r.algorithm, DdlAlgorithm.copy);
        expect(r.concurrencyImpact, ConcurrencyImpact.blocksDml);
      });

      test('CREATE INDEX CONCURRENTLY → inplace（允许并发 DML）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'CREATE INDEX CONCURRENTLY idx ON t(c)',
          ddlType: 'CREATE_INDEX',
          databaseType: 'postgresql',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
        expect(r.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
      });

      test('DROP INDEX CONCURRENTLY → inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'DROP INDEX CONCURRENTLY idx',
          ddlType: 'DROP_INDEX',
          databaseType: 'postgresql',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
        expect(r.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
      });

      test('TRUNCATE / DROP / RENAME → metadataOnly（瞬时元数据改）', () {
        for (final ddlType
            in ['TRUNCATE_TABLE', 'DROP_TABLE', 'RENAME_TABLE', 'RENAME_COLUMN']) {
          final r = DdlAlgorithmInferrer.infer(
            ddlStatement: 'TRUNCATE TABLE t',
            ddlType: ddlType,
            databaseType: 'postgresql',
          );
          expect(r.algorithm, DdlAlgorithm.metadataOnly, reason: ddlType);
          expect(r.concurrencyImpact, ConcurrencyImpact.none);
        }
      });

      test('CONCURRENTLY 大小写不敏感', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'create index concurrently idx on t(c)',
          ddlType: 'CREATE_INDEX',
          databaseType: 'postgresql',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });

      test('PG 不需要 serverVersion（锁模型与版本无关）', () {
        // 不传 serverVersion 也能正确推断（与 MySQL 不同）。
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'CREATE INDEX idx ON t(c)',
          ddlType: 'CREATE_INDEX',
          databaseType: 'postgresql',
        );
        expect(r.algorithm, DdlAlgorithm.copy);
      });
    });

    // ===== B4: SQLite 锁语义 =====
    group('SQLite（B4）', () {
      test('ADD COLUMN → metadataOnly（瞬时元数据改）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT DEFAULT 0',
          ddlType: 'ADD_COLUMN',
          databaseType: 'sqlite',
        );
        expect(r.algorithm, DdlAlgorithm.metadataOnly);
        expect(r.concurrencyImpact, ConcurrencyImpact.none);
      });

      test('DROP COLUMN / ALTER_COLUMN → copy（table rebuild）', () {
        for (final ddlType in ['DROP_COLUMN', 'ALTER_COLUMN']) {
          final r = DdlAlgorithmInferrer.infer(
            ddlStatement: 'ALTER TABLE t DROP COLUMN c',
            ddlType: ddlType,
            databaseType: 'sqlite',
          );
          expect(r.algorithm, DdlAlgorithm.copy, reason: ddlType);
          expect(r.concurrencyImpact, ConcurrencyImpact.blocksDml);
        }
      });

      test('CREATE INDEX → copy（扫描全表阻塞写）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'CREATE INDEX idx ON t(c)',
          ddlType: 'CREATE_INDEX',
          databaseType: 'sqlite',
        );
        expect(r.algorithm, DdlAlgorithm.copy);
        expect(r.concurrencyImpact, ConcurrencyImpact.blocksDml);
      });

      test('TRUNCATE / DROP / RENAME → metadataOnly', () {
        for (final ddlType
            in ['TRUNCATE_TABLE', 'DROP_TABLE', 'RENAME_TABLE', 'RENAME_COLUMN']) {
          final r = DdlAlgorithmInferrer.infer(
            ddlStatement: 'DROP TABLE t',
            ddlType: ddlType,
            databaseType: 'sqlite',
          );
          expect(r.algorithm, DdlAlgorithm.metadataOnly, reason: ddlType);
        }
      });
    });

    // ===== 版本解析 =====
    group('版本解析边界', () {
      test('MariaDB 10.5 → unknown（跳过，INSTANT 版本不同）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '10.5.8-MariaDB',
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
      });

      test('版本 null → unknown（保守）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: null,
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
        expect(r.concurrencyImpact, ConcurrencyImpact.unknown);
      });

      test('版本无法解析（乱码）→ unknown', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: 'unknown',
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
      });

      test('版本带后缀（8.0.32-log）正常解析', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32-log',
        );
        expect(r.algorithm, DdlAlgorithm.instant);
      });
    });

    // ===== ADD COLUMN（版本矩阵核心）=====
    group('ADD_COLUMN', () {
      final ddl = 'ALTER TABLE t ADD COLUMN c INT';

      test('8.0.32（末尾）→ instant', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.instant);
        expect(r.concurrencyImpact, ConcurrencyImpact.none);
        expect(r.lockType, contains('无锁'));
      });

      test('8.0.12（INSTANT 阈值边界）→ instant', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.12',
        );
        expect(r.algorithm, DdlAlgorithm.instant);
      });

      test('8.0.11（INSTANT 阈值前）→ inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.11',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
        expect(r.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
      });

      test('5.7.43 → inplace（不支持 INSTANT）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '5.7.43',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });

      test('带 AFTER 子句（非末尾）→ inplace（INSTANT 不支持指定位置）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT AFTER col2',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });

      test('带 FIRST 子句 → inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT FIRST',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });
    });

    // ===== DROP COLUMN =====
    group('DROP_COLUMN', () {
      final ddl = 'ALTER TABLE t DROP COLUMN c';

      test('8.0.29（INSTANT 阈值）→ instant', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'DROP_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.29',
        );
        expect(r.algorithm, DdlAlgorithm.instant);
      });

      test('8.0.32 → instant', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'DROP_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.instant);
        expect(r.concurrencyImpact, ConcurrencyImpact.none);
      });

      test('8.0.28（INSTANT 阈值前）→ inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'DROP_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.28',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });

      test('5.7.43 → inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: ddl,
          ddlType: 'DROP_COLUMN',
          databaseType: 'mysql',
          serverVersion: '5.7.43',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });
    });

    // ===== ALTER COLUMN（改类型 → COPY）=====
    group('ALTER_COLUMN', () {
      test('MODIFY COLUMN（改类型）→ copy', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
          ddlType: 'ALTER_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.copy);
        expect(r.concurrencyImpact, ConcurrencyImpact.blocksDml);
        expect(r.lockType, contains('全表锁'));
      });

      test('ALTER COLUMN TYPE → copy', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ALTER COLUMN c SET DATA TYPE BIGINT',
          ddlType: 'ALTER_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.copy);
      });

      test('CONVERT TO CHARACTER SET → copy（字符集变更）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t CONVERT TO CHARACTER SET utf8mb4',
          ddlType: 'ALTER_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.copy);
        expect(r.note, contains('字符集'));
      });

      test('CHARACTER SET 子句 → copy', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t MODIFY COLUMN c VARCHAR(100) CHARACTER SET utf8mb4',
          ddlType: 'ALTER_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.copy);
      });
    });

    // ===== INDEX 操作 =====
    group('INDEX 操作', () {
      test('CREATE INDEX → inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'CREATE INDEX idx ON t(c)',
          ddlType: 'CREATE_INDEX',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
        expect(r.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
      });

      test('CREATE UNIQUE INDEX → inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'CREATE UNIQUE INDEX idx ON t(c)',
          ddlType: 'CREATE_INDEX',
          databaseType: 'mysql',
          serverVersion: '5.7.43',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });

      test('DROP INDEX → inplace', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'DROP INDEX idx ON t',
          ddlType: 'DROP_INDEX',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
      });
    });

    // ===== 元数据操作（TRUNCATE / DROP / RENAME）=====
    group('元数据操作', () {
      test('TRUNCATE TABLE → metadataOnly', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'TRUNCATE TABLE t',
          ddlType: 'TRUNCATE_TABLE',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.metadataOnly);
        expect(r.concurrencyImpact, ConcurrencyImpact.none);
        expect(r.lockType, contains('元数据锁'));
        expect(r.note, contains('不可恢复'));
      });

      test('DROP TABLE → metadataOnly', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'DROP TABLE t',
          ddlType: 'DROP_TABLE',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.metadataOnly);
        expect(r.concurrencyImpact, ConcurrencyImpact.none);
      });

      test('RENAME TABLE → metadataOnly', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'RENAME TABLE t TO t2',
          ddlType: 'RENAME_TABLE',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.metadataOnly);
      });

      test('RENAME COLUMN → metadataOnly', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t RENAME COLUMN c TO c2',
          ddlType: 'RENAME_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.metadataOnly);
      });
    });

    // ===== 显式 ALGORITHM= / LOCK=（用户意图优先）=====
    group('显式 ALGORITHM=/LOCK=', () {
      test('ALGORITHM=INSTANT → instant（用户指定）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT, ALGORITHM=INSTANT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '5.7.43', // 即使 5.7 也尊重用户指定
        );
        expect(r.algorithm, DdlAlgorithm.instant);
        expect(r.note, contains('用户'));
      });

      test('ALGORITHM=INPLACE, LOCK=NONE → inplace + 允许并发', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement:
              'ALTER TABLE t MODIFY COLUMN c BIGINT, ALGORITHM=INPLACE, LOCK=NONE',
          ddlType: 'ALTER_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.inplace);
        expect(r.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
        expect(r.lockType, contains('LOCK=NONE'));
      });

      test('ALGORITHM=COPY → copy（用户显式）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT, ALGORITHM=COPY',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32', // 即使支持 INSTANT，用户要 COPY 就 COPY
        );
        expect(r.algorithm, DdlAlgorithm.copy);
        expect(r.concurrencyImpact, ConcurrencyImpact.blocksDml);
      });

      test('ALGORITHM=DEFAULT → unknown（让 MySQL 自选，无法静态确定）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT, ALGORITHM=DEFAULT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
      });
    });

    // ===== 未知 DDL 类型 =====
    group('未知 DDL 类型', () {
      test('CREATE_TABLE → unknown（不在锁语义范围）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'CREATE TABLE t (id INT)',
          ddlType: 'CREATE_TABLE',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
      });

      test('UNKNOWN → unknown（保守）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'GRANT SELECT ON t TO user',
          ddlType: 'UNKNOWN',
          databaseType: 'mysql',
          serverVersion: '8.0.32',
        );
        expect(r.algorithm, DdlAlgorithm.unknown);
        expect(r.note, contains('保守'));
      });
    });

    // ===== MySQL 9.x 假设（延续 INSTANT 支持）=====
    group('MySQL 9.x+', () {
      test('9.0.0 ADD COLUMN → instant（假设延续支持）', () {
        final r = DdlAlgorithmInferrer.infer(
          ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
          ddlType: 'ADD_COLUMN',
          databaseType: 'mysql',
          serverVersion: '9.0.0',
        );
        expect(r.algorithm, DdlAlgorithm.instant);
      });
    });
  });
}
