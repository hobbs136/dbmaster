import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/utils/app_logger.dart';
import 'package:dbmaster/utils/sql_escape_utils.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/schema_diff/table_dependency_sorter.dart';
import 'package:dbmaster/services/schema_analyzer/rollback_generator.dart';

/// Schema 同步服务
/// 根据差异报告生成并执行迁移脚本
class SchemaSyncService {
  final DatabaseService _databaseService;

  SchemaSyncService(this._databaseService);

  /// 根据差异报告生成同步计划（DDL 脚本列表）
  SyncPlan generateSyncPlan({
    required SchemaDiffReport report,
    required String targetConnectionId,
    required String targetDatabase,
    required DatabaseType dbType,
  }) {
    final operations = <SyncOperation>[];
    int opIndex = 0;

    final q = _getQuoteChar(dbType);

    // 多 schema 同步——目标库需先创建源库涉及的 schema（仅 PG/SQLServer）。
    // 从 added 表/视图/过程的限定名提取 schema 前缀，生成 CREATE SCHEMA IF NOT EXISTS。
    // 放最前，执行时在 useDatabase 之后、建表之前。
    if (dbType == DatabaseType.postgresql || dbType == DatabaseType.sqlserver) {
      final schemas = <String>{};
      void collectSchema(String? name) {
        if (name == null) return;
        final dot = name.indexOf('.');
        if (dot > 0 && dot < name.length - 1) {
          schemas.add(name.substring(0, dot));
        }
      }

      for (final d in report.tableDiffs) {
        if (d.type == DiffType.added) collectSchema(d.name);
      }
      for (final d in report.viewDiffs) {
        if (d.type == DiffType.added) collectSchema(d.name);
      }
      for (final d in report.procedureDiffs) {
        if (d.type == DiffType.added) collectSchema(d.name);
      }
      for (final schema in (schemas.toList()..sort())) {
        final quotedSchema =
            SqlEscapeUtils.escapePgQualifiedIdentifier(schema);
        final sql = dbType == DatabaseType.postgresql
            ? 'CREATE SCHEMA IF NOT EXISTS $quotedSchema;'
            : "IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = "
                "'${schema.replaceAll("'", "''")}') "
                "EXEC('CREATE SCHEMA $quotedSchema');";
        operations.add(
          SyncOperation(
            id: 'op_${opIndex++}',
            description: 'Create schema "$schema" if not exists',
            sql: sql,
            type: DiffType.added,
            targetTable: schema,
          ),
        );
      }
    }

    // 1. 处理删除的表（按外键依赖反向排序：先删引用表，后删被引用表）
    final removedTables = report.tableDiffs
        .where((t) => t.type == DiffType.removed)
        .toList();

    // Build FK dependency map from targetCreateSql for topological sort
    final removedSqlMap = <String, String>{};
    for (final tableDiff in removedTables) {
      final sql = tableDiff.targetCreateSql;
      if (sql != null && sql.isNotEmpty) {
        removedSqlMap[tableDiff.name] = sql;
      }
    }
    final removedOrder = removedSqlMap.isNotEmpty
        ? TableDependencySorter.sortByDropOrder(removedSqlMap)
        : removedTables.map((t) => t.name).toList();

    final removedByName = {for (final t in removedTables) t.name: t};
    for (final name in removedOrder) {
      final tableDiff = removedByName[name];
      if (tableDiff == null) continue;
      final dropSql = switch (dbType) {
        DatabaseType.mysql || DatabaseType.doris =>
          'SET FOREIGN_KEY_CHECKS = 0; DROP TABLE IF EXISTS $q${tableDiff.name}$q; SET FOREIGN_KEY_CHECKS = 1;',
        DatabaseType.postgresql =>
          'DROP TABLE IF EXISTS ${_quoteTable(tableDiff.name, dbType)} CASCADE;',
        _ => 'DROP TABLE IF EXISTS ${_quoteTable(tableDiff.name, dbType)};',
      };
      operations.add(
        SyncOperation(
          id: 'op_${opIndex++}',
          description: 'Drop table "${tableDiff.name}"',
          sql: dropSql,
          type: DiffType.removed,
          targetTable: tableDiff.name,
        ),
      );
    }

    // 2. 处理修改的表（ALTER TABLE）
    final modifiedTables = report.tableDiffs
        .where((t) => t.type == DiffType.modified)
        .toList();

    for (final tableDiff in modifiedTables) {
      final prevLen = operations.length;
      operations.addAll(
        _generateAlterTableOperations(
          tableDiff: tableDiff,
          dbType: dbType,
          startIndex: opIndex,
        ),
      );
      opIndex += operations.length - prevLen;
    }

