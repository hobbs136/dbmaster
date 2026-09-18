import 'package:dbmaster/pro/data_sync/data_sync_models.dart';
import 'package:dbmaster/services/database_abstract.dart';

/// 游标分页器
/// 使用游标（Cursor-based）分页，避免 OFFSET 深分页性能问题
class CursorPaginator {
  final DatabaseAdapter adapter;
  final String tableName;
  final String segmentField;
  final String? primaryKey;
  final int pageSize;
  final SyncSegment segment;

  /// 当前游标值（最后一条记录的分段字段值）
  dynamic _lastCursorValue;

  /// 当前游标主键值（最后一条记录的主键值）
  dynamic _lastCursorPk;

  /// 是否还有更多数据
  bool _hasMore = true;

  /// 当前页码（从0开始）
  int _currentPage = -1;

  CursorPaginator({
    required this.adapter,
    required this.tableName,
    required this.segmentField,
    this.primaryKey,
    required this.pageSize,
    required this.segment,
  });

  bool get hasNext => _hasMore;

  int get currentPage => _currentPage;

  /// 获取下一页数据
  Future<List<Map<String, dynamic>>> nextPage() async {
    if (!_hasMore) return [];

    final sql = _buildQuerySql();
    final result = await adapter.executeQuery(sql);
    final rows = result.rows;

    _currentPage++;

    if (rows.isEmpty || rows.length < pageSize) {
      _hasMore = false;
    }

    if (rows.isNotEmpty) {
      final lastRow = rows.last;
      _lastCursorValue = lastRow[segmentField];
      if (primaryKey != null) {
        _lastCursorPk = lastRow[primaryKey];
      }
    }

    return rows;
  }

  /// 构建查询 SQL
  String _buildQuerySql() {
    final buffer = StringBuffer();
    buffer.write('SELECT * FROM `$tableName`');

    // 段条件 + 游标条件
    final whereConditions = _buildWhereConditions();
    if (whereConditions.isNotEmpty) {
      buffer.write(' WHERE $whereConditions');
    }

    // ORDER BY（必须按分段字段 + 主键排序，确保游标有效）
    final orderBy = _buildOrderBy();
    buffer.write(' ORDER BY $orderBy');

    // LIMIT
    buffer.write(' LIMIT $pageSize');

    return buffer.toString();
  }

  /// 构建 WHERE 条件
  String _buildWhereConditions() {
    final conditions = <String>[];

    // 1. 段范围条件
    final startValue = segment.startValue;
    final endValue = segment.endValue;

    if (startValue != null) {
      conditions.add('`$segmentField` >= ${_formatValue(startValue)}');
    }
    if (endValue != null) {
      conditions.add('`$segmentField` < ${_formatValue(endValue)}');
    }

    // 2. 游标条件（用于跳过已读取的数据）
    if (_lastCursorValue != null) {
      if (primaryKey != null && _lastCursorPk != null) {
        // 复合游标：处理分段字段值相同的情况
        conditions.add(
          '(`$segmentField` > ${_formatValue(_lastCursorValue)} '
          'OR (`$segmentField` = ${_formatValue(_lastCursorValue)} '
          'AND `$primaryKey` > ${_formatValue(_lastCursorPk)}))',
        );
      } else {
        // 简单游标
        conditions.add('`$segmentField` > ${_formatValue(_lastCursorValue)}');
      }
    }

    return conditions.join(' AND ');
  }

  /// 构建 ORDER BY
  String _buildOrderBy() {
    if (primaryKey != null && primaryKey != segmentField) {
      return '`$segmentField`, `$primaryKey`';
    }
    return '`$segmentField`';
  }

  /// 格式化值用于 SQL
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
    return value.toString();
  }

  /// 重置游标（用于重新读取）
  void reset() {
    _lastCursorValue = null;
    _lastCursorPk = null;
    _hasMore = true;
    _currentPage = -1;
  }
}
