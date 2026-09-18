import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/execution_result.dart';
import '../services/database_service.dart';
import '../services/readonly_guard.dart';
import '../services/multi_execution_service.dart';
import '../services/sql_parser_service.dart';
import '../services/pii_masker.dart';
import '../services/audit_log_service.dart';
import '../utils/app_logger.dart';
import '../models/database_models.dart' show DatabaseType;
// spec 041: per-tab 面板可见性 / FilterBar 状态值模型（不进 toJson、不持久化）
import '../models/panel_layout.dart';
import '../models/filter_condition.dart';
import '../models/dml_risk_models.dart';

// ============================================================================
// 异常类 & 数据模型
// ============================================================================

/// Exception thrown when attempting to close a tab with unsaved changes.
class UnsavedTabException implements Exception {
  final QueryTab tab;
  UnsavedTabException(this.tab);
}

/// Exception thrown when attempting to save a query with a duplicate name
/// under the same connection.
class DuplicateSavedQueryNameException implements Exception {
  final String title;
  final String? connectionId;

  DuplicateSavedQueryNameException(this.title, {this.connectionId});

  @override
  String toString() =>
      'Saved query name "$title" already exists for this connection';
}

/// 结果子标签类型
enum ResultSubTabType { result, error, history }

/// 查询结果子标签
///
/// 每次执行查询生成一个 Result N 子标签。
/// Pin 机制：固定子标签不被新结果覆盖。
class ResultSubTab {
  final String id;
  String label;
  final List<ExecutionResult> executionResults;
  bool isPinned;
  final String? errorMessage;
  final DateTime timestamp;
  final String? executedSql;
  final Duration? executionTime;
  final ResultSubTabType type;

  ResultSubTab({
    required this.id,
    required this.label,
    this.executionResults = const [],
    this.isPinned = false,
    this.errorMessage,
    DateTime? timestamp,
    this.executedSql,
    this.executionTime,
    this.type = ResultSubTabType.result,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
  bool get isHistory => type == ResultSubTabType.history;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'executionResults': executionResults.map((e) => e.toJson()).toList(),
    'isPinned': isPinned,
    'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
    'executedSql': executedSql,
    'executionTimeMs': executionTime?.inMilliseconds,
    'type': type.name,
  };

  factory ResultSubTab.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    final type = ResultSubTabType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ResultSubTabType.result,
    );
    return ResultSubTab(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      executionResults:
          (json['executionResults'] as List<dynamic>?)
              ?.map(
                (e) => ExecutionResult.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          [],
      isPinned: json['isPinned'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      executedSql: json['executedSql'] as String?,
      executionTime: json['executionTimeMs'] != null
          ? Duration(milliseconds: json['executionTimeMs'] as int)
          : null,
      type: type,
    );
  }
}

// ============================================================================
// TabProvider - 专注标签页和查询执行管理
// ============================================================================
///
/// 职责：标签页 CRUD、查询执行、保存查询、结果子标签管理
///
/// 每个 QueryTab 自带 connectionId + databaseName + sessionId（per-tab 隔离），
/// 不再需要 Workspace 层包裹。
class TabProvider extends ChangeNotifier {
  final DatabaseService _dbService;

  TabProvider(this._dbService);

  // ==================== 状态 ====================

  final List<QueryTab> _tabs = [];
  int _activeTabIndex = 0;
  int _queryCounter = 1;
  List<QueryTab> _savedQueries = [];

  // 命令面板操作标志
  bool _formatRequested = false;
  bool _executeRequested = false;

  String? _errorMessage;

  // ==================== Result 子标签状态 ====================

  /// 每个 Tab 的结果子标签列表，key = tabId
  final Map<String, List<ResultSubTab>> _tabResults = {};

  /// 每个 Tab 当前活跃的结果子标签索引，key = tabId
  final Map<String, int> _tabActiveResultIndex = {};

  // C22 M2 走查反馈二轮：语句层并入子标签层后内层索引机制
  // （_tabActiveInnerResultIndex 全套）移除——每个子标签恰一条结果，
  // 无内层切换语义。

  // ==================== Panel 布局状态（spec 041 三面板状态机）====================
  // 与 _tabResults/_tabActiveResultIndex 同构：per-tab 会话内、不进 QueryTab.toJson、不持久化。
  final Map<String, PanelLayout> _tabPanelLayout = {};
  final Map<String, String> _tabBrowseTarget = {};
  final Map<String, List<FilterCondition>> _tabFilterConditions = {};
  final Map<String, FilterCombinator> _tabFilterCombinator = {};

  /// 某 tab 的面板可见性（默认 query 预设）。纯读，无 putIfAbsent（规避 build 期写状态）。
  PanelLayout panelLayoutFor(String tabId) =>
      _tabPanelLayout[tabId] ?? PanelLayout.query;

  /// 某 tab 的 FilterBar 目标表/视图名（qualified）。普通 query tab 返回 null。
  String? browseTargetFor(String tabId) => _tabBrowseTarget[tabId];

  /// 某 tab 的筛选条件（unmodifiable，默认空）。
  List<FilterCondition> filterConditionsFor(String tabId) => List.unmodifiable(
    _tabFilterConditions[tabId] ?? const <FilterCondition>[],
  );

  /// 某 tab 的筛选组合器（默认 and）。
  FilterCombinator filterCombinatorFor(String tabId) =>
      _tabFilterCombinator[tabId] ?? FilterCombinator.and;

