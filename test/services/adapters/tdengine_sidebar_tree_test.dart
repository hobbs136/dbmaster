import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/tdengine_models.dart';

/// TDengine Sidebar Tree 结构测试
void main() {
  group('TDengine 树形结构数据模型', () {
    test('超级表应包含列和标签', () {
      final superTable = TdSuperTable(
        name: 'meters',
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP', isPrimaryKey: true),
          TdColumn(name: 'current', type: 'FLOAT'),
          TdColumn(name: 'voltage', type: 'INT'),
        ],
        tags: [
          TdTag(name: 'location', type: 'BINARY(64)'),
          TdTag(name: 'group_id', type: 'INT'),
        ],
      );

      expect(superTable.name, equals('meters'));
      expect(superTable.columns.length, equals(3));
      expect(superTable.tags.length, equals(2));
      expect(superTable.columns.first.isPrimaryKey, isTrue);
    });

    test('子表应关联到超级表并包含标签值', () {
      final subTable = TdSubTable(
        name: 'd1001',
        superTableName: 'meters',
        tags: {'location': 'California.SanFrancisco', 'group_id': 2},
      );

      expect(subTable.name, equals('d1001'));
      expect(subTable.superTableName, equals('meters'));
      expect(subTable.tags['location'], equals('California.SanFrancisco'));
      expect(subTable.tags['group_id'], equals(2));
    });

    test('超级表 JSON 序列化应正确', () {
      final superTable = TdSuperTable(
        name: 'test_table',
        columns: [TdColumn(name: 'ts', type: 'TIMESTAMP')],
        tags: [TdTag(name: 'device', type: 'BINARY(32)')],
        comment: 'Test super table',
      );

      final json = superTable.toJson();
      expect(json['name'], equals('test_table'));
      expect(json['comment'], equals('Test super table'));
      expect(json['columns'], isA<List>());
      expect(json['tags'], isA<List>());

      final restored = TdSuperTable.fromJson(json);
      expect(restored.name, equals('test_table'));
      expect(restored.comment, equals('Test super table'));
    });
  });

  group('TDengine 标识符验证（树形结构）', () {
    test('超级表名应合法', () {
      expect(_isValidTdIdentifier('meters'), isTrue);
      expect(_isValidTdIdentifier('device_data'), isTrue);
    });

    test('包含危险字符的表名应被拒绝', () {
      expect(_isValidTdIdentifier('meters;drop'), isFalse);
      expect(_isValidTdIdentifier('table--'), isFalse);
    });
  });

  group('TDengine 系统数据库过滤', () {
    test('应过滤 information_schema', () {
      final databases = ['my_db', 'information_schema', 'test_db'];
      final filtered = _filterSystemDatabases(databases);
      expect(filtered, equals(['my_db', 'test_db']));
    });

    test('应过滤 performance_schema', () {
      final databases = ['my_db', 'performance_schema', 'test_db'];
      final filtered = _filterSystemDatabases(databases);
      expect(filtered, equals(['my_db', 'test_db']));
    });

    test('应同时过滤多个系统数据库', () {
      final databases = [
        'my_db',
        'information_schema',
        'performance_schema',
        'test_db',
      ];
      final filtered = _filterSystemDatabases(databases);
      expect(filtered, equals(['my_db', 'test_db']));
    });

    test('大小写不敏感过滤', () {
      final databases = ['my_db', 'INFORMATION_SCHEMA', 'Performance_Schema'];
      final filtered = _filterSystemDatabases(databases);
      expect(filtered, equals(['my_db']));
    });

    test('无系统数据库时应保持不变', () {
      final databases = ['my_db', 'test_db', 'iot_data'];
      final filtered = _filterSystemDatabases(databases);
      expect(filtered, equals(databases));
    });
  });

  group('超级表缓存键应包含数据库名', () {
    test('不同数据库的超级表应使用不同缓存键', () {
      final key1 = _buildSuperTableCacheKey('conn1', 'db1');
      final key2 = _buildSuperTableCacheKey('conn1', 'db2');
      expect(key1, isNot(equals(key2)));
    });

    test('相同数据库应使用相同缓存键', () {
      final key1 = _buildSuperTableCacheKey('conn1', 'db1');
      final key2 = _buildSuperTableCacheKey('conn1', 'db1');
      expect(key1, equals(key2));
    });

    test('不同连接的相同数据库应使用不同缓存键', () {
      final key1 = _buildSuperTableCacheKey('conn1', 'db1');
      final key2 = _buildSuperTableCacheKey('conn2', 'db1');
      expect(key1, isNot(equals(key2)));
    });
  });
}

bool _isValidTdIdentifier(String name) {
  if (name.isEmpty) return false;
  final dangerousChars = RegExp(
    r'''[;\-\-\*/\\'"`\s!@#\$%\^\u0026\*\(\)\+={}\[\]|:\u003c\u003e,\?]''',
  );
  if (dangerousChars.hasMatch(name)) {
    return false;
  }
  return true;
}

final _systemDatabases = {'information_schema', 'performance_schema'};

List<String> _filterSystemDatabases(List<String> databases) {
  return databases
      .where((db) => !_systemDatabases.contains(db.toLowerCase()))
      .toList();
}

String _buildSuperTableCacheKey(String connectionId, String databaseName) {
  return '$connectionId:$databaseName';
}
