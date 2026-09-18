import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/code_snippet_service.dart';
import 'package:dbmaster/models/code_snippet.dart';

void main() {
  group('CodeSnippetService', () {
    late CodeSnippetService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = CodeSnippetService();
      await service.init();
    });

    test('should initialize with built-in snippets', () {
      final snippets = service.getAllSnippets();
      expect(snippets.length, greaterThan(0));
      expect(snippets.any((s) => s.isBuiltIn), true);
    });

    test('should have 28 built-in snippets', () {
      // 020-mongo US3 — added 8 Mongo built-ins (20 SQL + 8 Mongo = 28)
      final snippets = service.getAllSnippets();
      final builtInCount = snippets.where((s) => s.isBuiltIn).length;
      expect(builtInCount, 28);
    });

    test('Mongo built-ins tagged mongodb; SQL built-ins tagged sql (US3)', () {
      // 020-mongo US3
      final builtIns = service
          .getAllSnippets()
          .where((s) => s.isBuiltIn)
          .toList();
      final mongo = builtIns
          .where((s) => s.databaseFamily == SnippetDbFamily.mongodb)
          .toList();
      expect(mongo.length, 8);
      expect(mongo.any((s) => s.id == 'builtin-mongo-find'), isTrue);
      expect(mongo.every((s) => s.category.startsWith('Mongo')), isTrue);
      final sql = builtIns
          .where((s) => s.databaseFamily == SnippetDbFamily.sql)
          .toList();
      expect(sql.length, 20);
      // 没有内置片段留在 all 族（全部分类到 sql/mongodb）
      expect(
        builtIns.where((s) => s.databaseFamily == SnippetDbFamily.all).length,
        0,
      );
    });

    test('should get snippets by category', () {
      final dmlSnippets = service.getSnippetsByCategory('DML');
      expect(dmlSnippets.length, 8);
      expect(dmlSnippets.every((s) => s.category == 'DML'), true);
    });

    test('should search snippets by name', () {
      final results = service.searchSnippets('select');
      expect(results.length, greaterThan(0));
      expect(
        results.every(
          (s) =>
              s.name.toLowerCase().contains('select') ||
              s.description.toLowerCase().contains('select'),
        ),
        true,
      );
    });

    test('should get frequently used snippets', () {
      final frequent = service.getFrequentlyUsed(limit: 5);
      expect(frequent.length, lessThanOrEqualTo(5));
    });

    test('should increment usage count', () async {
      final snippets = service.getAllSnippets();
      final snippet = snippets.first;
      final originalCount = snippet.usageCount;

      final updated = await service.incrementUsage(snippet.id);

      expect(updated, isNotNull);
      expect(updated!.usageCount, originalCount + 1);
      expect(updated.lastUsedAt, isNotNull);
    });

    test('should add custom snippet', () async {
      final customSnippet = CodeSnippet(
        id: 'custom-1',
        name: 'My Snippet',
        description: 'Custom snippet',
        category: 'Custom',
        content: 'SELECT * FROM my_table;',
      );

      await service.addSnippet(customSnippet);

      final snippets = service.getAllSnippets();
      expect(snippets.any((s) => s.id == 'custom-1'), true);
    });

    test('should not exceed max custom snippets', () async {
      // Add 50 custom snippets
      for (var i = 0; i < 50; i++) {
        await service.addSnippet(
          CodeSnippet(
            id: 'custom-$i',
            name: 'Snippet $i',
            description: 'Test',
            category: 'Custom',
            content: 'SELECT $i',
          ),
        );
      }

      // 51st should fail
      expect(
        () async => await service.addSnippet(
          CodeSnippet(
            id: 'custom-51',
            name: 'Snippet 51',
            description: 'Test',
            category: 'Custom',
            content: 'SELECT 51',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('should reject empty snippet ID', () async {
      expect(
        () => service.addSnippet(
          CodeSnippet(
            id: '',
            name: 'Test',
            description: 'Test',
            category: 'Custom',
            content: 'SELECT 1',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should reject builtin- prefix for custom snippets', () async {
      expect(
        () => service.addSnippet(
          CodeSnippet(
            id: 'builtin-custom',
            name: 'Test',
            description: 'Test',
            category: 'Custom',
            content: 'SELECT 1',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should reject duplicate snippet ID', () async {
      await service.addSnippet(
        CodeSnippet(
          id: 'custom-1',
          name: 'Test',
          description: 'Test',
          category: 'Custom',
          content: 'SELECT 1',
        ),
      );

      expect(
        () => service.addSnippet(
          CodeSnippet(
            id: 'custom-1',
            name: 'Test 2',
            description: 'Test 2',
            category: 'Custom',
            content: 'SELECT 2',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should reject empty content', () async {
      expect(
        () => service.addSnippet(
          CodeSnippet(
            id: 'custom-1',
            name: 'Test',
            description: 'Test',
            category: 'Custom',
            content: '',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should reject content too long', () async {
      expect(
        () => service.addSnippet(
          CodeSnippet(
            id: 'custom-1',
            name: 'Test',
            description: 'Test',
            category: 'Custom',
            content: 'SELECT 1' * 2000, // More than 10000 chars
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'should throw ArgumentError when incrementing usage of non-existent snippet',
      () async {
        expect(
          () => service.incrementUsage('non-existent-id'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('should persist built-in usage across restarts', () async {
      // Use snippet
      final snippets = service.getAllSnippets();
      final snippet = snippets.firstWhere((s) => s.isBuiltIn);

      await service.incrementUsage(snippet.id);

      // Create new service instance (simulating restart)
      final newService = CodeSnippetService();
      await newService.init();

      // Verify usage count persisted
      final updatedSnippets = newService.getAllSnippets();
      final updatedSnippet = updatedSnippets.firstWhere(
        (s) => s.id == snippet.id,
      );
      expect(updatedSnippet.usageCount, greaterThan(0));
    });

    test('should throw StateError when updating built-in snippet', () async {
      final snippets = service.getAllSnippets();
      final builtIn = snippets.firstWhere((s) => s.isBuiltIn);

      expect(() => service.updateSnippet(builtIn), throwsA(isA<StateError>()));
    });

    test(
      'should throw ArgumentError when updating non-existent snippet',
      () async {
        expect(
          () => service.updateSnippet(
            CodeSnippet(
              id: 'non-existent',
              name: 'Test',
              description: 'Test',
              category: 'Custom',
              content: 'SELECT 1',
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('should throw StateError when removing built-in snippet', () async {
      final snippets = service.getAllSnippets();
      final builtIn = snippets.firstWhere((s) => s.isBuiltIn);

      expect(
        () => service.removeSnippet(builtIn.id),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'should throw ArgumentError when removing non-existent snippet',
      () async {
        expect(
          () => service.removeSnippet('non-existent-id'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