    // 3. 处理新增的表（按外键依赖拓扑排序：先创建被引用表，后创建引用表）
    final addedTables = report.tableDiffs
        .where((t) => t.type == DiffType.added)
        .toList();

    // Build FK dependency map from sourceCreateSql for topological sort
    final addedSqlMap = <String, String>{};
    for (final tableDiff in addedTables) {
      final sql = tableDiff.sourceCreateSql;
      if (sql != null && sql.isNotEmpty) {
        addedSqlMap[tableDiff.name] = sql;
      }
    }
    final addedOrder = addedSqlMap.isNotEmpty
        ? TableDependencySorter.sortByCreateOrder(addedSqlMap)
        : addedTables.map((t) => t.name).toList();

    final addedByName = {for (final t in addedTables) t.name: t};
    for (final name in addedOrder) {
      final tableDiff = addedByName[name];
      if (tableDiff == null) continue;
      // 使用 sourceCreateSql（源库的表结构）在目标库创建
      final createSql = tableDiff.sourceCreateSql;
      if (createSql != null && createSql.isNotEmpty) {
        // 清理 SQL 中的跨库引用
        final cleanSql = _cleanCreateTableSql(createSql, dbType);
        operations.add(
          SyncOperation(
            id: 'op_${opIndex++}',
            description: 'Create table "${tableDiff.name}"',
            sql: cleanSql,
            type: DiffType.added,
            targetTable: tableDiff.name,
          ),
        );
      } else {
        // 没有 CREATE TABLE 语句，生成一个基本的
        operations.add(
          SyncOperation(
            id: 'op_${opIndex++}',
            description: 'Create table "${tableDiff.name}" (basic)',
            sql: _generateCreateTableSql(tableDiff.name, [], dbType),
            type: DiffType.added,
            targetTable: tableDiff.name,
          ),
        );
      }

      // 非唯一索引以独立 CREATE INDEX 创建（PG/SQLite 的 CREATE TABLE 内不接受内联
      // INDEX；indexDiffs 由 compareSnapshots 填充）。
      // hotfix: MySQL/Doris 的 sourceCreateSql（SHOW CREATE TABLE）已内联所有索引
      // （KEY / UNIQUE KEY / FULLTEXT），再 CREATE INDEX 会触发 MySQL 1061 Duplicate
      // key name（同步到新库时约一半语句失败）。仅当 CREATE TABLE 未内联索引时才单独建：
      // fallback 基本表，或 PG/SQLite/SQLServer。
      final hasInlineIndexes = (createSql != null && createSql.isNotEmpty) &&
          (dbType == DatabaseType.mysql || dbType == DatabaseType.doris);
      if (!hasInlineIndexes) {
        for (final idxDiff in tableDiff.indexDiffs) {
          if (idxDiff.type != DiffType.added) continue;
          final srcIdx = idxDiff.sourceIndex;
          if (srcIdx == null) continue;
          operations.add(
            SyncOperation(
              id: 'op_${opIndex++}',
              description: 'Create index "${idxDiff.name}" on "${tableDiff.name}"',
              sql: _generateCreateIndexSql(tableDiff.name, srcIdx, dbType),
              type: DiffType.added,
              targetTable: tableDiff.name,
            ),
          );
        }
      }
    }

    // 4. 处理删除的视图
    for (final viewDiff in report.viewDiffs.where(
      (v) => v.type == DiffType.removed,
    )) {
      operations.add(
        SyncOperation(
          id: 'op_${opIndex++}',
          description: 'Drop view "${viewDiff.name}"',
          sql: 'DROP VIEW IF EXISTS $q${viewDiff.name}$q;',
          type: DiffType.removed,
          targetTable: viewDiff.name,
        ),
      );
    }

    // 5. 处理新增的视图
    for (final viewDiff in report.viewDiffs.where(
      (v) => v.type == DiffType.added,
    )) {
      final createSql = viewDiff.createStatement;
      if (createSql != null && createSql.isNotEmpty) {
        // 清理 SQL 中的跨库引用
        final cleanSql = _cleanCreateViewSql(createSql, dbType);
        operations.add(
          SyncOperation(
            id: 'op_${opIndex++}',
            description: 'Create view "${viewDiff.name}"',
            sql: cleanSql,
            type: DiffType.added,
            targetTable: viewDiff.name,
          ),
        );
      } else {
        operations.add(
          SyncOperation(
            id: 'op_${opIndex++}',
            description:
                'Create view "${viewDiff.name}" (no CREATE statement found)',
            sql:
                '-- WARNING: Could not retrieve CREATE VIEW statement for ${viewDiff.name}\n-- Source: ${report.sourceConnection}/${report.sourceDatabase}',
            type: DiffType.added,
            targetTable: viewDiff.name,
          ),
        );
      }
    }

