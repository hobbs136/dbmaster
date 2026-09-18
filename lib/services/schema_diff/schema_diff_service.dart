import 'dart:convert';
import '../../utils/app_logger.dart';
import '../../models/database_models.dart';
import '../../models/schema_diff_models.dart';
import '../database_service.dart';
import '../database_abstract.dart';

/// Schema Diff 引擎服务
/// 负责比较两个数据库 Schema 或快照，生成差异报告
class SchemaDiffService {
  final DatabaseService _databaseService;

  SchemaDiffService(this._databaseService);

  /// 从实时数据库捕获 Schema 快照。
  ///
  /// [schemas]：对支持 schema 命名空间的库（PG/SQLServer），
  /// null = 采集全部用户 schema、对象名以 'schema.name' 限定；指定则只采集这些 schema。
  /// 其它库（MySQL/SQLite/NoSQL）忽略 schema，走当前 schema 裸名（行为不变）。
  Future<SchemaSnapshot> captureSnapshot({
    required String connectionId,
    required String connectionName,
    required String databaseName,
    List<String>? schemas,
  }) async {
    final adapter = _databaseService.getAdapter(connectionId);
    if (adapter == null) {
      throw Exception('Connection $connectionId not found or not connected');
    }

    // 确保使用正确的数据库
    await adapter.useDatabase(databaseName);

    final captureErrors = <String>[];

    // PG/SQLServer 走多 schema 限定名；其余走单 schema 裸名。
    final multi = adapter is SchemaAwareAdapter &&
        adapter is MultiSchemaObjectAdapter;
    final MultiSchemaObjectAdapter? ma =
        multi ? adapter as MultiSchemaObjectAdapter : null;
    final schemaNames = <String?>[
      if (multi)
        ...(schemas ?? await (adapter as SchemaAwareAdapter).getSchemas())
      else
        null,
    ];

    String qualify(String? schema, String name) =>
        (multi && schema != null) ? '$schema.$name' : name;

    final tables = <DbTable>[];
    final createStatements = <String, String>{};

    // 并行获取所有表的元数据（跨 schema，限定名）
    final tableFutures = <Future<DbTable?>>[];
    for (final schema in schemaNames) {
      final rawTableNames = ma != null
          ? await ma.getTables(schemaName: schema)
          : await adapter.getTables();
      for (final rawName in rawTableNames) {
        final qName = qualify(schema, rawName);
        tableFutures.add(() async {
          try {
            final columns = await adapter.getTableColumns(qName);
            final indexes = await adapter.getTableIndexes(qName);
            return DbTable(name: qName, columns: columns, indexes: indexes);
          } catch (e) {
            captureErrors.add('Table "$qName": $e');
            AppLogger.d('SchemaDiff', 'Error capturing table $qName: $e');
            return null;
          }
        }());
      }
    }
    tables.addAll((await Future.wait(tableFutures)).whereType<DbTable>());

    // 并行获取 CREATE TABLE 语句（key = 限定名）
    final createFutures = tables.map((table) async {
      try {
        final createSql = await _databaseService.getCreateTableSql(
          table.name,
          connectionId: connectionId,
        );
        return MapEntry(table.name, createSql);
      } catch (_) {
        return null;
      }
    });
    final createEntries = (await Future.wait(
      createFutures,
    )).whereType<MapEntry<String, String>>();
    createStatements.addEntries(createEntries);

    // 获取视图列表并并行获取 CREATE 语句（跨 schema，限定名）
    final views = <String>[];
    final viewCreateStatements = <String, String>{};
    try {
      final viewFutures = <Future<MapEntry<String, String>?>>[];
      for (final schema in schemaNames) {
        final rawViews = ma != null
            ? await ma.getViews(schemaName: schema)
            : await adapter.getViews();
        for (final rawView in rawViews) {
          final qName = qualify(schema, rawView);
          views.add(qName);
          viewFutures.add(() async {
            try {
              final createSql = await _getCreateViewSql(adapter, qName);
              if (createSql != null && createSql.isNotEmpty) {
                return MapEntry(qName, createSql);
              }
            } catch (e) {
              captureErrors.add('View "$qName": $e');
            }
            return null;
          }());
        }
      }
      final viewEntries = (await Future.wait(
        viewFutures,
      )).whereType<MapEntry<String, String>>();
      viewCreateStatements.addEntries(viewEntries);
    } catch (_) {
      // 某些数据库可能不支持视图
    }

    // 获取存储过程/函数列表并获取 CREATE 语句（串行，避免同一连接并发查询冲突）
    final procedures = <String>[];
    final procedureCreateStatements = <String, String>{};
    try {
      for (final schema in schemaNames) {
        final rawProcs = ma != null
            ? [
                ...(await ma.getProcedures(schemaName: schema)),
                ...(await ma.getFunctions(schemaName: schema)),
              ]
            : [
                ...(await adapter.getFunctions()),
                ...(await adapter.getProcedures()),
              ];
        for (final rawProc in rawProcs) {
          final qName = qualify(schema, rawProc);
          procedures.add(qName);
          try {
            final createSql = await _getCreateProcedureSql(adapter, qName);
            if (createSql != null && createSql.isNotEmpty) {
              procedureCreateStatements[qName] = createSql;
            }
          } catch (e) {
            captureErrors.add('Procedure "$qName": $e');
          }
        }
      }
    } catch (_) {
      // 某些数据库可能不支持存储过程
    }

    return SchemaSnapshot(
      connectionId: connectionId,
      connectionName: connectionName,
      databaseName: databaseName,
      capturedAt: DateTime.now(),
      tables: tables,
      views: views,
      procedures: procedures,
      createStatements: createStatements,
      viewCreateStatements: viewCreateStatements,
      procedureCreateStatements: procedureCreateStatements,
      captureErrors: captureErrors,
    );
  }

