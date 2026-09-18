import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/code_snippet.dart';

void main() {
  group('CodeSnippet', () {
    test('should create snippet with required fields', () {
      final snippet = CodeSnippet(
        id: 'test-1',
        name: 'Select All',
        description: 'Select all columns',
        category: 'DML',
        content: 'SELECT * FROM {{tableName}};',
        variables: ['tableName'],
      );

      expect(snippet.id, 'test-1');
      expect(snippet.name, 'Select All');
      expect(snippet.category, 'DML');
      expect(snippet.isBuiltIn, false);
      expect(snippet.usageCount, 0);
    });

    test('should be immutable - usageCount cannot be modified directly', () {
      final snippet = CodeSnippet(
        id: 'test-1',
        name: 'Test',
        description: 'Test desc',
        category: 'DML',
        content: 'SELECT 1',
        usageCount: 5,
      );

      // This should be a compile-time error if fields are final
      // We can't test compile-time errors at runtime, so we verify
      // that the value doesn't change when we try to "modify" it
      // (which actually creates a new instance via copyWith)
      final originalCount = snippet.usageCount;

      // Verify incrementUsage returns new instance, doesn't modify original
      final updated = snippet.incrementUsage();
      expect(snippet.usageCount, originalCount); // Original unchanged
      expect(updated.usageCount, originalCount + 1);
    });

    test('incrementUsage should return new instance', () {
      final snippet = CodeSnippet(
        id: 'test-1',
        name: 'Test',
        description: 'Test desc',
        category: 'DML',
        content: 'SELECT 1',
        usageCount: 5,
      );

      final updated = snippet.incrementUsage();

      expect(updated.usageCount, 6);
      expect(snippet.usageCount, 5); // Original unchanged
      expect(updated.lastUsedAt, isNotNull);
    });

    test('should serialize to JSON', () {
      final snippet = CodeSnippet(
        id: 'test-1',
        name: 'Test',
        description: 'Test desc',
        category: 'DML',
        content: 'SELECT 1',
        variables: ['tableName'],
        isBuiltIn: true,
        usageCount: 10,
      );

      final json = snippet.toJson();

      expect(json['id'], 'test-1');
      expect(json['name'], 'Test');
      expect(json['variables'], ['tableName']);
      expect(json['isBuiltIn'], true);
      expect(json['usageCount'], 10);
    });

    test('should deserialize from JSON', () {
      final json = {
        'id': 'test-1',
        'name': 'Test',
        'description': 'Test desc',
        'category': 'DML',
        'content': 'SELECT 1',
        'variables': ['tableName'],
        'isBuiltIn': false,
        'usageCount': 5,
        'createdAt': '2026-04-01T10:00:00.000Z',
        'updatedAt': '2026-04-01T10:00:00.000Z',
        'lastUsedAt': '2026-04-01T12:00:00.000Z',
      };

      final snippet = CodeSnippet.fromJson(json);

      expect(snippet.id, 'test-1');
      expect(snippet.name, 'Test');
      expect(snippet.usageCount, 5);
      expect(snippet.lastUsedAt, isNotNull);
    });

    test('copyWith should create updated copy', () {
      final snippet = CodeSnippet(
        id: 'test-1',
        name: 'Test',
        description: 'Test desc',
        category: 'DML',
        content: 'SELECT 1',
      );

      final copy = snippet.copyWith(name: 'Updated', usageCount: 10);

      expect(copy.id, 'test-1');
      expect(copy.name, 'Updated');
      expect(copy.usageCount, 10);
      expect(snippet.name, 'Test'); // Original unchanged
    });

    test('should round-trip JSON serialization', () {
      final original = CodeSnippet(
        id: 'round-trip-1',
        name: 'Round Trip Test',
        description: 'Testing JSON round trip',
        category: 'DML',
        content: 'SELECT * FROM {{tableName}};',
        variables: ['tableName', 'columnName'],
        isBuiltIn: true,
        usageCount: 42,
      );

      // Serialize to JSON
      final json = original.toJson();

      // Deserialize from JSON
      final reconstructed = CodeSnippet.fromJson(json);

      // Verify all fields match
      expect(reconstructed.id, original.id);
      expect(reconstructed.name, original.name);
      expect(reconstructed.description, original.description);
      expect(reconstructed.category, original.category);
      expect(reconstructed.content, original.content);
      expect(reconstructed.variables, original.variables);
      expect(reconstructed.isBuiltIn, original.isBuiltIn);
      expect(reconstructed.usageCount, original.usageCount);
      expect(reconstructed.createdAt, original.createdAt);
      expect(reconstructed.updatedAt, original.updatedAt);
      expect(reconstructed.lastUsedAt, original.lastUsedAt);
    });

    // 020-mongo US3 — databaseFamily
    test('databaseFamily defaults to all and round-trips (US3)', () {
      final snippet = CodeSnippet(
        id: 'fam-1',
        name: 'Fam',
        description: 'd',
        category: 'DML',
        content: 'SELECT 1',
        databaseFamily: SnippetDbFamily.mongodb,
      );
      expect(snippet.databaseFamily, SnippetDbFamily.mongodb);
      final json = snippet.toJson();
      expect(json['databaseFamily'], 'mongodb');
      expect(CodeSnippet.fromJson(json).databaseFamily, SnippetDbFamily.mongodb);
    });

    test('old JSON without databaseFamily defaults to all (US3 backward-compat)', () {
      final json = <String, dynamic>{
        'id': 'old-1',
        'name': 'Old',
        'description': 'd',
        'category': 'DML',
        'content': 'SELECT 1',
        'variables': <String>[],
        'isBuiltIn': false,
        'usageCount': 0,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      };
      expect(CodeSnippet.fromJson(json).databaseFamily, SnippetDbFamily.all);
    });
  });
}
