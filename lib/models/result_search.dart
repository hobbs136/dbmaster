class SearchResult {
  final int rowIndex;
  final String columnName;
  final String matchedText;
  final int startIndex;
  final int endIndex;

  const SearchResult({
    required this.rowIndex,
    required this.columnName,
    required this.matchedText,
    required this.startIndex,
    required this.endIndex,
  });

  String get cellKey => '${rowIndex}_$columnName';
}

class ResultSearchService {
  String _searchText = '';
  bool _useRegex = false;
  bool _caseSensitive = false;
  List<SearchResult> _results = [];
  int _currentIndex = -1;

  String get searchText => _searchText;
  bool get useRegex => _useRegex;
  bool get caseSensitive => _caseSensitive;
  List<SearchResult> get results => _results;
  int get currentIndex => _currentIndex;
  int get resultCount => _results.length;
  bool get hasResults => _results.isNotEmpty;
  SearchResult? get currentResult =>
      _currentIndex >= 0 && _currentIndex < _results.length
      ? _results[_currentIndex]
      : null;

  void setSearchText(String text) {
    _searchText = text;
    _results = [];
    _currentIndex = -1;
  }

  void toggleRegex() {
    _useRegex = !_useRegex;
  }

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
  }

  void setRegex(bool value) {
    _useRegex = value;
  }

  void setCaseSensitive(bool value) {
    _caseSensitive = value;
  }

  void search(List<Map<String, dynamic>> data, List<String> columns) {
    _results = [];
    _currentIndex = -1;

    if (_searchText.isEmpty || data.isEmpty || columns.isEmpty) {
      return;
    }

    RegExp? regex;
    if (_useRegex) {
      try {
        regex = RegExp(_searchText, caseSensitive: _caseSensitive);
      } catch (e) {
        return;
      }
    }

    for (var i = 0; i < data.length; i++) {
      final row = data[i];
      for (var col in columns) {
        final value = row[col];
        if (value == null) continue;

        final strValue = value.toString();
        final matches = _findMatches(strValue, regex);
        for (var match in matches) {
          _results.add(
            SearchResult(
              rowIndex: i,
              columnName: col,
              matchedText: strValue.substring(match[0], match[1]),
              startIndex: match[0],
              endIndex: match[1],
            ),
          );
        }
      }
    }

    if (_results.isNotEmpty) {
      _currentIndex = 0;
    }
  }

  List<List<int>> _findMatches(String text, RegExp? regex) {
    final matches = <List<int>>[];

    if (regex != null) {
      for (var match in regex.allMatches(text)) {
        matches.add([match.start, match.end]);
      }
    } else {
      final searchText = _caseSensitive
          ? _searchText
          : _searchText.toLowerCase();
      final searchTextLower = _caseSensitive ? text : text.toLowerCase();

      int index = 0;
      while (true) {
        final foundIndex = searchTextLower.indexOf(searchText, index);
        if (foundIndex == -1) break;
        matches.add([foundIndex, foundIndex + searchText.length]);
        index = foundIndex + 1;
      }
    }

    return matches;
  }

  SearchResult? nextResult() {
    if (_results.isEmpty) return null;
    _currentIndex = (_currentIndex + 1) % _results.length;
    return currentResult;
  }

  SearchResult? previousResult() {
    if (_results.isEmpty) return null;
    _currentIndex = (_currentIndex - 1 + _results.length) % _results.length;
    return currentResult;
  }

  void goToResult(int index) {
    if (index >= 0 && index < _results.length) {
      _currentIndex = index;
    }
  }

  void clear() {
    _searchText = '';
    _results = [];
    _currentIndex = -1;
  }

  bool isCurrentResult(int rowIndex, String columnName) {
    if (!hasResults) return false;
    final current = currentResult;
    return current?.rowIndex == rowIndex && current?.columnName == columnName;
  }

  bool hasMatchInCell(int rowIndex, String columnName) {
    return _results.any(
      (r) => r.rowIndex == rowIndex && r.columnName == columnName,
    );
  }

  List<SearchResult> getResultsForCell(int rowIndex, String columnName) {
    return _results
        .where((r) => r.rowIndex == rowIndex && r.columnName == columnName)
        .toList();
  }
}
