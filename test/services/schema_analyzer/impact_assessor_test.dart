import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/schema_analyzer/ddl_algorithm.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';
import 'package:dbmaster/services/schema_analyzer/impact_assessor.dart';

void main() {
  group('ImpactAssessor.extractDdlType', () {
    test('DROP TABLE', () {
      expect(ImpactAssessor.extractDdlType('DROP TABLE users'), 'DROP_TABLE');
      expect(
        ImpactAssessor.extractDdlType('DROP TABLE IF EXISTS users'),
        'DROP_TABLE',
      );
    });

    test('DROP COLUMN', () {
      expect(
        ImpactAssessor.extractDdlType('ALTER TABLE users DROP COLUMN email'),
        'DROP_COLUMN',
      );
    });

    test('ALTER TABLE ... MODIFY (MySQL)', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE users MODIFY COLUMN age INT',
        ),
        'ALTER_COLUMN',
      );
    });

    test('ALTER TABLE ... ALTER COLUMN (PostgreSQL)', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE users ALTER COLUMN age TYPE INT',
        ),
        'ALTER_COLUMN',
      );
    });

    // 字符集/排序规则变更（2026-08-09 修复：此前落 UNKNOWN → 漏报全表锁 copy）。
    // 归 ALTER_COLUMN 使 DdlAlgorithmInferrer._isCharsetChange 生效 → copy。
    test('ALTER TABLE CONVERT TO CHARACTER SET → ALTER_COLUMN', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE t CONVERT TO CHARACTER SET utf8mb4',
        ),
        'ALTER_COLUMN',
      );
    });

    test('ALTER TABLE DEFAULT CHARACTER SET → ALTER_COLUMN', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE t DEFAULT CHARACTER SET utf8mb4',
        ),
        'ALTER_COLUMN',
      );
    });

    test('ALTER TABLE COLLATE → ALTER_COLUMN', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE t COLLATE utf8mb4_unicode_ci',
        ),
        'ALTER_COLUMN',
      );
    });

    test('ADD COLUMN standard', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE users ADD COLUMN phone VARCHAR(20)',
        ),
        'ADD_COLUMN',
      );
    });

    test('ADD without COLUMN keyword (SQL Server style)', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE users ADD phone VARCHAR(20)',
        ),
        'ADD_COLUMN',
      );
    });

    test('ADD CONSTRAINT should not match ADD_COLUMN', () {
      final type = ImpactAssessor.extractDdlType(
        'ALTER TABLE users ADD CONSTRAINT fk_user FOREIGN KEY (id)',
      );
      expect(type, isNot('ADD_COLUMN'));
    });

    test('ADD PRIMARY KEY should not match ADD_COLUMN', () {
      final type = ImpactAssessor.extractDdlType(
        'ALTER TABLE users ADD PRIMARY KEY (id)',
      );
      expect(type, isNot('ADD_COLUMN'));
    });

    test('CREATE INDEX', () {
      expect(
        ImpactAssessor.extractDdlType('CREATE INDEX idx_email ON users(email)'),
        'CREATE_INDEX',
      );
    });

    test('CREATE UNIQUE INDEX', () {
      expect(
        ImpactAssessor.extractDdlType(
          'CREATE UNIQUE INDEX idx_email ON users(email)',
        ),
        'CREATE_INDEX',
      );
    });

    test('DROP INDEX', () {
      expect(
        ImpactAssessor.extractDdlType('DROP INDEX idx_email ON users'),
        'DROP_INDEX',
      );
    });

    test('RENAME TABLE', () {
      expect(
        ImpactAssessor.extractDdlType('RENAME TABLE users TO customers'),
        'RENAME_TABLE',
      );
    });

    test('handles bracket-quoted identifiers (SQL Server)', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE [users] DROP COLUMN [email]',
        ),
        'DROP_COLUMN',
      );
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE [dbo].[users] ADD [phone] VARCHAR(20)',
        ),
        'ADD_COLUMN',
      );
    });

    test('handles backtick-quoted identifiers (MySQL)', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE `users` DROP COLUMN `email`',
        ),
        'DROP_COLUMN',
      );
    });

    test('handles double-quoted identifiers (PostgreSQL)', () {
      expect(
        ImpactAssessor.extractDdlType(
          'ALTER TABLE "users" ADD COLUMN "phone" VARCHAR(20)',
        ),
        'ADD_COLUMN',
      );
    });

    test('unknown DDL returns UNKNOWN', () {
      expect(ImpactAssessor.extractDdlType('SELECT * FROM users'), 'UNKNOWN');
      expect(
        ImpactAssessor.extractDdlType('INSERT INTO users VALUES (1)'),
        'UNKNOWN',
      );
    });
  });

  group('ImpactAssessor.extractTargetTable', () {
    test('DROP TABLE extracts table name', () {
      expect(ImpactAssessor.extractTargetTable('DROP TABLE users'), 'users');
      expect(
        ImpactAssessor.extractTargetTable('DROP TABLE IF EXISTS products'),
        'products',
      );
    });

    test('ALTER TABLE extracts table name', () {
      expect(
        ImpactAssessor.extractTargetTable(
          'ALTER TABLE users DROP COLUMN email',
        ),
        'users',
      );
      expect(
        ImpactAssessor.extractTargetTable(
          'ALTER TABLE products ADD COLUMN price DECIMAL',
        ),
        'products',
      );
    });

    test('CREATE INDEX extracts table name', () {
      expect(
        ImpactAssessor.extractTargetTable(
          'CREATE INDEX idx_email ON users(email)',
        ),
        'users',
      );
    });

    test('RENAME TABLE extracts old table name', () {
      expect(
        ImpactAssessor.extractTargetTable('RENAME TABLE users TO customers'),
        'users',
      );
    });

    test('handles schema-qualified identifiers', () {
      expect(
        ImpactAssessor.extractTargetTable('DROP TABLE dbo.orders'),
        'orders',
      );
      expect(
        ImpactAssessor.extractTargetTable(
          'ALTER TABLE public.users ADD COLUMN phone VARCHAR',
        ),
        'users',
      );
    });

    test('handles bracket-quoted schema.table (SQL Server)', () {
      expect(
        ImpactAssessor.extractTargetTable(
          'ALTER TABLE [dbo].[users] ADD [phone] VARCHAR',
        ),
        'users',
      );
      expect(
        ImpactAssessor.extractTargetTable('DROP TABLE [dbo].[products_2024]'),
        'products_2024',
      );
    });

    test('handles backtick-quoted (MySQL)', () {
      expect(
        ImpactAssessor.extractTargetTable(
          'ALTER TABLE `users` ADD COLUMN phone VARCHAR',
        ),
        'users',
      );
    });

    test('handles double-quoted (PostgreSQL)', () {
      expect(
        ImpactAssessor.extractTargetTable(
          'ALTER TABLE "users" DROP COLUMN "email"',
        ),
        'users',
      );
    });

    test('CREATE INDEX with schema-qualified table', () {
      expect(
        ImpactAssessor.extractTargetTable(
          'CREATE INDEX idx ON public.users(email)',
        ),
        'users',
      );
    });

    test('returns unknown for unrecognized statements', () {
      expect(
        ImpactAssessor.extractTargetTable('SELECT * FROM users'),
        'unknown',
      );
      expect(ImpactAssessor.extractTargetTable('-- some comment'), 'unknown');
    });
  });

  group('ImpactAssessor DDL type and target table integration', () {
    test('DROP COLUMN extracts type and target correctly', () {
      const ddl = 'ALTER TABLE users DROP COLUMN email';
      expect(ImpactAssessor.extractDdlType(ddl), 'DROP_COLUMN');
      expect(ImpactAssessor.extractTargetTable(ddl), 'users');
    });

    test('SQL Server ADD column extracts type and target correctly', () {
      const ddl = 'ALTER TABLE [dbo].[orders] ADD [status] VARCHAR(20)';
      expect(ImpactAssessor.extractDdlType(ddl), 'ADD_COLUMN');
      expect(ImpactAssessor.extractTargetTable(ddl), 'orders');
    });

    test('PostgreSQL ALTER COLUMN extracts type and target correctly', () {
      const ddl = 'ALTER TABLE "public"."users" ALTER COLUMN "age" TYPE INT';
      expect(ImpactAssessor.extractDdlType(ddl), 'ALTER_COLUMN');
      expect(ImpactAssessor.extractTargetTable(ddl), 'users');
    });

    test('MySQL CREATE INDEX extracts type and target correctly', () {
      const ddl = 'CREATE INDEX `idx_status` ON `orders`(`status`)';
      expect(ImpactAssessor.extractDdlType(ddl), 'CREATE_INDEX');
      expect(ImpactAssessor.extractTargetTable(ddl), 'orders');
    });
  });

  // 第四阶段 R18：TRUNCATE TABLE 识别 bug 修复。
  group('ImpactAssessor.extractDdlType TRUNCATE (R18 bug fix)', () {
    test('TRUNCATE TABLE → TRUNCATE_TABLE（之前落 UNKNOWN）', () {
      expect(
        ImpactAssessor.extractDdlType('TRUNCATE TABLE users'),
        'TRUNCATE_TABLE',
      );
    });

    test('TRUNCATE（无 TABLE 关键字）→ TRUNCATE_TABLE', () {
      expect(
        ImpactAssessor.extractDdlType('TRUNCATE users'),
        'TRUNCATE_TABLE',
      );
    });

    test('TRUNCATE TABLE（小写）→ TRUNCATE_TABLE', () {
      expect(
        ImpactAssessor.extractDdlType('truncate table users'),
        'TRUNCATE_TABLE',
      );
    });

    test('TRUNCATE TABLE（带反引号）→ TRUNCATE_TABLE', () {
      expect(
        ImpactAssessor.extractDdlType('TRUNCATE TABLE `users`'),
        'TRUNCATE_TABLE',
      );
    });
  });

  // 第四阶段 R18：TRUNCATE 评级修复（之前兜底 medium，破坏性操作被低估）。
  group('ImpactAssessor.assessRiskLevel TRUNCATE (R18 bug fix)', () {
    test('TRUNCATE_TABLE → high（破坏性，清空数据）', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'TRUNCATE TABLE users',
        ddlType: 'TRUNCATE_TABLE',
        dependencies: [],
        estimatedAffectedRows: 0,
      );
      expect(risk, RiskLevel.high);
    });

    test('TRUNCATE_TABLE 带外键 → critical', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'TRUNCATE TABLE users',
        ddlType: 'TRUNCATE_TABLE',
        dependencies: [
          SchemaDependency(
            sourceTable: 'users',
            dependentObject: 'orders',
            dependentType: AffectedObjectType.foreignKey,
            relationship: 'FK',
          ),
        ],
        estimatedAffectedRows: 0,
      );
      expect(risk, RiskLevel.critical);
    });
  });

  // 第四阶段 R15：algorithm 驱动评级（design §4.5）。
  group('ImpactAssessor.assessRiskLevel algorithm-driven (R15)', () {
    test('instant → low（秒级无锁，不论表大小）', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        ddlType: 'ADD_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 5000000, // 即使百万行也 low
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.instant,
          concurrencyImpact: ConcurrencyImpact.none,
        ),
      );
      expect(risk, RiskLevel.low);
    });

    test('metadataOnly → low（DROP/TRUNCATE 已在破坏性分支拦截，此处测非破坏性）', () {
      // CREATE TABLE 等非破坏性 metadataOnly 走这里。
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'RENAME TABLE t TO t2',
        ddlType: 'RENAME_TABLE',
        dependencies: [],
        estimatedAffectedRows: 0,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          concurrencyImpact: ConcurrencyImpact.none,
        ),
      );
      expect(risk, RiskLevel.low);
    });

    test('inplace 小表（行数 ≤ 默认阈值 100000）→ low（B2：不骚扰小表）', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT AFTER x',
        ddlType: 'ADD_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 100,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.inplace,
          concurrencyImpact: ConcurrencyImpact.allowsConcurrentDml,
        ),
      );
      expect(risk, RiskLevel.low);
    });

    test('inplace 大表（行数 > 默认阈值 100000）→ medium（B2：提示耗时）', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'CREATE INDEX idx ON t(c)',
        ddlType: 'CREATE_INDEX',
        dependencies: [],
        estimatedAffectedRows: 500000,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.inplace,
          concurrencyImpact: ConcurrencyImpact.allowsConcurrentDml,
        ),
      );
      expect(risk, RiskLevel.medium);
    });

    test('inplace 自定义阈值（小表用低阈值也触发 medium）', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'CREATE INDEX idx ON t(c)',
        ddlType: 'CREATE_INDEX',
        dependencies: [],
        estimatedAffectedRows: 5000,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.inplace,
          concurrencyImpact: ConcurrencyImpact.allowsConcurrentDml,
        ),
        inplaceMediumRowThreshold: 1000, // 调严：1000 以上即 medium
      );
      expect(risk, RiskLevel.medium);
    });

    test('inplace（有依赖）→ high', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT AFTER x',
        ddlType: 'ADD_COLUMN',
        dependencies: [
          SchemaDependency(
            sourceTable: 't',
            dependentObject: 'v_t',
            dependentType: AffectedObjectType.view,
            relationship: 'view',
          ),
        ],
        estimatedAffectedRows: 100,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.inplace,
          concurrencyImpact: ConcurrencyImpact.allowsConcurrentDml,
        ),
      );
      expect(risk, RiskLevel.high);
    });

    test('copy + 大表（>1M）→ critical', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
        ddlType: 'ALTER_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 2000000,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.copy,
          concurrencyImpact: ConcurrencyImpact.blocksDml,
        ),
      );
      expect(risk, RiskLevel.critical);
    });

    test('copy + 中表（>10K）→ high', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
        ddlType: 'ALTER_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 50000,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.copy,
          concurrencyImpact: ConcurrencyImpact.blocksDml,
        ),
      );
      expect(risk, RiskLevel.high);
    });

    test('copy + 小表 → medium', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
        ddlType: 'ALTER_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 500,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.copy,
          concurrencyImpact: ConcurrencyImpact.blocksDml,
        ),
      );
      expect(risk, RiskLevel.medium);
    });

    test('algorithm=unknown → 回落既有行数阈值（ALTER_COLUMN >10K = high）', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
        ddlType: 'ALTER_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 50000,
        algorithmResult: DdlAlgorithmResult.unknown,
      );
      expect(risk, RiskLevel.high); // 既有逻辑
    });

    test('algorithmResult=null（既有调用方）→ 既有行为不变', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        ddlType: 'ADD_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 1000,
        // 不传 algorithmResult
      );
      expect(risk, RiskLevel.low); // 既有 ADD_COLUMN 逻辑
    });

    test('破坏性操作（DROP_TABLE）即使 instant 也优先数据丢失维度 → high', () {
      // 注：DROP_TABLE 实际是 metadataOnly，但破坏性优先。
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'DROP TABLE t',
        ddlType: 'DROP_TABLE',
        dependencies: [],
        estimatedAffectedRows: 0,
        algorithmResult: const DdlAlgorithmResult(
          algorithm: DdlAlgorithm.metadataOnly,
          concurrencyImpact: ConcurrencyImpact.none,
        ),
      );
      expect(risk, RiskLevel.high); // 数据丢失维度优先，不走 instant→low
    });
  });
}
