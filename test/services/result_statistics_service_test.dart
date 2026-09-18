import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/result_filter.dart';
import 'package:dbmaster/services/result_statistics_service.dart';

/// ResultStatisticsService 纯函数单测（R3 就地分析）。
/// 覆盖：数值列（median/null）、分类列（TOP5/distinct）、日期列（min/max/span）、
/// 阈值降级、SQL 生成。
void main() {
  group('ResultStatisticsService.compute', () {
    test('空数据返回空列表', () {
      final stats = ResultStatisticsService.compute(
        data: const [],
        columnTypes: const {},
      );
      expect(stats, isEmpty);
    });

    test('数值列：count/sum/avg/min/max/median/nullCount', () {
      final stats = ResultStatisticsService.compute(
        data: [
          {'score': 80},
          {'score': 90},
          {'score': 100},
          {'score': null}, // null 计数
          {'score': 'invalid'}, // 不可解析 → null
        ],
        columnTypes: {'score': ColumnDataType.numeric},
      );
      final col = stats.single;
      expect(col.name, 'score');
      expect(col.count, 3);
      expect(col.sum, 270);
      expect(col.avg, closeTo(90, 0.01));
      expect(col.min, 80);
      expect(col.max, 100);
      expect(col.median, 90); // 排序后 [80,90,100]，中位数 90
      expect(col.nullCount, 2);
    });

    test('数值列偶数个值的中位数（中间两数均值）', () {
      final stats = ResultStatisticsService.compute(
        data: [
          {'v': 10},
          {'v': 20},
          {'v': 30},
          {'v': 40},
        ],
        columnTypes: {'v': ColumnDataType.numeric},
      );
      // [10,20,30,40] → 中位数 (20+30)/2 = 25
      expect(stats.single.median, 25);
    });

    test('数值列全是 null → count=0, nullCount=N', () {
      final stats = ResultStatisticsService.compute(
        data: [
          {'v': null},
          {'v': null},
        ],
        columnTypes: {'v': ColumnDataType.numeric},
      );
      expect(stats.single.count, isNull);
      expect(stats.single.nullCount, 2);
    });

    test('分类列：distinctCount + TOP5 频次', () {
      final stats = ResultStatisticsService.compute(
        data: [
          {'city': 'A'}, {'city': 'A'}, {'city': 'A'},
          {'city': 'B'}, {'city': 'B'},
          {'city': 'C'},
          {'city': null}, // null 计数
        ],
        columnTypes: {'city': ColumnDataType.string},
      );
      final col = stats.single;
      expect(col.distinctCount, 3); // A/B/C
      expect(col.topValues, isNotNull);
      expect(col.topValues!.first.key, 'A');
      expect(col.topValues!.first.value, 3);
      expect(col.topValues!.length, lessThanOrEqualTo(5));
      expect(col.nullCount, 1);
    });

    test('分类列 TOP5 截断（>5 个唯一值只取前5）', () {
      final data = List.generate(10, (i) => {'cat': 'c$i'});
      final stats = ResultStatisticsService.compute(
        data: data,
        columnTypes: {'cat': ColumnDataType.string},
      );
      expect(stats.single.topValues!.length, 5);
      expect(stats.single.distinctCount, 10);
    });

    test('日期列：min/max/span（天）', () {
      final stats = ResultStatisticsService.compute(
        data: [
          {'d': '2026-01-01'},
          {'d': '2026-01-10'},
          {'d': null},
        ],
        columnTypes: {'d': ColumnDataType.dateTime},
      );
      final col = stats.single;
      expect(col.dateMin, isNotNull);
      expect(col.dateMax, isNotNull);
      expect(col.dateSpan, contains('天'));
      expect(col.dateSpan, '9 天');
      expect(col.nullCount, 1);
    });

    test('日期列接受 DateTime 对象', () {
      final stats = ResultStatisticsService.compute(
        data: [
          {'d': DateTime(2026, 1, 1, 10)},
          {'d': DateTime(2026, 1, 1, 12)},
        ],
        columnTypes: {'d': ColumnDataType.dateTime},
      );
      // 跨度 2 小时
      expect(stats.single.dateSpan, '2 小时');
    });

    test('混合列：数值 + 分类同时计算', () {
      final stats = ResultStatisticsService.compute(
        data: [
          {'name': 'Alice', 'score': 90},
          {'name': 'Bob', 'score': 80},
        ],
        columnTypes: {
          'name': ColumnDataType.string,
          'score': ColumnDataType.numeric,
        },
      );
      expect(stats.length, 2);
      final numeric = stats.firstWhere((s) => s.name == 'score');
      final cat = stats.firstWhere((s) => s.name == 'name');
      expect(numeric.avg, 85);
      expect(cat.distinctCount, 2);
    });

    test('>10K 行抛 DatasetTooLargeException', () {
      final data = List.generate(10001, (i) => {'v': i});
      expect(
        () => ResultStatisticsService.compute(
          data: data,
          columnTypes: {'v': ColumnDataType.numeric},
        ),
        throwsA(isA<DatasetTooLargeException>()),
      );
    });

    test('=10K 行不抛（边界）', () {
      final data = List.generate(10000, (i) => {'v': i});
      final stats = ResultStatisticsService.compute(
        data: data,
        columnTypes: {'v': ColumnDataType.numeric},
      );
      expect(stats.single.count, 10000);
    });
  });

  group('ResultStatisticsService.generateStatsSql', () {
    test('生成聚合 SQL（带表名）', () {
      final sql = ResultStatisticsService.generateStatsSql(
        column: 'price', agg: 'AVG', table: 'orders',
      );
      expect(sql, 'SELECT AVG(price) FROM orders;');
    });

    test('无表名用占位符', () {
      final sql = ResultStatisticsService.generateStatsSql(column: 'amt', agg: 'SUM');
      expect(sql, contains('<target_table>'));
      expect(sql, contains('SUM(amt)'));
    });
  });

  group('ResultStatisticsService.generateGroupBySql', () {
    test('默认 COUNT(*) GROUP BY', () {
      final sql = ResultStatisticsService.generateGroupBySql(
        column: 'region', table: 'sales',
      );
      expect(sql, contains('GROUP BY region'));
      expect(sql, contains('COUNT(*)'));
      expect(sql, contains('ORDER BY value DESC'));
    });

    test('指定聚合列 SUM(amt) GROUP BY', () {
      final sql = ResultStatisticsService.generateGroupBySql(
        column: 'region', aggColumn: 'amt', agg: 'SUM', table: 'sales',
      );
      expect(sql, contains('SUM(amt)'));
    });
  });

  group('ColumnStatistics 谓词', () {
    test('isNumeric / isCategorical / isDateTime', () {
      const numeric = ColumnStatistics(name: 'a', type: ColumnDataType.numeric);
      const cat = ColumnStatistics(name: 'b', type: ColumnDataType.string);
      const dt = ColumnStatistics(name: 'c', type: ColumnDataType.dateTime);
      expect(numeric.isNumeric, isTrue);
      expect(cat.isCategorical, isTrue);
      expect(dt.isDateTime, isTrue);
    });
  });

  group('DatasetTooLargeException', () {
    test('toString 含行数和阈值', () {
      final e = DatasetTooLargeException(15000, 10000);
      expect(e.toString(), contains('15000'));
      expect(e.toString(), contains('10000'));
    });
  });
}
