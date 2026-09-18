import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/import_models.dart';

void main() {
  group('ImportFormat', () {
    test('has 3 values', () {
      expect(ImportFormat.values.length, 3);
      expect(
        ImportFormat.values,
        containsAll([ImportFormat.csv, ImportFormat.json, ImportFormat.excel]),
      );
    });
  });

  group('ImportStatus', () {
    test('has 4 values', () {
      expect(ImportStatus.values.length, 4);
    });
  });

  group('ImportConfig', () {
    test('defaults are correct', () {
      final cfg = ImportConfig(tableName: 'users', format: ImportFormat.csv);
      expect(cfg.hasHeader, true);
      expect(cfg.delimiter, ',');
      expect(cfg.overwriteTable, false);
      expect(cfg.batchSize, 100);
    });

    test('copyWith updates fields', () {
      final cfg = ImportConfig(tableName: 'users', format: ImportFormat.csv);
      final copied = cfg.copyWith(delimiter: ';', batchSize: 500);
      expect(copied.delimiter, ';');
      expect(copied.batchSize, 500);
      expect(copied.tableName, 'users'); // unchanged
    });
  });

  group('ImportProgress', () {
    test('progress percentage calculation', () {
      final p = ImportProgress(
        totalRecords: 200,
        importedRecords: 50,
        status: ImportStatus.importing,
      );
      expect(p.progress, closeTo(25.0, 0.1));
    });

    test('progress at 100%', () {
      final p = ImportProgress(
        totalRecords: 100,
        importedRecords: 100,
        status: ImportStatus.success,
      );
      expect(p.progress, closeTo(100.0, 0.1));
    });

    test('progress zero total returns 0', () {
      final p = ImportProgress(
        totalRecords: 0,
        importedRecords: 0,
        status: ImportStatus.ready,
      );
      expect(p.progress, 0);
    });

    test('isCompleted for success and failed statuses', () {
      expect(
        ImportProgress(
          totalRecords: 0,
          importedRecords: 0,
          status: ImportStatus.success,
        ).isCompleted,
        true,
      );
      expect(
        ImportProgress(
          totalRecords: 0,
          importedRecords: 0,
          status: ImportStatus.failed,
        ).isCompleted,
        true,
      );
      expect(
        ImportProgress(
          totalRecords: 0,
          importedRecords: 0,
          status: ImportStatus.importing,
        ).isCompleted,
        false,
      );
    });

    test('copyWith updates fields', () {
      final p = ImportProgress(
        totalRecords: 100,
        importedRecords: 50,
        status: ImportStatus.importing,
      );
      final copied = p.copyWith(importedRecords: 75, failedRecords: 5);
      expect(copied.importedRecords, 75);
      expect(copied.failedRecords, 5);
      expect(copied.totalRecords, 100);
    });
  });

  group('ImportDataRow', () {
    test('defaults are valid', () {
      final row = ImportDataRow(data: {'name': 'test'}, rowNumber: 1);
      expect(row.isValid, true);
      expect(row.errorMessage, isNull);
    });

    test('invalid row with error', () {
      final row = ImportDataRow(
        data: {},
        rowNumber: 2,
        isValid: false,
        errorMessage: 'Missing required field',
      );
      expect(row.isValid, false);
      expect(row.errorMessage, 'Missing required field');
    });

    test('copyWith updates fields', () {
      final row = ImportDataRow(data: {'x': 1}, rowNumber: 3);
      final copied = row.copyWith(rowNumber: 4);
      expect(copied.rowNumber, 4);
      expect(copied.data['x'], 1);
    });
  });

  group('ImportPreview', () {
    test('toJson/fromJson round-trip through fields', () {
      final preview = ImportPreview(
        format: ImportFormat.json,
        fileName: 'data.json',
        data: [
          ImportDataRow(data: {'id': 1}, rowNumber: 1),
        ],
        fields: ['id', 'name'],
        totalRows: 100,
        success: true,
      );
      expect(preview.format, ImportFormat.json);
      expect(preview.fileName, 'data.json');
      expect(preview.fields.length, 2);
      expect(preview.totalRows, 100);
      expect(preview.success, true);
    });

    test('copyWith updates fields', () {
      final preview = ImportPreview(
        format: ImportFormat.csv,
        fileName: 'f',
        data: [],
        fields: [],
        totalRows: 0,
        success: true,
      );
      final copied = preview.copyWith(fileName: 'new.csv', totalRows: 50);
      expect(copied.fileName, 'new.csv');
      expect(copied.totalRows, 50);
    });
  });
}