    // 6. 处理删除的存储过程/函数
    for (final procDiff in report.procedureDiffs.where(
      (p) => p.type == DiffType.removed,
    )) {
      operations.add(
        SyncOperation(
          id: 'op_${opIndex++}',
          description: 'Drop procedure/function "${procDiff.name}"',
          sql:
              'DROP PROCEDURE IF EXISTS $q${procDiff.name}$q;\nDROP FUNCTION IF EXISTS $q${procDiff.name}$q;',
          type: DiffType.removed,
          targetTable: procDiff.name,
        ),
      );
    }

    // 7. 处理新增的存储过程/函数
    for (final procDiff in report.procedureDiffs.where(
      (p) => p.type == DiffType.added,
    )) {
      final createSql = procDiff.createStatement;
      if (createSql != null && createSql.isNotEmpty) {
        operations.add(
          SyncOperation(
            id: 'op_${opIndex++}',
            description: 'Create procedure/function "${procDiff.name}"',
            sql: createSql,
            type: DiffType.added,
            targetTable: procDiff.name,
          ),
        );
      } else {
        operations.add(
          SyncOperation(
            id: 'op_${opIndex++}',
            description:
                'Create procedure/function "${procDiff.name}" (no CREATE statement found)',
            sql:
                '-- WARNING: Could not retrieve CREATE PROCEDURE/FUNCTION statement for ${procDiff.name}\n-- Source: ${report.sourceConnection}/${report.sourceDatabase}',
            type: DiffType.added,
            targetTable: procDiff.name,
          ),
        );
      }
    }