  /// active tab 的面板可见性。
  PanelLayout get activePanelLayout => panelLayoutFor(activeTab?.id ?? '');

  /// active tab 是否支持 FilterBar（SQL 系 6 种，单一真值源 `DatabaseType.isSqlLike`）。
  bool get activeSupportsFilterBar =>
      activeTab?.databaseType?.isSqlLike ?? false;

  /// 设置某 tab 的完整布局。
  void setPanelLayout(String tabId, PanelLayout layout) {
    _tabPanelLayout[tabId] = layout;
    notifyListeners();
  }

  /// 翻转单个面板可见位（copyWith 后写回）。
  void updatePanelLayout(
    String tabId, {
    bool? editor,
    bool? filterBar,
    bool? results,
  }) {
    _tabPanelLayout[tabId] = panelLayoutFor(tabId).copyWith(
      editorVisible: editor,
      filterBarVisible: filterBar,
      resultsVisible: results,
    );
    notifyListeners();
  }

  /// 设置/清除 FilterBar 目标表（null = 清除）。
  void setBrowseTarget(String tabId, String? qualifiedTableName) {
    if (qualifiedTableName == null) {
      _tabBrowseTarget.remove(tabId);
    } else {
      _tabBrowseTarget[tabId] = qualifiedTableName;
    }
    notifyListeners();
  }

  void setFilterConditions(String tabId, List<FilterCondition> conditions) {
    _tabFilterConditions[tabId] = List<FilterCondition>.from(conditions);
    notifyListeners();
  }

  void setFilterCombinator(String tabId, FilterCombinator combinator) {
    _tabFilterCombinator[tabId] = combinator;
    notifyListeners();
  }

  /// 任何 result-write（成功/错误）后确保 results 面板可见（spec 041 FR-009）。
  /// 由 addResultToTab / addErrorMessageToTab 在末尾 notify 前调用，复用同一次 notify。
  /// 任意成功 result-write（含返回 0 行的空结果集）都翻 resultsVisible=true。
  void _ensureResultsVisible(String tabId) {
    final current = _tabPanelLayout[tabId];
    if (current == null) {
      _tabPanelLayout[tabId] = PanelLayout.query.copyWith(resultsVisible: true);
    } else if (!current.resultsVisible) {
      _tabPanelLayout[tabId] = current.copyWith(resultsVisible: true);
    }
  }

  // ==================== Getters ====================

  List<QueryTab> get tabs => List.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  bool get formatRequested => _formatRequested;
  bool get executeRequested => _executeRequested;
  String? get errorMessage => _errorMessage;
  List<QueryTab> get savedQueries => List.unmodifiable(_savedQueries);

  /// 获取属于指定连接和数据库的保存查询
  List<QueryTab> savedQueriesFor(String connectionId, String? databaseName) {
    return _savedQueries
        .where(
          (q) =>
              q.connectionId == connectionId && q.databaseName == databaseName,
        )
        .toList();
  }

  /// 获取属于指定连接的所有保存查询（跨数据库）
  List<QueryTab> savedQueriesForConnection(String connectionId) {
    return _savedQueries.where((q) => q.connectionId == connectionId).toList();
  }

  /// 根据 ID 获取保存的查询
  QueryTab? getSavedQueryById(String queryId) {
    try {
      return _savedQueries.firstWhere((q) => q.id == queryId);
    } catch (_) {
      return null;
    }
  }

  QueryTab? get activeTab => _tabs.isNotEmpty && _activeTabIndex < _tabs.length
      ? _tabs[_activeTabIndex]
      : null;

  /// 获取指定 Tab 的结果子标签列表
  List<ResultSubTab> getResultsForTab(String tabId) {
    return _tabResults.putIfAbsent(tabId, () => []);
  }

  /// 获取指定 Tab 当前活跃的结果子标签索引
  int getActiveResultIndexForTab(String tabId) {
    return _tabActiveResultIndex[tabId] ?? 0;
  }

  /// 便捷：获取 active tab 的结果子标签
  List<ResultSubTab> get activeResults {
    final tab = activeTab;
    if (tab == null) return [];
    return getResultsForTab(tab.id);
  }

  /// 便捷：获取 active tab 的活跃结果索引
  int get activeResultIndex {
    final tab = activeTab;
    if (tab == null) return 0;
    return getActiveResultIndexForTab(tab.id);
  }

  /// active tab 当前活跃的 ResultSubTab（可能为 null）。
  ///
  /// 直接读 [_tabResults]（而非 [activeResults]）以避免 putIfAbsent 的副作用。
  ResultSubTab? get activeResultSubTab {
    final tab = activeTab;
    if (tab == null) return null;
    final results = _tabResults[tab.id];
    if (results == null || results.isEmpty) return null;
    final idx = _tabActiveResultIndex[tab.id] ?? 0;
    if (idx < 0 || idx >= results.length) return null;
    return results[idx];
  }

  // ==================== 错误处理 ====================

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ==================== 标签页操作 ====================

  void addTab(QueryTab tab) {
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    notifyListeners();
  }

