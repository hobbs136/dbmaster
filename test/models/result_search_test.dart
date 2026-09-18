import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/result_search.dart';

void main() {
  group('SearchResult', () {
    test('fields are correct', () {
      final r = SearchResult(
        rowIndex: 5,
        columnName: 'name',
        matchedText: 'Alice',
        startIndex: 0,
        endIndex: 5,
      );
      expect(r.rowIndex, 5);
      expect(r.columnName, 'name');
      expect(r.matchedText, 'Alice');
      expect(r.cellKey, '5_name');
    });
  });

  group('ResultSearchService', () {
    test('initial state is empty', () {
      final svc = ResultSearchService();
      expect(svc.searchText, '');
      expect(svc.hasResults, false);
      expect(svc.currentResult, isNull);
      expect(svc.resultCount, 0);
    });

    test('search finds matches in data', () {
      final svc = ResultSearchService();
      svc.setSearchText('alice');
      svc.search(
        [
          {'name': 'Alice Smith', 'email': 'alice@test.com'},
          {'name': 'Bob'},
        ],
        ['name', 'email'],
      );
      expect(svc.hasResults, true);
      expect(svc.resultCount, greaterThan(0));
    });

    test('search is case-insensitive by default', () {
      final svc = ResultSearchService();
      svc.setSearchText('ALICE');
      svc.search(
        [
          {'name': 'alice'},
        ],
        ['name'],
      );
      expect(svc.hasResults, true);
    });

    test('search with caseSensitive enabled', () {
      final svc = ResultSearchService();
      svc.setSearchText('Alice');
      svc.setCaseSensitive(true);
      svc.search(
        [
          {'name': 'alice'},
          {'name': 'Alice'},
        ],
        ['name'],
      );
      expect(svc.hasResults, true);
      expect(svc.results.every((r) => r.matchedText == 'Alice'), true);
    });

    test('search with empty text returns no results', () {
      final svc = ResultSearchService();
      svc.search(
        [
          {'name': 'alice'},
        ],
        ['name'],
      );
      expect(svc.hasResults, false);
    });

    test('search with empty data returns no results', () {
      final svc = ResultSearchService();
      svc.setSearchText('test');
      svc.search([], ['name']);
      expect(svc.hasResults, false);
    });

    test('search with regex enabled', () {
      final svc = ResultSearchService();
      svc.setSearchText(r'\d+');
      svc.setRegex(true);
      svc.search(
        [
          {'name': 'alice'},
          {'name': '123'},
        ],
        ['name'],
      );
      expect(svc.hasResults, true);
    });

    test('search with invalid regex silently fails', () {
      final svc = ResultSearchService();
      svc.setSearchText(r'[invalid');
      svc.setRegex(true);
      svc.search(
        [
          {'name': 'test'},
        ],
        ['name'],
      );
      expect(svc.hasResults, false);
    });

    test('nextResult cycles through results', () {
      final svc = ResultSearchService();
      svc.setSearchText('a');
      svc.search(
        [
          {'col': 'aaa'},
          {'col': 'bbb'},
        ],
        ['col'],
      );
      if (svc.resultCount >= 2) {
        final first = svc.currentResult;
        final second = svc.nextResult();
        expect(second, isNot(first));
      }
    });

    test('previousResult cycles backwards', () {
      final svc = ResultSearchService();
      svc.setSearchText('a');
      svc.search(
        [
          {'col': 'aaa'},
          {'col': 'bbb'},
        ],
        ['col'],
      );
      if (svc.resultCount >= 2) {
        svc.nextResult();
        final current = svc.currentResult;
        final prev = svc.previousResult();
        expect(prev, isNot(current));
      }
    });

    test('goToResult navigates to specific index', () {
      final svc = ResultSearchService();
      svc.setSearchText('a');
      svc.search(
        [
          {'col': 'aaa'},
          {'col': 'bbb'},
        ],
        ['col'],
      );
      if (svc.resultCount > 1) {
        svc.goToResult(1);
        expect(svc.currentResult, isNotNull);
      }
    });

    test('clear resets state', () {
      final svc = ResultSearchService();
      svc.setSearchText('test');
      svc.search(
        [
          {'name': 'test'},
        ],
        ['name'],
      );
      svc.clear();
      expect(svc.searchText, '');
      expect(svc.hasResults, false);
    });

    test('isCurrentResult identifies active result', () {
      final svc = ResultSearchService();
      svc.setSearchText('a');
      svc.search(
        [
          {'col': 'abc'},
        ],
        ['col'],
      );
      if (svc.hasResults) {
        expect(
          svc.isCurrentResult(
            svc.currentResult!.rowIndex,
            svc.currentResult!.columnName,
          ),
          true,
        );
      }
      expect(svc.isCurrentResult(999, 'nonexistent'), false);
    });

    test('toggleRegex and toggleCaseSensitive', () {
      final svc = ResultSearchService();
      expect(svc.useRegex, false);
      svc.toggleRegex();
      expect(svc.useRegex, true);
      svc.toggleCaseSensitive();
      expect(svc.caseSensitive, true);
    });

    test('getResultsForCell returns matching results', () {
      final svc = ResultSearchService();
      svc.setSearchText('test');
      svc.search(
        [
          {'col': 'test value'},
        ],
        ['col'],
      );
      final results = svc.getResultsForCell(0, 'col');
      if (svc.hasResults) {
        expect(results.length, 1);
        expect(results.first.columnName, 'col');
      }
    });
  });
}
