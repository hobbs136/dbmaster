import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/mongo_index_advisor.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  late MongoIndexAdvisorService advisor;

  setUp(() => advisor = MongoIndexAdvisorService());

  group('MongoIndexAdvisorService.analyzeForIndex', () {
    test('find 等值字段无索引 → 建议创建索引', () {
      final recs = advisor.analyzeForIndex(
        'db.users.find({email: "a@b.com"})',
        existingIndexes: const [],
      );
      expect(recs, hasLength(1));
      expect(recs.first.duplicateOfExisting, isFalse);
      expect(recs.first.key.containsKey('email'), isTrue);
      expect(recs.first.reason, IndexRecommendationReason.equality);
    });

    test('既有索引覆盖字段 → duplicateOfExisting=true', () {
      final recs = advisor.analyzeForIndex(
        'db.users.find({email: "a@b.com"})',
        existingIndexes: [
          DbIndex(name: 'email_1', columns: const ['email']),
        ],
      );
      expect(recs, hasLength(1));
      expect(recs.first.duplicateOfExisting, isTrue);
    });

    test('find 排序 → sort 字段进入键', () {
      final recs = advisor.analyzeForIndex(
        'db.logs.find({level: "error"}).sort({ts: -1})',
        existingIndexes: const [],
      );
      expect(recs.first.key.containsKey('level'), isTrue);
      expect(recs.first.key['ts'], -1);
    });

    test('aggregate \$match + \$sort → 合成 ESR 键', () {
      final recs = advisor.analyzeForIndex(
        "db.orders.aggregate([{\$match: {status: 'paid'}}, {\$sort: {amount: -1}}])",
        existingIndexes: const [],
      );
      expect(recs.first.key.containsKey('status'), isTrue);
      expect(recs.first.key['amount'], -1);
    });

    test('范围操作符字段归入 R 段', () {
      final recs = advisor.analyzeForIndex(
        'db.events.find({ts: {\$gte: 1, \$lt: 100}})',
        existingIndexes: const [],
      );
      expect(recs.first.key.containsKey('ts'), isTrue);
    });

    test('无可索引字段 → 无需索引', () {
      final recs = advisor.analyzeForIndex(
        'db.coll.find()',
        existingIndexes: const [],
      );
      expect(recs.first.key, isEmpty);
    });
  });

  group('MongoIndexAdvisorService.generateReport', () {
    test('全部重复 → 已覆盖消息', () {
      final recs = advisor.analyzeForIndex(
        'db.users.find({email: "a@b.com"})',
        existingIndexes: [
          DbIndex(name: 'email_1', columns: const ['email']),
        ],
      );
      final report = advisor.generateReport(
        'db.users.find({email: "a@b.com"})',
        recs,
      );
      expect(report, contains('已被既有索引覆盖'));
    });
  });
}
