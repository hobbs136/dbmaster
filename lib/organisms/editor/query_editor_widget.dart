import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../connection/error_boundary.dart';
import '../../services/readonly_guard.dart';
// 编辑器焦点跟踪（spec 040 Phase 2.2）
import '../../core/shortcuts/editor_focus_state.dart';
import '../../models/database_models.dart' hide QueryTab;
import '../../models/formatter_models.dart';
import '../../providers/tab_provider.dart'
    show QueryTab, DuplicateSavedQueryNameException;
import '../../models/drag_models.dart';
import '../../models/execution_result.dart';
import '../../models/sql_statement.dart';
import '../../molecules/toolbar_button.dart';
import '../../services/sql_autocomplete_service.dart';
import '../../services/mongo_autocomplete_service.dart'; // 020-mongo US1
import '../../services/sql_formatter_service.dart';
import '../../services/sql_parser_service.dart';
import '../../services/database_service.dart';
import '../../services/saved_query_api_service.dart';
import '../server/approval/submit_approval_dialog.dart';
import '../ai_panel/ddl_confirm_dialog.dart';
import '../dialogs/dml_confirm_dialog.dart';
import '../results/safety_warning_banner.dart';
import '../../models/dml_risk_models.dart';
import '../../services/sql_validator_service.dart';
import '../../utils/app_logger.dart';
import '../../models/code_snippet.dart'
    show SnippetDbFamily; // 021-mongo-snippet-overlay-wiring T001
import '../connection/code_formatter_dialog.dart';
import '../../services/safety/safety_rule.dart';
import '../../services/safety/safety_finding.dart' as safety;
import '../../services/safety/safety_review_indicator.dart';
import '../../services/safety/safety_review_service.dart';
import '../../services/safety/rules/schema_compat_rule.dart';
import '../../services/safety/rules/missing_limit_rule.dart';
import '../../services/safety/rules/full_table_scan_rule.dart';
import '../../services/safety/rules/sql_injection_rule.dart';
import '../../services/safety/rules/explain_full_scan_rule.dart';
import '../../services/safety/rules/explain_estimated_rows_rule.dart';
import '../../services/safety/rules/executable_comment_rule.dart';
import '../../services/safety/rules/tautology_predicate_rule.dart';
import '../../services/safety/rules/complementary_or_rule.dart';
import '../../services/safety/rules/writable_cte_rule.dart';
import '../../services/safety/rules/file_write_rule.dart';
// 第四阶段：DDL 锁语义分析（统一执行门路径）。
import '../../services/safety/ddl_script_analyzer.dart';
import '../dialogs/execution_gate_dialog.dart';
import '../dialogs/pii_masking_dialog.dart';
import '../pro/pro_import_ui.dart';
import '../../services/ai_service.dart';
import '../../molecules/context_menu.dart';
import '../../l10n/app_localizations.dart';

import '../results/results_widget.dart';
import '../query_optimizer/query_plan_visualizer.dart';
import '../../services/query_optimizer/query_optimizer_service.dart';

import 're_sql_editor.dart';
import 're_sql_editor_controller.dart';
import 'query_editor_toolbar.dart';
import 'query_editor_status_bar.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

/// QueryEditorWidget - 查询编辑器主容器
/// T003: 重构后仅保留协调逻辑，UI 子组件已提取
class QueryEditorWidget extends StatefulWidget {
  final int tabIndex;
  final GlobalKey<ResultsWidgetState>? resultsWidgetKey;

  /// 命令面板入口回调（C21 M3：随 BreadcrumbBar 退役从面包屑迁入工具栏）。
  final VoidCallback? onCommandPalette;

  const QueryEditorWidget({
    super.key,
    required this.tabIndex,
    this.resultsWidgetKey,
    this.onCommandPalette,
  });

  @override
  State<QueryEditorWidget> createState() => QueryEditorWidgetState();
}

class QueryEditorWidgetState extends State<QueryEditorWidget> {
  // T17/T18：re_editor 全量替换旧 TextField 编辑器（行式渲染根治大文本卡顿）。
  late ReSqlEditorController _sqlController;
  late FocusNode _focusNode;

  /// 当前语法高亮语言（sql / javascript），随 Tab 数据库类型切换。
  String _editorLanguage = 'sql';

  /// Exposes the underlying editor controller for testing and external reuse.
  ReSqlEditorController get controller => _sqlController;

  /// Exposes the merged line-level error map (validation + safety red dots)
  /// for testing and debugging.
  Map<int, ErrorSeverity> get mergedEditorErrors => _mergedErrorsByLine();
  bool _isExecuting = false;
  DmlWarningRequiredException? _dmlWarning;
  bool _isSaving = false;
  String _lastSql = '';

  // T011: SQL 校验错误
  Map<int, ErrorSeverity> _validationErrorsByLine = {};

  // B3：安全审查行级红点。审查执行时填充，编辑器内容变化时清空（避免错位）。
  // 与 _validationErrorsByLine 并行，最终合并传给 ReSqlEditor.errors。
  Map<int, ErrorSeverity> _safetyErrorsByLine = {};

  // L1: SQL 校验防抖计时器
  Timer? _validationDebounceTimer;

  // T014: Provider SQL 更新防抖计时器
  Timer? _sqlUpdateDebounceTimer;

  // SQL 安全审查引擎（懒初始化）。
  SafetyReviewService? _safetyService;
  // ExecutionGateDialog「知情继续」后设此 flag，跳过 DDL 二次确认弹窗。
  bool _ddlBypassSafety = false;

  // 执行代际：每次 _executeQuery 自增。审查这类长前置 await 返回后用它
  // 识别「停止后用户又点了运行」的交错，防止旧一轮复活下发查询。
  int _execGeneration = 0;

  // 用户在查询下发前（安全审查/执行门阶段）点了停止。
  bool _stopRequested = false;

  // 真正的查询是否已下发。审查阶段的停止只置标记（cancelQuery 对无在途
  // 查询会报「取消失败」），已下发阶段才走 cancelQuery 取消链路。
  bool _queryStarted = false;

  SplitMode _splitMode = SplitMode.none;
  ReSqlEditorController? _splitSqlController;

  // T18：多语句执行进度（ValueNotifier 局部刷新，避免逐条 setState 重建
  // 整个编辑器——长脚本执行期 n/total 计数只动工具栏一小块文本）。
  final ValueNotifier<String?> _execProgress = ValueNotifier(null);

  // C21 状态条：光标行列（选区回调局部重建）+ 执行已耗时（1s tick）。
  // 与 _execProgress 同款契约——不让高频信号触发整编辑器 setState。
  final ValueNotifier<({int line, int column})> _cursorPos =
      ValueNotifier((line: 1, column: 1));
  final ValueNotifier<Duration?> _execElapsed = ValueNotifier(null);
  Timer? _execElapsedTimer;
  DateTime? _execStartAt;

  /// 测试探针用：读取光标位置通知器。
  @visibleForTesting
  ValueNotifier<({int line, int column})> get cursorPosDebug => _cursorPos;

  /// 测试探针用：读取执行进度标签与执行态。
  @visibleForTesting
  ValueNotifier<String?> get execProgressDebug => _execProgress;

  @visibleForTesting
  bool get isExecutingDebug => _isExecuting;

  late SQLAutocompleteService _autocompleteService;
  MongoAutocompleteService? _mongoAutocompleteService; // 020-mongo US1

  final SqlFormatterService _formatterService = SqlFormatterService();

