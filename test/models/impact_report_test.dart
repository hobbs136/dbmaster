import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';

void main() {
  group('AffectedObjectType', () {
    test('has 7 values', () {
      expect(AffectedObjectType.values.length, 7);
    });
  });

  group('RiskLevel', () {
    test('has 4 values', () {
      expect(RiskLevel.values.length, 4);
    });

    test('isHighOrAbove', () {
      expect(RiskLevel.critical.isHighOrAbove, true);
      expect(RiskLevel.high.isHighOrAbove, true);
      expect(RiskLevel.medium.isHighOrAbove, false);
      expect(RiskLevel.low.isHighOrAbove, false);
    });

    test('displayName and description are set', () {
      for (final level in RiskLevel.values) {
        expect(level.code, isNotEmpty);
        expect(level.displayName, isNotEmpty);
        expect(level.description, isNotEmpty);
      }
    });
  });

  group('AffectedObject', () {
    test('fields are correctly set', () {
      final obj = AffectedObject(
        type: AffectedObjectType.view,
        name: 'user_summary',
        schema: 'public',
        impactDescription: 'This view depends on the column being dropped',
        dependentColumn: 'user_id',
      );
      expect(obj.type, AffectedObjectType.view);
      expect(obj.name, 'user_summary');
      expect(obj.schema, 'public');
      expect(obj.dependentColumn, 'user_id');
    });

    test('toJson produces correct map', () {
      final obj = AffectedObject(
        type: AffectedObjectType.foreignKey,
        name: 'fk_orders_users',
        impactDescription: 'Foreign key constraint will be dropped',
      );
      final json = obj.toJson();
      expect(json['type'], 'foreignKey');
      expect(json['name'], 'fk_orders_users');
    });
  });

  group('SchemaDependency', () {
    test('toJson produces correct map', () {
      final dep = SchemaDependency(
        sourceTable: 'users',
        sourceColumn: 'id',
        dependentObject: 'orders',
        dependentType: AffectedObjectType.foreignKey,
        relationship: 'Referenced by FK',
      );
      final json = dep.toJson();
      expect(json['sourceTable'], 'users');
      expect(json['sourceColumn'], 'id');
      expect(json['dependentType'], 'foreignKey');
    });
  });

  group('RollbackScript', () {
    test('defaults requiresDataBackup to false', () {
      final rs = RollbackScript(
        originalDdl: 'ALTER TABLE users DROP COLUMN email',
        rollbackDdl: 'ALTER TABLE users ADD COLUMN email VARCHAR(255)',
        description: 'Rollback dropping email column',
      );
      expect(rs.requiresDataBackup, false);
    });

    test('toJson produces correct map', () {
      final rs = RollbackScript(
        originalDdl: 'DROP TABLE users',
        rollbackDdl: '-- Cannot rollback DROP TABLE',
        description: 'Data will be lost',
        requiresDataBackup: true,
      );
      final json = rs.toJson();
      expect(json['originalDdl'], 'DROP TABLE users');
      expect(json['requiresDataBackup'], true);
    });
  });

  group('ImpactReport', () {
    final report = ImpactReport(
      ddlStatement: 'ALTER TABLE users DROP COLUMN email',
      targetTable: 'users',
      ddlType: 'DROP_COLUMN',
      riskLevel: RiskLevel.high,
      affectedObjects: [
        AffectedObject(
          type: AffectedObjectType.view,
          name: 'user_emails',
          impactDescription: 'View references dropped column',
        ),
        AffectedObject(
          type: AffectedObjectType.index_,
          name: 'idx_email',
          impactDescription: 'Index on dropped column',
        ),
      ],
      dependencies: [
        SchemaDependency(
          sourceTable: 'users',
          sourceColumn: 'email',
          dependentObject: 'user_emails',
          dependentType: AffectedObjectType.view,
          relationship: 'Used in view definition',
        ),
      ],
      rollbackScript: RollbackScript(
        originalDdl: 'ALTER TABLE users DROP COLUMN email',
        rollbackDdl: 'ALTER TABLE users ADD COLUMN email VARCHAR(255)',
        description: 'Restore email column (data will be lost)',
        requiresDataBackup: true,
      ),
      warnings: ['Data loss: email column values will be permanently deleted'],
      recommendations: ['Backup the email column data before proceeding'],
      requiresConfirmation: true,
      analyzedAt: DateTime(2026, 6, 1, 12, 0),
    );

    test('fields are correctly set', () {
      expect(report.ddlStatement, contains('DROP COLUMN email'));
      expect(report.targetTable, 'users');
      expect(report.ddlType, 'DROP_COLUMN');
      expect(report.riskLevel, RiskLevel.high);
      expect(report.affectedObjects.length, 2);
      expect(report.dependencies.length, 1);
      expect(report.warnings.length, 1);
      expect(report.requiresConfirmation, true);
    });

    test('affectedObjectCounts groups by type', () {
      final counts = report.affectedObjectCounts;
      expect(counts['view'], 1);
      expect(counts['index_'], 1);
    });

    test('hasDataLossRisk detects data loss warnings', () {
      expect(report.hasDataLossRisk, true);

      final safeReport = ImpactReport(
        ddlStatement: 'ALTER TABLE users ADD COLUMN phone VARCHAR(20)',
        targetTable: 'users',
        ddlType: 'ADD_COLUMN',
        riskLevel: RiskLevel.low,
        affectedObjects: [],
        dependencies: [],
        warnings: ['Minor schema change'],
        recommendations: [],
        requiresConfirmation: false,
        analyzedAt: DateTime(2026, 6, 1),
      );
      expect(safeReport.hasDataLossRisk, false);
    });

    test('toJson includes computed properties', () {
      final json = report.toJson();
      expect(json['ddlStatement'], report.ddlStatement);
      expect(json['targetTable'], 'users');
      expect(json['riskLevel'], 'high');
      expect(json['hasDataLossRisk'], true);
      expect(json['requiresConfirmation'], true);
      expect(json['affectedObjectCounts'], isA<Map>());
      expect(json['analyzedAt'], isA<String>());
    });
  });
}