  /// [bindContext] 是否将上下文标记为用户显式绑定（绑定后侧边栏导航
  /// 不再覆写，见 [QueryTab.isContextBound]）。「+」新建的空白 tab 传
  /// false（跟随侧边栏）；携带显式上下文的调用方（如 openSavedQuery）传 true。
  Future<void> addNewTab({
    String? connectionId,
    String? databaseName,
    bool bindContext = false,
  }) async {
    // 捕获当前连接类型，确保 Tab 记住自己的数据库类型
    final currentServer = _dbService.currentServer;
    final tab = QueryTab(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      title: 'Query $_queryCounter',
      connectionId: connectionId,
      databaseName: databaseName,
      databaseType: currentServer?.type,
      isAutoTitle: true,
      isContextBound: bindContext,
    );

    _queryCounter++;
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    ensureHistorySubTab(tab.id);
  }

  /// 打开新 Query Tab（改造后的主要入口）
  ///
  /// 每个 Tab 独立管理数据库上下文：
  /// - MySQL/Doris: 为 Tab 创建独立 session，设置初始 USE database
  /// - 其他数据库: Tab 自带 connectionId + databaseName
  ///
  /// [connectionId] 数据库连接 ID
  /// [databaseName] 初始数据库名
  /// [sql] 可选的初始 SQL 内容
  /// [bindContext] 是否标记上下文为用户显式绑定（默认 true——本入口的
  /// 调用方均携带显式上下文：双击表/AI 面板/快速搜索等；侧边栏导航随后
  /// 不得覆写，见 [QueryTab.isContextBound]）。
  Future<QueryTab> openQueryTab({
    required String connectionId,
    required String databaseName,
    String? sql,
    String? title,
    String? savedQueryId,
    bool bindContext = true,
  }) async {
    final dbType = _dbService.getDatabaseType(connectionId);

    // 已保存查询：若已打开则直接激活现有 Tab
    if (savedQueryId != null && savedQueryId.isNotEmpty) {
      final existingIndex = _tabs.indexWhere(
        (t) => t.savedQueryId == savedQueryId,
      );
      if (existingIndex >= 0) {
        _activeTabIndex = existingIndex;
        notifyListeners();
        return _tabs[existingIndex];
      }
    }

    final tabId = '${DateTime.now().millisecondsSinceEpoch}';

    final isSavedQuery = savedQueryId != null && savedQueryId.isNotEmpty;
    final effectiveSql = sql ?? '';
    final tab = QueryTab(
      id: tabId,
      savedQueryId: savedQueryId,
      title: title ?? 'Query $_queryCounter',
      connectionId: connectionId,
      databaseName: databaseName,
      databaseType: dbType,
      sql: effectiveSql,
      isSaved: isSavedQuery,
      isModified: false,
      originalSql: isSavedQuery ? effectiveSql : null,
      isAutoTitle: title == null,
      isContextBound: bindContext,
    );

    if (title == null) {
      _queryCounter++;
    }
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    ensureHistorySubTab(tab.id);

    return tab;
  }