  /// 拆分可能带 schema 前缀的对象名（'schema.name' → (schema, name)）。
  (String?, String) _splitSchemaName(String name) {
    final dot = name.indexOf('.');
    if (dot <= 0 || dot >= name.length - 1) return (null, name);
    return (name.substring(0, dot), name.substring(dot + 1));
  }

  /// 单引号转义（用于内插到 PG 元数据查询的字符串字面量）。
  String _esc(String s) => s.replaceAll("'", "''");

  /// 比较两个 Schema 快照，生成差异报告
  SchemaDiffReport compareSnapshots({
    required SchemaSnapshot source,
    required SchemaSnapshot target,
  }) {
    final tableDiffs = <TableDiff>[];

    // 源表名集合
    final sourceTableNames = source.tables.map((t) => t.name).toSet();
    // 目标表名集合
    final targetTableNames = target.tables.map((t) => t.name).toSet();

    // 1. 处理新增的表（在源中存在，目标中不存在）
    for (final sourceTable in source.tables) {
      if (!targetTableNames.contains(sourceTable.name)) {
        // 新增表的非唯一索引作为 indexDiffs——由 sync 以独立 CREATE INDEX
        // 创建（PG/SQLite 的 CREATE TABLE 内不接受内联 INDEX，唯一索引已作为 UNIQUE 约束
        // 写进 sourceCreateSql）。见 SchemaSyncService 新增表段 + _buildCreateTableSql。
        final indexDiffs = sourceTable.indexes
            .where((i) => !i.isUnique)
            .map(
              (i) => IndexDiff(
                name: i.name,
                type: DiffType.added,
                sourceIndex: i,
              ),
            )
            .toList();
        tableDiffs.add(
          TableDiff(
            name: sourceTable.name,
            type: DiffType.added,
            sourceCreateSql: source.createStatements[sourceTable.name],
            indexDiffs: indexDiffs,
          ),
        );
      }
    }

    // 2. 处理删除的表（在目标中存在，源中不存在）
    for (final targetTable in target.tables) {
      if (!sourceTableNames.contains(targetTable.name)) {
        tableDiffs.add(
          TableDiff(
            name: targetTable.name,
            type: DiffType.removed,
            targetCreateSql: target.createStatements[targetTable.name],
          ),
        );
      }
    }

    // 3. 处理共有的表（对比列和索引）
    for (final sourceTable in source.tables) {
      if (!targetTableNames.contains(sourceTable.name)) {
        continue;
      }

      final targetTable = target.tables.firstWhere(
        (t) => t.name == sourceTable.name,
        orElse: () => throw Exception('Table not found'),
      );

      final columnDiffs = _compareColumns(sourceTable, targetTable);
      final indexDiffs = _compareIndexes(sourceTable, targetTable);

      // 判断表是否有变化
      final hasColumnChanges = columnDiffs.any(
        (c) => c.type != DiffType.unchanged,
      );
      final hasIndexChanges = indexDiffs.any(
        (i) => i.type != DiffType.unchanged,
      );

      tableDiffs.add(
        TableDiff(
          name: sourceTable.name,
          type: (hasColumnChanges || hasIndexChanges)
              ? DiffType.modified
              : DiffType.unchanged,
          columnDiffs: columnDiffs,
          indexDiffs: indexDiffs,
          sourceCreateSql: source.createStatements[sourceTable.name],
          targetCreateSql: target.createStatements[targetTable.name],
        ),
      );
    }

    // 按表名排序
    tableDiffs.sort((a, b) => a.name.compareTo(b.name));

    // 对比视图（简单列表对比）
    final viewDiffs = <ViewDiff>[];
    final sourceViews = source.views.toSet();
    final targetViews = target.views.toSet();
    // 新增的视图（源有目标没有）
    for (final viewName in sourceViews.difference(targetViews)) {
      viewDiffs.add(
        ViewDiff(
          name: viewName,
          type: DiffType.added,
          createStatement: source.viewCreateStatements[viewName],
        ),
      );
    }
    // 删除的视图（目标有源没有）
    for (final viewName in targetViews.difference(sourceViews)) {
      viewDiffs.add(
        ViewDiff(
          name: viewName,
          type: DiffType.removed,
          createStatement: target.viewCreateStatements[viewName],
        ),
      );
    }

    // 对比存储过程（简单列表对比）
    final procedureDiffs = <ProcedureDiff>[];
    final sourceProcedures = source.procedures.toSet();
    final targetProcedures = target.procedures.toSet();
    // 新增的存储过程（源有目标没有）
    for (final procName in sourceProcedures.difference(targetProcedures)) {
      procedureDiffs.add(
        ProcedureDiff(
          name: procName,
          type: DiffType.added,
          createStatement: source.procedureCreateStatements[procName],
        ),
      );
    }
    // 删除的存储过程（目标有源没有）
    for (final procName in targetProcedures.difference(sourceProcedures)) {
      procedureDiffs.add(
        ProcedureDiff(
          name: procName,
          type: DiffType.removed,
          createStatement: target.procedureCreateStatements[procName],
        ),
      );
    }

    return SchemaDiffReport(
      sourceConnection: source.connectionName,
      targetConnection: target.connectionName,
      sourceDatabase: source.databaseName,
      targetDatabase: target.databaseName,
      generatedAt: DateTime.now(),
      tableDiffs: tableDiffs,
      viewDiffs: viewDiffs,
      procedureDiffs: procedureDiffs,
      captureErrors: [...source.captureErrors, ...target.captureErrors],
    );
  }

