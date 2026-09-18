import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/mongo_optimizer_service.dart';

void main() {
  late MongoOptimizerService service;

  setUp(() => service = MongoOptimizerService());

  group('MongoOptimizerService.analyze', () {
    test('find 无投影 → 投影优化建议', () {
      final suggestions = service.analyze('db.users.find({active: true})');
      final types = suggestions.map((s) => s.type).toList();
      expect(types, contains('投影优化'));
    });

    test('find 带过滤但无索引 → 索引缺失建议', () {
      final suggestions = service.analyze(
        'db.users.find({age: {\$gte: 18}})',
        existingIndexes: const [],
      );
      final types = suggestions.map((s) => s.type).toList();
      expect(types, contains('索引缺失'));
    });

    test('aggregate \$match 未前置 → 管道顺序建议', () {
      final suggestions = service.analyze(
        "db.orders.aggregate([{\$sort: {amount: -1}}, {\$match: {status: 'paid'}}])",
      );
      final types = suggestions.map((s) => s.type).toList();
      expect(types, contains('管道顺序'));
      final reorder = suggestions.firstWhere((s) => s.type == '管道顺序');
      expect(reorder.priority, MongoOptimizationPriority.high);
    });

    test('已弃用 count() → API 迁移建议', () {
      final suggestions = service.analyze('db.users.count({active: true})');
      final types = suggestions.map((s) => s.type).toList();
      expect(types, contains('API 迁移'));
    });

    test('aggregate 含 \$lookup → 连接开销建议', () {
      final suggestions = service.analyze(
        'db.orders.aggregate([{\$lookup: {from: "users", localField: "uid", foreignField: "_id", as: "u"}}])',
      );
      expect(suggestions.map((s) => s.type), contains('连接开销'));
    });

    test('无法解析 → 返回解析提示而非抛异常', () {
      final suggestions = service.analyze('not a mongo query at all');
      expect(suggestions, hasLength(1));
      expect(suggestions.first.type, '解析提示');
    });
  });

  group('MongoOptimizerService.generateOptimizationReport', () {
    test('空建议 → 成功消息', () {
      final report = service.generateOptimizationReport(
        'db.users.find({}, {name: 1})',
        const [],
      );
      expect(report, contains('没有发现明显的优化点'));
    });

    test('有建议 → 报告含原始查询与建议', () {
      final suggestions = service.analyze('db.users.find({active: true})');
      final report = service.generateOptimizationReport(
        'db.users.find({active: true})',
        suggestions,
      );
      expect(report, contains('Mongo 查询优化分析报告'));
      expect(report, contains('db.users.find({active: true})'));
      expect(report, contains('优化建议'));
    });
  });
}
