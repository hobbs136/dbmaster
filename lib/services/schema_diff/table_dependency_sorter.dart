import '../../models/er_diagram.dart';

/// Topologically sorts tables based on FOREIGN KEY dependencies.
///
/// Usage:
/// - [sortByCreateOrder] for CREATE TABLE ordering (referenced tables first)
/// - [sortByDropOrder] for DROP TABLE ordering (referencing tables first)
class TableDependencySorter {
  /// Sort tables so that referenced tables come before referencing tables.
  ///
  /// [createSqlMap] maps table name -> CREATE TABLE SQL string.
  /// FK dependencies are parsed from the SQL via REFERENCES clauses.
  ///
  /// Returns the list of table names in topological order suitable for CREATE.
  static List<String> sortByCreateOrder(Map<String, String> createSqlMap) {
    final deps = _parseDependencies(createSqlMap);
    return _topologicalSort(deps);
  }

  /// Sort tables so that referencing tables come before referenced tables
  /// (reverse of create order), suitable for DROP.
  static List<String> sortByDropOrder(Map<String, String> createSqlMap) {
    final createOrder = sortByCreateOrder(createSqlMap);
    return createOrder.reversed.toList();
  }

  /// Sort tables by create order using pre-fetched ForeignKey info.
  ///
  /// [tableNames] all tables to sort.
  /// [foreignKeysMap] maps table name -> list of its foreign keys.
  ///
  /// Tables not in [foreignKeysMap] are treated as having no dependencies.
  static List<String> sortByCreateOrderFromFKs(
    List<String> tableNames,
    Map<String, List<ForeignKey>> foreignKeysMap,
  ) {
    final deps = <String, Set<String>>{};
    for (final name in tableNames) {
      deps[name] = {};
    }

    for (final name in tableNames) {
      final fks = foreignKeysMap[name] ?? [];
      for (final fk in fks) {
        if (tableNames.contains(fk.referencedTable)) {
          deps[name]!.add(fk.referencedTable);
        }
      }
    }

    return _topologicalSort(deps);
  }

  /// Parse CREATE TABLE SQL strings to extract FK dependencies.
  ///
  /// Returns Map<tableName, Set<referencedTableNames>>.
  static Map<String, Set<String>> _parseDependencies(
    Map<String, String> createSqlMap,
  ) {
    final deps = <String, Set<String>>{};

    String? schemaOf(String name) {
      final dot = name.indexOf('.');
      return dot > 0 && dot < name.length - 1 ? name.substring(0, dot) : null;
    }

    for (final entry in createSqlMap.entries) {
      final tableName = entry.key;
      final sql = entry.value;
      deps[tableName] = {};

      if (sql.isEmpty) continue;

      // 保留 schema 前缀（"schema"."table"），并把裸引用解析回限定 key。
      // group(1)=可选 schema 段，group(2)=表名段。
      final refRegex = RegExp(
        r'REFERENCES\s+(?:["`]([^`"]+)["`]\.)?["`]([^`"]+)["`]',
        caseSensitive: false,
      );
      final mySchema = schemaOf(tableName);

      for (final match in refRegex.allMatches(sql)) {
        final refSchema = match.group(1);
        final refTable = match.group(2);
        if (refTable == null) continue;
        // 解析为 createSqlMap 的 key：限定引用优先；否则同 schema 限定；否则裸名。
        // （同 schema FK 解析正确；跨 schema 裸引用为 L3 已知限制，解析失败则忽略。）
        final candidates = <String>[
          if (refSchema != null) '$refSchema.$refTable',
          if (mySchema != null) '$mySchema.$refTable',
          refTable,
        ];
        final resolved = candidates.firstWhere(
          (c) => createSqlMap.containsKey(c),
          orElse: () => '',
        );
        if (resolved.isNotEmpty && resolved != tableName) {
          deps[tableName]!.add(resolved);
        }
      }
    }

    return deps;
  }

  /// Kahn's algorithm for topological sorting.
  ///
  /// [deps]: table -> set of tables it depends on (must create those first).
  static List<String> _topologicalSort(Map<String, Set<String>> deps) {
    // Build reverse graph: table -> tables that depend on it
    final reverseDeps = <String, Set<String>>{};
    for (final name in deps.keys) {
      reverseDeps[name] = {};
    }

    // In-degree: how many dependencies this table has
    final inDegree = <String, int>{};
    for (final name in deps.keys) {
      inDegree[name] = 0;
      reverseDeps[name] = {};
    }

    for (final entry in deps.entries) {
      for (final dep in entry.value) {
        if (!deps.containsKey(dep)) continue;
        reverseDeps[dep] ??= {};
        reverseDeps[dep]!.add(entry.key);
        inDegree[entry.key] = (inDegree[entry.key] ?? 0) + 1;
      }
    }

    // Kahn's algorithm
    final queue = <String>[];
    for (final name in deps.keys) {
      if ((inDegree[name] ?? 0) == 0) {
        queue.add(name);
      }
    }

    final result = <String>[];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      result.add(current);

      for (final dependent in reverseDeps[current] ?? {}) {
        inDegree[dependent] = (inDegree[dependent] ?? 1) - 1;
        if (inDegree[dependent] == 0) {
          queue.add(dependent);
        }
      }
    }

    // If there are unresolved tables (cycles), add them at the end
    for (final name in deps.keys) {
      if (!result.contains(name)) {
        result.add(name);
      }
    }

    return result;
  }
}
