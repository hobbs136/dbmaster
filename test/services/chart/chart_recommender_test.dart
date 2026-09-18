import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/result_filter.dart';
import 'package:dbmaster/services/chart/chart_recommender.dart';

/// ChartRecommender 纯函数单测（R2 智能推荐）。
/// 覆盖推荐矩阵：日期+数值→线 / 1分类+1数值→饼 / 2数值→散点 / 分类+数值→柱。
void main() {
  group('ChartRecommender.recommend', () {
    test('日期列 + 数值列 → 折线图', () {
      final r = ChartRecommender.recommend(columnTypes: {
        'order_date': ColumnDataType.dateTime,
        'amount': ColumnDataType.numeric,
      });
      expect(r.type, ChartType.line);
      expect(r.xAxis, 'order_date');
      expect(r.yAxis, 'amount');
    });

    test('1 分类 + 1 数值（采样基数 ≤10）→ 饼图', () {
      final r = ChartRecommender.recommend(
        columnTypes: {
          'category': ColumnDataType.string,
          'count': ColumnDataType.numeric,
        },
        sampleData: [
          {'category': 'A', 'count': 1},
          {'category': 'B', 'count': 2},
          {'category': 'A', 'count': 3},
        ],
      );
      expect(r.type, ChartType.pie);
      expect(r.xAxis, 'category');
      expect(r.yAxis, 'count');
    });

    test('1 分类 + 1 数值（采样基数 >10）→ 不推荐饼图（退回柱状）', () {
      // 唯一值超过 10，饼图不可读
      final sample = List.generate(15, (i) => {'cat': 'c$i', 'n': i});
      final r = ChartRecommender.recommend(
        columnTypes: {
          'cat': ColumnDataType.string,
          'n': ColumnDataType.numeric,
        },
        sampleData: sample,
      );
      expect(r.type, ChartType.bar);
    });

    test('2 数值列（无日期）→ 散点图', () {
      final r = ChartRecommender.recommend(columnTypes: {
        'x_val': ColumnDataType.numeric,
        'y_val': ColumnDataType.numeric,
      });
      expect(r.type, ChartType.scatter);
      expect(r.xAxis, 'x_val');
      expect(r.yAxis, 'y_val');
    });

    test('分类 + 数值（多分类列）→ 柱状图', () {
      final r = ChartRecommender.recommend(
        columnTypes: {
          'region': ColumnDataType.string,
          'country': ColumnDataType.string,
          'sales': ColumnDataType.numeric,
        },
        sampleData: [],
      );
      // 多于 1 个分类列 → 不走饼图，走柱状
      expect(r.type, ChartType.bar);
      expect(r.yAxis, 'sales');
    });

    test('日期 + 多数值 → 折线（日期优先）', () {
      final r = ChartRecommender.recommend(columnTypes: {
        'ts': ColumnDataType.dateTime,
        'a': ColumnDataType.numeric,
        'b': ColumnDataType.numeric,
      });
      // 日期 + 数值 → 折线优先于散点
      expect(r.type, ChartType.line);
      expect(r.xAxis, 'ts');
    });

    test('空列 → 兜底柱状图', () {
      final r = ChartRecommender.recommend(columnTypes: {});
      expect(r.type, ChartType.bar);
      expect(r.reason, isNotNull);
    });

    test('只有数值列（1 个）→ 柱状兜底', () {
      final r = ChartRecommender.recommend(columnTypes: {
        'single': ColumnDataType.numeric,
      });
      expect(r.type, ChartType.bar);
      expect(r.yAxis, 'single');
    });

    test('无采样数据时 1 分类 + 1 数值 → 保守退回柱状（基数未知）', () {
      // sampleData 为空 → _categoryCardinality 返回 999 → 不满足饼图 ≤10
      final r = ChartRecommender.recommend(
        columnTypes: {
          'cat': ColumnDataType.string,
          'n': ColumnDataType.numeric,
        },
        sampleData: [],
      );
      expect(r.type, ChartType.bar);
    });

    test('json 列被忽略（不参与推荐）', () {
      final r = ChartRecommender.recommend(columnTypes: {
        'meta': ColumnDataType.json,
        'date': ColumnDataType.dateTime,
        'val': ColumnDataType.numeric,
      });
      // json 列不参与，仍按 日期+数值 → 折线
      expect(r.type, ChartType.line);
      expect(r.xAxis, 'date');
    });
  });

  group('ChartRecommendation 模型', () {
    test('字段可构造且可读', () {
      const r = ChartRecommendation(
        type: ChartType.scatter,
        xAxis: 'x',
        yAxis: 'y',
        reason: 'test',
      );
      expect(r.type, ChartType.scatter);
      expect(r.xAxis, 'x');
      expect(r.yAxis, 'y');
      expect(r.reason, 'test');
    });
  });

  group('ChartType 枚举', () {
    test('有 4 个值', () {
      expect(ChartType.values.length, 4);
      expect(ChartType.values, contains(ChartType.line));
      expect(ChartType.values, contains(ChartType.bar));
      expect(ChartType.values, contains(ChartType.pie));
      expect(ChartType.values, contains(ChartType.scatter));
    });
  });
}