  /// 对比两个表的列
  List<ColumnDiff> _compareColumns(DbTable source, DbTable target) {
    final diffs = <ColumnDiff>[];
    final sourceColumnNames = source.columns.map((c) => c.name).toSet();
    final targetColumnNames = target.columns.map((c) => c.name).toSet();

    // 按目标表列顺序遍历，保持目标结构顺序
    final allColumnNames = {...sourceColumnNames, ...targetColumnNames};

    for (final columnName in allColumnNames) {
      if (!targetColumnNames.contains(columnName)) {
        // 源有、目标没有的列 → 需要添加到目标
        final sourceColumn = source.columns.firstWhere(
          (c) => c.name == columnName,
          orElse: () => throw Exception('Column not found'),
        );
        diffs.add(
          ColumnDiff(
            name: columnName,
            type: DiffType.added,
            sourceColumn: sourceColumn,
          ),
        );
      } else if (!sourceColumnNames.contains(columnName)) {
        // 目标有、源没有的列 → 需要从目标删除
        final targetColumn = target.columns.firstWhere(
          (c) => c.name == columnName,
          orElse: () => throw Exception('Column not found'),
        );
        diffs.add(
          ColumnDiff(
            name: columnName,
            type: DiffType.removed,
            targetColumn: targetColumn,
          ),
        );
      } else {
        // 对比列定义
        final sourceColumn = source.columns.firstWhere(
          (c) => c.name == columnName,
          orElse: () => throw Exception('Column not found'),
        );
        final targetColumn = target.columns.firstWhere(
          (c) => c.name == columnName,
          orElse: () => throw Exception('Column not found'),
        );
        final isModified =
            sourceColumn.type != targetColumn.type ||
            sourceColumn.isPrimaryKey != targetColumn.isPrimaryKey ||
            sourceColumn.isNullable != targetColumn.isNullable ||
            sourceColumn.defaultValue != targetColumn.defaultValue;

        diffs.add(
          ColumnDiff(
            name: columnName,
            type: isModified ? DiffType.modified : DiffType.unchanged,
            sourceColumn: sourceColumn,
            targetColumn: targetColumn,
          ),
        );
      }
    }

    // 按目标表列顺序重新排序（新增列放在最后）
    diffs.sort((a, b) {
      final aIndex = target.columns.indexWhere((c) => c.name == a.name);
      final bIndex = target.columns.indexWhere((c) => c.name == b.name);
      if (aIndex >= 0 && bIndex >= 0) {
        return aIndex.compareTo(bIndex);
      }
      if (aIndex >= 0) return -1;
      if (bIndex >= 0) return 1;
      return a.name.compareTo(b.name);
    });

    return diffs;
  }

