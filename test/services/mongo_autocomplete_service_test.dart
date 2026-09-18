import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/mongo_autocomplete_service.dart';
import 'package:dbmaster/services/sql_autocomplete_service.dart' show SuggestionType;

// US1 — Mongo autocomplete (collections/methods/$operators).
// DB-dependent paths (collection names) return gracefully empty without a
// connection (mirrors test/services/sql_autocomplete_service_test.dart convention).
void main() {
  late MongoAutocompleteService service;

  setUp(() {
    service = MongoAutocompleteService(DatabaseService());
  });

  group('MongoAutocompleteService - static tables', () {
    test('getMethods matches by prefix', () {
      final fi = service.getMethods('fi');
      expect(fi.any((s) => s.text == 'find'), isTrue);
      expect(fi.every((s) => s.text.startsWith('fi')), isTrue);
      expect(fi.any((s) => s.type == SuggestionType.method), isTrue);
    });

    test('getDollarOperators matches by dollar prefix', () {
      final g = service.getDollarOperators('\$g');
      expect(g.any((s) => s.text == '\$gte'), isTrue);
      expect(g.any((s) => s.text == '\$gt'), isTrue);
      expect(g.every((s) => s.text.startsWith('\$g')), isTrue);
      expect(g.any((s) => s.type == SuggestionType.operator), isTrue);
    });

    test('empty prefix returns full sets', () {
      expect(service.getMethods('').length, greaterThan(0));
      expect(service.getDollarOperators('').length, greaterThan(0));
    });
  });

  group('MongoAutocompleteService - context routing (no connection)', () {
    test('afterDbDot falls back to methods when no collection data', () async {
      final q = 'db.';
      final s = await service.getSuggestions(q, q.length);
      expect(s.any((x) => x.text == 'find'), isTrue);
    });

    test('afterCollectionDot suggests methods', () async {
      final q = 'db.users.';
      final s = await service.getSuggestions(q, q.length);
      expect(s.any((x) => x.text == 'find'), isTrue);
      expect(s.any((x) => x.text == 'aggregate'), isTrue);
      expect(s.any((x) => x.type == SuggestionType.method), isTrue);
    });

    test('afterDollar suggests dollar-operators', () async {
      final q = 'db.users.find({\$';
      final s = await service.getSuggestions(q, q.length);
      expect(s.any((x) => x.text == '\$gte'), isTrue);
      expect(s.any((x) => x.type == SuggestionType.operator), isTrue);
    });

    test('none context suggests methods + dollar-operators', () async {
      final s = await service.getSuggestions('', 0);
      expect(s.any((x) => x.text == 'find'), isTrue);
      expect(s.any((x) => x.text == '\$gte'), isTrue);
    });

    test('unparseable input does not throw', () async {
      await expectLater(service.getSuggestions('}}}}', 4), completes);
      final s = await service.getSuggestions('}}}}', 4);
      expect(s, isA<List>());
    });

    test('getCollectionNames returns empty when no connection', () async {
      expect(await service.getCollectionNames('us'), isEmpty);
    });
  });

  // 020-mongo US2 — 字段补全
  group('MongoAutocompleteService - field completion (US2)', () {
    test('buildFieldSuggestions maps sampled fields with coverage', () {
      final schema = <String, dynamic>{
        'collectionName': 'users',
        'totalSampled': 100,
        'fields': <String, dynamic>{
          'age': <String, dynamic>{'type': 'int', 'occurrence': 95},
          'name': <String, dynamic>{'type': 'String', 'occurrence': 50},
        },
      };
      final s = MongoAutocompleteService.buildFieldSuggestions(schema, '');
      expect(s.length, 2);
      final age = s.firstWhere((x) => x.text == 'age');
      expect(age.type, SuggestionType.field);
      expect(age.detail, contains('int'));
      expect(age.detail, contains('95%')); // 95/100
    });

    test('buildFieldSuggestions filters by prefix', () {
      final schema = <String, dynamic>{
        'totalSampled': 10,
        'fields': <String, dynamic>{
          'age': <String, dynamic>{'type': 'int', 'occurrence': 10},
          'name': <String, dynamic>{'type': 'String', 'occurrence': 10},
        },
      };
      final s = MongoAutocompleteService.buildFieldSuggestions(schema, 'ag');
      expect(s.length, 1);
      expect(s.single.text, 'age');
    });

    test('buildFieldSuggestions handles empty / zero-sampled schema', () {
      expect(
        MongoAutocompleteService.buildFieldSuggestions(<String, dynamic>{}, ''),
        isEmpty,
      );
      final schema = <String, dynamic>{
        'totalSampled': 0,
        'fields': <String, dynamic>{
          'x': <String, dynamic>{'type': 'int', 'occurrence': 0},
        },
      };
      final s = MongoAutocompleteService.buildFieldSuggestions(schema, '');
      expect(s.length, 1);
      expect(s.single.detail, contains('0%'));
    });

    test('getFieldNames returns empty when no collection / no connection', () async {
      expect(await service.getFieldNames('', collection: ''), isEmpty);
      expect(
        await service.getFieldNames('a', collection: 'users'),
        isEmpty,
      );
    });
  });
}
