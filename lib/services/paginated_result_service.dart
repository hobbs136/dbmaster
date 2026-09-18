class PaginatedResultService {
  static const int _defaultPageSize = 100;
  static const int _maxCachedPages = 3;

  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _currentPageData = [];
  final Map<int, List<Map<String, dynamic>>> _cachedPages = {};
  int _currentPage = 0;
  int _pageSize = _defaultPageSize;

  int get totalPages =>
      _allData.isEmpty ? 0 : (_allData.length / _pageSize).ceil();
  int get currentPage => _allData.isEmpty ? 0 : _currentPage + 1;
  int get totalRows => _allData.length;
  List<Map<String, dynamic>> get currentPageData => _currentPageData;

  void setData(List<Map<String, dynamic>> data) {
    _allData = data;
    _currentPage = 0;
    _cachedPages.clear();
    _loadPage();
  }

  void setPageSize(int size) {
    if (size > 0) {
      _pageSize = size;
      _currentPage = 0;
      _cachedPages.clear();
      if (_allData.isNotEmpty) {
        _loadPage();
      }
    }
  }

  void _loadPage() {
    if (_cachedPages.containsKey(_currentPage)) {
      _currentPageData = _cachedPages[_currentPage]!;
      return;
    }

    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _allData.length);
    _currentPageData = _allData.sublist(start, end);
    _cachedPages[_currentPage] = _currentPageData;

    // Clean up old cached pages
    if (_cachedPages.length > _maxCachedPages) {
      final pagesToRemove = _cachedPages.keys
          .where((page) => (page - _currentPage).abs() > 1)
          .toList();
      for (var page in pagesToRemove) {
        _cachedPages.remove(page);
      }
    }
  }

  void nextPage() {
    if (_currentPage < totalPages - 1) {
      _currentPage++;
      _loadPage();
    }
  }

  void previousPage() {
    if (_currentPage > 0) {
      _currentPage--;
      _loadPage();
    }
  }

  void goToPage(int page) {
    if (page >= 1 && page <= totalPages) {
      _currentPage = page - 1;
      _loadPage();
    }
  }

  bool get hasNextPage => _currentPage < totalPages - 1;
  bool get hasPreviousPage => _currentPage > 0;

  void clear() {
    _allData = [];
    _currentPageData = [];
    _cachedPages.clear();
    _currentPage = 0;
  }
}