  /// 对比两个表的索引
  List<IndexDiff> _compareIndexes(DbTable source, DbTable target) {
    final diffs = <IndexDiff>[];
    final sourceIndexNames = source.indexes.map((i) => i.name).toSet();
    final targetIndexNames = target.indexes.map((i) => i.name).toSet();

    final allIndexNames = {...sourceIndexNames, ...targetIndexNames};

    for (final indexName in allIndexNames) {
      if (!targetIndexNames.contains(indexName)) {
        // 源有、目标没有的索引 → 需要添加到目标
        final sourceIndex = source.indexes.firstWhere(
          (i) => i.name == indexName,
          orElse: () => throw Exception('Index not found'),
        );
        diffs.add(
          IndexDiff(
            name: indexName,
            type: DiffType.added,
            sourceIndex: sourceIndex,
          ),
        );
      } else if (!sourceIndexNames.contains(indexName)) {
        // 目标有、源没有的索引 → 需要从目标删除
        final targetIndex = target.indexes.firstWhere(
          (i) => i.name == indexName,
          orElse: () => throw Exception('Index not found'),
        );
        diffs.add(
          IndexDiff(
            name: indexName,
            type: DiffType.removed,
            targetIndex: targetIndex,
          ),
        );
      } else {
        // 对比索引定义
        final sourceIndex = source.indexes.firstWhere(
          (i) => i.name == indexName,
          orElse: () => throw Exception('Index not found'),
        );
        final targetIndex = target.indexes.firstWhere(
          (i) => i.name == indexName,
          orElse: () => throw Exception('Index not found'),
        );
        final isModified =
            !_listsEqual(sourceIndex.columns, targetIndex.columns) ||
            sourceIndex.isUnique != targetIndex.isUnique;

        diffs.add(
          IndexDiff(
            name: indexName,
            type: isModified ? DiffType.modified : DiffType.unchanged,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
          ),
        );
      }
    }

    diffs.sort((a, b) => a.name.compareTo(b.name));
    return diffs;
  }

  bool _listsEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 将快照序列化为 JSON 字符串
  String snapshotToJson(SchemaSnapshot snapshot) {
    return jsonEncode(snapshot.toJson());
  }