  void renameTab(int index, String newTitle) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].title = newTitle;
      _tabs[index].isAutoTitle = false;
      notifyListeners();
    }
  }

  /// 判断给定 Tab 是否包含未保存的修改。
  ///
  /// - 新建（未保存）标签：非空内容即视为未保存；
  /// - 已保存查询标签：以显式的 isModified 状态为准。
  static bool isTabUnsaved(QueryTab tab) {
    return (!tab.isSaved && tab.sql.trim().isNotEmpty) ||
        (tab.isSaved && tab.isModified);
  }

  /// 关闭 Tab（含未保存检查）
  ///
  /// 如果 Tab 有未保存的修改，抛出 [UnsavedTabException]。
  /// 调用方应捕获此异常并显示确认对话框，确认后调用 [forceCloseTab]。
  Future<void> closeTab(int index) async {
    if (index >= 0 && index < _tabs.length) {
      final tab = _tabs[index];

      if (isTabUnsaved(tab)) {
        throw UnsavedTabException(tab);
      }

      await _doCloseTab(index, tab);
    }
  }

  /// 强制关闭 Tab（跳过未保存检查）
  Future<void> forceCloseTab(int index) async {
    if (index >= 0 && index < _tabs.length) {
      final tab = _tabs[index];
      await _doCloseTab(index, tab);
    }
  }

  /// 内部关闭逻辑：清理结果缓存（T29：MySQL 族 tab session 随网关壳下线，
  /// 无 session 资源可释放）
  Future<void> _doCloseTab(int index, QueryTab tab) async {
    // 清理结果子标签缓存
    _tabResults.remove(tab.id);
    _tabActiveResultIndex.remove(tab.id);
    // spec 041: 清理 per-tab 布局/FilterBar 会话态（防内存泄漏，与 _tabResults 同构）
    _tabPanelLayout.remove(tab.id);
    _tabBrowseTarget.remove(tab.id);
    _tabFilterConditions.remove(tab.id);
    _tabFilterCombinator.remove(tab.id);

    _tabs.removeAt(index);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    if (_activeTabIndex < 0) _activeTabIndex = 0;
    notifyListeners();
  }

  void setActiveTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      _activeTabIndex = index;
      notifyListeners();
    }
  }

  /// U16 崩溃恢复：批量还原标签页（来自 TabSessionStore，调用方已过滤失效
  /// 连接）。不建 MySQL/Doris tab session——连接尚未就绪，执行时按需退化
  /// 默认会话（恢复的 tab sessionId 恒为 null）。activeIndex 越界收缩。
  void restoreTabs(List<QueryTab> restored, int activeIndex) {
    if (restored.isEmpty) return;
    _tabs.addAll(restored);
    _activeTabIndex = activeIndex.clamp(0, _tabs.length - 1);
    notifyListeners();
  }

  void updateTabSql(int index, String sql) {
    if (index >= 0 && index < _tabs.length) {
      final tab = _tabs[index];
      tab.sql = sql;
      if (tab.isSaved && tab.originalSql != null) {
        tab.isModified = tab.sql != tab.originalSql;
      }
      notifyListeners();
    }
  }

  void updateTabExecutionResults(int index, List<ExecutionResult> results) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].executionResults = results;
      notifyListeners();
    }
  }

  void updateTabConnection(int index, String? connectionId) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].connectionId = connectionId;
      notifyListeners();
    }
  }

  void updateTabDatabase(int index, String? databaseName) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].databaseName = databaseName;
      notifyListeners();
    }
  }

  void updateTabDatabaseType(int index, DatabaseType? databaseType) {
    if (index >= 0 && index < _tabs.length) {
      _tabs[index].databaseType = databaseType;
      notifyListeners();
    }
  }

  /// 将 tab 上下文标记为用户显式绑定（工具栏下拉选连接/选库等显式动作
  /// 后调用——此后侧边栏导航不再覆写该 tab 上下文，见
  /// [QueryTab.isContextBound]）。
  void bindTabContext(int index) {
    if (index >= 0 && index < _tabs.length) {
      if (_tabs[index].isContextBound) return;
      _tabs[index].isContextBound = true;
      notifyListeners();
    }
  }

  Future<void> closeAllTabs() async {
    _tabResults.clear();
    _tabActiveResultIndex.clear();
    // spec 041: 清理 per-tab 布局/FilterBar 会话态
    _tabPanelLayout.clear();
    _tabBrowseTarget.clear();
    _tabFilterConditions.clear();
    _tabFilterCombinator.clear();
    _tabs.clear();
    _activeTabIndex = 0;
    notifyListeners();
  }

  /// 关闭指定连接下的所有 Tab（强制，跳过未保存检查）
  Future<void> closeTabsForConnection(String connectionId) async {
    final indicesToClose = <int>[];
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].connectionId == connectionId) {
        indicesToClose.add(i);
      }
    }
    // 从后往前关闭，避免索引变化
    for (int i = indicesToClose.length - 1; i >= 0; i--) {
      await forceCloseTab(indicesToClose[i]);
    }
  }

  void reopenTab(QueryTab tab) {
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    ensureHistorySubTab(tab.id);
  }

  // ==================== 查询执行 ====================

  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    try {
      final results = await _dbService.executeQuery(
        sql,
        connectionId: connectionId,
        database: database,
        sessionId: sessionId,
        skipDdlAnalysis: skipDdlAnalysis,
      );

      // Apply PII masking to SELECT query results
      final isSelect = sql.trim().toUpperCase().startsWith('SELECT');
      if (isSelect && results.isNotEmpty) {
        return PIIMasker().maskRows(results);
      }

      return results;
    } on DdlConfirmationRequiredException {
      rethrow;
    } catch (e) {
      // 错误不再弹窗，由调用方通过 addErrorMessageToTab 在结果面板中显示
      rethrow;
    }
  }

  Future<List<ExecutionResult>> executeCurrentQuery({
    String? overrideSql,
    String? connectionId,
    String? databaseName,
    String? sessionId,
    bool skipDdlAnalysis = false,
    void Function(int current, int total)? onStatementProgress,
  }) async {
    final tab = activeTab;
    final sqlToExecute = overrideSql ?? tab?.sql ?? '';
    AppLogger.d(
      'TabProvider',
      '[TabProvider] executeCurrentQuery: sqlToExecute=${AppLogger.sqlPreview(sqlToExecute)}, globalActiveTab=${tab?.id}, connectionId=$connectionId, databaseName=$databaseName, sessionId=$sessionId',
    );
    if (sqlToExecute.isEmpty) {
      throw Exception('没有可执行的查询');
    }

    // 优先使用显式传入的上下文，否则从当前 Tab 取
    final cid = connectionId ?? tab?.connectionId;
    final db = databaseName ?? tab?.databaseName;
    final sid = sessionId ?? tab?.sessionId;
    AppLogger.d(
      'TabProvider',
      '[TabProvider] executeCurrentQuery: resolved cid=$cid, db=$db, sid=$sid',
    );

    final statements = SQLParserService.split(sqlToExecute);
    final auditLog = AuditLogService();
    await auditLog.initialize();

    if (statements.length == 1) {
      // 单语句执行
      final startTime = DateTime.now();
      try {
        final data = await executeQuery(
          sqlToExecute,
          connectionId: cid,
          database: db,
          sessionId: sid,
          skipDdlAnalysis: skipDdlAnalysis,
        );
        final executionTime = DateTime.now().difference(startTime);

        // 记录审计日志
        auditLog.recordQuery(
          connectionId: cid ?? 'unknown',
          databaseName: db,
          sql: sqlToExecute,
          executionTime: executionTime,
          rowCount: data.length,
          success: true,
          isWriteQuery: _isWriteQuery(sqlToExecute),
        );

        return [
          ExecutionResult(
            statement: statements.first,
            success: true,
            data: data,
            executionTime: executionTime,
            isTruncated: _dbService.lastQueryWasTruncated,
            limitValue: _dbService.lastQueryLimitValue,
            columnTypes: _dbService.lastColumnTypes,
            truncatedColumns: _dbService.lastTruncatedColumns,
            dataShape: _dbService.lastDataShape,
          ),
        ];
      } on DdlConfirmationRequiredException {
        rethrow;
      } on DmlConfirmationRequiredException {
        rethrow;
      } on DmlWarningRequiredException {
        rethrow;
      } on ReadOnlyBlockedException {
        rethrow;
      } catch (e) {
        final executionTime = DateTime.now().difference(startTime);

        // 记录审计日志
        auditLog.recordQuery(
          connectionId: cid ?? 'unknown',
          databaseName: db,
          sql: sqlToExecute,
          executionTime: executionTime,
          success: false,
          errorMessage: e.toString(),
          isWriteQuery: _isWriteQuery(sqlToExecute),
        );

        return [
          ExecutionResult(
            statement: statements.first,
            success: false,
            errorMessage: e.toString(),
            executionTime: executionTime,
          ),
        ];
      }
    } else {
      // 多语句执行
      final service = MultiExecutionService(
        _dbService,
        connectionId: cid,
        database: db,
        sessionId: sid,
      );
      final results = await service.execute(
        statements,
        skipDdlAnalysis: skipDdlAnalysis,
        onProgress: onStatementProgress == null
            ? null
            : (p) => onStatementProgress(p.currentIndex, p.totalCount),
      );
      service.dispose();

      // 为每个语句记录审计日志
      for (final result in results) {
        auditLog.recordQuery(
          connectionId: cid ?? 'unknown',
          databaseName: db,
          sql: result.statement.sql,
          executionTime: result.executionTime,
          rowCount: result.data?.length ?? result.affectedRows,
          success: result.success,
          errorMessage: result.errorMessage,
          isWriteQuery: _isWriteQuery(result.statement.sql),
        );
      }

      return results;
    }
  }

  /// 审计日志的写语句判定。startsWith 覆盖常规形态；\b 正则覆盖 CTE
  /// （WITH ... INSERT）/ 前置注释等不以关键字开头的写语句（U17——此前
  /// 仅 startsWith，这类语句在审计里被记为读）。
  static const List<String> _sqlWriteKeywords = [
    'INSERT',
    'UPDATE',
    'DELETE',
    'CREATE',
    'ALTER',
    'DROP',
    'TRUNCATE',
    'REPLACE',
  ];

  bool _isWriteQuery(String sql) {
    final trimmed = sql.trim();
    // 020-mongo US4 — Mongo 写操作检测（基于 db.coll.method 文本，无需 dbType）
    if (trimmed.startsWith('db.')) {
      return isMongoWriteQuery(trimmed);
    }
    return isSqlWriteStatement(trimmed);
  }

  /// 纯 SQL 写语句判定（无 Mongo 分支，供测试与其它调用方复用）。
  static bool isSqlWriteStatement(String sql) {
    final upper = sql.trim().toUpperCase();
    for (final keyword in _sqlWriteKeywords) {
      if (upper.startsWith(keyword) ||
          RegExp(r'\b' + keyword + r'\b').hasMatch(upper)) {
        return true;
      }
    }
    return false;
  }

  /// Mongo 写操作方法集合（US4）。aggregate 单独判定（含 $out/$merge 才算写）。
  static const Set<String> mongoWriteMethods = {
    'insertone',
    'insertmany',
    'updateone',
    'updatemany',
    'replaceone',
    'deleteone',
    'deletemany',
    'findoneandupdate',
    'findoneandreplace',
    'findoneanddelete',
  };

  /// 判定 Mongo shell 语句是否为写操作（US4）。
  /// 基于 `db.<coll>.<method>(...)` 文本提取方法名，无需 dbType；非 Mongo 语句返回 false。
  static bool isMongoWriteQuery(String sql) {
    final match = RegExp(r'db\.[A-Za-z0-9_]+\.([A-Za-z0-9_]+)').firstMatch(sql);
    if (match == null) return false;
    final method = match.group(1)!.toLowerCase();
    if (mongoWriteMethods.contains(method)) return true;
    if (method == 'aggregate') {
      return sql.contains('\$out') || sql.contains('\$merge');
    }
    return false;
  }

  Future<bool> cancelQuery({String? connectionId}) async {
    final tab = activeTab;
    final trackingKey = tab?.sessionId ?? (connectionId ?? tab?.connectionId);
    if (trackingKey == null) return false;
    return await _dbService.cancelQuery(trackingKey);
  }

  // ==================== Result 子标签管理 ====================

  /// 从 SQL 注释中提取结果标签名（支持 `// NAME: custom_name` 语法）
  static String? _extractResultName(String sql) {
    final regex = RegExp(r'^\s*//\s*NAME\s*:\s*(.+)$', multiLine: true);
    final match = regex.firstMatch(sql);
    return match?.group(1)?.trim();
  }

  /// 生成结果标签名
  String _generateResultLabel(List<ResultSubTab> resultList) {
    return 'Result ${resultList.length + 1}';
  }

  /// 执行查询后将结果添加到 Tab 的结果子标签中
  ///
  /// C22 M2 走查反馈二轮（2026-08-22）：语句层并入子标签层——一次执行
  /// N 条语句**扇出 N 个 Result 子标签**（沿用既有命名），每个子标签恰
  /// 一条 ExecutionResult；结果面板不再有语句内层 tab。
  ///
  /// 替换语义（沿用「一个 query 只有一个 result 批次」）：**整批替换
  /// 所有未 Pin 的 result 子标签**（History 是 pinned 不受影响；Pin 住
  /// 的旧结果保留，pin 粒度细化到单条语句）。单语句 + Name 注解仍用
  /// 注解命名。
  void addResultToTab(
    String tabId,
    List<ExecutionResult> results, {
    required String sql,
    required Duration executionTime,
  }) {
    final resultList = _tabResults.putIfAbsent(tabId, () => []);

    final customName = results.length == 1 ? _extractResultName(sql) : null;
    final replaceIndex = resultList.indexWhere((r) => !r.isPinned);
    final insertAt = replaceIndex >= 0 ? replaceIndex : resultList.length;
    // 复用被替换子标签的 id（保持首条 id 稳定，沿旧替换路径行为）。
    final firstId = replaceIndex >= 0
        ? resultList[replaceIndex].id
        : '${DateTime.now().millisecondsSinceEpoch}';
    final batchTime = DateTime.now().millisecondsSinceEpoch;
    resultList.removeWhere((r) => !r.isPinned);

    for (var i = 0; i < results.length; i++) {
      resultList.insert(
        insertAt + i,
        ResultSubTab(
          id: i == 0 ? firstId : '${batchTime}_$i',
          label: customName ?? _generateResultLabel(resultList),
          executionResults: [results[i]],
          executedSql: results[i].statement.sql,
          executionTime: results[i].executionTime,
          timestamp: DateTime.now(),
        ),
      );
    }
    _tabActiveResultIndex[tabId] = insertAt;

    _ensureResultsVisible(tabId); // spec 041 FR-009: result-write 后显 results
    notifyListeners();
  }

  /// 将错误信息作为新的错误结果标签（红色标识）
  void addErrorMessageToTab(String tabId, String error, {String? sql}) {
    final resultList = _tabResults.putIfAbsent(tabId, () => []);
    final newIdx = resultList.length;
    resultList.add(
      ResultSubTab(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        label: 'Error',
        errorMessage: error,
        executedSql: sql,
        timestamp: DateTime.now(),
      ),
    );
    _tabActiveResultIndex[tabId] = newIdx;
    _ensureResultsVisible(tabId); // spec 041 FR-009: 错误 result-write 后显 results
    notifyListeners();
  }

  /// Pin 一个结果子标签（固定后不会被新结果覆盖）
  void pinResult(String tabId, int resultIndex) {
    final resultList = _tabResults[tabId];
    if (resultList != null &&
        resultIndex >= 0 &&
        resultIndex < resultList.length) {
      resultList[resultIndex].isPinned = true;
      notifyListeners();
    }
  }

  /// 取消 Pin 一个结果子标签
  void unpinResult(String tabId, int resultIndex) {
    final resultList = _tabResults[tabId];
    if (resultList != null &&
        resultIndex >= 0 &&
        resultIndex < resultList.length) {
      resultList[resultIndex].isPinned = false;
      notifyListeners();
    }
  }

  /// 关闭一个结果子标签
  /// Pinned 子标签（包括历史子标签）不可关闭。
  void closeResult(String tabId, int resultIndex) {
    final resultList = _tabResults[tabId];
    if (resultList == null ||
        resultIndex < 0 ||
        resultIndex >= resultList.length) {
      return;
    }

    final result = resultList[resultIndex];
    if (result.isPinned) return;

    resultList.removeAt(resultIndex);

    final activeIdx = _tabActiveResultIndex[tabId] ?? 0;
    if (resultList.isEmpty) {
      _tabActiveResultIndex[tabId] = 0;
    } else if (activeIdx >= resultList.length) {
      _tabActiveResultIndex[tabId] = resultList.length - 1;
    }

    notifyListeners();
  }

  /// 关闭指定 Tab 的所有结果子标签
  void closeAllResults(String tabId) {
    _tabResults.remove(tabId);
    _tabActiveResultIndex[tabId] = 0;
    notifyListeners();
  }

  /// 为指定 Tab 添加一个 pinned 的历史子标签（如果不存在），并激活它
  void ensureHistorySubTab(String tabId) {
    final resultList = _tabResults.putIfAbsent(tabId, () => []);
    final historyIndex = resultList.indexWhere((r) => r.isHistory);
    if (historyIndex >= 0) {
      _tabActiveResultIndex[tabId] = historyIndex;
    } else {
      resultList.add(
        ResultSubTab(
          id: 'history_${DateTime.now().millisecondsSinceEpoch}',
          label: 'History',
          isPinned: true,
          type: ResultSubTabType.history,
        ),
      );
      _tabActiveResultIndex[tabId] = resultList.length - 1;
    }
    notifyListeners();
  }

  /// 获取指定 Tab 当前活跃子标签的类型
  ResultSubTabType? getActiveSubTabType(String tabId) {
    final resultList = _tabResults[tabId];
    final activeIndex = _tabActiveResultIndex[tabId] ?? 0;
    if (resultList == null ||
        activeIndex < 0 ||
        activeIndex >= resultList.length) {
      return null;
    }
    return resultList[activeIndex].type;
  }

  /// 设置指定 Tab 的活跃结果子标签索引
  void setActiveResult(String tabId, int index) {
    final resultList = _tabResults[tabId];
    if (resultList != null && index >= 0 && index < resultList.length) {
      _tabActiveResultIndex[tabId] = index;
      notifyListeners();
    }
  }

  // ==================== 命令面板标志 ====================

  void setFormatRequested(bool value) {
    _formatRequested = value;
    notifyListeners();
  }

  void setExecuteRequested(bool value) {
    _executeRequested = value;
    notifyListeners();
  }

  void formatCurrentSql() {
    _formatRequested = true;
    notifyListeners();
  }

  // ==================== 保存的查询 ====================

  Future<void> loadSavedQueries() async {
    final prefs = await SharedPreferences.getInstance();
    final queriesJson = prefs.getString('saved_queries');
    if (queriesJson != null) {
      try {
        final List<dynamic> list = jsonDecode(queriesJson);
        _savedQueries = list
            .map((e) => QueryTab.fromJson(e as Map<String, dynamic>))
            .toList();
        // 迁移：旧保存查询没有 savedQueryId 时，使用其 id 作为 savedQueryId
        for (final query in _savedQueries) {
          if (query.savedQueryId == null || query.savedQueryId!.isEmpty) {
            query.savedQueryId = query.id;
          }
        }
      } catch (e) {
        AppLogger.e('TabProvider', 'Failed to load saved queries', e);
        _savedQueries = [];
      }
    }
    notifyListeners();
  }

  Future<bool> saveQuery(QueryTab tab) async {
    final trimmedTitle = tab.title.trim();
    if (trimmedTitle.isEmpty) return false;

    final targetSavedQueryId = tab.savedQueryId;

    // 同一连接下禁止同名保存查询（排除自身）
    final duplicateIndex = _savedQueries.indexWhere((q) {
      if (q.connectionId != tab.connectionId) return false;
      if (q.title != trimmedTitle) return false;
      final qId = q.savedQueryId ?? q.id;
      final tId = targetSavedQueryId ?? tab.id;
      return qId != tId;
    });
    if (duplicateIndex >= 0) {
      throw DuplicateSavedQueryNameException(
        trimmedTitle,
        connectionId: tab.connectionId,
      );
    }

    final existingIndex = _savedQueries.indexWhere((q) {
      if (targetSavedQueryId == null) return false;
      return q.savedQueryId == targetSavedQueryId;
    });

    if (existingIndex >= 0) {
      // 更新已存在的保存查询
      _savedQueries[existingIndex]
        ..isSaved = true
        ..title = trimmedTitle
        ..sql = tab.sql
        ..connectionId = tab.connectionId
        ..databaseName = tab.databaseName
        ..databaseType = tab.databaseType;
    } else {
      // 创建新的保存查询
      if (_savedQueries.length >= 20) {
        _savedQueries.removeAt(0);
      }
      final newId = tab.savedQueryId ?? tab.id;
      final savedQuery = tab.copyWith(
        id: newId,
        savedQueryId: newId,
        title: trimmedTitle,
        isSaved: true,
        isModified: false,
        originalSql: tab.sql,
      );
      _savedQueries.add(savedQuery);
      // 回写 savedQueryId，方便调用方将当前 Tab 关联到新创建的保存查询
      tab.savedQueryId = newId;
    }

    // 保存成功后，当前 Tab 也进入未修改状态
    tab.isSaved = true;
    tab.isModified = false;
    tab.originalSql = tab.sql;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_queries',
      jsonEncode(_savedQueries.map((q) => q.toJson()).toList()),
    );

    // 同时更新 tabs 中的标记和标题
    final tabIndex = _tabs.indexWhere((t) => t.id == tab.id);
    if (tabIndex >= 0) {
      _tabs[tabIndex]
        ..isSaved = true
        ..isModified = false
        ..originalSql = tab.sql
        ..title = tab.title
        ..isAutoTitle = false;
      if (tab.savedQueryId != null) {
        _tabs[tabIndex].savedQueryId = tab.savedQueryId;
      }
    }

    notifyListeners();
    return true;
  }

  Future<void> renameSavedQuery(String queryId, String newTitle) async {
    final index = _savedQueries.indexWhere((q) => q.id == queryId);
    if (index < 0) return;
    _savedQueries[index].title = newTitle.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_queries',
      jsonEncode(_savedQueries.map((q) => q.toJson()).toList()),
    );

    notifyListeners();
  }

  Future<void> deleteSavedQuery(String queryId) async {
    _savedQueries.removeWhere((q) => q.id == queryId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_queries',
      jsonEncode(_savedQueries.map((q) => q.toJson()).toList()),
    );

    notifyListeners();
  }

  Future<void> openSavedQuery(QueryTab savedQuery) async {
    // 检查是否已在 tabs 中打开
    final tabIndex = _tabs.indexWhere((t) => t.id == savedQuery.id);
    if (tabIndex >= 0) {
      _activeTabIndex = tabIndex;
    } else {
      // 保存查询携带保存时显式设定的上下文 → 绑定（侧边栏导航不覆写）；
      // 无连接信息的保存查询开成跟随型 tab。
      await addNewTab(
        connectionId: savedQuery.connectionId,
        databaseName: savedQuery.databaseName,
        bindContext: savedQuery.connectionId != null,
      );
      _tabs[_activeTabIndex].id = savedQuery.id;
      _tabs[_activeTabIndex].title = savedQuery.title;
      _tabs[_activeTabIndex].sql = savedQuery.sql;
      _tabs[_activeTabIndex].isSaved = true;
      _tabs[_activeTabIndex].isModified = false;
      _tabs[_activeTabIndex].originalSql = savedQuery.sql;
      _tabs[_activeTabIndex].connectionId = savedQuery.connectionId;
      _tabs[_activeTabIndex].databaseName = savedQuery.databaseName;
    }
    ensureHistorySubTab(_tabs[_activeTabIndex].id);
  }
}

