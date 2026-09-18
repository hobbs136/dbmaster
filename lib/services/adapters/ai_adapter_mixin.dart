import 'dart:convert';
import '../ai/ai_service_localizations.dart';
import '../database_abstract.dart';
import '../readonly_guard.dart';
import '../../../utils/app_logger.dart';

/// Default AI adapter implementations for SQL-based adapters.
/// NoSQL adapters (MongoDB, Redis) should override executeAiCommand and validateCommand.
mixin AiAdapterMixin {
  DatabaseAdapter get _adapter => this as DatabaseAdapter;

  Future<String> getAiSchemaSummary({
    String? target,
    String? databaseName,
    String locale = 'en',
  }) async {
    final l = AiServiceLocalizations(locale);
    final buffer = StringBuffer();
    try {
      final db =
          databaseName ?? _adapter.currentConnection?.database ?? 'unknown';
      buffer.writeln(
        l.schemaSummaryDbTypeLabel(_adapter.databaseType.displayName),
      );
      buffer.writeln(l.contextCurrentDatabase(db));

      final tables = await _adapter.getTables();
      buffer.writeln(l.schemaSummaryTableCount(tables.length));
      if (tables.isNotEmpty) {
        buffer.writeln(l.schemaSummaryTableList(tables.take(50).join(", ")));
        if (tables.length > 50)
          buffer.writeln(l.schemaSummaryMoreTables(tables.length));
      }

      if (target != null && target.isNotEmpty && tables.contains(target)) {
        try {
          final details = await _adapter.getTableDetails(target);
          buffer.writeln(l.schemaSummaryStructureHeader(target));
          for (final col in details.columns) {
            buffer.writeln(
              '  ${col.name} ${col.type}${col.isPrimaryKey ? " PRIMARY KEY" : ""}${col.isNullable ? "" : " NOT NULL"}',
            );
          }
          if (details.indexes.isNotEmpty) {
            buffer.writeln(l.schemaSummaryIndexesHeader);
            for (final idx in details.indexes) {
              buffer.writeln(
                '  ${idx.name}(${idx.columns.join(", ")})${idx.isUnique ? " UNIQUE" : ""}',
              );
            }
          }
          // 双向外键关系是删除/更新影响分析的关键上下文；单段失败静默不阻断摘要。
          try {
            final fks = await _adapter.getForeignKeys(target);
            if (fks.isNotEmpty) {
              buffer.writeln(l.schemaSummaryForeignKeysHeader);
              for (final fk in fks) {
                buffer.writeln(
                  l.schemaSummaryForeignKeyLine(
                    fk.column,
                    fk.referencedTable,
                    fk.referencedColumn,
                    fk.onDelete,
                  ),
                );
              }
            }
          } catch (_) {
            // 外键段失败不影响其余摘要
          }
          try {
            final refs = await _adapter.getReferencingForeignKeys(target);
            if (refs.isNotEmpty) {
              buffer.writeln(l.schemaSummaryReferencedByHeader);
              for (final fk in refs) {
                buffer.writeln(
                  l.schemaSummaryForeignKeyLine(
                    '${fk.table}.${fk.column}',
                    fk.referencedTable,
                    fk.referencedColumn,
                    fk.onDelete,
                  ),
                );
              }
            }
          } catch (_) {
            // 引用段失败不影响其余摘要
          }
        } catch (e) {
          buffer.writeln(
            l.schemaSummaryTableDetailsFailed(target, e.toString()),
          );
        }
      }
    } catch (e) {
      AppLogger.d('AiAdapterMixin', 'getAiSchemaSummary error: $e');
      buffer.writeln(l.schemaSummaryFetchFailed(e.toString()));
    }
    return buffer.toString();
  }

  Future<AiExecutionResult> executeAiCommand(
    String command, {
    String locale = 'en',
  }) async {
    try {
      final result = await _adapter.executeQuery(command);
      return AiExecutionResult.success(
        _formatQueryResult(result, locale: locale),
        data: {
          'columns': result.columns,
          'rows': result.rows,
          'affectedRows': result.affectedRows,
          'message': result.message,
        },
      );
    } catch (e) {
      return AiExecutionResult.failure(
        AiServiceLocalizations(locale).toolExecutionFailed(e.toString()),
      );
    }
  }

  SecurityCheckResult validateCommand(String command) {
    final upper = command.trim().toUpperCase();
    final firstWord = upper.split(RegExp(r'\s+')).firstOrNull ?? '';

    // Dangerous
    if (firstWord == 'DROP' || firstWord == 'TRUNCATE') {
      return SecurityCheckResult(
        false,
        CommandRiskLevel.dangerous,
        reason: 'Contains a $firstWord statement — high-risk operation',
      );
    }
    if ((firstWord == 'DELETE' || firstWord == 'UPDATE') &&
        !upper.contains('WHERE')) {
      return SecurityCheckResult(
        false,
        CommandRiskLevel.dangerous,
        reason: '$firstWord statement is missing a WHERE clause',
      );
    }

    // Warning
    if (firstWord == 'DELETE' ||
        firstWord == 'UPDATE' ||
        firstWord == 'INSERT' ||
        firstWord == 'ALTER') {
      return SecurityCheckResult(
        true,
        CommandRiskLevel.warning,
        reason: 'Write operation — recommend confirming before execution',
      );
    }

    return SecurityCheckResult.ok;
  }

  /// 判定一条查询是否为写操作（feature 039，只读守卫用）。
  ///
  /// 默认 SQL 关键字实现；NoSQL adapter（Redis/MongoDB）override 复用各自
  /// `validateCommand` 的写分类。**不**复用 `validateCommand` 本身——SQL Server
  /// stub 对所有命令返回 dangerous，会误拦 web 读（research D5）。
  bool isWriteCommand(String query) {
    final upper = query.trim().toUpperCase();
    const writeKeywords = [
      'INSERT',
      'UPDATE',
      'DELETE',
      'DROP',
      'CREATE',
      'ALTER',
      'TRUNCATE',
      'REPLACE',
      'GRANT',
      'REVOKE',
    ];
    for (final keyword in writeKeywords) {
      if (upper.startsWith(keyword) ||
          RegExp('\\b$keyword\\b').hasMatch(upper)) {
        return true;
      }
    }
    return false;
  }

  /// 写方法自守卫：`currentConnection.readOnly`（或连接缺失 fail-closed）→ 抛。
  /// 每个 adapter 写方法方法体首行调用（contracts C1/C5）。
  /// 公开（非下划线）：adapter 在各自文件（不同 library）需可调。
  void guardReadOnly({String? operation, String? commandName}) {
    final conn = _adapter.currentConnection;
    // null → fail-closed（写路径上 readOnly 不可确认 = 拒，FR-003）。
    if (conn?.readOnly ?? true) {
      throw ReadOnlyBlockedException(
        databaseType: _adapter.databaseType,
        operation: operation,
        commandName: commandName,
      );
    }
  }

  /// executeQuery 自守卫：只读 + isWriteCommand → 抛。
  /// null 连接放行给下游连接错误处理（非写路径 fail-closed 场景）。
  /// 公开（非下划线）：adapter 各文件需可调。
  void guardReadOnlyQuery(String query, {String? operation}) {
    final conn = _adapter.currentConnection;
    if (conn?.readOnly == true && isWriteCommand(query)) {
      throw ReadOnlyBlockedException(
        databaseType: _adapter.databaseType,
        operation: operation,
        commandName: query,
      );
    }
  }

  String _formatQueryResult(QueryResult result, {String locale = 'en'}) {
    if (result.message != null && result.message!.isNotEmpty) {
      return result.message!;
    }
    if (result.rows.isEmpty) {
      return AiServiceLocalizations(
        locale,
      ).affectedRows(result.affectedRows ?? 0);
    }
    final encoder = JsonEncoder.withIndent('  ');
    try {
      return encoder.convert(result.rows);
    } catch (_) {
      return result.rows.toString();
    }
  }
}
