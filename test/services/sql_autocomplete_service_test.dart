import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_autocomplete_service.dart';
import 'package:dbmaster/services/database_service.dart';

void main() {
  group('SQLAutocompleteService - static keyword lookup', () {
    // NOTE: These tests only cover the static/stateless parts of the service.
    // The DatabaseService-dependent parts (table/column caching) require mock setup.

    test('SQLContext enum has expected values', () {
      expect(SQLContext.values.length, 10);
      expect(
        SQLContext.values,
        containsAll([
          SQLContext.none,
          SQLContext.select,
          SQLContext.from,
          SQLContext.where,
          SQLContext.join,
          SQLContext.joinOn,
          SQLContext.groupBy,
          SQLContext.orderBy,
          SQLContext.insert,
          SQLContext.update,
        ]),
      );
    });

    test('SuggestionType enum has expected values', () {
      // 020-mongo — added collection/field/method (now 9)
      expect(SuggestionType.values.length, 9);
      expect(
        SuggestionType.values,
        containsAll([
          SuggestionType.keyword,
          SuggestionType.table,
          SuggestionType.column,
          SuggestionType.function,
          SuggestionType.datatype,
          SuggestionType.operator,
          SuggestionType.collection,
          SuggestionType.field,
          SuggestionType.method,
        ]),
      );
    });

    test('Suggestion has correct fields', () {
      final s = Suggestion(
        text: 'SELECT',
        type: SuggestionType.keyword,
        detail: 'Retrieves data from a table',
        priority: 100,
      );
      expect(s.text, 'SELECT');
      expect(s.type, SuggestionType.keyword);
      expect(s.detail, 'Retrieves data from a table');
      expect(s.priority, 100);
    });

    test('Suggestion toString returns text', () {
      final s = Suggestion(text: 'FROM', type: SuggestionType.keyword);
      expect(s.toString(), 'FROM');
    });
  });

  group('SQLAutocompleteService - extractTableNamesFromSQL', () {
    late SQLAutocompleteService service;

    setUp(() {
      service = SQLAutocompleteService(DatabaseService());
    });

    test('extracts bare table names', () {
      final tables = service.extractTableNamesFromSQL(
        'SELECT * FROM addresses LIMIT 100;',
      );
      expect(tables, equals(['addresses']));
    });

    test('extracts backtick-quoted MySQL table names', () {
      final tables = service.extractTableNamesFromSQL(
        'SELECT * FROM `addresses` LIMIT 100;',
      );
      expect(tables, equals(['addresses']));
    });

    test('extracts double-quoted PostgreSQL/SQLite table names', () {
      final tables = service.extractTableNamesFromSQL(
        'SELECT * FROM "addresses" LIMIT 100;',
      );
      expect(tables, equals(['addresses']));
    });

    test('extracts table names with WHERE clause inserted before LIMIT', () {
      final tables = service.extractTableNamesFromSQL(
        'SELECT * FROM `addresses` where p LIMIT 100;',
      );
      expect(tables, equals(['addresses']));
    });

    test('extracts multiple tables from JOIN', () {
      final tables = service.extractTableNamesFromSQL(
        'SELECT * FROM `users` JOIN "orders" ON users.id = orders.user_id;',
      );
      expect(tables, equals(['users', 'orders']));
    });

    test('deduplicates repeated tables', () {
      final tables = service.extractTableNamesFromSQL(
        'SELECT * FROM `addresses` a JOIN `addresses` b ON a.id = b.parent_id;',
      );
      expect(tables, equals(['addresses']));
    });
  });

  group('SQLAutocompleteService - parseSQLContext', () {
    late SQLAutocompleteService service;

    setUp(() {
      service = SQLAutocompleteService(DatabaseService());
    });

    test('returns where context for quoted table with LIMIT after cursor', () {
      const sql = 'SELECT * FROM `addresses` where p LIMIT 100;';
      final context = service.parseSQLContext(sql, sql.indexOf('p') + 1);
      expect(context, equals(SQLContext.where));
    });

    test('returns where context for bare table without LIMIT', () {
      const sql = 'select * from addresses where p';
      final context = service.parseSQLContext(sql, sql.length);
      expect(context, equals(SQLContext.where));
    });
  });
}
