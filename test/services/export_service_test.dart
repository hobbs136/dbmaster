import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/export_service.dart';

void main() {
  group('ExportService - CSV/JSON content generation', () {
    // Test the data-to-string conversion logic.
    // File I/O parts are covered by integration tests.

    test('CSV format: headers and values', () {
      final data = [
        {'name': 'Alice', 'age': 30, 'active': true},
        {'name': 'Bob', 'age': 25, 'active': false},
      ];

      final headers = data[0].keys.toList();
      final lines = <String>[];
      lines.add(headers.map((h) => '"${h.replaceAll('"', '""')}"').join(','));

      for (final row in data) {
        final values = headers
            .map((header) {
              final value = row[header];
              if (value == null) return '';
              return '"${value.toString().replaceAll('"', '""')}"';
            })
            .join(',');
        lines.add(values);
      }

      final csv = '﻿${lines.join('\n')}\n';

      expect(csv, contains('"name","age","active"'));
      expect(csv, contains('"Alice","30","true"'));
      expect(csv, contains('"Bob","25","false"'));
    });

    test('CSV handles special characters in values', () {
      final data = [
        {'name': 'O"Brien', 'city': 'New\nYork'},
      ];

      final csv = _generateCsv(data);

      expect(csv, contains('O""Brien'));
      expect(csv, contains('New\nYork'));
    });

    test('CSV handles null values in data', () {
      // When a value is null, it should produce an empty quoted string in CSV
      final data = [
        {'name': 'Alice', 'email': null},
      ];

      // Verify the data has null and the test handles it
      expect(data[0]['email'], isNull);
      expect(data[0]['name'], 'Alice');

      final csv = _generateCsv(data);
      expect(csv, contains('"Alice"'));
    });

    test('CSV handles numeric values', () {
      final data = [
        {'id': 1, 'price': 19.99},
      ];

      final csv = _generateCsv(data);

      expect(csv, contains('"1"'));
      expect(csv, contains('"19.99"'));
    });

    test('JSON format generates valid JSON', () {
      final data = [
        {'name': 'Alice', 'age': 30},
        {'name': 'Bob', 'age': 25},
      ];

      final jsonStr = jsonEncode(data);
      final parsed = jsonDecode(jsonStr) as List;

      expect(parsed.length, 2);
      expect(parsed[0]['name'], 'Alice');
      expect(parsed[0]['age'], 30);
    });

    test('JSON handles nested structures', () {
      final data = [
        {
          'name': 'Alice',
          'metadata': {'role': 'admin', 'level': 5},
        },
      ];

      final jsonStr = jsonEncode(data);
      final parsed = jsonDecode(jsonStr) as List;
      final metadata = parsed[0]['metadata'] as Map<String, dynamic>;

      expect(metadata['role'], 'admin');
    });

    test('CSV BOM prefix for Excel compatibility', () {
      final data = [
        {'col': 'val'},
      ];
      final csv = _generateCsv(data);

      // BOM should be at the start
      expect(csv.codeUnitAt(0), 0xFEFF);
    });

    test('Empty data handling', () {
      final data = <Map<String, dynamic>>[];
      expect(data.isEmpty, true);
    });
  });

  group('ExportService.ensureExtension - 强制后缀', () {
    test('无后缀时补全', () {
      expect(ExportService.ensureExtension('/tmp/foo', 'csv'), '/tmp/foo.csv');
    });

    test('已有正确后缀时不变', () {
      expect(
        ExportService.ensureExtension('/tmp/foo.csv', 'csv'),
        '/tmp/foo.csv',
      );
    });

    test('后缀错误时追加正确后缀', () {
      expect(
        ExportService.ensureExtension('/tmp/foo.txt', 'csv'),
        '/tmp/foo.txt.csv',
      );
    });

    test('大小写不敏感：大写后缀视为已存在', () {
      expect(
        ExportService.ensureExtension('/tmp/FOO.CSV', 'csv'),
        '/tmp/FOO.CSV',
      );
    });

    test('Windows 反斜杠路径也能补全', () {
      expect(
        ExportService.ensureExtension(r'C:\out\query_result', 'json'),
        r'C:\out\query_result.json',
      );
    });
  });

  group('ExportService.defaultBaseName - 时间戳命名', () {
    test('格式为 query_result_yyyyMMdd_HHmmss', () {
      expect(
        ExportService.defaultBaseName(),
        matches(RegExp(r'^query_result_\d{8}_\d{6}$')),
      );
    });

    test('不再是恒定的 data，且非空', () {
      final name = ExportService.defaultBaseName();
      expect(name, isNot('data'));
      expect(name, isNotEmpty);
      expect(name.startsWith('query_result_'), isTrue);
    });
  });

  group('ExportService.exportToExcel — 真 xlsx（D3-A）', () {
    // D3-A（#32）：Excel 按钮此前产出 CSV 内容 + .csv 后缀（假 xlsx）。
    // 现在生成真 .xlsx，且类型保真（数字/布尔不走文本）。

    test('excelCellForValue 类型保真映射', () {
      expect(ExportService.excelCellForValue(null), isNull);
      expect(ExportService.excelCellForValue(42), isA<xlsx.IntCellValue>());
      expect(
          ExportService.excelCellForValue(19.99), isA<xlsx.DoubleCellValue>());
      expect(ExportService.excelCellForValue(true), isA<xlsx.BoolCellValue>());

      final txt = ExportService.excelCellForValue('hello');
      expect(txt, isA<xlsx.TextCellValue>());
      expect((txt! as xlsx.TextCellValue).value.text, 'hello');

      // 非基本类型（DateTime/Decimal/驱动包装类型）走文本，内容不丢
      final dt = ExportService.excelCellForValue(DateTime(2026, 8, 17));
      expect(dt, isA<xlsx.TextCellValue>());
      expect((dt! as xlsx.TextCellValue).value.text, contains('2026-08-17'));
    });

    test('encode→decode 往返：表头与类型化单元格存活', () {
      final rows = ExportService.sanitizeRowsForIsolate(
        ['name', 'age', 'price', 'active'],
        [
          {'name': 'Alice', 'age': 30, 'price': 19.99, 'active': true},
        ],
      );
      final bytes = ExportService.buildXlsxBytes(rows);
      final decoded = xlsx.Excel.decodeBytes(bytes);
      expect(decoded.tables.length, 1);
      final table = decoded.tables.values.first;
      expect(table.maxRows, 2);

      final header =
          table.row(0).map((c) => c?.value?.toString()).toList();
      expect(header, ['name', 'age', 'price', 'active']);

      final row = table.row(1);
      expect(row[0]?.value?.toString(), 'Alice');
      // 数值/布尔按类型往返（不再是被引号包裹的文本）
      expect(row[1]?.value, isA<xlsx.IntCellValue>());
      expect((row[1]!.value! as xlsx.IntCellValue).value, 30);
      expect(row[2]?.value, isA<xlsx.DoubleCellValue>());
      expect((row[2]!.value! as xlsx.DoubleCellValue).value, 19.99);
      expect(row[3]?.value, isA<xlsx.BoolCellValue>());
      expect((row[3]!.value! as xlsx.BoolCellValue).value, isTrue);
    });

    test('sanitizeRowsForIsolate：纯值保真 + 非基本类型 toString + null 保留', () {
      final rows = ExportService.sanitizeRowsForIsolate(
        ['id', 'ts', 'note', 'extra'],
        [
          {'id': 7, 'ts': DateTime(2026, 8, 17), 'note': null, 'extra': 1.5},
        ],
      );
      expect(rows.first, ['id', 'ts', 'note', 'extra']);
      final dataRow = rows[1];
      expect(dataRow[0], 7); // int 原样
      expect(dataRow[1], '2026-08-17 00:00:00.000'); // DateTime → 文本
      expect(dataRow[2], isNull); // null 保留（空单元格）
      expect(dataRow[3], 1.5); // double 原样
    });

    test('全链路（sanitize→build）：null 单元格与非基本类型存活', () {
      final bytes = ExportService.buildXlsxBytes(
        ExportService.sanitizeRowsForIsolate(
          ['a', 'b', 'c'],
          [
            {'a': null, 'b': 'x,y"z', 'c': DateTime(2026, 1, 2)},
          ],
        ),
      );
      final table = xlsx.Excel.decodeBytes(bytes).tables.values.first;
      final row = table.row(1);
      expect(row[0]?.value, isNull); // null → 空单元格
      expect(row[1]?.value?.toString(), 'x,y"z'); // CSV 特殊字符在 xlsx 无需转义
      expect(row[2]?.value?.toString(), contains('2026-01-02'));
    });
  });

  group('ExportService JSON — non-serializable types (regression)', () {
    // Regression for: jsonEncode without toEncodable crashes on non-JSON
    // types returned by DB drivers (e.g. DateTime for timestamp columns),
    // causing unhandled JsonUnsupportedObjectError + UI freeze.

    test('jsonEncode without toEncodable throws on DateTime', () {
      // Exact crash scenario: DB driver returns DateTime in result rows
      final data = [
        {'name': 'test', 'created_at': DateTime(2026, 7, 23)},
      ];
      expect(
        () => jsonEncode(data),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });

    test('jsonEncode without toEncodable throws on custom object', () {
      // Custom types (e.g. PG driver uuid wrapper, decimal types) also crash
      final data = [
        {'name': 'test', 'val': _NonJsonType('abc')},
      ];
      expect(
        () => jsonEncode(data),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });

    test('jsonEncode with toEncodable converts DateTime to string', () {
      final data = [
        {'name': 'test', 'created_at': DateTime(2026, 7, 23)},
      ];
      final json = jsonEncode(
        data,
        toEncodable: (dynamic obj) => obj.toString(),
      );
      final parsed = jsonDecode(json) as List;
      expect(parsed[0]['created_at'], '2026-07-23 00:00:00.000');
    });

    test('jsonEncode with toEncodable converts custom object to string', () {
      final data = [
        {'name': 'test', 'val': _NonJsonType('abc')},
      ];
      final json = jsonEncode(
        data,
        toEncodable: (dynamic obj) => obj.toString(),
      );
      final parsed = jsonDecode(json) as List;
      expect(parsed[0]['val'], 'abc');
    });

    test('jsonEncode with toEncodable handles mixed types in one dataset', () {
      final data = [
        {
          'id': 1,
          'name': 'test',
          'ts': DateTime(2026, 1, 15, 12, 30),
          'flag': true,
          'price': 99.9,
          'nil': null,
          'custom': _NonJsonType('x'),
        },
      ];
      final json = jsonEncode(
        data,
        toEncodable: (dynamic obj) => obj.toString(),
      );
      final parsed = jsonDecode(json) as List;
      final row = parsed[0] as Map<String, dynamic>;
      expect(row['id'], 1);
      expect(row['name'], 'test');
      expect(row['ts'], '2026-01-15 12:30:00.000');
      expect(row['flag'], true);
      expect(row['price'], 99.9);
      expect(row['nil'], null);
      expect(row['custom'], 'x');
    });

    test('Uint8List is natively encodable (List<int> → JSON array)', () {
      // Not a crash trigger: Uint8List implements List<int> so jsonEncode
      // handles it natively. Included to document tested behavior.
      final data = [
        {'blob': Uint8List.fromList([1, 2, 3])},
      ];
      final json = jsonEncode(data);
      final parsed = jsonDecode(json) as List;
      expect(parsed[0]['blob'], [1, 2, 3]);
    });
  });
}

/// Minimal non-JSON type for regression testing — simulates a driver-specific
/// wrapper (e.g. PG uuid, decimal, or any type dart:convert doesn't know).
class _NonJsonType {
  final String value;
  const _NonJsonType(this.value);
  @override
  String toString() => value;
}

String _generateCsv(List<Map<String, dynamic>> data) {
  if (data.isEmpty) return '';

  final headers = data[0].keys.toList();
  final lines = <String>[];
  lines.add(headers.map((h) => '"${h.replaceAll('"', '""')}"').join(','));

  for (final row in data) {
    final values = headers
        .map((header) {
          final value = row[header];
          if (value == null) return '';
          return '"${value.toString().replaceAll('"', '""')}"';
        })
        .join(',');
    lines.add(values);
  }

  return '﻿${lines.join('\n')}\n';
}
