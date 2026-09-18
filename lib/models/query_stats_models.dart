/// 慢查询采样数据模型（reports-M1 / #29，server migration 016）。
///
/// 对应 server 端 `GET /api/query-stats/summary` 与 `GET /api/query-stats`
/// 的响应形状（`{ok, data, error}` 信封的 `data` 部分）。
library;

/// Top N 聚合组（summary 的 `items` 元素）——按 digest(+连接+库种) 分组。
class QueryStatsDigestSummary {
  final String digest;
  final String dbKind;
  final String connId;
  final int count;
  final int totalMs;
  final double avgMs;
  final int maxMs;
  final String firstSeen;
  final String lastSeen;
  /// 该组最新一条的明文样本；实例 `DBMASTER_SLOW_QUERY_STORE_SQL=false`
  /// 时恒为 null。
  final String? sampleSqlText;

  const QueryStatsDigestSummary({
    required this.digest,
    required this.dbKind,
    required this.connId,
    required this.count,
    required this.totalMs,
    required this.avgMs,
    required this.maxMs,
    required this.firstSeen,
    required this.lastSeen,
    this.sampleSqlText,
  });

  factory QueryStatsDigestSummary.fromJson(Map<String, dynamic> json) {
    return QueryStatsDigestSummary(
      digest: json['digest'] as String? ?? '',
      dbKind: json['db_kind'] as String? ?? '',
      connId: json['conn_id'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      totalMs: (json['total_ms'] as num?)?.toInt() ?? 0,
      avgMs: (json['avg_ms'] as num?)?.toDouble() ?? 0,
      maxMs: (json['max_ms'] as num?)?.toInt() ?? 0,
      firstSeen: json['first_seen'] as String? ?? '',
      lastSeen: json['last_seen'] as String? ?? '',
      sampleSqlText: json['sample_sql_text'] as String?,
    );
  }
}

/// summary 的 `meta`——实例口径（UI 渲染口径横幅用）。
class QueryStatsMeta {
  final int thresholdMs;
  final bool storeSql;
  final int retentionDays;
  final int? droppedTotal;
  final String? windowFrom;

  const QueryStatsMeta({
    required this.thresholdMs,
    required this.storeSql,
    required this.retentionDays,
    this.droppedTotal,
    this.windowFrom,
  });

  factory QueryStatsMeta.fromJson(Map<String, dynamic> json) {
    return QueryStatsMeta(
      thresholdMs: (json['threshold_ms'] as num?)?.toInt() ?? 1000,
      storeSql: json['store_sql'] as bool? ?? true,
      retentionDays: (json['retention_days'] as num?)?.toInt() ?? 14,
      droppedTotal: (json['dropped_total'] as num?)?.toInt(),
      windowFrom: json['window_from'] as String?,
    );
  }
}

/// summary 响应整体。
class QueryStatsSummary {
  final List<QueryStatsDigestSummary> items;
  final QueryStatsMeta meta;

  const QueryStatsSummary({required this.items, required this.meta});

  factory QueryStatsSummary.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final metaRaw = json['meta'];
    return QueryStatsSummary(
      items: rawItems is List<dynamic>
          ? rawItems
              .map((e) =>
                  QueryStatsDigestSummary.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      meta: metaRaw is Map<String, dynamic>
          ? QueryStatsMeta.fromJson(metaRaw)
          : const QueryStatsMeta(
              thresholdMs: 1000, storeSql: true, retentionDays: 14),
    );
  }
}

/// 明细行（`GET /api/query-stats` 的 `items` 元素）。
class QueryStatsRecord {
  final String id;
  final String source;
  final String connId;
  final String dbKind;
  final String? database;
  final String digest;
  final String? sqlText;
  final int elapsedMs;
  final int? rowCount;
  final int? affectedRows;
  /// `ok` | `error` | `cancelled`。
  final String status;
  final String? errorCode;
  final String? userId;
  /// `gw_sse` | `sync_query` | `txn_query` | `admin_script` | `mcp_read`。
  final String entry;
  final String capturedAt;

  const QueryStatsRecord({
    required this.id,
    required this.source,
    required this.connId,
    required this.dbKind,
    this.database,
    required this.digest,
    this.sqlText,
    required this.elapsedMs,
    this.rowCount,
    this.affectedRows,
    required this.status,
    this.errorCode,
    this.userId,
    required this.entry,
    required this.capturedAt,
  });

  factory QueryStatsRecord.fromJson(Map<String, dynamic> json) {
    return QueryStatsRecord(
      id: json['id'] as String? ?? '',
      source: json['source'] as String? ?? '',
      connId: json['conn_id'] as String? ?? '',
      dbKind: json['db_kind'] as String? ?? '',
      database: json['database'] as String?,
      digest: json['digest'] as String? ?? '',
      sqlText: json['sql_text'] as String?,
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      rowCount: (json['row_count'] as num?)?.toInt(),
      affectedRows: (json['affected_rows'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'ok',
      errorCode: json['error_code'] as String?,
      userId: json['user_id'] as String?,
      entry: json['entry'] as String? ?? '',
      capturedAt: json['captured_at'] as String? ?? '',
    );
  }
}

/// 明细分页响应。
class QueryStatsDetailPage {
  final List<QueryStatsRecord> items;
  final int total;
  final int limit;
  final int offset;

  const QueryStatsDetailPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory QueryStatsDetailPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return QueryStatsDetailPage(
      items: rawItems is List<dynamic>
          ? rawItems
              .map(
                  (e) => QueryStatsRecord.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 50,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}
