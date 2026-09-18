import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/backup_models.dart';

void main() {
  group('BackupFile', () {
    final now = DateTime(2026, 6, 1, 12, 0);
    final file = BackupFile(
      id: 'bf-1',
      name: 'my_backup',
      type: 'sql',
      size: 1024 * 512,
      createdAt: now,
      database: 'test_db',
      tables: ['users', 'products'],
      description: 'Daily backup',
      connectionId: 'conn-1',
    );

    test('toJson produces correct map', () {
      final json = file.toJson();
      expect(json['id'], 'bf-1');
      expect(json['name'], 'my_backup');
      expect(json['type'], 'sql');
      expect(json['size'], 1024 * 512);
      expect(json['tables'], ['users', 'products']);
    });

    test('fromJson creates correct object', () {
      final json = file.toJson();
      final restored = BackupFile.fromJson(json);
      expect(restored.id, 'bf-1');
      expect(restored.name, 'my_backup');
      expect(restored.size, 1024 * 512);
      expect(restored.tables, ['users', 'products']);
      expect(restored.description, 'Daily backup');
    });

    test('sizeFormatted returns correct units', () {
      expect(
        BackupFile(
          id: 'b',
          name: 'b',
          type: 'sql',
          size: 500,
          createdAt: now,
          database: 'd',
          tables: [],
        ).sizeFormatted,
        '500B',
      );
      expect(
        BackupFile(
          id: 'b',
          name: 'b',
          type: 'sql',
          size: 2048,
          createdAt: now,
          database: 'd',
          tables: [],
        ).sizeFormatted,
        '2.0KB',
      );
      expect(
        BackupFile(
          id: 'b',
          name: 'b',
          type: 'sql',
          size: 2 * 1024 * 1024 + 500000,
          createdAt: now,
          database: 'd',
          tables: [],
        ).sizeFormatted,
        contains('MB'),
      );
    });

    test('typeDisplay returns display string', () {
      expect(file.typeDisplay, 'SQL 脚本');
      expect(
        BackupFile(
          id: 'b',
          name: 'b',
          type: 'json',
          size: 0,
          createdAt: now,
          database: 'd',
          tables: [],
        ).typeDisplay,
        'JSON 数据',
      );
      expect(
        BackupFile(
          id: 'b',
          name: 'b',
          type: 'csv',
          size: 0,
          createdAt: now,
          database: 'd',
          tables: [],
        ).typeDisplay,
        'CSV 数据',
      );
    });

    test('copyWith updates specified fields', () {
      final copied = file.copyWith(name: 'new_name', size: 999);
      expect(copied.name, 'new_name');
      expect(copied.size, 999);
      expect(copied.id, file.id);
    });
  });

  group('BackupOptions', () {
    test('defaults are correct', () {
      final opts = BackupOptions();
      expect(opts.includeStructure, true);
      expect(opts.includeData, true);
      expect(opts.format, 'sql');
      expect(opts.addDropTable, true);
      expect(opts.addIfNotExists, true);
      expect(opts.completeInsert, false);
      expect(opts.extendedInsert, true);
      expect(opts.tables, isEmpty);
    });

    test('toJson/fromJson round-trip', () {
      final opts = BackupOptions(
        includeData: false,
        format: 'json',
        tables: ['users'],
        whereClause: 'id > 10',
        limit: 1000,
      );
      final restored = BackupOptions.fromJson(opts.toJson());
      expect(restored.includeData, false);
      expect(restored.format, 'json');
      expect(restored.tables, ['users']);
      expect(restored.whereClause, 'id > 10');
      expect(restored.limit, 1000);
    });

    test('copyWith updates fields', () {
      final opts = BackupOptions();
      final copied = opts.copyWith(format: 'csv', includeData: false);
      expect(copied.format, 'csv');
      expect(copied.includeData, false);
      expect(copied.includeStructure, true); // unchanged
    });
  });

  group('ImportOptions', () {
    test('defaults are correct', () {
      final opts = ImportOptions();
      expect(opts.format, 'sql');
      expect(opts.incremental, false);
      expect(opts.skipErrors, false);
      expect(opts.charset, 'utf8mb4');
    });

    test('toJson/fromJson round-trip', () {
      final opts = ImportOptions(
        format: 'csv',
        truncateBeforeImport: true,
        targetTable: 'users',
        columnMapping: ['id', 'name'],
      );
      final restored = ImportOptions.fromJson(opts.toJson());
      expect(restored.format, 'csv');
      expect(restored.truncateBeforeImport, true);
      expect(restored.targetTable, 'users');
      expect(restored.columnMapping, ['id', 'name']);
    });
  });

  group('BackupProgress', () {
    test('defaults are correct', () {
      final p = BackupProgress();
      expect(p.status, 'idle');
      expect(p.progress, 0.0);
      expect(p.processedRows, 0);
    });

    test('copyWith updates fields', () {
      final p = BackupProgress();
      final copied = p.copyWith(
        status: 'running',
        progress: 0.5,
        processedRows: 500,
      );
      expect(copied.status, 'running');
      expect(copied.progress, 0.5);
      expect(copied.processedRows, 500);
    });
  });
}