    return SyncPlan(
      sourceSnapshot: '${report.sourceConnection}/${report.sourceDatabase}',
      targetSnapshot: '${report.targetConnection}/${report.targetDatabase}',
      operations: operations,
      isDryRun: true,
    );
  }

  /// 生成 ALTER TABLE 操作列表
  List<SyncOperation> _generateAlterTableOperations({
    required TableDiff tableDiff,
    required DatabaseType dbType,
    required int startIndex,
  }) {
    final operations = <SyncOperation>[];
    int index = startIndex;

    // Step 1: 先删除索引（避免后续删除列时因索引依赖报错）
    for (final idxDiff in tableDiff.indexDiffs) {
      if (idxDiff.type == DiffType.unchanged) continue;

      switch (idxDiff.type) {
        case DiffType.removed:
          // 目标有、源没有的索引 → 从目标删除
          operations.add(
            SyncOperation(
              id: 'op_${index++}',
              description:
                  'Drop index "${idxDiff.name}" from "${tableDiff.name}"',
              sql: _generateDropIndexSql(
                tableDiff.name,
                idxDiff.name,
                dbType,
                isUnique: idxDiff.targetIndex?.isUnique ?? false,
              ),
              type: DiffType.removed,
              targetTable: tableDiff.name,
            ),
          );
          break;

        case DiffType.modified:
          // 两边都有但定义不同 → 先删除目标旧索引
          if (idxDiff.targetIndex != null) {
            operations.add(
              SyncOperation(
                id: 'op_${index++}',
                description:
                    'Drop index "${idxDiff.name}" from "${tableDiff.name}"',
                sql: _generateDropIndexSql(
                  tableDiff.name,
                  idxDiff.name,
                  dbType,
                  isUnique: idxDiff.targetIndex!.isUnique,
                ),
                type: DiffType.removed,
                targetTable: tableDiff.name,
              ),
            );
          }
          break;

        case DiffType.added:
        case DiffType.unchanged:
          break;
      }
    }

    // Step 2: 处理列变更（删除、修改、添加）
    for (final colDiff in tableDiff.columnDiffs) {
      if (colDiff.type == DiffType.unchanged) continue;

      switch (colDiff.type) {
        case DiffType.removed:
          // 目标有、源没有的列 → 从目标删除
          operations.add(
            SyncOperation(
              id: 'op_${index++}',
              description:
                  'Drop column "${colDiff.name}" from "${tableDiff.name}"',
              sql: _generateDropColumnSql(tableDiff.name, colDiff.name, dbType),
              type: DiffType.removed,
              targetTable: tableDiff.name,
            ),
          );
          break;

        case DiffType.modified:
          // 两边都有但定义不同 → 修改目标以匹配源
          if (colDiff.sourceColumn != null) {
            operations.add(
              SyncOperation(
                id: 'op_${index++}',
                description:
                    'Modify column "${colDiff.name}" in "${tableDiff.name}"',
                sql: _generateModifyColumnSql(
                  tableDiff.name,
                  colDiff.sourceColumn!,
                  dbType,
                ),
                type: DiffType.modified,
                targetTable: tableDiff.name,
              ),
            );
          }
          break;

        case DiffType.added:
          // 源有、目标没有的列 → 添加到目标
          if (colDiff.sourceColumn != null) {
            operations.add(
              SyncOperation(
                id: 'op_${index++}',
                description:
                    'Add column "${colDiff.name}" to "${tableDiff.name}"',
                sql: _generateAddColumnSql(
                  tableDiff.name,
                  colDiff.sourceColumn!,
                  dbType,
                ),
                type: DiffType.added,
                targetTable: tableDiff.name,
              ),
            );
          }
          break;

        case DiffType.unchanged:
          break;
      }
    }

    // Step 3: 创建新索引（在列变更完成后）
    for (final idxDiff in tableDiff.indexDiffs) {
      if (idxDiff.type == DiffType.unchanged) continue;

      switch (idxDiff.type) {
        case DiffType.added:
          // 源有、目标没有的索引 → 添加到目标
          if (idxDiff.sourceIndex != null) {
            operations.add(
              SyncOperation(
                id: 'op_${index++}',
                description:
                    'Create index "${idxDiff.name}" on "${tableDiff.name}"',
                sql: _generateCreateIndexSql(
                  tableDiff.name,
                  idxDiff.sourceIndex!,
                  dbType,
                ),
                type: DiffType.added,
                targetTable: tableDiff.name,
              ),
            );
          }
          break;

        case DiffType.modified:
          // 两边都有但定义不同 → 创建源定义的新索引
          if (idxDiff.sourceIndex != null) {
            operations.add(
              SyncOperation(
                id: 'op_${index++}',
                description:
                    'Create index "${idxDiff.name}" on "${tableDiff.name}"',
                sql: _generateCreateIndexSql(
                  tableDiff.name,
                  idxDiff.sourceIndex!,
                  dbType,
                ),
                type: DiffType.added,
                targetTable: tableDiff.name,
              ),
            );
          }
          break;

        case DiffType.removed:
        case DiffType.unchanged:
          break;
      }
    }

    return operations;
  }

  /// 执行同步计划（Dry-run 或实际执行）
  Future<SyncPlan> executeSyncPlan({
    required SyncPlan plan,
    required String connectionId,
    required String databaseName,
    bool dryRun = true,
  }) async {
    if (dryRun) {
      // Dry-run 模式：仅返回计划，不执行
      return SyncPlan(
        sourceSnapshot: plan.sourceSnapshot,
        targetSnapshot: plan.targetSnapshot,
        operations: plan.operations,
        isDryRun: true,
      );
    }

    final adapter = _databaseService.getAdapter(connectionId);
    if (adapter == null) {
      throw Exception('Connection $connectionId not found');
    }

    // 确保使用正确的数据库
    await adapter.useDatabase(databaseName);

    final executedOperations = <SyncOperation>[];

    for (final operation in plan.operations) {
      if (operation.isExecuted) {
        executedOperations.add(operation);
        continue;
      }

      try {
        await adapter.executeQuery(operation.sql);
        executedOperations.add(operation.copyWith(isExecuted: true));
      } catch (e) {
        executedOperations.add(operation.copyWith(error: e.toString()));
      }
    }

    return SyncPlan(
      sourceSnapshot: plan.sourceSnapshot,
      targetSnapshot: plan.targetSnapshot,
      operations: executedOperations,
      isDryRun: false,
    );
  }

  // Phase B — Stream-based execution with real-time progress

  /// 执行同步计划，通过 Stream 发射实时进度
  /// [dryRun]=true 时不执行实际 SQL，仅验证并发射进度
  /// PostgreSQL 使用事务包裹（失败自动回滚），MySQL/Doris 逐条执行
  Stream<SyncProgress> executeWithProgress({
    required SyncPlan plan,
    required String connectionId,
    required String databaseName,
    required DatabaseType dbType,
    bool dryRun = true,
  }) async* {
    final totalSteps = plan.operations.length;
    final completedSteps = <SyncStep>[];
    final stopwatch = Stopwatch()..start();

    // Emit initial state
    yield SyncProgress(
      currentStep: 0,
      totalSteps: totalSteps,
      completedSteps: completedSteps,
      phase: SyncExecutionPhase.validating,
    );

    if (dryRun) {
      // Dry-run: yield progress for each operation without executing
      for (int i = 0; i < plan.operations.length; i++) {
        final operation = plan.operations[i];
        final step = SyncStep(
          operation: operation,
          status: SyncStepStatus.skipped,
        );
        completedSteps.add(step);

        yield SyncProgress(
          currentStep: i + 1,
          totalSteps: totalSteps,
          currentOperation: step,
          completedSteps: List.unmodifiable(completedSteps),
          phase: SyncExecutionPhase.executing,
        );
      }

      stopwatch.stop();
      yield SyncProgress(
        currentStep: totalSteps,
        totalSteps: totalSteps,
        completedSteps: List.unmodifiable(completedSteps),
        phase: SyncExecutionPhase.completed,
      );
      return;
    }

    // Real execution
    final adapter = _databaseService.getAdapter(connectionId);
    if (adapter == null) {
      yield SyncProgress(
        currentStep: 0,
        totalSteps: totalSteps,
        completedSteps: completedSteps,
        phase: SyncExecutionPhase.failed,
        error: 'Connection $connectionId not found',
      );
      return;
    }

    try {
      await adapter.useDatabase(databaseName);

      // Check if transactional DDL is supported (PostgreSQL)
      final supportsTransactionalDdl = dbType == DatabaseType.postgresql;

      if (supportsTransactionalDdl && adapter is TransactionalAdapter) {
        // PostgreSQL: wrap in transaction
        try {
          await adapter.beginTransaction();
        } catch (e) {
          yield SyncProgress(
            currentStep: 0,
            totalSteps: totalSteps,
            completedSteps: completedSteps,
            phase: SyncExecutionPhase.failed,
            error: 'Failed to begin transaction: $e',
          );
          return;
        }
      }

      bool hasFailed = false;
      StringBuffer? rollbackBuffer;

      for (int i = 0; i < plan.operations.length; i++) {
        final operation = plan.operations[i];

        // Emit progress before execution
        final runningStep = SyncStep(
          operation: operation,
          status: SyncStepStatus.running,
        );

        yield SyncProgress(
          currentStep: i,
          totalSteps: totalSteps,
          currentOperation: runningStep,
          completedSteps: List.unmodifiable(completedSteps),
          phase: SyncExecutionPhase.executing,
        );

        final stepStopwatch = Stopwatch()..start();

        try {
          await adapter.executeQuery(operation.sql);
          stepStopwatch.stop();

          final successStep = SyncStep(
            operation: operation.copyWith(isExecuted: true),
            status: SyncStepStatus.success,
            duration: stepStopwatch.elapsed,
          );
          completedSteps.add(successStep);

          yield SyncProgress(
            currentStep: i + 1,
            totalSteps: totalSteps,
            currentOperation: successStep,
            completedSteps: List.unmodifiable(completedSteps),
            phase: SyncExecutionPhase.executing,
          );
        } catch (e) {
          stepStopwatch.stop();
          hasFailed = true;

          // 记录失败语句与错误——否则 PG 事务回滚后错误只进 Stream 的
          // error 字段，被部分 UI（SchemaDiffPage）吞掉，用户看不到根因。
          AppLogger.e(
            'SchemaSync',
            '同步语句失败: ${operation.description} | SQL: ${operation.sql}',
            e,
          );

          final failedStep = SyncStep(
            operation: operation.copyWith(error: e.toString()),
            status: SyncStepStatus.failed,
            error: e.toString(),
            duration: stepStopwatch.elapsed,
          );
          completedSteps.add(failedStep);

          // Build rollback script for failed operations
          rollbackBuffer ??= StringBuffer();
          rollbackBuffer.writeln(
            '-- Rollback for: ${operation.description}',
          );
          rollbackBuffer.writeln('-- Error: ${e.toString()}');

          // Try to generate rollback DDL
          try {
            final rollback = RollbackGenerator.generateRollback(
              ddlStatement: operation.sql,
              ddlType: _ddlTypeFromOperation(operation),
              tableName: operation.targetTable,
              databaseType: dbType.name,
            );
            if (rollback != null) {
              rollbackBuffer.writeln('-- Rollback DDL:');
              rollbackBuffer.writeln(rollback.rollbackDdl);
            }
          } catch (_) {
            rollbackBuffer.writeln('-- Could not generate rollback DDL');
          }

          if (supportsTransactionalDdl) {
            // PG: break on first failure, transaction will be rolled back
            break;
          }
          // MySQL/Doris: continue with remaining operations
        }
      }

      if (supportsTransactionalDdl && adapter is TransactionalAdapter) {
        if (hasFailed) {
          // Rollback the entire transaction
          try {
            await adapter.rollback();
          } catch (_) {
            // Rollback itself failed — log but don't crash
          }

          stopwatch.stop();
          yield SyncProgress(
            currentStep: completedSteps.length,
            totalSteps: totalSteps,
            completedSteps: List.unmodifiable(completedSteps),
            phase: SyncExecutionPhase.rollingBack,
            error: 'Transaction rolled back due to errors',
          );

          yield SyncProgress(
            currentStep: completedSteps.length,
            totalSteps: totalSteps,
            completedSteps: List.unmodifiable(completedSteps),
            phase: SyncExecutionPhase.completed,
            error: rollbackBuffer?.toString(),
          );
        } else {
          // Commit
          try {
            await adapter.commit();
          } catch (e) {
            yield SyncProgress(
              currentStep: completedSteps.length,
              totalSteps: totalSteps,
              completedSteps: List.unmodifiable(completedSteps),
              phase: SyncExecutionPhase.failed,
              error: 'Failed to commit transaction: $e',
            );
            return;
          }

          stopwatch.stop();
          yield SyncProgress(
            currentStep: totalSteps,
            totalSteps: totalSteps,
            completedSteps: List.unmodifiable(completedSteps),
            phase: SyncExecutionPhase.completed,
          );
        }
      } else {
        // Non-transactional: emit final completion
        stopwatch.stop();
        yield SyncProgress(
          currentStep: totalSteps,
          totalSteps: totalSteps,
          completedSteps: List.unmodifiable(completedSteps),
          phase: hasFailed
              ? SyncExecutionPhase.completed
              : SyncExecutionPhase.completed,
          error: rollbackBuffer?.toString(),
        );
      }
    } catch (e) {
      stopwatch.stop();
      yield SyncProgress(
        currentStep: completedSteps.length,
        totalSteps: totalSteps,
        completedSteps: List.unmodifiable(completedSteps),
        phase: SyncExecutionPhase.failed,
        error: 'Execution error: $e',
      );
    }
  }

  /// 从 SyncOperation 推断 DDL 类型（用于 RollbackGenerator）
  String _ddlTypeFromOperation(SyncOperation operation) {
    final sql = operation.sql.toUpperCase().trim();
    // CREATE SCHEMA 单独分类——回滚交由 RollbackGenerator 默认返回 null
    // （DROP SCHEMA 有误删既有对象风险；PG 事务会自动回滚）。
    if (sql.startsWith('CREATE SCHEMA')) {
      return 'CREATE_SCHEMA';
    }
    if (sql.startsWith('DROP TABLE') || sql.contains('DROP TABLE')) {
      return 'DROP_TABLE';
    }
    if (sql.startsWith('DROP COLUMN') || sql.contains('DROP COLUMN')) {
      return 'DROP_COLUMN';
    }
    if (sql.startsWith('ADD COLUMN') || sql.contains('ADD COLUMN')) {
      return 'ADD_COLUMN';
    }
    if (sql.startsWith('ALTER TABLE') && sql.contains('ALTER COLUMN')) {
      return 'ALTER_COLUMN';
    }
    if (sql.contains('MODIFY COLUMN')) {
      return 'ALTER_COLUMN';
    }
    if (sql.startsWith('CREATE') && sql.contains('INDEX')) {
      return 'CREATE_INDEX';
    }
    if (sql.startsWith('DROP INDEX') || sql.contains('DROP INDEX')) {
      return 'DROP_INDEX';
    }
    if (sql.startsWith('RENAME TABLE') || sql.contains('RENAME TO')) {
      return 'RENAME_TABLE';
    }
    return 'ALTER_COLUMN';
  }

  // ========== SQL 生成辅助方法 ==========

  /// 清理 CREATE TABLE SQL，移除跨库/跨schema前缀引用
  /// 将 `db`.`table` 或 "db"."table" 或 "schema"."table" 改为 `table` 或 "table"
  String _cleanCreateTableSql(String sql, DatabaseType dbType) {
    // PG/SQLServer 多 schema 同步须保留 schema 限定前缀（"schema"."table"），
    // 不剥离；仅 MySQL/Doris 剥离跨库前缀（目标库已 USE，不能带 `db`.`table`）。
    // SQLite 表名裸（无非 multi 限定），双引号正则不会匹配，无需特殊处理。
    if (dbType == DatabaseType.postgresql || dbType == DatabaseType.sqlserver) {
      return sql;
    }
    String result = sql;
    // Strip backtick-qualified prefixes: `prefix`.`identifier` → `identifier`
    // Handles both two-part (`db`.`tbl`) and three-part (`db`.`schema`.`tbl`)
    result = result.replaceAllMapped(
      RegExp(r'`[^`]+`\.(`[^`]+`)'),
      (match) => '`${match.group(1)}`',
    );
    // Strip double-quote-qualified prefixes: "prefix"."identifier" → "identifier"
    result = result.replaceAllMapped(
      RegExp(r'"[^"]+"\."([^"]+)"'),
      (match) => '"${match.group(1)}"',
    );
    return result;
  }

  /// 清理 CREATE VIEW SQL，只移除 CREATE VIEW 子句中的跨库前缀，保留 SELECT 部分不变
  String _cleanCreateViewSql(String sql, DatabaseType dbType) {
    String result = sql;
    // 只对 CREATE VIEW 后的视图名进行清理：CREATE VIEW `db`.`view` → CREATE VIEW `view`
    if (dbType == DatabaseType.mysql || dbType == DatabaseType.doris) {
      result = result.replaceAllMapped(
        RegExp(
          r'CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+`[^`]+`\.`([^`]+)`',
          caseSensitive: false,
        ),
        (match) => 'CREATE ${match.group(1) ?? ''}VIEW `${match.group(2)}`',
      );
    } else if (dbType == DatabaseType.postgresql) {
      result = result.replaceAllMapped(
        RegExp(
          r'CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+"[^"]+"\."([^"]+)"',
          caseSensitive: false,
        ),
        (match) => 'CREATE ${match.group(1) ?? ''}VIEW "${match.group(2)}"',
      );
    }
    return result;
  }

  /// 格式化 DEFAULT 值，自动为非关键字字符串添加引号
  String _formatDefaultValue(String value) {
    final upper = value.toUpperCase();
    // SQL 关键字 / 字面量不需要引号
    if (upper == 'CURRENT_TIMESTAMP' ||
        upper == 'CURRENT_DATE' ||
        upper == 'CURRENT_TIME' ||
        upper == 'NULL' ||
        upper == 'TRUE' ||
        upper == 'FALSE') {
      return value;
    }
    // 数字不需要引号
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
      return value;
    }
    // 已带引号的不处理
    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      return value;
    }
    return "'$value'";
  }

  /// 根据数据库类型获取标识符引号字符
  String _getQuoteChar(DatabaseType dbType) {
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.doris:
        return '`';
      case DatabaseType.sqlserver:
        return '"';
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      default:
        return '"';
    }
  }

  /// schema-aware 表名引号——PG/SQLServer 按 schema.table 拆段逐段转义
  /// （复用 SqlEscapeUtils.escapePgQualifiedIdentifier），其余库用单字符 quote。
  /// 表名可能为限定名 'schema.table'，裸 `${_quoteTable(tableName, dbType)}` 会生成含点的非法单标识符。
  String _quoteTable(String name, DatabaseType dbType) {
    if (dbType == DatabaseType.postgresql ||
        dbType == DatabaseType.sqlserver) {
      return SqlEscapeUtils.escapePgQualifiedIdentifier(name);
    }
    final q = _getQuoteChar(dbType);
    return '$q$name$q';
  }

  String _generateCreateTableSql(
    String tableName,
    List<DbColumn> columns,
    DatabaseType dbType,
  ) {
    final q = _getQuoteChar(dbType);
    final buffer = StringBuffer();
    buffer.writeln('CREATE TABLE ${_quoteTable(tableName, dbType)} (');

    if (columns.isEmpty) {
      // 空表，添加一个默认列
      buffer.writeln('  id INT PRIMARY KEY');
    } else {
      for (int i = 0; i < columns.length; i++) {
        final col = columns[i];
        buffer.write('  $q${col.name}$q ${col.type}');
        if (!col.isNullable) buffer.write(' NOT NULL');
        if (col.defaultValue != null)
          buffer.write(' DEFAULT ${col.defaultValue}');
        if (col.isPrimaryKey) buffer.write(' PRIMARY KEY');
        if (i < columns.length - 1) buffer.write(',');
        buffer.writeln();
      }
    }

    buffer.writeln(');');
    return buffer.toString();
  }

  String _generateAddColumnSql(
    String tableName,
    DbColumn column,
    DatabaseType dbType,
  ) {
    final q = _getQuoteChar(dbType);
    final buffer = StringBuffer();
    final addKeyword = dbType == DatabaseType.sqlserver ? 'ADD' : 'ADD COLUMN';
    // PG serial 列（同 _buildCreateTableSql，见 resolvePgSerialColumn）。
    final resolved = resolvePgSerialColumn(dbType, column.type, column.defaultValue);
    buffer.write(
      'ALTER TABLE ${_quoteTable(tableName, dbType)} $addKeyword $q${column.name}$q ${resolved.type}',
    );
    if (!column.isNullable) buffer.write(' NOT NULL');
    if (resolved.defaultValue != null) {
      buffer.write(' DEFAULT ${_formatDefaultValue(resolved.defaultValue!)}');
    }
    buffer.write(';');
    return buffer.toString();
  }

  String _generateDropColumnSql(
    String tableName,
    String columnName,
    DatabaseType dbType,
  ) {
    final q = _getQuoteChar(dbType);
    return 'ALTER TABLE ${_quoteTable(tableName, dbType)} DROP COLUMN $q$columnName$q;';
  }

  String _generateModifyColumnSql(
    String tableName,
    DbColumn column,
    DatabaseType dbType,
  ) {
    final q = _getQuoteChar(dbType);
    final buffer = StringBuffer();

    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.doris:
        buffer.write(
          'ALTER TABLE ${_quoteTable(tableName, dbType)} MODIFY COLUMN $q${column.name}$q ${column.type}',
        );
        if (!column.isNullable) buffer.write(' NOT NULL');
        if (column.defaultValue != null)
          buffer.write(' DEFAULT ${_formatDefaultValue(column.defaultValue!)}');
        buffer.write(';');
        break;
      case DatabaseType.postgresql:
        buffer.write(
          'ALTER TABLE ${_quoteTable(tableName, dbType)} ALTER COLUMN $q${column.name}$q TYPE ${column.type};',
        );
        if (!column.isNullable) {
          buffer.write(
            '\nALTER TABLE ${_quoteTable(tableName, dbType)} ALTER COLUMN $q${column.name}$q SET NOT NULL;',
          );
        }
        if (column.defaultValue != null) {
          buffer.write(
            '\nALTER TABLE ${_quoteTable(tableName, dbType)} ALTER COLUMN $q${column.name}$q SET DEFAULT ${_formatDefaultValue(column.defaultValue!)};',
          );
        }
        break;
      case DatabaseType.sqlite:
        buffer.write(
          '-- WARNING: SQLite does not support direct column modification.\n',
        );
        buffer.write(
          '-- The column $q${column.name}$q in table ${_quoteTable(tableName, dbType)} must be modified manually.\n',
        );
        buffer.write('-- Desired definition: ${column.type}');
        if (!column.isNullable) buffer.write(' NOT NULL');
        if (column.defaultValue != null)
          buffer.write(' DEFAULT ${column.defaultValue}');
        break;
      case DatabaseType.sqlserver:
        buffer.write(
          'ALTER TABLE ${_quoteTable(tableName, dbType)} ALTER COLUMN $q${column.name}$q ${column.type}',
        );
        if (!column.isNullable) buffer.write(' NOT NULL');
        buffer.write(';');
        if (column.defaultValue != null) {
          buffer.write(
            '\nALTER TABLE ${_quoteTable(tableName, dbType)} ADD CONSTRAINT DF_${tableName}_${column.name} DEFAULT ${_formatDefaultValue(column.defaultValue!)} FOR $q${column.name}$q;',
          );
        }
        break;
      default:
        buffer.write(
          'ALTER TABLE ${_quoteTable(tableName, dbType)} ALTER COLUMN $q${column.name}$q ${column.type}',
        );
        if (!column.isNullable) buffer.write(' NOT NULL');
        if (column.defaultValue != null)
          buffer.write(' DEFAULT ${_formatDefaultValue(column.defaultValue!)}');
        buffer.write(';');
    }

    return buffer.toString();
  }

  String _generateCreateIndexSql(
    String tableName,
    DbIndex index,
    DatabaseType dbType,
  ) {
    final q = _getQuoteChar(dbType);
    final unique = index.isUnique ? 'UNIQUE ' : '';
    final columns = index.columns.map((c) => '$q$c$q').join(', ');
    return 'CREATE ${unique}INDEX $q${index.name}$q ON ${_quoteTable(tableName, dbType)} ($columns);';
  }

  String _generateDropIndexSql(
    String tableName,
    String indexName,
    DatabaseType dbType, {
    bool isUnique = false,
  }) {
    final q = _getQuoteChar(dbType);
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.doris:
        return 'DROP INDEX $q$indexName$q ON ${_quoteTable(tableName, dbType)};';
      case DatabaseType.postgresql:
        if (isUnique) {
          return 'ALTER TABLE ${_quoteTable(tableName, dbType)} DROP CONSTRAINT IF EXISTS $q$indexName$q;';
        }
        return 'DROP INDEX IF EXISTS $q$indexName$q;';
      case DatabaseType.sqlite:
        return 'DROP INDEX IF EXISTS $q$indexName$q;';
      case DatabaseType.sqlserver:
        return 'DROP INDEX $q$indexName$q ON ${_quoteTable(tableName, dbType)};';
      default:
        return 'DROP INDEX $q$indexName$q;';
    }
  }
}
