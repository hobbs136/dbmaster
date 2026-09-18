import '../models/query_history.dart';

/// 历史查询的日期分组标签
enum QueryHistoryDateGroup { today, yesterday, last7Days, older }

/// 将历史记录按日期分组
///
/// 返回的 Map 保持分组顺序：Today -> Yesterday -> Last 7 days -> Older
Map<QueryHistoryDateGroup, List<QueryHistory>> groupQueryHistoryByDate(
  List<QueryHistory> history,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final sevenDaysAgo = today.subtract(const Duration(days: 7));

  final groups = <QueryHistoryDateGroup, List<QueryHistory>>{
    QueryHistoryDateGroup.today: <QueryHistory>[],
    QueryHistoryDateGroup.yesterday: <QueryHistory>[],
    QueryHistoryDateGroup.last7Days: <QueryHistory>[],
    QueryHistoryDateGroup.older: <QueryHistory>[],
  };

  for (final item in history) {
    final ts = item.timestamp;
    final date = DateTime(ts.year, ts.month, ts.day);

    if (date == today) {
      groups[QueryHistoryDateGroup.today]!.add(item);
    } else if (date == yesterday) {
      groups[QueryHistoryDateGroup.yesterday]!.add(item);
    } else if (date.isAfter(sevenDaysAgo) || date == sevenDaysAgo) {
      groups[QueryHistoryDateGroup.last7Days]!.add(item);
    } else {
      groups[QueryHistoryDateGroup.older]!.add(item);
    }
  }

  return groups;
}

/// 获取日期分组的显示标题 key
String dateGroupTitleKey(QueryHistoryDateGroup group) {
  switch (group) {
    case QueryHistoryDateGroup.today:
      return 'queryHistoryToday';
    case QueryHistoryDateGroup.yesterday:
      return 'queryHistoryYesterday';
    case QueryHistoryDateGroup.last7Days:
      return 'queryHistoryLast7Days';
    case QueryHistoryDateGroup.older:
      return 'queryHistoryOlder';
  }
}
