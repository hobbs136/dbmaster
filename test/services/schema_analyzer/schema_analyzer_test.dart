import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/schema_analyzer/impact_assessor.dart';
import 'package:dbmaster/services/schema_analyzer/rollback_generator.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';

void main() {
  group('ImpactAssessor', () {
    test('extracts DDL type correctly', () {
      expect(
        ImpactAssessor.extractDdlType('DROP TABLE users'),
        equals('DROP_TABLE'),
      );
      expect(
        ImpactAssessor.extractDdlType('ALTER TABLE users DROP COLUMN name'),
        equals('DROP_COLUMN'),
      );
      expect(
        ImpactAssessor.extractDdlType('ALTER TABLE users ADD COLUMN age INT'),
        equals('ADD_COLUMN'),
      );
      expect(
        ImpactAssessor.extractDdlType('CREATE INDEX idx_name ON users(name)'),
        equals('CREATE_INDEX'),
      );
      expect(
        ImpactAssessor.extractDdlType('RENAME TABLE users TO customers'),
        equals('RENAME_TABLE'),
      );
    });

    test('extracts target table correctly', () {
      expect(
        ImpactAssessor.extractTargetTable('DROP TABLE users'),
        equals('users'),
      );
      expect(
        ImpactAssessor.extractTargetTable(
          'ALTER TABLE orders ADD COLUMN status',
        ),
        equals('orders'),
      );
      expect(
        ImpactAssessor.extractTargetTable('CREATE INDEX idx ON products(code)'),
        equals('products'),
      );
    });

    test('assesses DROP TABLE as high risk', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'DROP TABLE users',
        ddlType: 'DROP_TABLE',
        dependencies: [],
        estimatedAffectedRows: 1000,
      );
      expect(risk, equals(RiskLevel.high));
    });

    test('assesses DROP TABLE with foreign keys as critical', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'DROP TABLE users',
        ddlType: 'DROP_TABLE',
        dependencies: [
          SchemaDependency(
            sourceTable: 'users',
            dependentObject: 'orders',
            dependentType: AffectedObjectType.foreignKey,
            relationship: 'FK',
          ),
        ],
        estimatedAffectedRows: 1000,
      );
      expect(risk, equals(RiskLevel.critical));
    });

    test('assesses ADD COLUMN as low risk', () {
      final risk = ImpactAssessor.assessRiskLevel(
        ddlStatement: 'ALTER TABLE users ADD COLUMN age INT',
        ddlType: 'ADD_COLUMN',
        dependencies: [],
        estimatedAffectedRows: 1000,
      );
      expect(risk, equals(RiskLevel.low));
    });

    test('generates warnings for DROP TABLE', () {
      final warnings = ImpactAssessor.generateWarnings(
        ddlStatement: 'DROP TABLE users',
        ddlType: 'DROP_TABLE',
        dependencies: [],
        estimatedAffectedRows: 5000,
      );

      expect(warnings.isNotEmpty, isTrue);
      expect(warnings.any((w) => w.contains('permanently delete')), isTrue);
      expect(warnings.any((w) => w.contains('5000 rows')), isTrue);
    });

    test('generates warnings for dependencies', () {
      final warnings = ImpactAssessor.generateWarnings(
        ddlStatement: 'DROP TABLE users',
        ddlType: 'DROP_TABLE',
        dependencies: [
          SchemaDependency(
            sourceTable: 'users',
            dependentObject: 'active_users_view',
            dependentType: AffectedObjectType.view,
            relationship: 'View',
          ),
          SchemaDependency(
            sourceTable: 'users',
            dependentObject: 'update_trigger',
            dependentType: AffectedObjectType.trigger,
            relationship: 'Trigger',
          ),
        ],
        estimatedAffectedRows: 100,
      );

      expect(warnings.any((w) => w.contains('view(s)')), isTrue);
      expect(warnings.any((w) => w.contains('trigger(s)')), isTrue);
    });

    test('requires confirmation for high risk', () {
      expect(ImpactAssessor.requiresConfirmation(RiskLevel.high), isTrue);
      expect(ImpactAssessor.requiresConfirmation(RiskLevel.critical), isTrue);
      expect(ImpactAssessor.requiresConfirmation(RiskLevel.low), isFalse);
    });
  });

  group('RollbackGenerator', () {
    test('generates DROP TABLE rollback', () {
      final rollback = RollbackGenerator.generateRollback(
        ddlStatement: 'DROP TABLE users',
        ddlType: 'DROP_TABLE',
        tableName: 'users',
        databaseType: 'mysql',
      );

      expect(rollback, isNotNull);
      expect(rollback!.requiresDataBackup, isTrue);
      expect(rollback.rollbackDdl, contains('Cannot automatically restore'));
    });

    test('generates ADD COLUMN rollback', () {
      final rollback = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users ADD COLUMN age INT',
        ddlType: 'ADD_COLUMN',
        tableName: 'users',
        columnName: 'age',
        databaseType: 'mysql',
      );

      expect(rollback, isNotNull);
      expect(rollback!.rollbackDdl, contains('DROP COLUMN'));
      expect(rollback.rollbackDdl, contains('age'));
    });

    test('generates CREATE INDEX rollback', () {
      final rollback = RollbackGenerator.generateRollback(
        ddlStatement: 'CREATE INDEX idx_name ON users(name)',
        ddlType: 'CREATE_INDEX',
        tableName: 'users',
        databaseType: 'mysql',
      );

      expect(rollback, isNotNull);
      expect(rollback!.rollbackDdl, contains('DROP INDEX'));
      expect(rollback.rollbackDdl, contains('idx_name'));
    });

    test('generates RENAME TABLE rollback', () {
      final rollback = RollbackGenerator.generateRollback(
        ddlStatement: 'RENAME TABLE users TO customers',
        ddlType: 'RENAME_TABLE',
        tableName: 'users',
        databaseType: 'mysql',
      );

      expect(rollback, isNotNull);
      expect(rollback!.rollbackDdl, contains('customers'));
      expect(rollback.rollbackDdl, contains('users'));
    });

    test('extracts column name correctly', () {
      expect(
        RollbackGenerator.extractColumnName(
          'ALTER TABLE users DROP COLUMN name',
          'DROP_COLUMN',
        ),
        equals('name'),
      );
      expect(
        RollbackGenerator.extractColumnName(
          'ALTER TABLE users ADD COLUMN age INT',
          'ADD_COLUMN',
        ),
        equals('age'),
      );
    });
  });
}
