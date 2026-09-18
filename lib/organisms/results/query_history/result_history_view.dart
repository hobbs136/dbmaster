import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/query_history.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/query_history_provider.dart';
import 'result_history_empty.dart';
import 'result_history_header.dart';
import 'result_history_pagination.dart';
import 'result_history_table.dart';

/// Default number of history records shown per page.
const int _kDefaultPageSize = 50;

/// Per-tab history view state so switching tabs preserves each tab's search/page.
class _HistoryViewState {
  String searchQuery;
  int currentPage;

  _HistoryViewState({this.searchQuery = '', this.currentPage = 1});
}

/// History view displayed inside the result panel.
///
/// Shows the query history scoped to the active tab's connection. Supports
/// search, pagination, double-click to reuse, and delete/clear actions.
class ResultHistoryView extends StatefulWidget {
  final String tabId;
  final String? connectionId;
  final ValueChanged<QueryHistory> onHistoryDoubleTapped;
  final ValueChanged<QueryHistory>? onHistoryTapped;

  const ResultHistoryView({
    super.key,
    required this.tabId,
    this.connectionId,
    required this.onHistoryDoubleTapped,
    this.onHistoryTapped,
  });

  @override
  State<ResultHistoryView> createState() => _ResultHistoryViewState();
}

class _ResultHistoryViewState extends State<ResultHistoryView> {
  static final Map<String, _HistoryViewState> _perTabState = {};

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _perTabState.putIfAbsent(widget.tabId, _HistoryViewState.new);
    final state = _perTabState[widget.tabId];
    _searchController.text = state?.searchQuery ?? '';
  }

  @override
  void didUpdateWidget(covariant ResultHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId) {
      _perTabState.putIfAbsent(widget.tabId, _HistoryViewState.new);
      _searchController.text = _perTabState[widget.tabId]?.searchQuery ?? '';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  _HistoryViewState get _state =>
      _perTabState.putIfAbsent(widget.tabId, _HistoryViewState.new);

  String get _searchQuery => _state.searchQuery;
  set _searchQuery(String value) => _state.searchQuery = value;

  int get _currentPage => _state.currentPage;
  set _currentPage(int value) => _state.currentPage = value;

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _currentPage = 1;
    });
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final connectionId =
        widget.connectionId ?? appProvider.connection.currentServer?.id;

    if (connectionId == null || connectionId.isEmpty) {
      return const ResultHistoryEmpty();
    }

    final historyProvider = appProvider.queryHistory;
    final allHistory = _filteredHistory(historyProvider, connectionId);
    final totalPages = (allHistory.length / _kDefaultPageSize).ceil();

    // Adjust current page when deletion reduces total pages below it.
    if (_currentPage > totalPages && totalPages > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentPage = totalPages;
          });
        }
      });
    }

    final pagedHistory = _pagedHistory(allHistory);

    if (allHistory.isEmpty) {
      return const ResultHistoryEmpty();
    }

    return Column(
      children: [
        ResultHistoryHeader(
          searchQuery: _searchQuery,
          onSearchChanged: _onSearchChanged,
          onClearAll: () =>
              _confirmClearAll(context, connectionId, historyProvider),
        ),
        Expanded(
          child: ResultHistoryTable(
            history: pagedHistory,
            onRowTap: (entry) => widget.onHistoryTapped?.call(entry),
            onRowDoubleTap: widget.onHistoryDoubleTapped,
            onRowDelete: (entry) => _confirmDelete(context, entry, historyProvider),
          ),
        ),
        ResultHistoryPagination(
          currentPage: _currentPage,
          totalPages: totalPages,
          onPageChanged: _onPageChanged,
        ),
      ],
    );
  }

  List<QueryHistory> _filteredHistory(
    QueryHistoryProvider provider,
    String connectionId,
  ) {
    return provider.searchQueryHistory(_searchQuery, connectionId: connectionId)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<QueryHistory> _pagedHistory(List<QueryHistory> history) {
    final start = (_currentPage - 1) * _kDefaultPageSize;
    if (start >= history.length) return [];
    final end = (start + _kDefaultPageSize).clamp(0, history.length);
    return history.sublist(start, end);
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    String connectionId,
    QueryHistoryProvider provider,
  ) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.queryHistoryClearAll),
        content: Text(l10n.queryHistoryConfirmClearAll),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.commonDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await provider.clearQueryHistoryByConnection(connectionId);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    QueryHistory item,
    QueryHistoryProvider provider,
  ) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.queryHistoryDelete),
        content: Text(l10n.queryHistoryConfirmDelete(item.displayTitle ?? item.sql)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.commonDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await provider.deleteQueryHistory(item.id);
    }
  }
}


