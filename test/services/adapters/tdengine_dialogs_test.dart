import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/tdengine_models.dart';

/// TDengine 对话框逻辑测试
void main() {
  group('创建超级表对话框逻辑', () {
    test('应验证超级表名不为空', () {
      final name = '';
      expect(_isValidSuperTableName(name), isFalse);
    });

    test('应验证超级表名不包含特殊字符', () {
      expect(_isValidSuperTableName('meters'), isTrue);
      expect(_isValidSuperTableName('device_001'), isTrue);
      expect(_isValidSuperTableName('table;drop'), isFalse);
      expect(_isValidSuperTableName('name--'), isFalse);
    });

    test('应要求至少一个列且第一列为 TIMESTAMP', () {
      final columns = [
        TdColumn(name: 'ts', type: 'TIMESTAMP'),
        TdColumn(name: 'current', type: 'FLOAT'),
      ];
      expect(_validateSuperTableColumns(columns), isNull);
    });

    test('缺少 TIMESTAMP 列应返回错误', () {
      final columns = [TdColumn(name: 'current', type: 'FLOAT')];
      expect(
        _validateSuperTableColumns(columns),
        equals('第一列必须是 TIMESTAMP 类型'),
      );
    });

    test('空列列表应返回错误', () {
      final columns = <TdColumn>[];
      expect(_validateSuperTableColumns(columns), equals('至少需要一个列'));
    });

    test('应要求至少一个标签', () {
      final tags = <TdTag>[];
      expect(_validateSuperTableTags(tags), equals('至少需要一个标签'));
    });

    test('标签列表有效应返回 null', () {
      final tags = [TdTag(name: 'location', type: 'BINARY(64)')];
      expect(_validateSuperTableTags(tags), isNull);
    });
  });

  group('TDengine SQL 生成', () {
    test('应生成正确的 CREATE STABLE SQL', () {
      final name = 'meters';
      final columns = [
        TdColumn(name: 'ts', type: 'TIMESTAMP'),
        TdColumn(name: 'current', type: 'FLOAT'),
        TdColumn(name: 'voltage', type: 'INT'),
      ];
      final tags = [
        TdTag(name: 'location', type: 'BINARY(64)'),
        TdTag(name: 'group_id', type: 'INT'),
      ];

      final sql = _buildCreateStableSql(name, columns, tags);
      expect(sql, contains('CREATE STABLE IF NOT EXISTS'));
      expect(sql, contains('meters'));
      expect(sql, contains('(ts TIMESTAMP, current FLOAT, voltage INT)'));
      expect(sql, contains('TAGS (location BINARY(64), group_id INT)'));
    });
  });
}

bool _isValidSuperTableName(String name) {
  if (name.isEmpty) return false;
  if (RegExp(
    r'''[;\-\-\*/\\'"`\s!@#\$%\^\u0026\*\(\)\+={}\[\]|:\u003c\u003e,\?]''',
  ).hasMatch(name)) {
    return false;
  }
  return true;
}

String? _validateSuperTableColumns(List<TdColumn> columns) {
  if (columns.isEmpty) return '至少需要一个列';
  if (columns.first.type != 'TIMESTAMP') return '第一列必须是 TIMESTAMP 类型';
  return null;
}

String? _validateSuperTableTags(List<TdTag> tags) {
  if (tags.isEmpty) return '至少需要一个标签';
  return null;
}

String _buildCreateStableSql(
  String name,
  List<TdColumn> columns,
  List<TdTag> tags,
) {
  final columnDefs = columns.map((c) => '${c.name} ${c.type}').join(', ');
  final tagDefs = tags
      .map((t) {
        if (t.length != null &&
            (t.type.contains('BINARY') || t.type.contains('NCHAR'))) {
          return '${t.name} ${t.type}(${t.length})';
        }
        return '${t.name} ${t.type}';
      })
      .join(', ');
  return 'CREATE STABLE IF NOT EXISTS $name ($columnDefs) TAGS ($tagDefs)';
}
