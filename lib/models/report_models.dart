/// 报告中心数据模型（#29 reports 管道 M2，server migration 017）。
///
/// Report.content 是 JSON 字符串（服务端透传）；`slow_query_weekly` 类型有
/// typed 视图 [SlowQueryWeeklyReport]（content_version 1 契约），未知类型由
/// UI 走 JSON 回退渲染。
library;

import 'dart:convert';

/// reports 表行。
class Report {
  final String id;
  final String? taskId;
  final String reportType;
  final String title;
  /// JSON 字符串（原样透传；用 [contentDecoded] 取解析结果）。
  final String content;
  final String generatedAt;

  const Report({
    required this.id,
    this.taskId,
    required this.reportType,
    required this.title,
    required this.content,
    required this.generatedAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as String? ?? '',
      taskId: json['task_id'] as String?,
      reportType: json['report_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '{}',
      generatedAt: json['generated_at'] as String? ?? '',
    );
  }

  /// content 解析结果；解析失败返回 null（UI 走原始字符串回退）。
  Map<String, dynamic>? get contentDecoded {
    if (content.isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// `GET /api/reports` 分页响应。
class ReportsPage {
  final List<Report> items;
  final int total;
  final int limit;
  final int offset;

  const ReportsPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory ReportsPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ReportsPage(
      items: rawItems is List<dynamic>
          ? rawItems
              .map((e) => Report.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 50,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `POST /api/reports/generate` 响应（幂等：created=false 表示本窗口已有）。
class GenerateReportResult {
  final String id;
  final bool created;
  final String reportType;

  const GenerateReportResult({
    required this.id,
    required this.created,
    required this.reportType,
  });

  factory GenerateReportResult.fromJson(Map<String, dynamic> json) {
    return GenerateReportResult(
      id: json['id'] as String? ?? '',
      created: json['created'] as bool? ?? false,
      reportType: json['report_type'] as String? ?? '',
    );
  }
}

/// `slow_query_weekly` 的 typed content（content_version 1）。
class SlowQueryWeeklyReport {
  final int contentVersion;
  final String windowFrom;
  final String windowTo;
  /// retention 早于窗口起点 → true（覆盖不全，如实声明）。
  final bool windowTruncated;
  final SlowQueryWeeklySummary summary;
  final List<SlowQueryWeeklyTopItem> top;
  final List<SlowQueryWeeklyConnItem> byConnection;
  final List<SlowQueryWeeklyDayItem> byDay;

  const SlowQueryWeeklyReport({
    required this.contentVersion,
    required this.windowFrom,
    required this.windowTo,
    required this.windowTruncated,
    required this.summary,
    required this.top,
    required this.byConnection,
    required this.byDay,
  });

  static const reportType = 'slow_query_weekly';

  /// 从已解析的 content map 构造；形状不符（含未知 content_version）返回
  /// null → UI 走 JSON 回退。
  static SlowQueryWeeklyReport? fromDecoded(Map<String, dynamic> json) {
    if (json['report_type'] != reportType) return null;
    if ((json['content_version'] as num?)?.toInt() != 1) return null;
    final summaryRaw = json['summary'];
    if (summaryRaw is! Map<String, dynamic>) return null;
    final topRaw = json['top'];
    final connRaw = json['by_connection'];
    final dayRaw = json['by_day'];
    return SlowQueryWeeklyReport(
      contentVersion: 1,
      windowFrom: json['window_from'] as String? ?? '',
      windowTo: json['window_to'] as String? ?? '',
      windowTruncated: json['window_truncated'] as bool? ?? false,
      summary: SlowQueryWeeklySummary.fromJson(summaryRaw),
      top: topRaw is List<dynamic>
          ? topRaw
              .whereType<Map<String, dynamic>>()
              .map(SlowQueryWeeklyTopItem.fromJson)
              .toList()
          : const [],
      byConnection: connRaw is List<dynamic>
          ? connRaw
              .whereType<Map<String, dynamic>>()
              .map(SlowQueryWeeklyConnItem.fromJson)
              .toList()
          : const [],
      byDay: dayRaw is List<dynamic>
          ? dayRaw
              .whereType<Map<String, dynamic>>()
              .map(SlowQueryWeeklyDayItem.fromJson)
              .toList()
          : const [],
    );
  }
}

class SlowQueryWeeklySummary {
  final int totalSamples;
  final int distinctDigests;
  final int totalMs;
  final int errorCount;
  final int cancelledCount;
  /// 上一窗口无数据时 null（服务端不猜）。
  final double? weekOverWeekPct;

  const SlowQueryWeeklySummary({
    required this.totalSamples,
    required this.distinctDigests,
    required this.totalMs,
    required this.errorCount,
    required this.cancelledCount,
    this.weekOverWeekPct,
  });

  factory SlowQueryWeeklySummary.fromJson(Map<String, dynamic> json) {
    return SlowQueryWeeklySummary(
      totalSamples: (json['total_samples'] as num?)?.toInt() ?? 0,
      distinctDigests: (json['distinct_digests'] as num?)?.toInt() ?? 0,
      totalMs: (json['total_ms'] as num?)?.toInt() ?? 0,
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
      cancelledCount: (json['cancelled_count'] as num?)?.toInt() ?? 0,
      weekOverWeekPct: (json['week_over_week_pct'] as num?)?.toDouble(),
    );
  }
}

class SlowQueryWeeklyTopItem {
  final String digest;
  final String dbKind;
  final String connId;
  final int count;
  final int totalMs;
  final double avgMs;
  final int maxMs;
  final String? sampleSqlText;

  const SlowQueryWeeklyTopItem({
    required this.digest,
    required this.dbKind,
    required this.connId,
    required this.count,
    required this.totalMs,
    required this.avgMs,
    required this.maxMs,
    this.sampleSqlText,
  });

  factory SlowQueryWeeklyTopItem.fromJson(Map<String, dynamic> json) {
    return SlowQueryWeeklyTopItem(
      digest: json['digest'] as String? ?? '',
      dbKind: json['db_kind'] as String? ?? '',
      connId: json['conn_id'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      totalMs: (json['total_ms'] as num?)?.toInt() ?? 0,
      avgMs: (json['avg_ms'] as num?)?.toDouble() ?? 0,
      maxMs: (json['max_ms'] as num?)?.toInt() ?? 0,
      sampleSqlText: json['sample_sql_text'] as String?,
    );
  }
}

class SlowQueryWeeklyConnItem {
  final String connId;
  final String dbKind;
  final int count;
  final int totalMs;

  const SlowQueryWeeklyConnItem({
    required this.connId,
    required this.dbKind,
    required this.count,
    required this.totalMs,
  });

  factory SlowQueryWeeklyConnItem.fromJson(Map<String, dynamic> json) {
    return SlowQueryWeeklyConnItem(
      connId: json['conn_id'] as String? ?? '',
      dbKind: json['db_kind'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      totalMs: (json['total_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class SlowQueryWeeklyDayItem {
  final String date;
  final int count;
  final int totalMs;

  const SlowQueryWeeklyDayItem({
    required this.date,
    required this.count,
    required this.totalMs,
  });

  factory SlowQueryWeeklyDayItem.fromJson(Map<String, dynamic> json) {
    return SlowQueryWeeklyDayItem(
      date: json['date'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      totalMs: (json['total_ms'] as num?)?.toInt() ?? 0,
    );
  }
}
