import 'package:dbmaster/pro/data_sync/data_sync_models.dart';
import 'package:dbmaster/services/database_abstract.dart';

/// 批量插入器
/// 将数据批量插入目标库，支持多种目标策略和事务管理
class BatchInserter {
  final DatabaseAdapter targetAdapter;
  final String targetTable;
  final TargetStrategy strategy;

  /// 目标表主键字段（用于 upsert 策略）
  final String? primaryKey;

  BatchInserter({
    required this.targetAdapter,
    required this.targetTable,
    required this.strategy,
    this.primaryKey,
  });

  /// 执行批量插入
  /// 返回：{synced: 成功行数, failed: 失败行数, skipped: 跳过行数}
  Future<Map<String, int>> insertBatch(
    List<Map<String, dynamic>> rows, {
    bool isFirstBatch = false,
  }) async {
    if (rows.isEmpty) {
      return {'synced': 0, 'failed': 0, 'skipped': 0};
    }

    final fields = rows.first.keys.toList();

    try {
      await targetAdapter.beginTransaction();

      // 根据策略生成并执行 SQL
      final sql = _buildInsertSql(rows, fields);
      await targetAdapter.executeQuery(sql);

      await targetAdapter.commit();

      return {'synced': rows.length, 'failed': 0, 'skipped': 0};
    } catch (e) {
      // 批量插入失败，回滚后逐条重试
      try {
        await targetAdapter.rollback();
      } catch (_) {
        // 某些适配器可能不支持 rollback，忽略
      }

      return _insertOneByOne(rows, fields);
    }
  }

  /// 逐条插入（批量失败后的回退策略）
  Future<Map<String, int>> _insertOneByOne(
    List<Map<String, dynamic>> rows,
    List<String> fields,
  ) async {
    int synced = 0;
    int failed = 0;
    int skipped = 0;

    for (final row in rows) {
      try {
        final sql = _buildSingleInsertSql(row, fields);
        await targetAdapter.executeQuery(sql);
        synced++;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        // 重复键错误视为跳过
        if (errorStr.contains('duplicate') ||
            errorStr.contains('unique') ||
            errorStr.contains('constraint')) {
          skipped++;
        } else {
          failed++;
        }
      }
    }

    return {'synced': synced, 'failed': failed, 'skipped': skipped};
  }

  /// 构建批量 INSERT SQL
  String _buildInsertSql(List<Map<String, dynamic>> rows, List<String> fields) {
    switch (strategy) {
      case TargetStrategy.truncate:
      case TargetStrategy.append:
        return _buildStandardInsert(rows, fields);
      case TargetStrategy.replace:
        return _buildReplaceInsert(rows, fields);
      case TargetStrategy.upsert:
        return _buildUpsertInsert(rows, fields);
    }
  }

  /// 标准 INSERT（truncate / append）
  String _buildStandardInsert(
    List<Map<String, dynamic>> rows,
    List<String> fields,
  ) {
    final fieldList = fields.map((f) => '`$f`').join(', ');
    final values = rows
        .map((row) {
          final valueList = fields.map((f) => _formatValue(row[f])).join(', ');
          return '($valueList)';
        })
        .join(',\n  ');

    if (strategy == TargetStrategy.append) {
      return 'INSERT IGNORE INTO `$targetTable` ($fieldList) VALUES\n  $values';
    }

    return 'INSERT INTO `$targetTable` ($fieldList) VALUES\n  $values';
  }

  /// REPLACE INTO
  String _buildReplaceInsert(
    List<Map<String, dynamic>> rows,
    List<String> fields,
  ) {
    final fieldList = fields.map((f) => '`$f`').join(', ');
    final values = rows
        .map((row) {
          final valueList = fields.map((f) => _formatValue(row[f])).join(', ');
          return '($valueList)';
        })
        .join(',\n  ');

    return 'REPLACE INTO `$targetTable` ($fieldList) VALUES\n  $values';
  }

  /// INSERT ... ON DUPLICATE KEY UPDATE（MySQL/Doris）
  String _buildUpsertInsert(
    List<Map<String, dynamic>> rows,
    List<String> fields,
  ) {
    final fieldList = fields.map((f) => '`$f`').join(', ');
    final values = rows
        .map((row) {
          final valueList = fields.map((f) => _formatValue(row[f])).join(', ');
          return '($valueList)';
        })
        .join(',\n  ');

    // 生成 UPDATE 部分（排除主键）
    final updateFields = fields.where((f) => f != primaryKey).toList();
    final updates = updateFields.map((f) => '`$f` = VALUES(`$f`)').join(', ');

    if (updates.isEmpty) {
      // 只有主键字段，退化为 INSERT IGNORE
      return 'INSERT IGNORE INTO `$targetTable` ($fieldList) VALUES\n  $values';
    }

    return 'INSERT INTO `$targetTable` ($fieldList) VALUES\n  $values\n'
        'ON DUPLICATE KEY UPDATE $updates';
  }

  /// 单条 INSERT SQL
  String _buildSingleInsertSql(Map<String, dynamic> row, List<String> fields) {
    final fieldList = fields.map((f) => '`$f`').join(', ');
    final values = fields.map((f) => _formatValue(row[f])).join(', ');

    switch (strategy) {
      case TargetStrategy.truncate:
        return 'INSERT INTO `$targetTable` ($fieldList) VALUES ($values)';
      case TargetStrategy.append:
        return 'INSERT IGNORE INTO `$targetTable` ($fieldList) VALUES ($values)';
      case TargetStrategy.replace:
        return 'REPLACE INTO `$targetTable` ($fieldList) VALUES ($values)';
      case TargetStrategy.upsert:
        final updateFields = fields.where((f) => f != primaryKey).toList();
        final updates = updateFields
            .map((f) => '`$f` = VALUES(`$f`)')
            .join(', ');
        if (updates.isEmpty) {
          return 'INSERT IGNORE INTO `$targetTable` ($fieldList) VALUES ($values)';
        }
        return 'INSERT INTO `$targetTable` ($fieldList) VALUES ($values) '
            'ON DUPLICATE KEY UPDATE $updates';
    }
  }

  /// 格式化值
  String _formatValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is String) {
      final escaped = value.replaceAll("'", "''");
      return "'$escaped'";
    }
    if (value is DateTime) {
      final formatted = value
          .toIso8601String()
          .replaceFirst('T', ' ')
          .split('.')
          .first;
      return "'$formatted'";
    }
    if (value is bool) return value ? '1' : '0';
    return value.toString();
  }
}