/// QueryTab - 查询标签页数据模型
class QueryTab {
  String id;

  /// 持久化保存查询的独立标识符；打开保存查询时由 Tab 持有，用于更新原查询。
  String? savedQueryId;
  String title;
  String sql;
  List<ExecutionResult> executionResults;
  String? connectionId;
  String? databaseName;
  DatabaseType? databaseType;

  /// MySQL/Doris 的专属连接会话 ID，其他数据库类型为 null
  String? sessionId;
  bool isSaved;

  /// 当前编辑器内容是否与 [originalSql] 不一致；仅对 [isSaved] 为 true 的保存查询标签有效。
  bool isModified;

  /// 打开或上次保存时的 SQL 快照，用于判断 [isModified]。
  String? originalSql;
  String? error;

  /// 标题是否为系统自动生成（切换语言时可重新本地化）
  bool isAutoTitle;

  /// 上下文是否已被用户显式绑定（双击表/工具栏下拉选连接选库/打开保存
  /// 查询等）。绑定后侧边栏导航（switchToConnection 的活跃 tab 跟随）不再
  /// 覆写本 tab 上下文——per-tab 隔离对活跃 tab 同样成立；未绑定的空白
  /// tab（如「+」新建）继续跟随侧边栏（2026-08-27 修复语义保留）。
  bool isContextBound;

