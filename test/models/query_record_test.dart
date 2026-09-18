import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/query_history/query_record.dart';

// US4 — QueryRecord Mongo-aware getters (detectedQueryType / extractedTables).
void main() {
  group('QueryRecord Mongo detection (US4)', () {
    QueryRecord mongoRecord(String sql) => QueryRecord(
      sqlStatement: sql,
      connectionId: 'c1',
      executionTimeMs: 10,
      isSuccess: true,
      createdAt: DateTime(2026, 7, 14),
      databaseType: 'mongodb',
    );

    test('detectedQueryType maps Mongo methods', () {
      expect(mongoRecord('db.users.find({})').detectedQueryType, 'find');
      expect(mongoRecord('db.users.findOne({})').detectedQueryType, 'find');
      expect(
        mongoRecord(r'db.users.aggregate([{$match:{}}])').detectedQueryType,
        'aggregate',
      );
      expect(
        mongoRecord(r'db.users.updateOne({},{$set:{a:1}})').detectedQueryType,
        'update',
      );
      expect(mongoRecord('db.users.deleteOne({})').detectedQueryType, 'delete');
      expect(mongoRecord('db.users.insertOne({a:1})').detectedQueryType, 'insert');
      expect(
        mongoRecord('db.users.countDocuments({})').detectedQueryType,
        'find',
      );
    });

    test('extractedTables extracts Mongo collection', () {
      expect(
        mongoRecord(r'db.users.find({age:{$gte:18}})').extractedTables,
        ['users'],
      );
      expect(mongoRecord('db.orders.aggregate([])').extractedTables, ['orders']);
    });

    test('unknown Mongo method returns null type', () {
      expect(mongoRecord('db.users.bulkWrite([])').detectedQueryType, isNull);
    });

    test('SQL path unchanged', () {
      final r = QueryRecord(
        sqlStatement: 'SELECT * FROM users',
        connectionId: 'c1',
        executionTimeMs: 10,
        isSuccess: true,
        createdAt: DateTime(2026, 7, 14),
        databaseType: 'mysql',
      );
      expect(r.detectedQueryType, 'SELECT');
      expect(r.extractedTables, ['users']);
    });
  });
}
