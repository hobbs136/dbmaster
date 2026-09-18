import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/code_snippet.dart';

class CodeSnippetService {
  static const int maxCustomSnippets = 50;
  static const String _storageKey = 'code_snippets_custom';
  static const String _storageVersionKey = 'code_snippets_version';
  static const String _currentVersion = '1.1'; // 020-mongo US3 — databaseFamily 字段
  static const String _builtInUsageKey = 'code_snippets_builtin_usage';

  late SharedPreferences _prefs;
  final List<CodeSnippet> _builtInSnippets = [];
  final List<CodeSnippet> _customSnippets = [];
  final Map<String, int> _builtInUsageCounts = {};

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _initBuiltInSnippets();
    await _loadCustomSnippets();
  }

  void _initBuiltInSnippets() {
    _builtInSnippets.addAll([
      // DML (8)
      CodeSnippet(
        id: 'builtin-select-all',
        name: 'Select All',
        description: 'Select all records from a table',
        category: 'DML',
        content: 'SELECT * FROM {{tableName}};',
        variables: ['tableName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-select-where',
        name: 'Select Where',
        description: 'Select records with WHERE clause',
        category: 'DML',
        content: "SELECT * FROM {{tableName}} WHERE {{column}} = '{{value}}';",
        variables: ['tableName', 'column', 'value'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-insert',
        name: 'Insert',
        description: 'Insert a new record',
        category: 'DML',
        content: 'INSERT INTO {{tableName}} ({{columns}}) VALUES ({{values}});',
        variables: ['tableName', 'columns', 'values'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-update',
        name: 'Update',
        description: 'Update existing records',
        category: 'DML',
        content:
            "UPDATE {{tableName}} SET {{column}} = '{{value}}' WHERE id = 1;",
        variables: ['tableName', 'column', 'value'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-delete',
        name: 'Delete',
        description: 'Delete records',
        category: 'DML',
        content: 'DELETE FROM {{tableName}} WHERE id = 1;',
        variables: ['tableName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-count',
        name: 'Count',
        description: 'Count all records in a table',
        category: 'DML',
        content: 'SELECT COUNT(*) FROM {{tableName}};',
        variables: ['tableName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-limit',
        name: 'Limit',
        description: 'Select with LIMIT clause',
        category: 'DML',
        content: 'SELECT * FROM {{tableName}} LIMIT {{limit}};',
        variables: ['tableName', 'limit'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-order-by',
        name: 'Order By',
        description: 'Select with ORDER BY clause',
        category: 'DML',
        content: 'SELECT * FROM {{tableName}} ORDER BY {{column}} DESC;',
        variables: ['tableName', 'column'],
        isBuiltIn: true,
      ),
      // DDL (6)
      CodeSnippet(
        id: 'builtin-create-table',
        name: 'Create Table',
        description: 'Create a new table with id and timestamp',
        category: 'DDL',
        content: '''CREATE TABLE {{tableName}} (
  id INT PRIMARY KEY AUTO_INCREMENT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);''',
        variables: ['tableName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-alter-table',
        name: 'Alter Table',
        description: 'Add a column to existing table',
        category: 'DDL',
        content:
            'ALTER TABLE {{tableName}} ADD COLUMN {{columnName}} {{dataType}};',
        variables: ['tableName', 'columnName', 'dataType'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-drop-table',
        name: 'Drop Table',
        description: 'Drop a table if it exists',
        category: 'DDL',
        content: 'DROP TABLE IF EXISTS {{tableName}};',
        variables: ['tableName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-create-index',
        name: 'Create Index',
        description: 'Create an index on a column',
        category: 'DDL',
        content:
            'CREATE INDEX {{indexName}} ON {{tableName}} ({{columnName}});',
        variables: ['indexName', 'tableName', 'columnName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-drop-index',
        name: 'Drop Index',
        description: 'Drop an index',
        category: 'DDL',
        content: 'DROP INDEX {{indexName}} ON {{tableName}};',
        variables: ['indexName', 'tableName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-truncate',
        name: 'Truncate',
        description: 'Truncate a table',
        category: 'DDL',
        content: 'TRUNCATE TABLE {{tableName}};',
        variables: ['tableName'],
        isBuiltIn: true,
      ),
      // Query (4)
      CodeSnippet(
        id: 'builtin-join',
        name: 'Inner Join',
        description: 'Join two tables',
        category: 'Query',
        content: '''SELECT * FROM {{table1}}
INNER JOIN {{table2}} ON {{table1}}.{{column1}} = {{table2}}.{{column2}};''',
        variables: ['table1', 'table2', 'column1', 'column2'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-group-by',
        name: 'Group By',
        description: 'Group by with COUNT',
        category: 'Query',
        content: '''SELECT {{column}}, COUNT(*) 
FROM {{tableName}} 
GROUP BY {{column}};''',
        variables: ['tableName', 'column'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-subquery',
        name: 'Subquery',
        description: 'SELECT with subquery',
        category: 'Query',
        content: '''SELECT * FROM {{tableName}} 
WHERE {{column}} IN (
  SELECT {{column}} FROM {{otherTable}} WHERE {{condition}}
);''',
        variables: ['tableName', 'otherTable', 'column', 'condition'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-union',
        name: 'Union',
        description: 'UNION two SELECTs',
        category: 'Query',
        content: '''SELECT {{column}} FROM {{table1}}
UNION
SELECT {{column}} FROM {{table2}};''',
        variables: ['table1', 'table2', 'column'],
        isBuiltIn: true,
      ),
      // Utility (2)
      CodeSnippet(
        id: 'builtin-explain',
        name: 'Explain',
        description: 'EXPLAIN SELECT query',
        category: 'Utility',
        content: 'EXPLAIN SELECT * FROM {{tableName}};',
        variables: ['tableName'],
        isBuiltIn: true,
      ),
      CodeSnippet(
        id: 'builtin-show-tables',
        name: 'Show Tables',
        description: 'Show all tables in database',
        category: 'Utility',
        content: 'SHOW TABLES;',
        variables: [],
        isBuiltIn: true,
      ),
      // 020-mongo US3 — Mongo 内置片段（databaseFamily: mongodb）
      CodeSnippet(
        id: 'builtin-mongo-find',
        name: 'Mongo Find',
        description: 'Find documents in a collection',
        category: 'Mongo CRUD',
        content: r'db.{{collection}}.find({{filter}});',
        variables: ['collection', 'filter'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
      CodeSnippet(
        id: 'builtin-mongo-find-one',
        name: 'Mongo Find One',
        description: 'Find a single document',
        category: 'Mongo CRUD',
        content: r'db.{{collection}}.findOne({{filter}});',
        variables: ['collection', 'filter'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
      CodeSnippet(
        id: 'builtin-mongo-insert',
        name: 'Mongo Insert',
        description: 'Insert one document',
        category: 'Mongo CRUD',
        content: r'db.{{collection}}.insertOne({{document}});',
        variables: ['collection', 'document'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
      CodeSnippet(
        id: 'builtin-mongo-update',
        name: 'Mongo Update',
        description: 'Update one document with \$set',
        category: 'Mongo CRUD',
        content: r'db.{{collection}}.updateOne({{filter}}, {$set: {{update}}});',
        variables: ['collection', 'filter', 'update'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
      CodeSnippet(
        id: 'builtin-mongo-delete',
        name: 'Mongo Delete',
        description: 'Delete one document',
        category: 'Mongo CRUD',
        content: r'db.{{collection}}.deleteOne({{filter}});',
        variables: ['collection', 'filter'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
      CodeSnippet(
        id: 'builtin-mongo-aggregate',
        name: 'Mongo Aggregate',
        description: 'Aggregate with \$match and \$group',
        category: 'Mongo Aggregation',
        content:
            r'db.{{collection}}.aggregate([{$match: {{match}}}, {$group: {_id: {{groupKey}}, count: {$sum: 1}}}]);',
        variables: ['collection', 'match', 'groupKey'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
      CodeSnippet(
        id: 'builtin-mongo-create-index',
        name: 'Mongo Create Index',
        description: 'Create an index on a field',
        category: 'Mongo Index',
        content: r'db.{{collection}}.createIndex({{field}}: 1);',
        variables: ['collection', 'field'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
      CodeSnippet(
        id: 'builtin-mongo-count',
        name: 'Mongo Count',
        description: 'Count documents matching a filter',
        category: 'Mongo Utility',
        content: r'db.{{collection}}.countDocuments({{filter}});',
        variables: ['collection', 'filter'],
        isBuiltIn: true,
        databaseFamily: SnippetDbFamily.mongodb,
      ),
    ]);
    // 020-mongo US3 — 所有未显式标注族的内置片段归为 sql 族
    // （保留「SQL tab 显示」，Mongo tab 过滤时隐藏）。用户自定义片段默认 all（见 _parseFamily）。
    for (var i = 0; i < _builtInSnippets.length; i++) {
      if (_builtInSnippets[i].databaseFamily == SnippetDbFamily.all) {
        _builtInSnippets[i] = _builtInSnippets[i].copyWith(
          databaseFamily: SnippetDbFamily.sql,
        );
      }
    }
  }

  Future<void> _loadCustomSnippets() async {
    final version = _prefs.getString(_storageVersionKey);
    if (version != _currentVersion) {
      // 020-mongo US3 — 1.0→1.1 新增 databaseFamily 字段。
      // 旧自定义片段 JSON 缺该字段时，CodeSnippet._parseFamily 回退 SnippetDbFamily.all，
      // 无需显式数据迁移（向后兼容，自定义片段继续在所有数据库类型显示）。
      await _prefs.setString(_storageVersionKey, _currentVersion);
    }

    final jsonString = _prefs.getString(_storageKey);
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _customSnippets.clear();
        _customSnippets.addAll(
          jsonList.map(
            (json) => CodeSnippet.fromJson(json as Map<String, dynamic>),
          ),
        );
      } catch (e) {
        _errorController.add('Failed to load custom snippets: $e');
      }
    }

    // Load built-in usage counts
    final builtInUsageJson = _prefs.getString(_builtInUsageKey);
    if (builtInUsageJson != null) {
      try {
        final usageMap = jsonDecode(builtInUsageJson) as Map<String, dynamic>;
        _builtInUsageCounts.clear();
        _builtInUsageCounts.addAll(
          usageMap.map((key, value) => MapEntry(key, value as int)),
        );
      } catch (e) {
        _errorController.add('Failed to load built-in usage counts: $e');
      }
    }
  }

  Future<void> _saveBuiltInUsage() async {
    try {
      final jsonString = jsonEncode(_builtInUsageCounts);
      await _prefs.setString(_builtInUsageKey, jsonString);
    } catch (e) {
      _errorController.add('Failed to save built-in usage counts: $e');
    }
  }

  Future<void> _saveCustomSnippets() async {
    try {
      final jsonList = _customSnippets.map((s) => s.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await _prefs.setString(_storageKey, jsonString);
    } catch (e) {
      _errorController.add('Failed to save custom snippets: $e');
    }
  }

  List<CodeSnippet> getAllSnippets() {
    final builtInWithUsage = _builtInSnippets.map((s) {
      final usageCount = _builtInUsageCounts[s.id] ?? 0;
      return s.copyWith(usageCount: usageCount);
    }).toList();
    return [...builtInWithUsage, ..._customSnippets];
  }

  List<CodeSnippet> getSnippetsByCategory(String category) {
    return getAllSnippets().where((s) => s.category == category).toList();
  }

  List<CodeSnippet> searchSnippets(String query) {
    final lowerQuery = query.toLowerCase();
    return getAllSnippets()
        .where(
          (s) =>
              s.name.toLowerCase().contains(lowerQuery) ||
              s.description.toLowerCase().contains(lowerQuery),
        )
        .toList();
  }

  List<CodeSnippet> getFrequentlyUsed({int limit = 10}) {
    final sorted = getAllSnippets().where((s) => s.usageCount > 0).toList()
      ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
    return sorted.take(limit).toList();
  }

  List<CodeSnippet> getRecentlyUsed({int limit = 10}) {
    final sorted = getAllSnippets().where((s) => s.lastUsedAt != null).toList()
      ..sort((a, b) => b.lastUsedAt!.compareTo(a.lastUsedAt!));
    return sorted.take(limit).toList();
  }

  // Validation methods
  void _validateSnippetId(String id) {
    if (id.isEmpty) {
      throw ArgumentError('Snippet ID cannot be empty');
    }
    if (id.startsWith('builtin-')) {
      throw ArgumentError(
        'ID cannot start with "builtin-" (reserved for built-in snippets)',
      );
    }
    if (_customSnippets.any((s) => s.id == id)) {
      throw ArgumentError('Snippet with ID "$id" already exists');
    }
  }

  void _validateSnippetContent(String content) {
    if (content.isEmpty) {
      throw ArgumentError('Snippet content cannot be empty');
    }
    if (content.length > 10000) {
      throw ArgumentError('Snippet content too long (max 10000 chars)');
    }
  }

  Future<void> addSnippet(CodeSnippet snippet) async {
    _validateSnippetId(snippet.id);
    _validateSnippetContent(snippet.content);

    if (!snippet.isBuiltIn && _customSnippets.length >= maxCustomSnippets) {
      throw StateError(
        'Maximum number of custom snippets ($maxCustomSnippets) reached',
      );
    }

    if (_builtInSnippets.any((s) => s.id == snippet.id)) {
      throw ArgumentError('Snippet with ID "${snippet.id}" already exists');
    }

    _customSnippets.add(snippet);
    await _saveCustomSnippets();
  }

  Future<void> updateSnippet(CodeSnippet snippet) async {
    if (snippet.isBuiltIn) {
      throw StateError('Cannot update built-in snippets');
    }

    final index = _customSnippets.indexWhere((s) => s.id == snippet.id);
    if (index == -1) {
      throw ArgumentError('Snippet with ID "${snippet.id}" not found');
    }

    _validateSnippetContent(snippet.content);

    _customSnippets[index] = snippet.copyWith(updatedAt: DateTime.now());
    await _saveCustomSnippets();
  }

  Future<void> removeSnippet(String id) async {
    // Check if it's a built-in snippet first
    if (_builtInSnippets.any((s) => s.id == id)) {
      throw StateError('Cannot remove built-in snippets');
    }

    _customSnippets.firstWhere(
      (s) => s.id == id,
      orElse: () => throw ArgumentError('Snippet with ID "$id" not found'),
    );

    _customSnippets.removeWhere((s) => s.id == id);
    await _saveCustomSnippets();
  }

  Future<CodeSnippet?> incrementUsage(String id) async {
    // Check built-in snippets
    final builtInIndex = _builtInSnippets.indexWhere((s) => s.id == id);
    if (builtInIndex != -1) {
      // Track usage in memory for built-in snippets
      final currentCount = _builtInUsageCounts[id] ?? 0;
      _builtInUsageCounts[id] = currentCount + 1;

      // Persist built-in usage counts
      await _saveBuiltInUsage();

      return _builtInSnippets[builtInIndex].copyWith(
        usageCount: currentCount + 1,
        lastUsedAt: DateTime.now(),
      );
    }

    // Check custom snippets
    final customIndex = _customSnippets.indexWhere((s) => s.id == id);
    if (customIndex != -1) {
      final updated = _customSnippets[customIndex].incrementUsage();
      _customSnippets[customIndex] = updated;
      await _saveCustomSnippets();
      return updated;
    }

    throw ArgumentError('Snippet not found: $id');
  }

  void dispose() {
    _errorController.close();
  }
}