  /// 从 JSON 字符串反序列化快照
  SchemaSnapshot snapshotFromJson(String json) {
    return SchemaSnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// 获取视图的 CREATE 语句
  Future<String?> _getCreateViewSql(
    DatabaseAdapter adapter,
    String viewName,
  ) async {
    final dbType = adapter.databaseType;

    if (dbType == DatabaseType.mysql || dbType == DatabaseType.doris) {
      final result = await adapter.executeQuery('SHOW CREATE VIEW `$viewName`');
      if (result.rows.isNotEmpty) {
        var sql = result.rows.first['Create View']?.toString() ?? '';
        if (sql.isNotEmpty) {
          // 移除 DEFINER 子句，避免目标数据库用户不一致导致执行失败
          // 匹配 DEFINER=`user`@`host` 格式（MySQL 反引号）
          sql = sql.replaceAllMapped(
            RegExp(r'DEFINER\s*=\s*`[^`]+`\s*@\s*`[^`]+`\s+'),
            (match) => '',
          );
        }
        return sql.isNotEmpty ? sql : null;
      }
    } else if (dbType == DatabaseType.postgresql) {
      // 支持限定名 'schema.view'：按 schema 过滤、输出限定名
      final (viewSchema, pureView) = _splitSchemaName(viewName);
      final schemaClause = viewSchema != null
          ? "n.nspname = '${_esc(viewSchema)}'"
          : 'n.nspname = current_schema()';
      final result = await adapter.executeQuery('''
        SELECT pg_get_viewdef(c.oid, true) as definition
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = '${_esc(pureView)}' AND c.relkind = 'v'
          AND $schemaClause
      ''');
      if (result.rows.isNotEmpty) {
        final definition = result.rows.first['definition']?.toString();
        if (definition != null && definition.isNotEmpty) {
          // 使用 CREATE OR REPLACE VIEW 包装视图定义（限定名）
          final label = viewSchema != null
              ? '"${_esc(viewSchema)}"."${_esc(pureView)}"'
              : '"${_esc(pureView)}"';
          return 'CREATE OR REPLACE VIEW $label AS\n$definition;';
        }
      }
    } else if (dbType == DatabaseType.sqlite) {
      final result = await adapter.executeQuery('''
        SELECT sql FROM sqlite_master WHERE type = 'view' AND name = '$viewName'
      ''');
      if (result.rows.isNotEmpty) {
        return result.rows.first['sql']?.toString();
      }
    } else if (dbType == DatabaseType.sqlserver) {
      final result = await adapter.executeQuery('''
        SELECT OBJECT_DEFINITION(OBJECT_ID('$viewName')) as definition
      ''');
      if (result.rows.isNotEmpty) {
        final definition = result.rows.first['definition']?.toString();
        if (definition != null && definition.isNotEmpty) {
          return definition;
        }
      }
    }

    return null;
  }

  /// 获取存储过程/函数的 CREATE 语句
  Future<String?> _getCreateProcedureSql(
    DatabaseAdapter adapter,
    String procName,
  ) async {
    final dbType = adapter.databaseType;

    if (dbType == DatabaseType.mysql || dbType == DatabaseType.doris) {
      // 先尝试 PROCEDURE（函数不是过程，会报错，需 try-catch）
      try {
        final result = await adapter.executeQuery(
          'SHOW CREATE PROCEDURE `$procName`',
        );
        if (result.rows.isNotEmpty) {
          return result.rows.first['Create Procedure']?.toString();
        }
      } catch (_) {
        // 不是 PROCEDURE，继续尝试 FUNCTION
      }
      // 再尝试 FUNCTION
      try {
        final result = await adapter.executeQuery(
          'SHOW CREATE FUNCTION `$procName`',
        );
        if (result.rows.isNotEmpty) {
          return result.rows.first['Create Function']?.toString();
        }
      } catch (_) {
        // 也失败了
      }
    } else if (dbType == DatabaseType.postgresql) {
      // 支持限定名 'schema.func'
      final (procSchema, pureProc) = _splitSchemaName(procName);
      final schemaClause = procSchema != null
          ? "n.nspname = '${_esc(procSchema)}'"
          : 'n.nspname = current_schema()';
      final result = await adapter.executeQuery('''
        SELECT pg_get_functiondef(p.oid) as definition
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE p.proname = '${_esc(pureProc)}' AND $schemaClause
      ''');
      if (result.rows.isNotEmpty) {
        return result.rows.first['definition']?.toString();
      }
    } else if (dbType == DatabaseType.sqlite) {
      // SQLite 不支持存储过程
      return null;
    } else if (dbType == DatabaseType.sqlserver) {
      // Try stored procedure first
      var result = await adapter.executeQuery('''
        SELECT OBJECT_DEFINITION(OBJECT_ID('$procName')) as definition
      ''');
      if (result.rows.isNotEmpty) {
        final definition = result.rows.first['definition']?.toString();
        if (definition != null && definition.isNotEmpty) {
          return definition;
        }
      }
      // Try function
      result = await adapter.executeQuery('''
        SELECT OBJECT_DEFINITION(OBJECT_ID('$procName')) as definition
      ''');
      if (result.rows.isNotEmpty) {
        return result.rows.first['definition']?.toString();
      }
    }

    return null;
  }

  // Phase B — Ignore rule filtering + categorization

  /// 应用忽略规则到差异报告，过滤噪音差异
  /// 返回新的报告副本，原报告不受影响
  SchemaDiffReport applyIgnoreRules(
    SchemaDiffReport report,
    List<DiffIgnoreRule> rules,
  ) {
    final enabledRules = rules.where((r) => r.enabled).toList();
    if (enabledRules.isEmpty) return report;

    final filteredTableDiffs = report.tableDiffs.map((tableDiff) {
      return _applyIgnoreRulesToTable(tableDiff, enabledRules);
    }).toList();

    return SchemaDiffReport(
      sourceConnection: report.sourceConnection,
      targetConnection: report.targetConnection,
      sourceDatabase: report.sourceDatabase,
      targetDatabase: report.targetDatabase,
      generatedAt: report.generatedAt,
      tableDiffs: filteredTableDiffs,
      viewDiffs: report.viewDiffs,
      procedureDiffs: report.procedureDiffs,
      captureErrors: report.captureErrors,
    );
  }

  /// 对单个表差异应用忽略规则
  TableDiff _applyIgnoreRulesToTable(
    TableDiff tableDiff,
    List<DiffIgnoreRule> rules,
  ) {
    var filteredColumns = tableDiff.columnDiffs;
    var filteredIndexes = tableDiff.indexDiffs;

    for (final rule in rules) {
      switch (rule.target) {
        case DiffIgnoreTarget.autoIncrement:
          // 过滤仅因 AUTO_INCREMENT 值不同而产生的列差异
          filteredColumns = filteredColumns.map((colDiff) {
            if (colDiff.type != DiffType.modified) return colDiff;
            // 如果源列和目标列仅默认值不同且涉及自增，标记为 unchanged
            if (_isAutoIncrementDiff(colDiff)) {
              return ColumnDiff(
                name: colDiff.name,
                type: DiffType.unchanged,
                sourceColumn: colDiff.sourceColumn,
                targetColumn: colDiff.targetColumn,
              );
            }
            return colDiff;
          }).toList();
          break;

        case DiffIgnoreTarget.comment:
          // 过滤注释差异（列注释/表注释变化不影响结构）
          filteredColumns = filteredColumns.map((colDiff) {
            if (colDiff.type != DiffType.modified) return colDiff;
            if (_isCommentOnlyDiff(colDiff)) {
              return ColumnDiff(
                name: colDiff.name,
                type: DiffType.unchanged,
                sourceColumn: colDiff.sourceColumn,
                targetColumn: colDiff.targetColumn,
              );
            }
            return colDiff;
          }).toList();
          break;

        case DiffIgnoreTarget.collation:
          // 过滤排序规则差异
          filteredColumns = filteredColumns.map((colDiff) {
            if (colDiff.type != DiffType.modified) return colDiff;
            if (_isCollationOnlyDiff(colDiff)) {
              return ColumnDiff(
                name: colDiff.name,
                type: DiffType.unchanged,
                sourceColumn: colDiff.sourceColumn,
                targetColumn: colDiff.targetColumn,
              );
            }
            return colDiff;
          }).toList();
          break;

        case DiffIgnoreTarget.columnDefault:
          // 过滤仅默认值不同的列差异
          if (rule.pattern != null && rule.pattern!.isNotEmpty) {
            final regex = RegExp(rule.pattern!);
            filteredColumns = filteredColumns.map((colDiff) {
              if (colDiff.type != DiffType.modified) return colDiff;
              if (_isDefaultOnlyDiff(colDiff) &&
                  regex.hasMatch(colDiff.name)) {
                return ColumnDiff(
                  name: colDiff.name,
                  type: DiffType.unchanged,
                  sourceColumn: colDiff.sourceColumn,
                  targetColumn: colDiff.targetColumn,
                );
              }
              return colDiff;
            }).toList();
          }
          break;

        case DiffIgnoreTarget.indexName:
          // 过滤匹配模式的索引差异
          if (rule.pattern != null && rule.pattern!.isNotEmpty) {
            final regex = RegExp(rule.pattern!);
            filteredIndexes = filteredIndexes.map((idxDiff) {
              if (idxDiff.type == DiffType.unchanged) return idxDiff;
              if (regex.hasMatch(idxDiff.name)) {
                return IndexDiff(
                  name: idxDiff.name,
                  type: DiffType.unchanged,
                  sourceIndex: idxDiff.sourceIndex,
                  targetIndex: idxDiff.targetIndex,
                );
              }
              return idxDiff;
            }).toList();
          }
          break;
      }
    }

    // 重新计算表的差异类型
    final hasColumnChanges = filteredColumns.any(
      (c) => c.type != DiffType.unchanged,
    );
    final hasIndexChanges = filteredIndexes.any(
      (i) => i.type != DiffType.unchanged,
    );
    final newType = (tableDiff.type == DiffType.added ||
            tableDiff.type == DiffType.removed)
        ? tableDiff.type
        : (hasColumnChanges || hasIndexChanges)
            ? DiffType.modified
            : DiffType.unchanged;

    return TableDiff(
      name: tableDiff.name,
      type: newType,
      columnDiffs: filteredColumns,
      indexDiffs: filteredIndexes,
      sourceCreateSql: tableDiff.sourceCreateSql,
      targetCreateSql: tableDiff.targetCreateSql,
    );
  }

  /// 判断列差异是否仅由 AUTO_INCREMENT 引起
  bool _isAutoIncrementDiff(ColumnDiff colDiff) {
    final src = colDiff.sourceColumn;
    final tgt = colDiff.targetColumn;
    if (src == null || tgt == null) return false;

    // 如果类型、主键、可空性都相同，仅默认值不同 — 可能是自增
    final structuralSame = src.type == tgt.type &&
        src.isPrimaryKey == tgt.isPrimaryKey &&
        src.isNullable == tgt.isNullable;

    if (!structuralSame) return false;

    // 检查默认值是否包含自增相关值
    final srcDefault = src.defaultValue ?? '';
    final tgtDefault = tgt.defaultValue ?? '';
    if (srcDefault == tgtDefault) return false;

    // AUTO_INCREMENT 或 nextval 相关差异
    final autoIncPatterns = [
      'AUTO_INCREMENT',
      'auto_increment',
      'nextval',
      'NEXTVAL',
      'IDENTITY',
      'identity',
    ];
    for (final pattern in autoIncPatterns) {
      if (srcDefault.contains(pattern) || tgtDefault.contains(pattern)) {
        return true;
      }
    }

    // 纯数字差异也可能是自增值
    if (RegExp(r'^\d+$').hasMatch(srcDefault) &&
        RegExp(r'^\d+$').hasMatch(tgtDefault)) {
      return true;
    }

    return false;
  }

  /// 判断列差异是否仅为注释差异
  bool _isCommentOnlyDiff(ColumnDiff colDiff) {
    // 注释通常嵌入在列类型/DDL 中，不体现在 DbColumn 模型
    // 如果类型相同且仅 COMMENT 子句不同，则结构相同
    final src = colDiff.sourceColumn;
    final tgt = colDiff.targetColumn;
    if (src == null || tgt == null) return false;

    return src.type == tgt.type &&
        src.isPrimaryKey == tgt.isPrimaryKey &&
        src.isNullable == tgt.isNullable &&
        src.defaultValue == tgt.defaultValue;
  }

  /// 判断列差异是否仅为排序规则差异
  bool _isCollationOnlyDiff(ColumnDiff colDiff) {
    final src = colDiff.sourceColumn;
    final tgt = colDiff.targetColumn;
    if (src == null || tgt == null) return false;

    // 排序规则体现在 COLLATE 子句中
    final srcType = src.type.toUpperCase();
    final tgtType = tgt.type.toUpperCase();

    // 去除 COLLATE 部分后比较
    final srcClean = srcType.replaceAll(RegExp(r'\s+COLLATE\s+\S+'), '');
    final tgtClean = tgtType.replaceAll(RegExp(r'\s+COLLATE\s+\S+'), '');

    return srcClean == tgtClean &&
        src.isPrimaryKey == tgt.isPrimaryKey &&
        src.isNullable == tgt.isNullable &&
        src.defaultValue == tgt.defaultValue;
  }

  /// 判断列差异是否仅为默认值差异
  bool _isDefaultOnlyDiff(ColumnDiff colDiff) {
    final src = colDiff.sourceColumn;
    final tgt = colDiff.targetColumn;
    if (src == null || tgt == null) return false;

    return src.type == tgt.type &&
        src.isPrimaryKey == tgt.isPrimaryKey &&
        src.isNullable == tgt.isNullable;
    // 默认值不同但其他结构相同
  }
}