  QueryTab({
    required this.id,
    this.savedQueryId,
    required this.title,
    this.sql = '',
    this.executionResults = const [],
    this.connectionId,
    this.databaseName,
    this.databaseType,
    this.sessionId,
    this.isSaved = false,
    this.isModified = false,
    this.originalSql,
    this.error,
    this.isAutoTitle = false,
    this.isContextBound = false,
  });

  QueryTab copyWith({
    String? id,
    String? savedQueryId,
    String? title,
    String? sql,
    List<ExecutionResult>? executionResults,
    String? connectionId,
    String? databaseName,
    DatabaseType? databaseType,
    String? sessionId,
    bool? isSaved,
    bool? isModified,
    String? originalSql,
    String? error,
    bool? isAutoTitle,
    bool? isContextBound,
  }) {
    return QueryTab(
      id: id ?? this.id,
      savedQueryId: savedQueryId ?? this.savedQueryId,
      title: title ?? this.title,
      sql: sql ?? this.sql,
      executionResults: executionResults ?? this.executionResults,
      connectionId: connectionId ?? this.connectionId,
      databaseName: databaseName ?? this.databaseName,
      databaseType: databaseType ?? this.databaseType,
      sessionId: sessionId ?? this.sessionId,
      isSaved: isSaved ?? this.isSaved,
      isModified: isModified ?? this.isModified,
      originalSql: originalSql ?? this.originalSql,
      error: error ?? this.error,
      isAutoTitle: isAutoTitle ?? this.isAutoTitle,
      isContextBound: isContextBound ?? this.isContextBound,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (savedQueryId != null) 'savedQueryId': savedQueryId,
    'title': title,
    'sql': sql,
    'executionResults': executionResults.map((e) => e.toJson()).toList(),
    'connectionId': connectionId,
    'databaseName': databaseName,
    'databaseType': databaseType?.name,
    'sessionId': sessionId,
    'isSaved': isSaved,
    'isModified': isModified,
    if (originalSql != null) 'originalSql': originalSql,
    'error': error,
    'isAutoTitle': isAutoTitle,
    'isContextBound': isContextBound,
  };

  factory QueryTab.fromJson(Map<String, dynamic> json) {
    DatabaseType? dbType;
    final typeStr = json['databaseType'] as String?;
    if (typeStr != null) {
      try {
        dbType = DatabaseType.values.firstWhere((e) => e.name == typeStr);
      } catch (_) {
        dbType = null;
      }
    }
    return QueryTab(
      id: json['id'] as String,
      savedQueryId: json['savedQueryId'] as String?,
      title: json['title'] as String,
      sql: json['sql'] as String? ?? '',
      executionResults:
          (json['executionResults'] as List<dynamic>?)
              ?.map(
                (e) => ExecutionResult.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          [],
      connectionId: json['connectionId'] as String?,
      databaseName: json['databaseName'] as String?,
      databaseType: dbType,
      sessionId: json['sessionId'] as String?,
      isSaved: json['isSaved'] as bool? ?? false,
      isModified: json['isModified'] as bool? ?? false,
      originalSql: json['originalSql'] as String?,
      error: json['error'] as String?,
      isAutoTitle: json['isAutoTitle'] as bool? ?? false,
      // 旧持久化数据无此字段：带上下文恢复的 tab 视为已绑定（崩溃恢复后
      // 首次侧边栏导航不得劫持其上下文），无上下文的跟随。
      isContextBound:
          json['isContextBound'] as bool? ??
          json['connectionId'] != null,
    );
  }
}