  bool get _isCtrlOrMetaPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  bool get _isShiftPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  bool get _isAltPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.altLeft) ||
        keys.contains(LogicalKeyboardKey.altRight);
  }

  final GlobalKey _connectionSelectorKey = GlobalKey();
  final GlobalKey _databaseSelectorKey = GlobalKey();

  /// Appends [sql] to the end of the current editor content.
  ///
  /// If the editor is not empty, a newline is inserted before the appended SQL.
  /// The cursor is moved to the end of the document.
  void appendSql(String sql) {
    final newText = appendSqlText(_sqlController.text, sql);
    _sqlController.text = newText;
    _sqlController.requestFocus();
  }

  /// Replaces the current editor content with [sql] and moves the cursor to the
  /// end of the document.
  void setSql(String sql) {
    _sqlController.text = sql;
    _sqlController.requestFocus();
  }

  /// Inserts [text] at the current cursor selection (replaces any selection),
  /// used by external callers such as the sidebar's double-click-on-column
  /// action via the [AppProvider.insertIntoActiveEditor] bridge.
  // 暴露光标处插入给侧栏桥接调用
  void insertAtCursor(String text) => _insertTextAtCursor(text);

  /// Computes the editor text after appending [sql] to [currentText].
  static String appendSqlText(String currentText, String sql) {
    final separator = currentText.trim().isEmpty ? '' : '\n';
    return '$currentText$separator$sql';
  }

  // 事务管理
  bool _isInTransaction = false;

  Future<void> _beginTransaction() async {
    try {
      final provider = context.read<AppProvider>();
      await provider.beginTransaction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction started'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          'Failed to start transaction: $e',
        );
      }
    }
  }

  Future<void> _commitTransaction() async {
    try {
      final provider = context.read<AppProvider>();
      await provider.commitTransaction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction committed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          'Failed to commit transaction: $e',
        );
      }
    }
  }

  Future<void> _rollbackTransaction() async {
    try {
      final provider = context.read<AppProvider>();
      await provider.rollbackTransaction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction rolled back'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          'Failed to rollback transaction: $e',
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _sqlController = ReSqlEditorController();
    _focusNode = _sqlController.focusNode;
    _focusNode.onKeyEvent = _handleFocusNodeKeyEvent;
    // 注册编辑器焦点节点（全局快捷键据此判断是否让位，避免双触发；spec 040 Phase 2.2）
    registerEditorFocusNode(_focusNode);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final provider = context.read<AppProvider>();
        _autocompleteService = SQLAutocompleteService(provider.dbService);
        _syncTabContent();
        _updateEditorLanguage();
        _checkFocusRequest();

        // 监听事务状态变化
        provider.addListener(_onTransactionStateChange);
        _updateTransactionState();
      } catch (e) {
        // Silently handle init error
      }
    });
  }

  void _checkFormatRequested() {
    if (!mounted) return;
    try {
      final provider = context.read<AppProvider>();
      if (provider.formatRequested &&
          widget.tabIndex == provider.activeTabIndex) {
        provider.clearFormatRequested();
        _quickFormat();
      }
    } catch (e) {
      // Silently handle format check error
    }
  }

  void _syncTabContent() {
    if (!mounted) return;
    try {
      final provider = context.read<AppProvider>();
      if (provider.tabs.isNotEmpty &&
          widget.tabIndex >= 0 &&
          widget.tabIndex < provider.tabs.length) {
        final tab = provider.tabs[widget.tabIndex];
        if (_lastSql != tab.sql) {
          _lastSql = tab.sql;
          // tab 切换装载：不可撤销 + 清空 undo 历史（避免跨 tab 撤销污染）。
          _sqlController.loadText(tab.sql);
        }
      }
    } catch (e) {
      // Silently handle sync error
    }
  }

  @override
  void didUpdateWidget(QueryEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex != widget.tabIndex) {
      // 补全/片段弹窗由 re_editor CodeAutocomplete 原生管理，随焦点/文本变化
      // 自行关闭，这里无需再手动摘除 overlay。
      _lastSql = '';
      _syncTabContent();
      _updateEditorLanguage();
    }
    _checkFocusRequest();
  }

  void _checkFocusRequest() {
    if (!mounted) return;
    try {
      final provider = context.read<AppProvider>();
      if (provider.shouldFocusEditor &&
          widget.tabIndex == provider.activeTabIndex) {
        provider.clearEditorFocusRequest();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
    } catch (e) {
      // Silently handle focus request check
    }
  }

  /// 获取当前 Tab 的数据库类型（优先使用 Tab 自身记录的类型，避免全局 currentServer 变化导致的问题）
  DatabaseType? _getTabDatabaseType() {
    try {
      final provider = context.read<AppProvider>();
      if (provider.tabs.isNotEmpty && widget.tabIndex < provider.tabs.length) {
        final tab = provider.tabs[widget.tabIndex];
        // 优先使用 Tab 自身记录的数据库类型
        if (tab.databaseType != null) {
          return tab.databaseType;
        }
        // 兼容旧数据：回退到通过 connectionId 查找
        if (tab.connectionId != null) {
          final server = provider.connection.savedConnections.firstWhere(
            (s) => s.id == tab.connectionId,
            orElse: () => provider.connection.currentServer!,
          );
          return server.type;
        }
      }
      // 最后回退到全局 currentServer
      return provider.connection.currentServer?.type;
    } catch (e) {
      return null;
    }
  }

  // 021-mongo-snippet-overlay-wiring T001 — dbType → family mapping helper
  SnippetDbFamily? familyFor(DatabaseType? dbType) {
    if (dbType == null) return null;
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.clickhouse:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.doris:
      case DatabaseType.sqlserver:
      case DatabaseType.tdengine:
        return SnippetDbFamily.sql;
      case DatabaseType.mongodb:
        return SnippetDbFamily.mongodb;
      default:
        return null; // Redis, Elasticsearch, etc. have no snippets
    }
  }

  /// 类型 → 事务支持映射（U13：ClickHouse adapter 无事务实现，返回 false 防假回滚）。
  ///
  /// T22-T25：OB/TiDB/MariaDB 支持事务；StarRocks 显式事务内仅允许
  /// begin/commit/rollback/DML（连 SELECT 都拒，实机 5305），编辑器事务面
  /// 与 server 薄适配能力位（supports_transactions=false）同口径关 false。
  static bool supportsTransactionFor(DatabaseType? dbType) {
    if (dbType == null) return false;
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.doris:
      case DatabaseType.sqlserver:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.mariadb:
        return true;
      case DatabaseType.clickhouse:
      case DatabaseType.mongodb:
      case DatabaseType.redis:
      case DatabaseType.tdengine:
      case DatabaseType.starrocks:
        return false;
    }
  }

  bool _supportsTransaction() {
    if (_isReadOnly()) return false;
    return supportsTransactionFor(_getTabDatabaseType());
  }

  bool _isReadOnly() {
    try {
      final provider = context.read<AppProvider>();
      final server = provider.connection.currentServer;
      return server?.readOnly ?? false;
    } catch (e) {
      return false;
    }
  }

  bool _supportsSmartImport() {
    final dbType = _getTabDatabaseType();
    if (dbType == null) return false;
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.clickhouse:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.doris:
      case DatabaseType.sqlserver:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return true;
      case DatabaseType.mongodb:
      case DatabaseType.redis:
      case DatabaseType.tdengine:
        return false;
    }
  }

  bool _supportsQueryPlan() {
    final dbType = _getTabDatabaseType();
    if (dbType == null) return false;
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.clickhouse:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.doris:
      case DatabaseType.sqlserver:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return true;
      case DatabaseType.mongodb:
      case DatabaseType.redis:
      case DatabaseType.tdengine:
        return false;
    }
  }

  bool _supportsFormat() {
    final dbType = _getTabDatabaseType();
    if (dbType == null) return false;
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.clickhouse:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.doris:
      case DatabaseType.tdengine:
      case DatabaseType.sqlserver:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return true;
      case DatabaseType.mongodb:
      case DatabaseType.redis:
        return false;
    }
  }

  bool _supportsPIIMasking() {
    final dbType = _getTabDatabaseType();
    if (dbType == null) return false;
    switch (dbType) {
      case DatabaseType.mysql:
      case DatabaseType.clickhouse:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.doris:
      case DatabaseType.sqlserver:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return true;
      case DatabaseType.mongodb:
      case DatabaseType.redis:
      case DatabaseType.tdengine:
        return false;
    }
  }

  void _onTransactionStateChange() {
    if (!mounted) return;
    _updateTransactionState();
  }

  void _updateTransactionState() {
    try {
      final provider = context.read<AppProvider>();
      final newState = provider.isInTransaction;
      if (_isInTransaction != newState) {
        setState(() {
          _isInTransaction = newState;
        });
      }
    } catch (e) {
      // Silently handle error
    }
  }

  void _toggleSplit(SplitMode mode) {
    setState(() {
      if (mode == SplitMode.none) {
        _splitMode = SplitMode.none;
        _disposeSplitController();
      } else if (_splitMode == mode) {
        _splitMode = SplitMode.none;
        _disposeSplitController();
      } else {
        _splitMode = mode;
        _initSplitController();
      }
    });
  }

  void _initSplitController() {
    if (_splitSqlController != null) return;
    _splitSqlController = ReSqlEditorController();
  }

  void _disposeSplitController() {
    _splitSqlController?.dispose();
    _splitSqlController = null;
  }

  void _onSplitTextChanged(String text) {
    // 分屏编辑器文本变化
  }

  @override
  void dispose() {
    _execProgress.dispose();
    _execElapsedTimer?.cancel();
    _execElapsed.dispose();
    _cursorPos.dispose();
    unregisterEditorFocusNode(
      _focusNode,
    ); // 须在 _sqlController dispose 前（spec 040 Phase 2.2）
    _validationDebounceTimer?.cancel(); // L1
    _sqlUpdateDebounceTimer?.cancel(); // T014
    _sqlController.dispose();
    _splitSqlController?.dispose();

    // 移除事务状态监听
    try {
      final provider = context.read<AppProvider>();
      provider.removeListener(_onTransactionStateChange);
    } catch (e) {
      // Provider might be disposed already
    }

    super.dispose();
  }

  void _onTextChanged(String text) {
    try {
      _lastSql = text;

      // B3：编辑器内容变化 → 清空安全审查行级红点（行号已错位，旧 finding 失效）。
      if (_safetyErrorsByLine.isNotEmpty) {
        _safetyErrorsByLine = {};
      }

      // L1: SQL 实时校验（500ms 防抖）
      _validationDebounceTimer?.cancel();
      _validationDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _validateSql(text);
      });

      // T014: Provider SQL 更新防抖（200ms）——减少notifyListeners触发频率
      _sqlUpdateDebounceTimer?.cancel();
      _sqlUpdateDebounceTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        final provider = context.read<AppProvider>();
        if (provider.tabs.isNotEmpty &&
            widget.tabIndex < provider.tabs.length) {
          provider.updateTabSql(widget.tabIndex, text);
        }
      });

      // 021/020：片段 `/trigger` 与 SQL/Mongo 补全已统一迁移到 re_editor
      // CodeAutocomplete 原生弹窗（ReAutocompleteBridge，随打字即时触发 +
      // 光标锚定 + IME 自动避让），不再在此防抖调度。
    } catch (e) {
      AppLogger.e('QueryEditorWidget', 'Error in _onTextChanged', e);
    }
  }

  // T012: 检测并显示代码片段命令
  // T011: SQL 实时校验
  Future<void> _validateSql(String sql) async {
    // 大文本走后台 isolate：MB 级脚本的全量扫描是数百 ms 的纯 CPU，
    // 同步跑会冻结 UI（粘贴后和每次击键的防抖都会触发）。
    // 阈值与 SqlHighlightController._maxHighlightLength 对齐。
    final List<SqlValidationError> errors;
    if (sql.length > 20000) {
      errors = await compute(SQLValidatorService.validate, sql);
    } else {
      errors = SQLValidatorService.validate(sql);
    }
    if (!mounted) return;
    final errorsByLine = <int, ErrorSeverity>{};
    for (final error in errors) {
      final existing = errorsByLine[error.line];
      if (existing == null || error.severity.index > existing.index) {
        errorsByLine[error.line] = error.severity;
      }
    }

    setState(() {
      _validationErrorsByLine = errorsByLine;
    });
  }

  /// ReAutocompleteBridge 的 async 补全解析器：按 Tab 数据库类型分派
  /// SQL / Mongo 服务（020-mongo US1 语义平价），schema 走服务内缓存。
  Future<List<Suggestion>> _resolveAutocomplete(
    String text,
    int cursorOffset,
  ) async {
    try {
      _autocompleteService;
    } catch (_) {
      final provider = context.read<AppProvider>();
      _autocompleteService = SQLAutocompleteService(provider.dbService);
    }

    final provider = context.read<AppProvider>();
    final currentTab =
        provider.tabs.isNotEmpty && widget.tabIndex < provider.tabs.length
        ? provider.tabs[widget.tabIndex]
        : null;
    final databaseName = currentTab?.databaseName;
    final connectionId = currentTab?.connectionId;

    final dbType = _getTabDatabaseType();
    if (dbType == DatabaseType.mongodb) {
      _mongoAutocompleteService ??= MongoAutocompleteService(
        provider.dbService,
      );
      return _mongoAutocompleteService!.getSuggestions(
        text,
        cursorOffset,
        databaseName: databaseName,
        connectionId: connectionId,
      );
    }
    return _autocompleteService.getSuggestions(
      text,
      cursorOffset,
      databaseName: databaseName,
      connectionId: connectionId,
    );
  }

  KeyEventResult _handleFocusNodeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // T17/T18：编辑器内层快捷键（粘贴/复制/撤销/Tab/Enter/方向键/补全导航/
    // Smart Home/Ctrl+S）已由 re_editor 内建 + ReSqlEditor 覆写动作承接，
    // re_editor 未认领的键冒泡到这里：
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        _isCtrlOrMetaPressed &&
        _isShiftPressed) {
      _quickFormat();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        _isCtrlOrMetaPressed &&
        _isAltPressed) {
      _quickFormat();
      return KeyEventResult.handled;
    }

    // F5 执行查询
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      _executeQuery();
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd+Enter 执行查询（re_editor 已摘除其默认换行绑定）
    if (event.logicalKey == LogicalKeyboardKey.enter && _isCtrlOrMetaPressed) {
      _executeQuery();
      return KeyEventResult.handled;
    }

    // US6: Ctrl/Cmd+S 保存当前查询到历史记录。正常情况下 re_editor 的
    // CodeShortcutSaveIntent 覆写动作（ReSqlEditor.onSaveShortcut）会消费该键，
    // 此处不触发；仅当内层快捷键链未消费（如 widget 测试合成键）时兜底。
    if (event.logicalKey == LogicalKeyboardKey.keyS && _isCtrlOrMetaPressed) {
      _saveCurrentQueryAsSavedQuery();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _getSqlToExecute() {
    if (_sqlController.hasSelection) {
      final selectedText = _sqlController.selectedText.trim();
      if (selectedText.isNotEmpty) return selectedText;
    }
    return _sqlController.text.trim();
  }

  /// 安全审查是否覆盖了当前库型（与 dbService 链路 A 的 analyzeDdl
  /// 支持面对齐——非 MySQL/Doris 时审查静默跳过，链路 A 语义保留）。
  bool _reviewCoversDdlAnalysis() {
    final dbType = _getTabDatabaseType();
    return dbType == DatabaseType.mysql || dbType == DatabaseType.doris;
  }

  /// Check if SQL contains DDL statements that may affect the schema
  bool _isDdlStatement(String sql) {
    final trimmed = sql.trim().toUpperCase();
    final ddlKeywords = [
      'CREATE ',
      'CREATE\t',
      'CREATE\n',
      'DROP ',
      'DROP\t',
      'DROP\n',
      'ALTER ',
      'ALTER\t',
      'ALTER\n',
      'RENAME ',
      'RENAME\t',
      'RENAME\n',
      'TRUNCATE ',
      'TRUNCATE\t',
      'TRUNCATE\n',
    ];
    return ddlKeywords.any((keyword) => trimmed.contains(keyword));
  }

  Future<void> _executeQuery() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final sql = _getSqlToExecute();
    if (sql.isEmpty) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, l10n.pleaseEnterSql);
      }
      return;
    }

    // 反馈先行：点击即切「停止」态 + 计时启动。安全审查（含 EXPLAIN /
    // 行数查询等多次 DB 往返）不再是无反馈死窗口——用户报告「点运行要
    // 过一会儿才有动静」。审查取消等提前返回统一走末尾 finally 复位。
    final generation = ++_execGeneration;
    _stopRequested = false;
    _queryStarted = false;
    setState(() => _isExecuting = true);
    _execProgress.value = null;
    _startElapsedTimer();

    try {
      // SQL 安全审查（执行前拦截）。仅 MySQL/Doris 启用；非 MySQL 静默跳过。
      // 审查异常：读类不阻断；写类走 fail-closed 执行门（T13 · D2）。
      if (!_ddlBypassSafety) {
        final reviewResult = await _runSafetyReview(sql);
        // 审查期间用户点了停止（或停止后又起了新一轮执行）→ 中止，
        // 不再下发查询。
        if (_stopRequested || generation != _execGeneration) return;
        if (reviewResult == ExecutionGateAction.cancel) {
          return; // 用户取消
        }
        if (reviewResult == ExecutionGateAction.applySuggestion) {
          return; // SQL 已替换，用户需重新执行
        }
        if (reviewResult == ExecutionGateAction.proceed) {
          _ddlBypassSafety = true; // 跳过后续 DDL 确认弹窗
        } else if (reviewResult == null && _reviewCoversDdlAnalysis()) {
          // 审查已完整跑过且无 medium/high（静默通过）→ dbService 逐条
          // 链路 A 属冗余：多语句脚本每条 DDL 再做一次影响分析（多条 DB
          // 往返）≈ 300ms/条，402 表脚本实测 139s+ 无反馈即用户报告的
          // 「执行中卡死」。执行门（含其 DDL 分析腿）是权威入口。
          _ddlBypassSafety = true;
        }
      }

      final startTime = DateTime.now();
      late final List<ExecutionResult> results;

      try {
        final currentTab = provider.activeTab;
        AppLogger.d(
          'QueryEditor',
          '[QueryEditor] _executeQuery: sql=${AppLogger.sqlPreview(sql)}, currentTab=${currentTab?.id}, connectionId=${currentTab?.connectionId}, databaseName=${currentTab?.databaseName}, sessionId=${currentTab?.sessionId}',
        );
        _queryStarted = true;
        results = await provider.executeCurrentQueryAndRecord(
          overrideSql: sql,
          // 执行门（ExecutionGateDialog）已确认风险时，跳过 database_service
          // 层链路 A 的重复 DDL 分析（避免又一次不带锁语义的 analyzeDdl + 异常路由）。
          skipDdlAnalysis: _ddlBypassSafety,
          onStatementProgress: (current, total) {
            if (total > 1) {
              _execProgress.value = '$current/$total';
            }
          },
        );
        AppLogger.d(
          'QueryEditor',
          '[QueryEditor] _executeQuery: results.length=${results.length}, firstResult.data.length=${results.isNotEmpty ? results.first.data?.length : "N/A"}, firstResult.success=${results.isNotEmpty ? results.first.success : "N/A"}',
        );
      } on DmlConfirmationRequiredException catch (e) {
        if (!mounted) return;
        final confirmResult = await DmlConfirmDialog.show(
          context,
          analysis: e.analysis,
          statements: e.statements,
          dbType: _getTabDatabaseType() ?? DatabaseType.mysql,
        );

        if (confirmResult != DmlConfirmResult.confirm) {
          // Log blocked operation
          final interceptor = provider.dbService.interceptor;
          interceptor.logDmlBlocked(
            sql: e.sql,
            connectionId: provider.connection.currentServer?.id ?? '',
            riskLevel: e.analysis.riskLevel,
            decision: AuditDecision.cancelled,
          );
          return;
        }

        // User confirmed — bypass DML check and re-execute
        final currentTab = provider.activeTab;
        final bypassResults = await provider.dbService.executeQueryBypassDml(
          e.sql,
          connectionId: currentTab?.connectionId,
          database: currentTab?.databaseName,
          sessionId: currentTab?.sessionId,
        );
        results = [
          ExecutionResult(
            statement: SQLStatement(
              index: 0,
              sql: e.sql,
              type: SQLType.other,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: bypassResults,
            executionTime: DateTime.now().difference(startTime),
          ),
        ];
      } on DmlWarningRequiredException catch (e) {
        if (!mounted) return;
        setState(() {
          _dmlWarning = e;
        });
        // Re-execute with bypass will be triggered by the banner's onConfirm callback
        return;
      } on DdlConfirmationRequiredException catch (e) {
        if (!mounted) return;
        // D1 合并：用户已在执行门（ExecutionGateDialog）确认过风险，
        // 跳过 DDL 二次确认弹窗，直接走 bypass 执行路径。
        if (_ddlBypassSafety) {
          final currentTab = provider.activeTab;
          final statements = SQLParserService.split(sql);
          if (statements.length == 1) {
            final data = await provider.dbService.executeQueryBypassDdl(
              sql,
              connectionId: currentTab?.connectionId,
              database: currentTab?.databaseName,
              sessionId: currentTab?.sessionId,
            );
            results = [
              ExecutionResult(
                statement: SQLStatement(
                  index: 0,
                  sql: sql,
                  type: SQLType.ddl,
                  lineStart: 1,
                  lineEnd: 1,
                ),
                success: true,
                data: data,
                executionTime: DateTime.now().difference(startTime),
              ),
            ];
          } else {
            final success = await provider.dbService.executeSqlScriptBypassDdl(
              sql,
              connectionId: currentTab?.connectionId,
            );
            results = [
              ExecutionResult(
                statement: SQLStatement(
                  index: 0,
                  sql: sql,
                  type: SQLType.ddl,
                  lineStart: 1,
                  lineEnd: 1,
                ),
                success: success,
                data: const [],
                executionTime: DateTime.now().difference(startTime),
              ),
            ];
          }
          provider.updateTabExecutionResults(provider.activeTabIndex, results);
          return;
        }
        final ctx = context;
        final confirmResult = await showDialog<DdlConfirmResult>(
          // ignore: use_build_context_synchronously
          context: ctx,
          barrierDismissible: false,
          builder: (ctx) =>
              DdlConfirmDialog(sql: e.sql, impactReport: e.impactReport),
        );

        if (confirmResult != DdlConfirmResult.execute) {
          return;
        }

        // 用户确认后绕过 DDL 检查执行
        final currentTab = provider.activeTab;
        final statements = SQLParserService.split(sql);
        if (statements.length == 1) {
          final data = await provider.dbService.executeQueryBypassDdl(
            sql,
            connectionId: currentTab?.connectionId,
            database: currentTab?.databaseName,
            sessionId: currentTab?.sessionId,
          );
          results = [
            ExecutionResult(
              statement: SQLStatement(
                index: 0,
                sql: sql,
                type: SQLType.ddl,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: data,
              executionTime: DateTime.now().difference(startTime),
            ),
          ];
        } else {
          final success = await provider.dbService.executeSqlScriptBypassDdl(
            sql,
            connectionId: currentTab?.connectionId,
          );
          results = [
            ExecutionResult(
              statement: SQLStatement(
                index: 0,
                sql: sql,
                type: SQLType.ddl,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: success,
              data: const [],
              executionTime: DateTime.now().difference(startTime),
            ),
          ];
        }

        // DDL bypass 路径手动更新结果和历史（非 DDL 路径由 executeCurrentQueryAndRecord 统一处理）
        provider.updateTabExecutionResults(provider.activeTabIndex, results);
        final bypassTotalTime = DateTime.now()
            .difference(startTime)
            .inMilliseconds;
        await provider.addQueryHistory(
          sql: sql,
          executionTime: bypassTotalTime,
          affectedRows: results.fold<int>(
            0,
            (sum, r) => sum + (r.affectedRows ?? 0),
          ),
          databaseType: _getTabDatabaseType(),
          connectionId: provider.connection.currentServer?.id,
          connectionName: provider.connection.currentServer?.name,
        );
      }

      if (!mounted) return;

      final successCount = results.where((r) => r.success).length;

      // Auto-refresh sidebar tree and entity panel if DDL statements were executed
      if (successCount > 0 && _isDdlStatement(sql)) {
        final currentTab = provider.activeTab;
        final cid = currentTab?.connectionId;
        final dbName = currentTab?.databaseName;
        if (cid != null && dbName != null) {
          provider.refreshDatabase(cid, dbName);
        }
      }

      // 查询执行摘要已在 _ExecutionStatusBar 和 Messages 子 Tab 中展示，
      // 不再弹出 SnackBar 遮挡底部状态栏。
    } on ParseException catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, l10n.queryFailed(e.message));
      }
    } on ReadOnlyBlockedException catch (_) {
      // 只读连接写拦截：本地化警告提示（非查询失败，FR-004）
      if (mounted) {
        AppErrorHandler.showWarningSnackBar(context, l10n.readOnlyModeBlocked);
      }
    } catch (e) {
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      await provider.addQueryHistory(
        sql: sql,
        error: e.toString(),
        databaseType: _getTabDatabaseType(),
        connectionId: provider.connection.currentServer?.id,
        connectionName: provider.connection.currentServer?.name,
      );

      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.queryFailed(e.toString()),
        );
      }
    } finally {
      _ddlBypassSafety = false; // 重置 bypass（下次执行重新审查）
      _queryStarted = false;
      _stopElapsedTimer();
      if (mounted) setState(() => _isExecuting = false);
    }
  }

  /// C21 状态条：执行开始 —— 记录起点并 1s tick 已耗时。
  void _startElapsedTimer() {
    _execStartAt = DateTime.now();
    _execElapsed.value = Duration.zero;
    _execElapsedTimer?.cancel();
    _execElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _execStartAt;
      if (start != null) {
        _execElapsed.value = DateTime.now().difference(start);
      }
    });
  }

  /// C21 状态条：执行结束 —— 停 tick 清空（null = 空闲，状态条回落「就绪」）。
  void _stopElapsedTimer() {
    _execElapsedTimer?.cancel();
    _execElapsedTimer = null;
    _execStartAt = null;
    _execElapsed.value = null;
  }

  /// C21 状态条：ReSqlEditor 选区回调 → 行列 ValueNotifier。
  void _onCursorPositionChanged(int line, int column) {
    _cursorPos.value = (line: line, column: column);
  }

  /// 运行 SQL 安全审查。返回弹窗动作（cancel/proceed/applySuggestion），
  /// 或 null（无 findings 静默通过 / 非 MySQL 跳过 / 审查异常且为读类）。
  /// T13 · D2：审查整体异常且为写类 → 注入 fail-closed finding 走执行门。
  Future<ExecutionGateAction?> _runSafetyReview(String sql) async {
    try {
      final provider = context.read<AppProvider>();
      final dbType = _getTabDatabaseType();
      // 仅 MySQL/Doris 启用审查。
      if (dbType != DatabaseType.mysql && dbType != DatabaseType.doris) {
        return null;
      }
      final connId = provider.activeTab?.connectionId;
      if (connId == null) return null;

      // 构建审查引擎（每次执行重建——规则对象无状态零成本，且能即时
      // 反映用户在设置页改的开关/阈值。去掉了原来的 ??= 缓存）。
      _safetyService = _buildSafetyService(provider);

      // 构造审查上下文。
      final server = provider.connection.currentServer;

      // 同一轮审查内 EXPLAIN 结果按语句 memo：R9/R10 会先后对同一语句
      // 各调一次 getExplainPlan（无共享），经网关就是两趟串行 DB 往返——
      // 首轮发起真请求，其余规则复用同一 in-flight Future，往返 2→1。
      // （用户报告：点运行后要过一会儿才执行——审查期往返是死窗口的一环。）
      final explainMemo = <String, Future<List<Map<String, dynamic>>>?>{};
      Future<List<Map<String, dynamic>>>? getExplainMemoized(String stmtSql) {
        return explainMemo.putIfAbsent(stmtSql, () {
          try {
            return provider.connection.dbService.getExplainPlan(stmtSql);
          } catch (_) {
            return null;
          }
        });
      }

      final context_ = SafetyContext(
        connectionId: connId,
        dbType: dbType!,
        database: server?.database,
        schemaCache: null, // MVP：无 schemaCache，SchemaCompatRule 跳过
        getRowCount: (tableName) async {
          try {
            return provider.connection.dbService.getTableRowCount(tableName);
          } catch (_) {
            return null;
          }
        },
        getColumns: (tableName) async => null, // MVP：无实时列查询
        // 第三阶段：EXPLAIN 能力注入。仅支持 EXPLAIN 的 SQL 库注入，
        // 其它库 null（EXPLAIN 规则跳过）。异常转 null（静默跳过）。
        getExplainPlan: _supportsExplain(dbType) ? getExplainMemoized : null,
      );

      // 审查（可能多条语句）。
      final statements = SQLParserService.split(sql);
      final List<safety.SafetyFinding> findings;
      if (statements.length > 1) {
        findings = await _safetyService!.reviewScript(
          statements.map((s) => s.sql).toList(),
          context_,
          // B3：传每条语句起始行号，让 finding 带 lineStart（行级红点）。
          statementLineStarts: statements.map((s) => s.lineStart).toList(),
        );
      } else {
        final single = await _safetyService!.review(sql, context_);
        // B3：单语句也要带语句起始行号——多行单语句的红点应落在
        // SELECT 所在行（文档 B3 第 3 行），而不是默认第 1 行。
        final lineStart = statements.isNotEmpty
            ? statements.first.lineStart
            : 0;
        if (lineStart > 0) {
          findings = [
            for (final f in single)
              safety.SafetyFinding(
                ruleId: f.ruleId,
                severity: f.severity,
                title: f.title,
                description: f.description,
                suggestion: f.suggestion,
                affectedTable: f.affectedTable,
                statementIndex: f.statementIndex,
                lineStart: lineStart,
              ),
          ];
        } else {
          findings = single;
        }
      }

      // D5: 更新状态栏安全审查指示器（无论是否弹窗，都给反馈）。
      SafetyReviewIndicator.instance.update(
        SafetyReviewResult(
          sqlPreview: sql.length > 40 ? '${sql.substring(0, 40)}...' : sql,
          findingCount: findings.length,
          hasHigh: findings.any((f) => f.severity == safety.Severity.high),
          hasMedium: findings.any((f) => f.severity == safety.Severity.medium),
          at: DateTime.now(),
        ),
      );

      // B3：聚合 finding 行号 → _safetyErrorsByLine（行级红点）。
      // severity 映射：high→error / medium→warning / low→info。
      // 单语句 finding.lineStart=0 时，默认标第 1 行（单语句审查的合理锚点）。
      // 只对完整编辑器文本审查时填充（选中片段执行的行号不对齐，跳过）。
      if (sql == _sqlController.text.trim()) {
        final safetyErrors = <int, ErrorSeverity>{};
        for (final f in findings) {
          if (f.severity == safety.Severity.low) continue; // low 不画红点（与弹窗策略一致）
          final line = f.lineStart > 0 ? f.lineStart : 1;
          final sev = f.severity == safety.Severity.high
              ? ErrorSeverity.error
              : ErrorSeverity.warning;
          final existing = safetyErrors[line];
          if (existing == null || sev.index > existing.index) {
            safetyErrors[line] = sev;
          }
        }
        if (mounted) {
          setState(() => _safetyErrorsByLine = safetyErrors);
        }
      }

      // 第四阶段 R17：统一执行门 DDL 路径到完整 SchemaAnalyzer.analyzeDdl。
      // P3 收口（2026-08-25）：整段脚本一次分析（firstMatch 只命中第一条
      // 目标表）→ 复用上方已 split 的 statements 逐条分析（预算内），
      // finding 带语句序号 + 行号。逐条失败降级跳过，不阻断执行。
      findings.addAll(
        await DdlScriptAnalyzer.analyzeScript(
          statements: statements,
          databaseType: dbType.name,
          executeQuery: (q) => provider.connection.dbService.executeQuery(q),
          getServerVersion: () async {
            final v = await provider.connection.dbService.getServerVersion();
            return v?['version'] as String?;
          },
          // B2：INPLACE 评级用用户配置的大表阈值（默认 100000）。
          inplaceMediumRowThreshold:
              provider.querySettings.safetyConfig.fullScanRowThreshold,
        ),
      );

      if (!SafetyReviewService.shouldShowDialog(findings)) {
        return null; // 无 medium/high → 静默通过
      }

      // 弹执行门。
      if (!mounted) return ExecutionGateAction.cancel;
      final action = await ExecutionGateDialog.show(
        context,
        findings: findings,
        statementCount: statements.length > 1 ? statements.length : null,
      );

      // applySuggestion → 替换编辑器 SQL + 还原横幅。
      if (action == ExecutionGateAction.applySuggestion) {
        final firstSuggestion = findings
            .firstWhere((f) => f.suggestion != null)
            .suggestion;
        if (firstSuggestion != null) {
          _applySuggestionWithBanner(sql, firstSuggestion);
        }
      }

      return action;
    } catch (e) {
      AppLogger.w('QueryEditor', '安全审查异常: $e');
      // T13 · D2 fail-closed：审查整体异常时，写类 SQL 不再静默放行——
      // 注入 review_degraded_fail_closed（high）finding 走既有执行门，
      // 由用户知情决定（high 语义本就是「弹窗置顶、建议修正或知情
      // 继续」，不硬编码 cancel 阻断）；读类维持不阻断。
      if (!SafetyReviewService.containsWriteStatement(sql)) {
        return null; // 读类：审查异常不阻断执行
      }
      try {
        if (!mounted) return ExecutionGateAction.cancel;
        // B1 开关（T14）：reviewFailClosedEnabled 关闭 → 回退纯 fail-open。
        if (!context
            .read<AppProvider>()
            .querySettings
            .safetyConfig
            .reviewFailClosedEnabled) {
          return null;
        }
        final action = await ExecutionGateDialog.show(
          context,
          findings: [SafetyReviewService.degradedFailClosedFinding()],
        );
        return action;
      } catch (e2) {
        // 执行门弹窗本身异常（如 context 失效）→ 退回旧行为，不阻断。
        AppLogger.w('QueryEditor', 'fail-closed 执行门弹窗异常，跳过: $e2');
        return null;
      }
    }
  }

  /// 按 [SafetyConfig] 构建审查引擎的规则列表。
  ///
  /// 每次执行前调用——规则对象无状态、构造零成本，即时反映用户在设置页
  /// 改的开关/阈值（无需 listen Provider 清缓存）。
  ///
  /// 门控说明：桌面端 Free/Pro 门控当前整体禁用。Pro 规则（FullTableScan/
  /// SqlInjection/ExplainFullScan/
  /// ExplainEstimatedRows）在此**无条件按 config 开关构造**，不加 license
  /// 检查——与既有「各 canXxx() 全返回 true」语义一致。门控恢复时在此加
  /// license 判断即可。
  SafetyReviewService _buildSafetyService(AppProvider provider) {
    final config = provider.querySettings.safetyConfig;
    final rules = <SafetyRule>[];

    if (config.schemaCompatEnabled) rules.add(SchemaCompatRule());
    if (config.missingLimitEnabled) {
      rules.add(MissingLimitRule(threshold: config.fullScanRowThreshold));
    }
    if (config.fullTableScanEnabled) rules.add(FullTableScanRule()); // Pro
    if (config.sqlInjectionEnabled) rules.add(SqlInjectionRule()); // Pro
    if (config.explainFullScanEnabled) {
      rules.add(
        ExplainFullScanRule(rowThreshold: config.fullScanRowThreshold),
      ); // Pro
    }
    if (config.explainEstimatedRowsEnabled) {
      rules.add(
        ExplainEstimatedRowsRule(rowThreshold: config.fullScanRowThreshold),
      ); // Pro
    }

    // B6 规则包（T14 收口，方案 §2.3 六条全默认开；severity 定级见
    // 各规则实现）。前五条是 SafetyRule 按开关构造；第六条
    // review_degraded_fail_closed 是引擎注入的 finding（非规则），
    // 经 failClosedForWrites 注入引擎与下方执行门 catch。
    if (config.executableCommentEnabled) rules.add(ExecutableCommentRule());
    if (config.tautologyPredicateEnabled) rules.add(TautologyPredicateRule());
    if (config.complementaryOrEnabled) rules.add(ComplementaryOrRule());
    if (config.writableCteEnabled) rules.add(WritableCteRule());
    if (config.fileWriteEnabled) rules.add(FileWriteRule());

    return SafetyReviewService(
      rules,
      failClosedForWrites: config.reviewFailClosedEnabled,
    );
  }

  /// 该数据库类型是否支持 EXPLAIN 审查（有专用解析器的库）。
  /// ExplainParser 支持 MySQL/Doris/PostgreSQL/SQLite；
  /// ClickHouse/SQL Server 落 generic（质量不可控），不注入。
  bool _supportsExplain(DatabaseType? dbType) {
    return dbType == DatabaseType.mysql ||
        dbType == DatabaseType.doris ||
        dbType == DatabaseType.postgresql ||
        dbType == DatabaseType.sqlite;
  }

  /// 替换编辑器 SQL 为建议版本，并显示还原横幅（D2）。
  ///
  /// 用 SnackBar 的「还原」按钮恢复原 SQL（10 秒内可见）。
  /// 注意：当前 `_sqlController.text =` 赋值不进入编辑器 undo 历史，
  /// Ctrl+Z 不可靠——完整 undo 支持需编辑器接入 UndoHistoryController，
  /// 列为 Part B 后续改进（见 tasks.md T13 备注）。
  void _applySuggestionWithBanner(String originalSql, String suggestedSql) {
    final oldText = _sqlController.text;
    _sqlController.text = _sqlController.text.replaceAll(
      originalSql,
      suggestedSql,
    );

    // 临时横幅（10 秒消失）。
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.editorSuggestionApplied),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: l10n.editorRestoreOriginalSql,
            onPressed: () {
              _sqlController.text = oldText;
            },
          ),
        ),
      );
    }
  }

  /// B2：把索引推荐的 DDL 填进编辑器（不自动执行）。
  ///
  /// 从查询计划对话框的「应用此索引」按钮触发。填进编辑器后用户手动点 Run，
  /// 届时走完整执行门（SafetyReviewService + SchemaAnalyzer.analyzeDdl，
  /// 含 B2 的 INPLACE 行数分级）。横幅提供 10 秒还原窗口（与
  /// _applySuggestionWithBanner 一致的 UX）。
  ///
  /// 不在此直接执行 DDL——避免在对话框里开辟绕过编辑器审查的新执行入口。
  void _applyDdlToEditor(String ddl) {
    final oldText = _sqlController.text;
    _sqlController.text = ddl;
    // 关闭查询计划对话框（栈顶即为该 dialog）。
    Navigator.of(context).pop();
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.editorIndexDdlFilled),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: l10n.editorRestoreOriginalSql,
            onPressed: () {
              _sqlController.text = oldText;
            },
          ),
        ),
      );
    }
  }

  Future<void> _stopQuery() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_isExecuting) return;

    // 查询尚未下发（安全审查/执行门阶段）：置停止标记 + 立即回落空闲态。
    // 不能走 cancelQuery——没有在途查询，只会弹「取消失败」误导；
    // 审查返回后 _executeQuery 看到 _stopRequested 自行中止。
    if (!_queryStarted) {
      _stopRequested = true;
      _stopElapsedTimer();
      if (mounted) setState(() => _isExecuting = false);
      return;
    }

    final provider = context.read<AppProvider>();
    final tab = provider.tab.activeTab;

    // 检查当前 Tab 是否处于事务中
    bool inTransaction = false;
    if (tab?.sessionId != null) {
      inTransaction = provider.dbService.isSessionInTransaction(
        tab!.sessionId!,
      );
    } else if (tab?.connectionId != null) {
      inTransaction = provider.dbService.isInTransaction(tab!.connectionId);
    }

    // 事务中需用户确认
    if (inTransaction) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.confirmCancelTransaction),
          content: Text(l10n.confirmCancelTransactionMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) return;
    }

    final success = await provider.cancelQuery();

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.cancelingQuery),
            backgroundColor: context.themeColors.warning,
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        AppErrorHandler.showErrorSnackBar(context, l10n.cancelQueryFailed);
      }
    }
  }

  Future<void> _saveQuery() async {
    await _saveCurrentQuery();
  }

  /// 将当前编辑器内容保存为连接级已保存查询（Ctrl/Cmd+S）。
  /// 空内容、无关联连接、只读模式或未连接时不执行任何操作。
  Future<void> _saveCurrentQueryAsSavedQuery() async {
    await _saveCurrentQuery();
  }

  /// 统一的保存查询入口：工具栏按钮与快捷键均走此逻辑。
  ///
  /// - 若当前 tab 已有 [QueryTab.savedQueryId]，直接保存（更新）。
  /// - 若当前 tab 没有 [QueryTab.savedQueryId]，弹出命名对话框后再保存。
  Future<void> _saveCurrentQuery() async {
    try {
      final provider = context.read<AppProvider>();
      if (provider.tabs.isEmpty || widget.tabIndex >= provider.tabs.length) {
        return;
      }

      final tab = provider.tabs[widget.tabIndex];
      final sql = _sqlController.text.trim();
      if (sql.isEmpty) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppErrorHandler.showErrorSnackBar(context, l10n.queryEmptyCannotSave);
        }
        return;
      }

      final connectionId =
          tab.connectionId ?? provider.connection.currentServer?.id;
      if (connectionId == null || connectionId.isEmpty) {
        if (mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            AppLocalizations.of(context)!.saveQueryNoConnection,
          );
        }
        return;
      }

      final server = provider.connection.savedConnections.firstWhere(
        (s) => s.id == connectionId,
        orElse: () =>
            provider.connection.currentServer ??
            DbServer(id: '', name: '', host: '', port: 0),
      );
      if (server.readOnly) {
        if (mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            AppLocalizations.of(context)!.saveQueryReadOnly,
          );
        }
        return;
      }

      final isUpdate = tab.savedQueryId != null;
      var title = tab.title;

      if (!isUpdate) {
        final suggestedTitle = _generateSavedQueryName(sql);
        final confirmedTitle = await _showSaveQueryNamingDialog(suggestedTitle);
        if (confirmedTitle == null || confirmedTitle.isEmpty) return;
        title = confirmedTitle;
      }

      final savedTab = QueryTab(
        id: tab.id,
        savedQueryId: tab.savedQueryId,
        title: title,
        sql: sql,
        isSaved: true,
        connectionId: connectionId,
        databaseName: tab.databaseName,
        databaseType: tab.databaseType ?? server.type,
      );

      await _persistSavedQuery(savedTab, title);
    } catch (e) {
      AppLogger.e('QueryEditorWidget', 'Failed to save query', e);
      // U17：此前未知异常只写日志，UI 无任何反馈（静默失败）。
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.saveQueryFailed(e.toString()),
        );
      }
    }
  }

  /// 发布当前编辑器内容到团队查询库（POST /api/queries）。与本地
  /// [_saveCurrentQuery] 正交：团队查询是 server-backed、workspace 共享的。
  /// 未连接 server / 空内容 / gated 时给出提示，不抛出。
  Future<void> _saveToTeamLibrary() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final provider = context.read<AppProvider>();
      if (provider.tabs.isEmpty || widget.tabIndex >= provider.tabs.length) {
        return;
      }
      final sql = _sqlController.text.trim();
      if (sql.isEmpty) {
        AppErrorHandler.showErrorSnackBar(context, l10n.queryEmptyCannotSave);
        return;
      }
      final suggestedTitle = _generateSavedQueryName(sql);
      final result = await _showSaveToTeamDialog(suggestedTitle);
      if (result == null) return;
      final api = SavedQueryApiService();
      await api.create(title: result.title, sqlText: sql, tags: result.tags);
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.saveToTeamSuccess(result.title),
        );
      }
    } on SavedQueryApiEntitlementException {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, l10n.saveToTeamGated);
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, e.toString());
      }
    }
  }

  /// 提交当前编辑器的 DDL 到 server 审批队列（POST /api/approvals）。打开
  /// SubmitApprovalDialog（只读预填当前 SQL + 选 target 连接 + gated 预检）。
  /// 未连接 server / 空内容 / 取消时不抛出。与 [_saveToTeamLibrary] 正交：
  /// 团队库是共享查询，审批是 DDL 变更治理流程。
  Future<void> _submitDdlForApproval() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final provider = context.read<AppProvider>();
      if (provider.tabs.isEmpty || widget.tabIndex >= provider.tabs.length) {
        return;
      }
      final sql = _sqlController.text.trim();
      if (sql.isEmpty) {
        AppErrorHandler.showErrorSnackBar(context, l10n.queryEmptyCannotSave);
        return;
      }
      final created = await showSubmitApprovalDialog(context, initialSql: sql);
      if (created == null) return; // cancelled
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, l10n.approvalSubmitSuccess);
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, e.toString());
      }
    }
  }

  /// 团队查询发布对话框：收集标题 + tags（逗号分隔）。取消返回 null。
  Future<({String title, List<String> tags})?> _showSaveToTeamDialog(
    String suggestedTitle,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: suggestedTitle);
    final tagsController = TextEditingController();
    final result = await showDialog<({String title, List<String> tags})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.saveToTeamTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.saveToTeamNameLabel,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsController,
                decoration: InputDecoration(
                  labelText: l10n.saveToTeamTagsLabel,
                  helperText: l10n.saveToTeamTagsHint,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.saveToTeamCancel),
          ),
          ElevatedButton(
            onPressed: () {
              final title = nameController.text.trim();
              if (title.isEmpty) return;
              final tags = tagsController.text
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
              Navigator.pop(ctx, (title: title, tags: tags));
            },
            child: Text(l10n.saveToTeamSubmit),
          ),
        ],
      ),
    );
    nameController.dispose();
    tagsController.dispose();
    return result;
  }

  /// 显示保存查询命名对话框，返回用户输入的名称；取消时返回 null。
  Future<String?> _showSaveQueryNamingDialog(String initialTitle) async {
    final controller = TextEditingController(text: initialTitle);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final dialogL10n = AppLocalizations.of(dialogCtx)!;
        return AlertDialog(
          backgroundColor: dialogCtx.themeColors.bgSecondary,
          title: Text(
            dialogL10n.saveQueryTitle,
            style: TextStyle(color: dialogCtx.themeColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: TextStyle(color: dialogCtx.themeColors.textPrimary),
                decoration: InputDecoration(
                  labelText: dialogL10n.queryName,
                  labelStyle: TextStyle(
                    color: dialogCtx.themeColors.textSecondary,
                  ),
                  hintText: dialogL10n.enterQueryName,
                  hintStyle: TextStyle(color: dialogCtx.themeColors.textMuted),
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppDesignSystem.space3),
              Text(
                dialogL10n.saveQueryHint,
                style: TextStyle(
                  color: dialogCtx.themeColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(dialogL10n.commonCancel),
            ),
            // U17：空标题时禁用保存——此前空文本点「保存」对话框直接关闭、
            // 保存静默中止，表现为「Ctrl+S 没反应」。
            ListenableBuilder(
              listenable: controller,
              builder: (ctx, _) {
                final canSave = controller.text.trim().isNotEmpty;
                return ElevatedButton(
                  onPressed: canSave
                      ? () => Navigator.pop(dialogCtx, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.themeColors.accentBlue,
                  ),
                  child: Text(dialogL10n.commonSave),
                );
              },
            ),
          ],
        );
      },
    );

    final text = controller.text.trim();
    // Dispose after the current frame to avoid accessing the controller while
    // the dialog's TextField is still being unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (result == true && text.isNotEmpty) {
      return text;
    }
    return null;
  }

  /// 持久化保存查询并显示结果提示。
  Future<void> _persistSavedQuery(QueryTab savedTab, String title) async {
    final provider = context.read<AppProvider>();
    final l10n = AppLocalizations.of(context)!;

    setState(() => _isSaving = true);
    try {
      final success = await provider.saveQuery(savedTab);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.querySaved(title)),
            backgroundColor: context.themeColors.success,
          ),
        );
      } else if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.saveQueryLimitReached),
            backgroundColor: context.themeColors.warning,
          ),
        );
      }
    } on DuplicateSavedQueryNameException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.savedQueryNameExists(e.title)),
            backgroundColor: context.themeColors.warning,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _generateSavedQueryName(String sql) {
    final firstLine = sql
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();
    if (firstLine.isNotEmpty) {
      return firstLine.length > 40
          ? '${firstLine.substring(0, 40)}...'
          : firstLine;
    }
    return 'Saved Query';
  }

  Future<void> _showSmartImportDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();

    if (!provider.tryDataImport(
      'data_import_${DateTime.now().millisecondsSinceEpoch}',
    )) {
      return;
    }

    final adapter = provider.dbService.currentAdapter;

    if (adapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseConnectDatabase),
          backgroundColor: context.themeColors.warning,
        ),
      );
      return;
    }

    // 获取当前 tab 的连接和数据库
    final currentTab =
        provider.tabs.isNotEmpty && widget.tabIndex < provider.tabs.length
        ? provider.tabs[widget.tabIndex]
        : null;

    // open-core Phase B.2：Smart Import 向导经 ProImportUi SPI 注入
    // （OSS=NoOp，门禁已拦截，此处兜底 no-op）。
    await context.read<ProImportUi>().openImportWizard(
      context,
      connectionId: currentTab?.connectionId,
      initialDatabase: currentTab?.databaseName,
      adapter: adapter,
      aiClient: AiService().client,
    );
  }

  Future<void> _showPIIMaskingDialog() async {
    await showDialog(
      context: context,
      builder: (context) => const PIIMaskingDialog(),
    );
  }

  Future<void> _showQueryPlan() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final adapter = provider.dbService.currentAdapter;
    final sql = _sqlController.text.trim();

    if (sql.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterSqlCode),
          backgroundColor: context.themeColors.warning,
        ),
      );
      return;
    }

    if (adapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseConnectDatabase),
          backgroundColor: context.themeColors.warning,
        ),
      );
      return;
    }

    try {
      final explainSql = 'EXPLAIN $sql';
      final currentTab =
          provider.tabs.isNotEmpty && widget.tabIndex < provider.tabs.length
          ? provider.tabs[widget.tabIndex]
          : null;
      final explainResults = await provider.dbService.executeQuery(
        explainSql,
        connectionId: currentTab?.connectionId,
        database: currentTab?.databaseName,
      );
      if (!mounted) return;

      final dbType = adapter.databaseType.name.toLowerCase();

      final report = QueryOptimizerService.analyzeQuery(
        rawExplainResults: explainResults,
        originalQuery: sql,
        databaseType: dbType,
      );

      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: context.themeColors.bgSecondary,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 700,
            height: 600,
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.network,
                      color: context.themeColors.accentPurple,
                    ),
                    const SizedBox(width: AppDesignSystem.space3),
                    Text(
                      l10n.queryExecutionPlan,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSize2xl,
                        fontWeight: FontWeight.w700,
                        color: context.themeColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        LucideIcons.x,
                        size: 20,
                        color: context.themeColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space4),
                Expanded(
                  child: SingleChildScrollView(
                    child: QueryPlanVisualizer(
                      report: report,
                      onApplyDdl: _applyDdlToEditor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        'Query plan analysis failed: $e',
      );
    }
  }

  void _formatSql() {
    final l10n = AppLocalizations.of(context)!;
    // 不支持格式化的连接（Mongo/Redis）直接返回，避免对 Mongo shell 误用 SQL 格式化器。
    if (!_supportsFormat()) return;
    final sql = _sqlController.text;
    if (sql.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterSqlCode),
          backgroundColor: context.themeColors.warning,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => CodeFormatterDialog(
        initialSql: sql,
        onFormatApplied: (formattedSql) {
          setState(() {
            _sqlController.text = formattedSql;
            _lastSql = formattedSql;
          });
          final provider = context.read<AppProvider>();
          if (provider.tabs.isNotEmpty &&
              widget.tabIndex < provider.tabs.length) {
            provider.updateTabSql(widget.tabIndex, formattedSql);
          }
        },
      ),
    );
  }

  void _quickFormat() {
    final l10n = AppLocalizations.of(context)!;
    // 不支持格式化的连接（Mongo/Redis）直接返回，避免对 Mongo shell 误用 SQL 格式化器。
    if (!_supportsFormat()) return;
    final sql = _sqlController.text;
    if (sql.trim().isEmpty) return;

    final formatted = _formatterService.format(sql, const FormatterOptions());
    setState(() {
      _sqlController.text = formatted;
      _lastSql = formatted;
    });

    final provider = context.read<AppProvider>();
    if (provider.tabs.isNotEmpty && widget.tabIndex < provider.tabs.length) {
      provider.updateTabSql(widget.tabIndex, formatted);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.sqlFormatted),
        backgroundColor: context.themeColors.success,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch formatRequested via a tiny invisible widget so this StatelessWidget
    // child only rebuilds when the flag actually changes — without wrapping
    // (and caching) the entire editor content, which would block setState-driven
    // local state updates (_isExecuting, _splitMode, _isSaving, etc.).
    return Column(
      children: [
        // DML Warning Banner (high risk)
        if (_dmlWarning != null)
          SafetyWarningBanner(
            warningText: AppLocalizations.of(
              context,
            )!.safetyDmlAllRowsWarning,
            detailText: _dmlWarning!.analysis.triggers
                .map((t) => t.name)
                .join(', '),
            onConfirm: () {
              setState(() => _dmlWarning = null);
              final sql = _getSqlToExecute();
              if (sql.isNotEmpty) {
                // Re-execute with DML warning bypass
                final appProvider = context.read<AppProvider>();
                final tab = appProvider.activeTab;
                appProvider.dbService
                    .executeQueryBypassDml(
                      sql,
                      connectionId: tab?.connectionId,
                      database: tab?.databaseName,
                      sessionId: tab?.sessionId,
                    )
                    .then((data) {
                      if (!mounted) return;
                      final activeTabId = appProvider.activeTab?.id;
                      if (activeTabId == null || activeTabId.isEmpty) return;
                      final results = [
                        ExecutionResult(
                          statement: SQLStatement(
                            index: 0,
                            sql: sql,
                            type: SQLType.other,
                            lineStart: 1,
                            lineEnd: 1,
                          ),
                          success: true,
                          data: data,
                          executionTime: Duration.zero,
                        ),
                      ];
                      // 写入两个结果源：executionResults（导出/AI 等读取）+ 子标签系统。
                      // ResultsWidget 只读子标签系统，原先仅写 executionResults 致成功结果不可见
                      // （见 .workflows/dml-warning-confirm-noop/01-diagnose.md RC-2）。
                      appProvider.updateTabExecutionResults(
                        appProvider.activeTabIndex,
                        results,
                      );
                      appProvider.tab.addResultToTab(
                        activeTabId,
                        results,
                        sql: sql,
                        executionTime: Duration.zero,
                      );
                      unawaited(
                        appProvider.addQueryHistory(
                          sql: sql,
                          affectedRows: data.length,
                          databaseType: _getTabDatabaseType(),
                          connectionId:
                              appProvider.connection.currentServer?.id,
                          connectionName:
                              appProvider.connection.currentServer?.name,
                        ),
                      );
                    })
                    .catchError((Object error) {
                      // 兜底 fire-and-forget 失败（修复 LATENT null-check 崩溃，缺陷#2）。
                      // 原先无 catchError，
                      // executeQueryBypassDml 抛错会成未处理 Future rejection 致应用崩溃。
                      AppLogger.e(
                        'QueryEditor',
                        'executeQueryBypassDml 失败',
                        error,
                      );
                      if (!mounted) return;
                      final activeTabId = appProvider.activeTab?.id;
                      if (activeTabId == null || activeTabId.isEmpty) return;
                      // 失败同样写入子标签系统，确保用户可见（原先仅写 executionResults 不可见）。
                      appProvider.tab.addErrorMessageToTab(
                        activeTabId,
                        error.toString(),
                        sql: sql,
                      );
                      unawaited(
                        appProvider.addQueryHistory(
                          sql: sql,
                          error: error.toString(),
                          databaseType: _getTabDatabaseType(),
                          connectionId:
                              appProvider.connection.currentServer?.id,
                          connectionName:
                              appProvider.connection.currentServer?.name,
                        ),
                      );
                    });
              }
            },
            onAddLimit: () {
              setState(() => _dmlWarning = null);
              final sql = _getSqlToExecute();
              final limited = sql.trim().endsWith(';')
                  ? '${sql.trim().substring(0, sql.trim().length - 1).trimRight()} LIMIT 1000;'
                  : '$sql LIMIT 1000';
              _sqlController.text = limited;
              context.read<AppProvider>().updateTabSql(
                widget.tabIndex,
                limited,
              );
            },
            onCancel: () {
              setState(() => _dmlWarning = null);
            },
          ),
        _FormatRequestListener(
          tabIndex: widget.tabIndex,
          onFormatRequested: _checkFormatRequested,
        ),
        Expanded(
          child: DragTarget<TableDragData>(
            onAcceptWithDetails: (details) {
              final d = details.data;
              // Use adapter for proper database-specific escaping instead of raw interpolation
              final p = context.read<AppProvider>();
              final adapter = p.dbService.getAdapter(d.connectionId);
              final sql =
                  adapter?.getDefaultBrowseQuery(d.tableName) ??
                  'SELECT * FROM "${d.tableName}" LIMIT 100;\n';
              _sqlController.insertAtCursor('$sql\n');
              if (widget.tabIndex >= 0 && p.tabs.length > widget.tabIndex) {
                p.updateTabSql(widget.tabIndex, _sqlController.text);
              }
            },
            builder: (context, candidate, rejected) {
              return Container(
                color: candidate.isNotEmpty
                    ? context.themeColors.accentBlue.withValues(alpha: 0.08)
                    : context.themeColors.bgPrimary,
                child: Column(
                  children: [
                    QueryEditorToolbar(
                      isExecuting: _isExecuting,
                      execProgress: _execProgress,
                      isSaving: _isSaving,
                      splitMode: _splitMode,
                      isInTransaction: _isInTransaction,
                      supportsTransaction: _supportsTransaction(),
                      isReadOnly: _isReadOnly(),
                      supportsFormat: _supportsFormat(),
                      onExecute: _executeQuery,
                      onStop: _stopQuery,
                      onFormat: _quickFormat,
                      onSave: _saveQuery,
                      onSaveToTeamLibrary: _saveToTeamLibrary,
                      onSubmitForApproval: _submitDdlForApproval,
                      onSmartImport: _supportsSmartImport()
                          ? _showSmartImportDialog
                          : null,
                      onShowPIISettings: _supportsPIIMasking()
                          ? _showPIIMaskingDialog
                          : null,
                      onQueryPlan: _supportsQueryPlan() ? _showQueryPlan : null,
                      onBeginTransaction: _beginTransaction,
                      onCommitTransaction: _commitTransaction,
                      onRollbackTransaction: _rollbackTransaction,
                      onSplitHorizontal: () =>
                          _toggleSplit(SplitMode.horizontal),
                      onSplitVertical: () => _toggleSplit(SplitMode.vertical),
                      onCloseSplit: () => _toggleSplit(SplitMode.none),
                      connectionSelector: _buildConnectionSelector(),
                      databaseSelector: _buildDatabaseSelector(),
                      limitSelector: _buildLimitSelector(),
                      timeoutSelector: _buildTimeoutSelector(),
                      commandPaletteButton: _buildCommandPaletteButton(),
                    ),
                    Expanded(child: _buildEditorContent()),
                    // C21 底部状态条（原型 editor-workspace 三段式）。
                    QueryEditorStatusBar(
                      cursorPosition: _cursorPos,
                      isExecuting: _isExecuting,
                      elapsed: _execElapsed,
                      languageLabel:
                          _editorLanguage == 'javascript' ? 'JavaScript' : 'SQL',
                      dbTypeLabel: _getTabDatabaseType()?.displayName,
                    ),
                  ],
                ),
              ); // Container
            },
          ), // DragTarget
        ),
      ],
    );
  }

  Widget _buildEditorContent() {
    if (_splitMode == SplitMode.none) {
      return _buildEditor();
    }

    final isHorizontal = _splitMode == SplitMode.horizontal;

    return Column(
      children: [
        if (isHorizontal) _buildSplitToolbar(),
        Expanded(
          child: isHorizontal
              ? Row(
                  children: [
                    Expanded(child: _buildEditor()),
                    _buildSplitDivider(isHorizontal: true),
                    Expanded(child: _buildSplitEditor()),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: _buildEditor()),
                    _buildSplitDivider(isHorizontal: false),
                    Expanded(child: _buildSplitEditor()),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSplitDivider({required bool isHorizontal}) {
    return GestureDetector(
      onPanUpdate: (details) {
        // Handle resize logic here if needed
      },
      child: MouseRegion(
        cursor: isHorizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: Container(
          width: isHorizontal ? 6 : double.infinity,
          height: isHorizontal ? double.infinity : 6,
          color: context.themeColors.bgTertiary,
          child: Center(
            child: Container(
              width: isHorizontal ? 2 : 40,
              height: isHorizontal ? 40 : 2,
              decoration: BoxDecoration(
                color: context.themeColors.borderColor,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitToolbar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      color: context.themeColors.bgSecondary,
      child: Row(
        children: [
          Text(
            l10n.split2Hint,
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          const Spacer(),
          ToolbarButton(
            icon: LucideIcons.x,
            label: l10n.toolbarClose,
            tooltip: l10n.toolbarClose,
            color: context.themeColors.textMuted,
            onPressed: () => _toggleSplit(_splitMode),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitEditor() {
    final l10n = AppLocalizations.of(context)!;
    if (_splitSqlController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      child: ReSqlEditor(
        controller: _splitSqlController!,
        language: _editorLanguage,
        hintText: l10n.split2Hint,
        onChanged: _onSplitTextChanged,
        onSelectionChanged: _onCursorPositionChanged,
      ),
    );
  }

  // ═══ C21 M3 上下文芯片：LIMIT / 超时 / 命令面板（原型 editor-workspace
  // 右端芯片集群；连接/库选择器沿用 _buildConnectionSelector 等既有实现）═══

  /// LIMIT 芯片——连接级行限覆盖。菜单：跟随设置 / 关闭 / 100 / 1000 /
  /// 3000 / 10000；显示当前有效值（覆盖优先，回落全局 autoLimit）。
  /// 连接 id 取 effectiveTabConnectionId（tab 绑定 ?? 活跃连接，与执行
  /// 链路同语义——只看 tab 绑定会在未绑定 tab 上静默无效）。
  Widget _buildLimitSelector() {
    return Selector<AppProvider, ({String? connectionId, int? override, bool globalEnabled, int globalValue})>(
      selector: (_, provider) {
        final connId = provider.effectiveTabConnectionId(widget.tabIndex);
        return (
          connectionId: connId,
          override: connId == null ? null : provider.queryRowLimitOverride(connId),
          globalEnabled: provider.autoLimitEnabled,
          globalValue: provider.autoLimitValue,
        );
      },
      builder: (context, data, _) {
        final l10n = AppLocalizations.of(context)!;
        // 有效显示：覆盖 0=强制关；>0=强制值；null=跟随全局（关/值）。
        final int? display = data.override == 0
            ? null
            : (data.override ?? (data.globalEnabled ? data.globalValue : null));
        final label = display == null ? 'LIMIT OFF' : 'LIMIT $display';
        final connId = data.connectionId;
        return _ContextChip(
          label: label,
          tooltip: l10n.toolbarLimitChipTooltip,
          menuItems: [
            _ChipMenuItem(value: null, label: l10n.toolbarChipFollowSettings),
            _ChipMenuItem(value: 0, label: l10n.toolbarChipOff),
            for (final v in const [100, 1000, 3000, 10000])
              _ChipMenuItem(value: v, label: 'LIMIT $v'),
          ],
          selectedValue: data.override,
          onSelected: connId == null
              ? null
              : (v) {
                  final provider = context.read<AppProvider>();
                  if (v == null) {
                    provider.clearConnectionQueryOverrideField(
                      connId,
                      rowLimit: true,
                    );
                  } else {
                    provider.setConnectionQueryOverride(connId, rowLimit: v);
                  }
                },
        );
      },
    );
  }

  /// 超时芯片——连接级查询超时覆盖。菜单：跟随连接 / 10 / 30 / 60 / 120 /
  /// 300 秒；显示当前有效秒数（覆盖 ?? 连接 timeoutSeconds）。
  Widget _buildTimeoutSelector() {
    return Selector<AppProvider, ({String? connectionId, int? override, int? effective})>(
      selector: (_, provider) {
        final connId = provider.effectiveTabConnectionId(widget.tabIndex);
        return (
          connectionId: connId,
          override: connId == null ? null : provider.dbService.queryOverride(connId)?.timeoutSeconds,
          effective: connId == null ? null : provider.queryTimeoutSeconds(connId),
        );
      },
      builder: (context, data, _) {
        final l10n = AppLocalizations.of(context)!;
        final connId = data.connectionId;
        return _ContextChip(
          label: data.effective == null ? '∞' : '${data.effective}s',
          tooltip: l10n.toolbarTimeoutChipTooltip,
          menuItems: [
            _ChipMenuItem(value: null, label: l10n.toolbarChipFollowConnection),
            for (final v in const [10, 30, 60, 120, 300])
              _ChipMenuItem(value: v, label: '${v}s'),
          ],
          selectedValue: data.override,
          onSelected: connId == null
              ? null
              : (v) {
                  final provider = context.read<AppProvider>();
                  if (v == null) {
                    provider.clearConnectionQueryOverrideField(
                      connId,
                      timeoutSeconds: true,
                    );
                  } else {
                    provider.setConnectionQueryOverride(
                      connId,
                      timeoutSeconds: v,
                    );
                  }
                },
        );
      },
    );
  }

  /// 命令面板入口（C21 M3：自 BreadcrumbBar 迁入，⌘K/Ctrl+K 徽章样式）。
  Widget _buildCommandPaletteButton() {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final onTap = widget.onCommandPalette;
    return Tooltip(
      message: l10n.searchPlaceholder,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: colors.borderLight),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 12, color: colors.textMuted),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                isMac ? '⌘K' : 'Ctrl+K',
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  color: colors.textMuted,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionSelector() {
    // C21 M3：连接选择器迁入工具栏右端芯片集群后常显（取代已退役的
    // BreadcrumbBar 连接显示）；toolbar 的 isWorkspaceMode 推断依赖本组件
    // 返回非 SizedBox。无连接时显示 selectConnection 占位，点击弹下拉。
    return Selector<
      AppProvider,
      ({String? connectionId, List<DbServer> connectedServers})
    >(
      selector: (_, provider) {
        final currentTab =
            provider.tabs.isNotEmpty && widget.tabIndex < provider.tabs.length
            ? provider.tabs[widget.tabIndex]
            : null;
        return (
          connectionId: currentTab?.connectionId,
          connectedServers: provider.savedConnections
              .where((s) => provider.isConnectionConnected(s.id))
              .toList(),
        );
      },
      builder: (context, data, _) {
        return InkWell(
          key: _connectionSelectorKey,
          onTap: () =>
              _showConnectionDropdown(data.connectedServers, data.connectionId),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.server,
                  color: context.themeColors.textMuted,
                  size: 12,
                ),
                const SizedBox(width: AppDesignSystem.space1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(
                    _getConnectionDisplayName(data.connectionId),
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: context.themeColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: context.themeColors.textMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getConnectionDisplayName(String? connectionId) {
    final l10n = AppLocalizations.of(context)!;
    if (connectionId == null) return l10n.selectConnection;
    final provider = context.read<AppProvider>();
    try {
      final server = provider.savedConnections.firstWhere(
        (s) => s.id == connectionId,
      );
      return server.name;
    } catch (e) {
      return l10n.selectConnection;
    }
  }

  void _showConnectionDropdown(
    List<DbServer> connectedServers,
    String? selectedId,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (connectedServers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noConnectedServer),
          backgroundColor: context.themeColors.warning,
        ),
      );
      return;
    }

    final buttonContext = _connectionSelectorKey.currentContext;
    if (buttonContext == null) return;

    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: context.themeColors.bgTertiary,
      items: connectedServers.map((server) {
        final isSelected = server.id == selectedId;
        return CompactPopupMenuItem<String>(
          value: server.id,
          child: Row(
            children: [
              // emoji→矢量图标+品牌色（F-37）
              Icon(
                server.type.typeIcon,
                size: 14,
                color: context.themeColors.brandColor(server.type),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  server.name,
                  style: TextStyle(
                    color: isSelected
                        ? context.themeColors.success
                        : context.themeColors.textPrimary,
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  LucideIcons.check,
                  size: 14,
                  color: context.themeColors.success,
                ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null && value != selectedId) {
        _switchConnection(value);
      }
    });
  }

  void _updateEditorLanguage() {
    final dbType = _getTabDatabaseType();
    final language = switch (dbType) {
      // Mongo shell 用 JavaScript 语法高亮（db.coll.find({...})），而非平铺 JSON。
      DatabaseType.mongodb => 'javascript',
      _ => 'sql',
    };
    if (_editorLanguage != language) {
      setState(() {
        _editorLanguage = language;
      });
    }
  }

  Future<void> _switchConnection(String connectionId) async {
    final provider = context.read<AppProvider>();
    // 切换成功才同步 tab 上下文（失败保持原连接，显示与执行一致）。
    // 工具栏下拉 = 用户对本 tab 上下文的显式设定：无条件覆写 + 绑定
    // （此后侧边栏导航不再劫持本 tab，方向 A）。
    if (await provider.switchToConnection(connectionId)) {
      provider.syncTabConnection(widget.tabIndex, connectionId);
      provider.bindTabContext(widget.tabIndex);
    }
    _updateEditorLanguage();
  }

  Widget _buildDatabaseSelector() {
    // C21 M3：同连接选择器，常显（面包屑退役后库显示唯一入口）。
    return Selector<
      AppProvider,
      ({String? connectionId, List<String> databases, String? selectedDb})
    >(
      selector: (_, provider) {
        final currentTab =
            provider.tabs.isNotEmpty && widget.tabIndex < provider.tabs.length
            ? provider.tabs[widget.tabIndex]
            : null;
        final connectionId = currentTab?.connectionId;
        return (
          connectionId: connectionId,
          databases: connectionId != null
              ? provider.getConnectionDatabases(connectionId)
              : <String>[],
          selectedDb: currentTab?.databaseName,
        );
      },
      builder: (context, data, _) {
        final l10n = AppLocalizations.of(context)!;
        return InkWell(
          key: _databaseSelectorKey,
          onTap: data.databases.isEmpty
              ? null
              : () => _showDatabaseDropdown(data.databases, data.selectedDb),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.database,
                  color: context.themeColors.textMuted,
                  size: 12,
                ),
                const SizedBox(width: AppDesignSystem.space1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Text(
                    data.selectedDb ?? l10n.selectDatabase,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: context.themeColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: context.themeColors.textMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDatabaseDropdown(List<String> databases, String? selectedDb) {
    final buttonContext = _databaseSelectorKey.currentContext;
    if (buttonContext == null) return;

    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: context.themeColors.bgTertiary,
      items: databases.map((db) {
        final isSelected = db == selectedDb;
        return CompactPopupMenuItem<String>(
          value: db,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  db,
                  style: TextStyle(
                    color: isSelected
                        ? context.themeColors.success
                        : context.themeColors.textPrimary,
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  LucideIcons.check,
                  size: 14,
                  color: context.themeColors.success,
                ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null && value != selectedDb) {
        _switchDatabase(value);
      }
    });
  }

  Future<void> _switchDatabase(String databaseName) async {
    final provider = context.read<AppProvider>();
    await provider.useDatabase(databaseName);
    provider.updateTabDatabase(widget.tabIndex, databaseName);
    // 工具栏选库 = 显式设定本 tab 上下文 → 绑定（同 _switchConnection）。
    provider.bindTabContext(widget.tabIndex);
  }

  void _insertTextAtCursor(String text) {
    // replaceSelection 语义：替换当前选区（无选区 = 光标处插入），
    // 可撤销，光标落在插入文本之后；变更经门面监听触发 _onTextChanged。
    _sqlController.insertAtCursor(text);
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      child: DragTarget<TableDragData>(
        onAcceptWithDetails: (details) {
          final provider = context.read<AppProvider>();
          final adapter = provider.dbService.getAdapter(
            details.data.connectionId,
          );
          final query =
              adapter?.getDefaultBrowseQuery(details.data.tableName) ??
              details.data.selectStatement;
          _insertTextAtCursor(query);
        },
        builder: (context, candidateData, rejectedData) {
          final isDragging = candidateData.isNotEmpty;
          return GestureDetector(
            onSecondaryTapUp: (details) =>
                _showContextMenu(details.globalPosition),
            child: Container(
              decoration: isDragging
                  ? BoxDecoration(
                      border: Border.all(
                        color: context.themeColors.accentBlue.withValues(
                          alpha: 0.5,
                        ),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    )
                  : null,
              child: _buildEnhancedEditor(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEnhancedEditor() {
    final l10n = AppLocalizations.of(context)!;
    final dbType = _getTabDatabaseType();
    final rawHint = switch (dbType) {
      DatabaseType.mongodb => l10n.editorHintTextMongodb,
      DatabaseType.redis => l10n.editorHintTextRedis,
      _ => l10n.editorHintText,
    };
    final hintText = Platform.isMacOS
        ? rawHint.replaceAll('Ctrl', '⌘')
        : rawHint;
    final provider = context.read<AppProvider>();
    return ReSqlEditor(
      controller: _sqlController,
      language: _editorLanguage,
      hintText: hintText,
      onChanged: _onTextChanged,
      onSelectionChanged: _onCursorPositionChanged,
      // T011 语法校验 + B3 安全审查行级红点合并（同行取最严重）。
      errors: _mergedErrorsByLine(),
      autocompleteResolver: _resolveAutocomplete,
      autocompleteEnabled: provider.autocompleteEnabled,
      snippetsEnabled: familyFor(_getTabDatabaseType()) != null,
      onSaveShortcut: _saveCurrentQueryAsSavedQuery,
    );
  }

  /// 合并语法校验 + 安全审查的行级错误（同行取 severity.index 最大）。
  Map<int, ErrorSeverity> _mergedErrorsByLine() {
    final merged = Map<int, ErrorSeverity>.from(_validationErrorsByLine);
    for (final entry in _safetyErrorsByLine.entries) {
      final existing = merged[entry.key];
      if (existing == null || entry.value.index > existing.index) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  void _showContextMenu(Offset position) {
    final hasSelection = _sqlController.hasSelection;
    final l10n = AppLocalizations.of(context)!;

    // 仅在支持格式化的连接（SQL 系）显示 Format 菜单项，与工具栏保持一致。
    final supportsFormat = _supportsFormat();

    final items = <ContextMenuItem>[
      ContextMenuItem(
        id: 'cut',
        label: l10n.menuCut,
        icon: LucideIcons.scissors,
        onTap: hasSelection ? () => _cutText() : null,
        enabled: hasSelection,
      ),
      ContextMenuItem(
        id: 'copy',
        label: l10n.menuCopy,
        icon: LucideIcons.copy,
        onTap: hasSelection ? () => _copyText() : null,
        enabled: hasSelection,
      ),
      ContextMenuItem(
        id: 'paste',
        label: l10n.menuPaste,
        icon: LucideIcons.clipboardPaste,
        onTap: () => _pasteText(),
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'select_all',
        label: l10n.menuSelectAll,
        icon: LucideIcons.textSelect,
        onTap: () => _selectAll(),
      ),
    ];

    if (supportsFormat) {
      items
        ..add(const ContextMenuItem.divider())
        ..add(
          ContextMenuItem(
            id: 'format',
            label: l10n.menuFormatSql,
            icon: LucideIcons.wandSparkles,
            onTap: () => _quickFormat(),
          ),
        )
        ..add(
          ContextMenuItem(
            id: 'format_options',
            label: l10n.formatterOptions,
            icon: LucideIcons.slidersHorizontal,
            onTap: () => _formatSql(),
          ),
        );
    }

    items
      ..add(const ContextMenuItem.divider())
      ..add(
        ContextMenuItem(
          id: 'execute',
          label: l10n.menuExecuteQuery,
          icon: LucideIcons.play,
          onTap: () => _executeQuery(),
        ),
      );

    ContextMenuUtils.show(context: context, position: position, items: items);
  }

  void _cutText() {
    if (_sqlController.hasSelection) {
      _sqlController.cut();
    }
  }

  void _copyText() {
    if (_sqlController.hasSelection) {
      _sqlController.copy();
    }
  }

  /// re_editor 原生粘贴（可撤销、行式插入），T02a 的 200K 分流拦截已随
  /// EditableText 路径一并退役。
  Future<void> _pasteText() async {
    _sqlController.paste();
  }

  void _selectAll() {
    _sqlController.selectAll();
  }
}

/// Tiny invisible widget that watches [AppProvider.formatRequested] and fires
/// [onFormatRequested] on the next frame when the flag is true.
///
/// Separated from the main editor build so that the editor content is **not**
/// wrapped in a [Selector]/[Consumer], whose child-caching would block
/// `setState`-driven local state updates (`_isExecuting`, `_splitMode`, etc.).
class _FormatRequestListener extends StatelessWidget {
  const _FormatRequestListener({
    required this.tabIndex,
    required this.onFormatRequested,
  });

  final int tabIndex;
  final VoidCallback onFormatRequested;

  @override
  Widget build(BuildContext context) {
    final formatRequested = context.watch<AppProvider>().formatRequested;
    if (formatRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onFormatRequested();
      });
    }
    return const SizedBox.shrink();
  }
}

/// C21 M3 上下文芯片菜单项。[value] null = 跟随（清除覆盖）；0 语义由
/// 调用方定义（LIMIT 芯片 = 强制关）。
class _ChipMenuItem {
  final int? value;
  final String label;

  const _ChipMenuItem({required this.value, required this.label});
}

/// C21 M3 上下文芯片（原型 editor-workspace 右端：bgTertiary 容器 +
/// border + chevron-down 下拉）。选择态打勾；值编码为字符串（'follow' /
/// 'off' / 数字）以规避 PopupMenuItem 的 null value 语义。
class _ContextChip extends StatelessWidget {
  final String label;
  final String? tooltip;
  final List<_ChipMenuItem> menuItems;
  final int? selectedValue;
  final void Function(int?)? onSelected;

  const _ContextChip({
    required this.label,
    this.tooltip,
    required this.menuItems,
    required this.selectedValue,
    this.onSelected,
  });

  String get _selectedKey => selectedValue == null
      ? 'follow'
      : (selectedValue == 0 ? 'off' : '$selectedValue');

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Icon(
            LucideIcons.chevronDown,
            size: 12,
            color: colors.textMuted,
          ),
        ],
      ),
    );

    final menu = PopupMenuButton<String>(
      tooltip: tooltip ?? label,
      offset: const Offset(0, 30),
      color: colors.bgTertiary,
      constraints: const BoxConstraints(minWidth: 140),
      initialValue: _selectedKey,
      onSelected: (key) {
        if (onSelected == null) return;
        final value = switch (key) {
          'follow' => null,
          'off' => 0,
          _ => int.tryParse(key),
        };
        onSelected!(value);
      },
      itemBuilder: (context) => [
        for (final item in menuItems)
          PopupMenuItem(
            value: item.value == null
                ? 'follow'
                : (item.value == 0 ? 'off' : '${item.value}'),
            height: 34,
            child: Row(
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textPrimary,
                  ),
                ),
                if (_isSelected(item)) ...[
                  const Spacer(),
                  Icon(
                    LucideIcons.check,
                    size: 14,
                    color: colors.accentBlue,
                  ),
                ],
              ],
            ),
          ),
      ],
      child: chip,
    );

    return tooltip == null ? menu : Tooltip(message: tooltip!, child: menu);
  }

  bool _isSelected(_ChipMenuItem item) =>
      (item.value == null
          ? 'follow'
          : (item.value == 0 ? 'off' : '${item.value}')) ==
      _selectedKey;
}
