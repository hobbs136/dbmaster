import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/database_models.dart' hide QueryTab;
// spec 041: panel 布局 / FilterBar 状态值模型
import '../models/panel_layout.dart';
import '../models/report_models.dart';
import '../models/filter_condition.dart';
import '../models/ai_tree_node_context.dart';
import '../models/table_maintenance_command.dart';
import '../models/connection_event.dart';
import '../models/dml_risk_models.dart';
import '../models/execution_result.dart';
import '../models/redis_function.dart';
import '../services/adapters/mongodb_adapter.dart';
import '../services/adapters/redis_adapter.dart';
import '../services/readonly_guard.dart';
import '../services/ai_quota_service.dart';
import '../models/pro_feature.dart';
import '../models/sql_statement.dart';
import '../models/tdengine_models.dart';
import '../services/database_service.dart';
import '../services/pro_module.dart';
import '../services/tab_session_store.dart';
import '../services/ai/mysql_ai_context_collector.dart';
import '../services/pii_masker.dart';
import '../services/ai_service.dart';
import '../services/ai/ai_service_localizations.dart';
import '../utils/app_logger.dart';
import '../utils/secret_redactor.dart';
import 'ai_config_provider.dart';
import 'connection_provider.dart';
import 'tab_provider.dart';
import 'query_history_provider.dart';
import 'ai_panel_provider.dart';
import 'sidebar_provider.dart';
import 'query_settings_provider.dart';
import 'recent_tables_provider.dart';
import 'task_provider.dart';
import 'execution_center_provider.dart';
import '../services/error_reporter.dart';

/// AppProvider - 应用状态 Facade
///
/// 委托给专门的 Provider：
/// - ConnectionProvider: 连接管理
/// - TabProvider: 标签页和查询执行
/// - QueryHistoryProvider: 查询历史
/// - AiPanelProvider: AI 面板
/// - AiConfigProvider: AI 配置
///
/// 这个类作为顶层协调者，处理需要多 Provider 协作的场景。
/// 单一职责的逻辑应该下沉到各自专门的 Provider 中。
class AppProvider extends ChangeNotifier {
  // ==================== 子 Provider ====================

  final ConnectionProvider connection;
  late final TabProvider tab;
  final QueryHistoryProvider queryHistory = QueryHistoryProvider();
  late final AiPanelProvider aiPanel;
  final SidebarProvider sidebar = SidebarProvider();

  /// 查询设置（独立 Provider）
  final QuerySettingsProvider querySettings = QuerySettingsProvider();

  /// 最近访问表（独立 Provider）
  final RecentTablesProvider recentTables = RecentTablesProvider();

  /// AI 配置（独立 Provider）
  final AiConfigProvider aiConfig = AiConfigProvider();

  /// Pro 能力模块（open-core SPI，构造注入；默认 [FreeProModule]）。
  /// 替代原硬持 PurchaseProvider 字段（修复宪法 I.8 禁 Provider 互引）。
  final ProModule proModule;

  /// 执行中心（错误历史 + 面板状态）——独立子 Provider
  final ExecutionCenterProvider executionCenter = ExecutionCenterProvider();

  /// AI 配额服务
  late final AiQuotaService _aiQuotaService;

  /// 待处理的升级提示（由 UI 层监听并展示购买对话框，见 home_screen.dart）
  String? _pendingUpgradeFeature;
  String? get pendingUpgradeFeature => _pendingUpgradeFeature;

  void setPendingUpgradeFeature(String feature) {
    _pendingUpgradeFeature = feature;
    notifyListeners();
  }

  void clearPendingUpgradeFeature() {
    _pendingUpgradeFeature = null;
    notifyListeners();
  }

  // ==================== 编辑器插入桥接 ====================
  /// 由 [_EditorResultsSplitState] 注册：把文本插入到当前活动查询编辑器的
  /// 光标处（供侧栏双击列名等外部触发）。
  /// 纯回调容器（非响应式 UI 状态），故 setter 不调用 [notifyListeners]；
  /// 用函数引用而非 GlobalKey，避免 Provider 层耦合 Widget。
  void Function(String)? insertIntoActiveEditor;

  // ==================== Free/Pro 限制 ====================

  /// 开发自测口子：仅 debug 构建生效（kDebugMode 为编译期常量，
  /// release 中该分支被 tree-shake 物理移除）。测试默认 false 走真实门禁。
  static bool devBypassGates = false;

  /// 单一咽喉：Pro = IAP 购买 ∥ 离线授权（debug 下可被 devBypassGates 短路）。
  bool get _isProUnlocked =>
      (kDebugMode && devBypassGates) || proModule.isPro;

  /// 数据库类型：8 种 Free 全部开放（有意决策，free_pro_gating.md §2 #1）
  bool isDatabaseTypeAllowed(DatabaseType type) => true;

  /// 是否可用 AI（Pro 无限，Free 月度配额 30 次内可用）
  Future<bool> canUseAi() => _aiQuotaService.hasQuota();

  /// AI 剩余配额（Pro 返回 -1 表示无限制）
  Future<int> getAiQuotaRemaining() => _aiQuotaService.getRemainingCount();

  /// 记录一次 AI 调用（Pro 不计）
  Future<void> recordAiUsage() => _aiQuotaService.recordUsage();

  /// Schema Diff 查看：Free 开放（有意，§2 #6）
  bool get canViewSchemaDiff => true;

  /// Schema Diff 同步：Pro 专属
  bool get canSyncSchemaDiff => _isProUnlocked;

  /// Data Import：Pro 专属
  bool get canUseDataImport => _isProUnlocked;

  /// Data Sync（跨库数据同步）：Pro 专属
  bool get canUseDataSync => _isProUnlocked;

  /// MongoDB 集群连接（副本集/分片）：Pro 专属（spec 044, PD-8）
  bool get canUseMongoCluster => _isProUnlocked;

  // ==================== 全免费客户端：门禁恒放行 ===================
  /// 全免费客户端——试用/门禁无操作。保留方法签名以维持调用方编译兼容。

  Future<void> ensureTrialInitialized() async {}

  ({ProFeature feature, int remaining})? get lastTrialConsumed => null;
  void clearLastTrialConsumed() {}

  /// AI 工具始终可用——全免费客户端无限制。
  Future<bool> _resolveAllowTools() async => true;

  /// 动作型门禁——全免费客户端恒放行。保留签名以维持调用方编译兼容。
  bool tryProAction(
    ProFeature feature, {
    required String actionId,
    required String upgradeFeatureKey,
  }) => true;

  bool trySchemaSync(String actionId) => true;
  bool tryDataImport(String actionId) => true;
  bool tryDataSync(String actionId) => true;
  bool tryMongoCluster(String actionId) => true;


  // ==================== 错误状态（跨 Provider 的全局错误） ====================

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ==================== PII 数据脱敏 ====================

  bool get piiMaskingEnabled => PIIMasker().enabled;

  void setPiiMaskingEnabled(bool value) {
    PIIMasker().enabled = value;
    notifyListeners();
  }

  void setPiiPatternEnabled(String pattern, bool enabled) {
    PIIMasker().setPatternEnabled(pattern, enabled);
    notifyListeners();
  }

  Map<String, bool> get piiPatternStates {
    return {
      for (final entry in PIIMasker().patterns.entries)
        entry.key: entry.value.enabled,
    };
  }

  /// 刷新指定数据库的侧边栏和实体面板
  void refreshDatabase(String connectionId, String databaseName) {
    invalidateDatabaseCache(connectionId, databaseName);
    loadDatabaseInfo(connectionId, databaseName, forceRefresh: true);
    notifyListeners();
  }

  // ==================== AI 浮层透明度（UI 状态，不持久化） ====================

  double _overlayOpacity = 1.0;
  static const double _minOverlayOpacity = 0.05;
  static const double _maxOverlayOpacity = 1.0;
  static const double _overlayOpacityStep = 0.05;

  double get overlayOpacity =>
      _overlayOpacity.clamp(_minOverlayOpacity, _maxOverlayOpacity);

  bool get isAiPanelOverlay => aiPanel.aiPanelFullscreen;

  void setAiPanelOverlay(bool value) {
    aiPanel.setAiPanelFullscreen(value);
  }

  void increaseOverlayOpacity() {
    _overlayOpacity = (_overlayOpacity + _overlayOpacityStep).clamp(
      _minOverlayOpacity,
      _maxOverlayOpacity,
    );
    notifyListeners();
  }

  void decreaseOverlayOpacity() {
    _overlayOpacity = (_overlayOpacity - _overlayOpacityStep).clamp(
      _minOverlayOpacity,
      _maxOverlayOpacity,
    );
    notifyListeners();
  }

  void setOverlayOpacity(double opacity) {
    _overlayOpacity = opacity.clamp(_minOverlayOpacity, _maxOverlayOpacity);
    notifyListeners();
  }

  // ==================== 事务状态 ====================

  bool _isInTransaction = false;
  bool get isInTransaction => _isInTransaction;

  StreamSubscription<String>? _transactionSubscription;
  StreamSubscription<ConnectionEvent>? _connectionEventSubscription;
  bool _pendingTransactionRollback = false;
  bool get hasPendingTransactionRollback => _pendingTransactionRollback;
  SessionRestored? _lastSessionRestored;
  SessionRestored? get lastSessionRestored => _lastSessionRestored;

  // ── U16：崩溃会话恢复 + 标签页自动落盘 ──
  TabSessionStore? _sessionStore;
  Timer? _sessionSaveTimer;
  bool _suppressSessionSave = false;
  int? _lastCrashRestoreTabCount;

  /// 上次异常退出后恢复的标签页数（恢复完成后置值，UI 弹一次性提示）。
  int? get lastCrashRestoreTabCount => _lastCrashRestoreTabCount;

  void clearCrashRestoreNotification() {
    _lastCrashRestoreTabCount = null;
    notifyListeners();
  }

  /// 测试注入：设置后 [initialize] 跳过 createDefault。
  @visibleForTesting
  TabSessionStore? testSessionStore;

  void clearTransactionRollbackWarning() {
    _pendingTransactionRollback = false;
    notifyListeners();
  }

  void clearSessionRestoredNotification() {
    _lastSessionRestored = null;
    notifyListeners();
  }

  void _updateTransactionState() {
    final wasInTransaction = _isInTransaction;
    _isInTransaction = connection.dbService.isInTransaction(null);
    if (wasInTransaction != _isInTransaction) {
      notifyListeners();
    }
  }

  Future<void> beginTransaction() async {
    try {
      await connection.dbService.beginTransaction();
      _isInTransaction = true;
      notifyListeners();
    } catch (e) {
      AppLogger.e('AppProvider', '开始事务失败: $e');
      rethrow;
    }
  }

  Future<void> commitTransaction() async {
    try {
      await connection.dbService.commit();
      _isInTransaction = false;
      notifyListeners();
    } catch (e) {
      AppLogger.e('AppProvider', '提交事务失败: $e');
      rethrow;
    }
  }

  Future<void> rollbackTransaction() async {
    try {
      await connection.dbService.rollback();
      _isInTransaction = false;
      notifyListeners();
    } catch (e) {
      AppLogger.e('AppProvider', '回滚事务失败: $e');
      rethrow;
    }
  }

  AppProvider({
    TaskProvider? taskProvider,
    ConnectionProvider? connectionProvider,
    ProModule? proModule,
  })  : connection = connectionProvider ??
            ConnectionProvider(
              dbService: DatabaseService(
                mongoClusterStrategy:
                    (proModule ?? FreeProModule()).mongoClusterStrategy,
              ),
            ),
        proModule = proModule ?? FreeProModule() {
    tab = TabProvider(connection.dbService);
    aiPanel = AiPanelProvider(
      dbService: connection.dbService,
      taskProvider: taskProvider,
      // open-core Phase B.1：Agent 运行器经 ProModule SPI 注入（OSS=FreeChatRunner，
      // Pro=完整工具循环 AiAgentService）。AppProvider 不直接 import
      // ai_agent_service.dart，使 OSS 构建可达图保持无 Pro 符号。
      agentFactory: this.proModule.createAgentRunner,
    );
    _aiQuotaService = AiQuotaService(isPro: () async => _isProUnlocked);
    // 全免费客户端——试用已移除，无需初始化试用服务。
    // open-core Phase B.2：注入 Pro 任务执行器注册器（import 等）。首次构造时
    // taskProvider 已传入则直接接好；后续 main.dart ProxyProvider 重建走
    // [updateTaskProvider] 再次回灌（保持幂等）。
    taskProvider?.setProTaskRegistrar(this.proModule.proTaskRegistrar);

    connection.addListener(_onConnectionChange);
    tab.addListener(_onTabChange);
    aiPanel.addListener(_onAiPanelChange);
    queryHistory.addListener(_onQueryHistoryChange);
    sidebar.addListener(_onSidebarChange);
    querySettings.addListener(_onQuerySettingsChange);
    recentTables.addListener(_onRecentTablesChange);
    aiConfig.addListener(_onAiConfigChange);
    this.proModule.addListener(_onPurchaseChange);
    // 挂接错误总线到执行中心
    ErrorReporter.instance.attach(executionCenter);
    executionCenter.addListener(_onExecutionCenterChange);

    // 加载查询设置和最近访问
    querySettings.load();
    recentTables.load();

    // 订阅事务事件
    _transactionSubscription = connection.dbService.transactionEvents.listen(
      (_) {
        _updateTransactionState();
      },
      onError: (error, stackTrace) {
        AppLogger.e(
          'AppProvider',
          'Transaction event stream error',
          error,
          stackTrace,
        );
      },
    );

    // 订阅连接事件（用于检测连接状态变更、事务回滚和会话恢复）
    _connectionEventSubscription = connection.dbService.events.listen(
      (event) {
        if (event is ConnectionDisconnected || event is ConnectionEstablished) {
          notifyListeners();
        } else if (event is TransactionRolledBack) {
          _pendingTransactionRollback = true;
          notifyListeners();
        } else if (event is SessionRestored) {
          _lastSessionRestored = event;
          notifyListeners();
        }
      },
      onError: (error, stackTrace) {
        AppLogger.e(
          'AppProvider',
          'Connection event stream error',
          error,
          stackTrace,
        );
      },
    );
  }

  void updateTaskProvider(TaskProvider taskProvider) {
    aiPanel.updateTaskProvider(taskProvider);
    // open-core Phase B.2：注入 Pro 任务执行器注册器（import 等）。
    // proModule 为同一 AppProvider 实例的 final 字段，taskProvider 由
    // main.dart ProxyProvider 每次重建时回灌——二者均非空，可安全访问。
    taskProvider.setProTaskRegistrar(proModule.proTaskRegistrar);
  }

  void _onExecutionCenterChange() {
    notifyListeners();
  }

  // ==================== 执行中心代理 ====================
  void openExecutionCenter() => executionCenter.open();
  void closeExecutionCenter() => executionCenter.close();
  void toggleExecutionCenter() => executionCenter.toggle();
  void setExecutionCenterHeight(double h) => executionCenter.setHeight(h);
  void setExecutionCenterTab(ExecutionCenterTab tab) =>
      executionCenter.setActiveTab(tab);
  void dismissExecutionCenterError(String id) =>
      executionCenter.dismissError(id);
  void clearExecutionCenterErrors() => executionCenter.clearErrors();

  void _onQueryHistoryChange() {
    notifyListeners();
  }

  void _onSidebarChange() {
    notifyListeners();
  }

  void _onQuerySettingsChange() {
    notifyListeners();
  }

  void _onRecentTablesChange() {
    notifyListeners();
  }

  void _onConnectionChange() {
    if (connection.errorMessage != _errorMessage) {
      _errorMessage = connection.errorMessage;
    }
    notifyListeners();
  }

  void _onTabChange() {
    if (tab.errorMessage != _errorMessage) {
      _errorMessage = tab.errorMessage;
    }
    _scheduleTabSessionSave();
    notifyListeners();
  }

  void _onAiPanelChange() {
    notifyListeners();
  }

  void _onAiConfigChange() {
    notifyListeners();
  }

  void _onPurchaseChange() {
    // Pro 状态变化（购买/授权/移除）→ 门面通知，UI 重新评估门禁显示
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    connection.clearError();
    tab.clearError();
    notifyListeners();
  }

  // ==================== 初始化 ====================

  Future<void> initialize() async {
    AppLogger.d('AppProvider', 'Initializing...');
    final sw = Stopwatch()..start();

    // 启动耗时分解（DEBUG）：哪一段慢一目了然（T29 后启动卡顿排查留桩）。
    Future<T> timed<T>(String name, Future<T> f) async {
      final at = sw.elapsedMilliseconds;
      final r = await f;
      AppLogger.d('AppProvider', 'init:$name +${sw.elapsedMilliseconds - at}ms');
      return r;
    }

    await Future.wait<dynamic>([
      timed('loadSavedConnections', connection.loadSavedConnections()),
      timed('loadSavedQueries', tab.loadSavedQueries()),
      timed('loadQueryHistory', queryHistory.loadQueryHistory()),
      timed('aiConfig', aiConfig.load()),
      timed('aiSessionManager', aiPanel.sessionManager.load()),
      timed('proModule', proModule.initialize()),
    ]);
    AppLogger.d('AppProvider', 'init:batch1 done at ${sw.elapsedMilliseconds}ms');

    await _initTabSession();
    AppLogger.d('AppProvider', 'init:tabSession done at ${sw.elapsedMilliseconds}ms');

    AppLogger.d('AppProvider', 'Initialization complete');
  }

  /// U16：崩溃检测 → 恢复标签页 → 启动自动落盘 + 退出标记。
  Future<void> _initTabSession() async {
    try {
      final store = testSessionStore ?? await TabSessionStore.createDefault();
      _sessionStore = store;
      final unclean = await store.wasUncleanExit();
      if (unclean) {
        final snapshot = await store.load();
        if (snapshot != null && snapshot.tabs.isNotEmpty) {
          // 只还原连接仍存在的 tab（连接被删的静默丢弃，防悬空引用）。
          final validIds = connection.savedConnections
              .map((c) => c.id)
              .toSet();
          final restorable = snapshot.tabs
              .where((t) =>
                  t.connectionId == null || validIds.contains(t.connectionId))
              .toList();
          if (restorable.isNotEmpty) {
            _suppressSessionSave = true;
            try {
              tab.restoreTabs(restorable, snapshot.activeTabIndex);
            } finally {
              _suppressSessionSave = false;
            }
            _lastCrashRestoreTabCount = restorable.length;
            AppLogger.i('AppProvider',
                'Crash session restored: ${restorable.length} tab(s)');
          }
        }
      }
      // 顺序敏感：先读旧标记再写 running=true，此后进程消失即视为异常退出。
      await store.markRunning();
    } catch (e, st) {
      AppLogger.w('AppProvider', 'Tab session init failed: $e\n$st');
    }
  }

  /// 标签页变更防抖落盘（编辑器侧已有 200ms 防抖，这里再加 800ms 合并连击）。
  void _scheduleTabSessionSave() {
    final store = _sessionStore;
    if (store == null || _suppressSessionSave) return;
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(const Duration(milliseconds: 800), () {
      final store = _sessionStore;
      if (store == null) return;
      unawaited(store.save(tab.tabs, tab.activeTabIndex));
    });
  }

  /// 正常退出路径（_WindowCloseGuard._doClose）调用：退出标记置 clean +
  /// 清空会话文件——用户在批量关闭确认里的「丢弃」决定必须被尊重。
  Future<void> prepareForCleanExit() async {
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = null;
    try {
      await _sessionStore?.markCleanExit();
    } catch (e) {
      AppLogger.w('AppProvider', 'prepareForCleanExit failed: $e');
    }
  }

  // ==================== 代理 Getters ====================

  List<String> get databases => connection.databases;

  List<QueryTab> get tabs => tab.tabs;

  int get activeTabIndex => tab.activeTabIndex;

  QueryTab? get activeTab => tab.activeTab;

  // spec 041: Panel 布局状态代理（per-tab 三面板状态机）。
  // UI 唯一入口——禁 Provider 间直引，UI 只认 AppProvider，内部转调 tab.xxx。
  PanelLayout panelLayoutFor(String tabId) => tab.panelLayoutFor(tabId);
  PanelLayout get activePanelLayout => tab.activePanelLayout;
  bool get activeSupportsFilterBar => tab.activeSupportsFilterBar;
  String? browseTargetFor(String tabId) => tab.browseTargetFor(tabId);
  List<FilterCondition> filterConditionsFor(String tabId) =>
      tab.filterConditionsFor(tabId);
  FilterCombinator filterCombinatorFor(String tabId) =>
      tab.filterCombinatorFor(tabId);
  void setPanelLayout(String tabId, PanelLayout layout) =>
      tab.setPanelLayout(tabId, layout);
  void updatePanelLayout(
    String tabId, {
    bool? editor,
    bool? filterBar,
    bool? results,
  }) =>
      tab.updatePanelLayout(
        tabId,
        editor: editor,
        filterBar: filterBar,
        results: results,
      );
  void setBrowseTarget(String tabId, String? qualifiedTableName) =>
      tab.setBrowseTarget(tabId, qualifiedTableName);
  void setFilterConditions(String tabId, List<FilterCondition> conditions) =>
      tab.setFilterConditions(tabId, conditions);
  void setFilterCombinator(String tabId, FilterCombinator combinator) =>
      tab.setFilterCombinator(tabId, combinator);

  /// 取某 tab 的 FilterBar 字段清单（走 dbService Facade，禁直接 new adapter）。
  /// browseTarget 缺失 / 无匹配 tab / 异常 时返回空列表。
  Future<List<DbColumn>> getTableColumnsForBrowse(String tabId) async {
    final target = tab.browseTargetFor(tabId);
    if (target == null) return const <DbColumn>[];
    final matching = tab.tabs.where((t) => t.id == tabId).toList();
    if (matching.isEmpty) return const <DbColumn>[];
    final cid = matching.first.connectionId;
    final dbName = matching.first.databaseName;
    if (cid == null) return const <DbColumn>[];
    try {
      // spec 041 US3 fix：用 service 级 getTableColumns 并传 databaseName。
      // MySQL 的 adapter.getTableColumns 用连接默认库（TABLE_SCHEMA=_currentConnection.database），
      // 浏览其他库的表时会查不到列 → FilterBar 误显「无字段」。service 级对 MySQL 走
      // `DESCRIBE \`db\`.\`table\``（按 databaseName 限定），与 entity panel 取列同路径。
      return await connection.dbService.getTableColumns(
        target,
        connectionId: cid,
        databaseName: dbName,
      );
    } catch (e) {
      AppLogger.e('AppProvider', 'getTableColumnsForBrowse 失败 tabId=$tabId', e);
      return const <DbColumn>[];
    }
  }

  bool get aiPanelOpen => aiPanel.aiPanelOpen;
  bool get aiPanelFullscreen => aiPanel.aiPanelFullscreen;
  List<AiMessage> get aiMessages => aiPanel.aiMessages;

  // AI Panel 状态代理
  String get selectedTable => aiPanel.selectedTable;
  String get searchQuery => aiPanel.searchQuery;

  // Tab 状态代理
  bool get formatRequested => tab.formatRequested;

  // DatabaseService 代理（方便访问）
  DatabaseService get dbService => connection.dbService;

  // ConnectionProvider 代理
  List<DbServer> get savedConnections => connection.savedConnections;
  List<String> get connectedIds => connection.connectedIds;
  int get activeConnectionCount => connection.activeConnectionCount;
  bool isConnectionConnected(String connectionId) =>
      connection.isConnectionConnected(connectionId);
  bool isConnectionConnecting(String connectionId) =>
      connection.isConnectionConnecting(connectionId);
  List<String> getConnectionDatabases(String connectionId) =>
      connection.getConnectionDatabases(connectionId);
  bool isShowingEmptyDatabases(String connectionId) =>
      connection.isShowingEmptyDatabases(connectionId);
  void toggleShowEmptyDatabases(String connectionId) =>
      connection.toggleShowEmptyDatabases(connectionId);
  int getTotalDatabaseCount(String connectionId) =>
      connection.getTotalDatabaseCount(connectionId);
  int getNonEmptyDatabaseCount(String connectionId) =>
      connection.getNonEmptyDatabaseCount(connectionId);
  Database? getCachedDatabase(String connectionId, String databaseName) =>
      connection.getCachedDatabase(connectionId, databaseName);

  // AI 配置代理
  String get selectedAiProvider => aiConfig.selectedAiProvider;
  String get selectedAiModel => aiConfig.selectedAiModel;
  Map<String, Map<String, String>> get aiApiConfigs => aiConfig.aiApiConfigs;
  bool get autoExecuteSql => aiConfig.autoExecuteSql;
  bool get autocompleteEnabled => aiConfig.autocompleteEnabled;
  Duration get aiTimeout => aiConfig.aiTimeout;

  // ==================== 查询上下文 getter ====================

  String? get currentQueryConnectionId => tab.activeTab?.connectionId;

  String? get currentQueryDatabaseName => tab.activeTab?.databaseName;

  String? get currentQuerySessionId => tab.activeTab?.sessionId;

  List<QueryTab> get currentQueryTabs => tab.tabs;

  int get currentQueryActiveTabIndex => tab.activeTabIndex;

  // ==================== 便捷的标签页操作 ====================

  Future<void> addNewTab({
    String? connectionId,
    String? databaseName,
    bool bindContext = false,
  }) async {
    final cid = connectionId ?? activeConnectionId;
    final db = databaseName ?? activeDatabaseName;
    if (cid != null && db != null) {
      // 「+」新建（无参）= 跟随型 tab（抄当前上下文但不绑定，侧边栏切
      // 连接时跟随）；显式传参的调用方按其语义绑定。
      await tab.openQueryTab(
        connectionId: cid,
        databaseName: db,
        bindContext: bindContext,
      );
      requestEditorFocus();
    }
  }

  String? get activeConnectionId {
    final t = tab.activeTab;
    if (t?.connectionId != null) return t!.connectionId;
    return connection.currentServer?.id;
  }

  String? get activeDatabaseName {
    final t = tab.activeTab;
    if (t?.databaseName != null) return t!.databaseName;
    return connection.currentServer?.database;
  }

  Future<void> openQueryTab(
    String connectionId,
    String databaseName, {
    String? sql,
  }) async {
    await tab.openQueryTab(
      connectionId: connectionId,
      databaseName: databaseName,
      sql: sql,
    );
    requestEditorFocus();
  }

  /// spec 041 US2：浏览表/视图数据专用入口。
  ///
  /// 以「editor 隐、FilterBar+results 显」预设开 tab + 自动执行默认查询，
  /// 用户右键浏览表数据即可直接看结果。**不改 `openQueryTab` 签名**（非浏览入口零改动）。
  Future<void> openBrowseDataTab(
    String connectionId,
    String databaseName,
    String qualifiedTableName, {
    bool isView = false,
  }) async {
    final adapter = connection.dbService.getAdapter(connectionId);
    final sql = adapter?.getDefaultBrowseQuery(qualifiedTableName) ??
        'SELECT * FROM "$qualifiedTableName" LIMIT 100;';
    final newTab = await tab.openQueryTab(
      connectionId: connectionId,
      databaseName: databaseName,
      sql: sql,
      title: qualifiedTableName,
    );
    // 浏览预设：隐 editor、results 隐到自动执行返回；FilterBar 仅 SQL 系——
    // 其 Apply 走 buildFilteredSelect（SQL WHERE 拼装），对 Mongo 等非 SQL
    // 会生成非法查询（集合浏览改文档渲染，字段级过滤待 FilterBar 支持
    // 非 SQL 方言后再放开）。
    final dbType = adapter?.databaseType;
    tab.setPanelLayout(
      newTab.id,
      PanelLayout(
        editorVisible: false,
        filterBarVisible: dbType == null || dbType.isSQL,
        resultsVisible: false,
      ),
    );
    tab.setBrowseTarget(newTab.id, qualifiedTableName);
    // 自动执行：[executeCurrentQueryAndRecord] 同步读 activeTab（即新 tab，无 await 间隙），
    // 故无需 post-frame / active-tab 守卫（对抗校验 D8 的更简实现）。
    // 其错误已写入结果子标签（addErrorMessageToTab），此处 catch 仅防未处理 rethrow。
    unawaited(_runBrowseAutoExecute(sql));
  }

  /// 浏览 tab 自动执行（复用全部守卫/行限 LIMIT 3000/历史/PII/结果子标签）。
  Future<void> _runBrowseAutoExecute(String sql) async {
    try {
      await executeCurrentQueryAndRecord(overrideSql: sql);
    } catch (e) {
      AppLogger.d('AppProvider', '浏览自动执行失败（已记录到结果子标签）: $e');
    }
  }

  /// 双击表/视图：打开 query 编辑器并预填默认浏览查询。
  ///
  /// 与 [openBrowseDataTab] 共用方言感知的 SQL 构造（`getDefaultBrowseQuery`），
  /// 区别：query 模式（editor 可见、results 首执前收起）、不自动执行。
  /// 进入 data 模式的唯一入口是右键「浏览数据」（[openBrowseDataTab]）。
  Future<void> openTableQueryTab(
    String connectionId,
    String databaseName,
    String qualifiedTableName,
  ) async {
    final adapter = connection.dbService.getAdapter(connectionId);
    final sql =
        adapter?.getDefaultBrowseQuery(qualifiedTableName) ??
        'SELECT * FROM "$qualifiedTableName" LIMIT 100;';
    await tab.openQueryTab(
      connectionId: connectionId,
      databaseName: databaseName,
      sql: sql,
      title: qualifiedTableName,
    );
    requestEditorFocus();
  }

  Future<void> closeTab(int index) async => tab.closeTab(index);

  Future<void> forceCloseTab(int index) async => tab.forceCloseTab(index);

  void setActiveTab(int index) => tab.setActiveTab(index);

  void updateTabSql(int index, String sql) => tab.updateTabSql(index, sql);

  void renameTab(int index, String title) => tab.renameTab(index, title);

  // 2026-08-27 修复：五月 workspace 实验（ad792732）把这三个代理抽成空
  // stub，但该实验早已不门控本路径（toolbar 的 isWorkspaceMode 推断恒
  // false），编辑器连接/库下拉与 AI 面板上下文应用仍按「tab 私有上下文」
  // 调它们——静默失效（工具栏显示与执行库不随切换更新）。恢复真实代理。
  void updateTabConnection(int index, String? connectionId) =>
      tab.updateTabConnection(index, connectionId);
  void updateTabDatabase(int index, String? databaseName) =>
      tab.updateTabDatabase(index, databaseName);
  void updateTabDatabaseType(int index, DatabaseType? databaseType) =>
      tab.updateTabDatabaseType(index, databaseType);

  /// switchToConnection 成功后的活跃 tab 上下文同步：connectionId +
  /// databaseType + 默认库（旧库不在新连接上，回落第一个库；树节点显式
  /// 选库的入口随后可再覆写 databaseName）。执行链读 tab 私有字段
  /// （跨连接路由修复钉定），显示与执行必须同源同步。
  void syncTabConnection(int index, String connectionId) {
    if (index < 0 || index >= tabs.length) return;
    updateTabConnection(index, connectionId);
    final saved = savedConnections;
    final server = saved.any((s) => s.id == connectionId)
        ? saved.firstWhere((s) => s.id == connectionId)
        : connection.currentServer;
    if (server != null) {
      updateTabDatabaseType(index, server.type);
    }
    final databases = getConnectionDatabases(connectionId);
    if (databases.isNotEmpty) {
      updateTabDatabase(index, databases.first);
    }
  }

  /// 将 tab 上下文标记为用户显式绑定（工具栏下拉选连接/选库后调用）——
  /// 此后 [switchToConnection] 的活跃 tab 跟随不再覆写该 tab。
  void bindTabContext(int index) => tab.bindTabContext(index);

  /// 侧边栏/快速搜索导航的跟随式选库：仅未绑定上下文的活跃 tab 跟随
  /// （方向 A）。已绑定 tab 的库芯片与执行库保持用户显式设定的值。
  void followActiveTabDatabase(String databaseName) {
    final active = tab.activeTab;
    if (active == null || active.isContextBound) return;
    updateTabDatabase(tab.activeTabIndex, databaseName);
  }

  // TabProvider 方法代理
  void updateTabExecutionResults(int index, List<ExecutionResult> results) {
    tab.updateTabExecutionResults(index, results);
  }

  void formatCurrentSql() {
    // formatCurrentSql 设置全局 _formatRequested flag，QueryEditor 通过 AppProvider.formatRequested 读取
    // Workspace 模式下也走此路径，因为 AppProvider.activeTabIndex / activeTab 已兼容 workspace
    tab.formatCurrentSql();
  }

  void clearFormatRequested() => tab.setFormatRequested(false);

  Future<bool> cancelQuery({String? connectionId}) async {
    final currentTab = activeTab;
    final effectiveConnectionId = connectionId ?? currentTab?.connectionId;
    return tab.cancelQuery(connectionId: effectiveConnectionId);
  }

  Future<void> addTab(QueryTab newTab) async {
    final cid = newTab.connectionId;
    final db = newTab.databaseName;
    if (cid != null && db != null) {
      final opened = await tab.openQueryTab(
        connectionId: cid,
        databaseName: db,
        sql: newTab.sql,
      );
      if (newTab.title.isNotEmpty && !newTab.isAutoTitle) {
        final idx = tab.tabs.indexWhere((t) => t.id == opened.id);
        if (idx >= 0) tab.renameTab(idx, newTab.title);
      }
    }
  }

  // QueryHistoryProvider 代理
  Future<void> addQueryHistory({
    required String sql,
    int? executionTime,
    int? affectedRows,
    String? database,
    String? error,
    DatabaseType? databaseType,
    String? connectionId,
    String? connectionName,
  }) => queryHistory.addQueryHistory(
    sql: sql,
    executionTime: executionTime ?? 0,
    affectedRows: affectedRows ?? 0,
    database: database,
    databaseType: databaseType,
    error: error,
    connectionId: connectionId ?? connection.currentServer?.id ?? '',
    connectionName: connectionName ?? connection.currentServer?.name,
  );

  // ==================== 便捷的分组操作 ====================
  List<ConnectionGroup> get connectionGroups => connection.connectionGroups;
  Future<void> addConnectionGroup(ConnectionGroup group) =>
      connection.addConnectionGroup(group);
  Future<void> deleteConnectionGroup(String groupId) =>
      connection.deleteConnectionGroup(groupId);
  Future<void> renameConnectionGroup(String groupId, String newName) =>
      connection.renameConnectionGroup(groupId, newName);
  Future<void> moveConnectionToGroup(String connectionId, String? groupId) =>
      connection.moveConnectionToGroup(connectionId, groupId);

  // ==================== 便捷的连接操作 ====================

  /// 保存连接（open-core：连接数不限）
  Future<void> saveConnection(DbServer server) async {
    await connection.saveConnection(server);
  }

  Future<bool> connectToServer(DbServer server) async {
    return connection.connectToServer(server);
  }

  /// 连接切换统一入口：成功后同步**活跃 tab** 上下文（connectionId +
  /// databaseType + 默认库）。执行链读 tab 私有字段（跨连接路由修复钉定），
  /// 显示与执行必须同源同步——否则 query 工具栏芯片停在原连接（2026-08-27
  /// bug）。所有切换入口（侧边栏点击 / 工具栏下拉 / 连接对话框 / 快速
  /// 搜索 / 树节点）都走本方法。
  ///
  /// 方向 A（2026-09-04）：仅**未绑定**上下文的活跃 tab 跟随（「+」新建
  /// 空白 tab 等）；已绑定 tab（isContextBound——双击表打开 / 工具栏下拉
  /// 显式选过 / 恢复的历史 tab）不被侧边栏导航劫持，per-tab 隔离对活跃
  /// tab 同样成立。工具栏下拉等显式绑定动作走 [syncTabConnection] +
  /// [bindTabContext]（无条件覆写）。
  Future<bool> switchToConnection(String connectionId) async {
    final ok = await connection.switchToConnection(connectionId);
    if (ok) {
      final active = tab.activeTab;
      if (active == null || !active.isContextBound) {
        syncTabConnection(activeTabIndex, connectionId);
      }
    }
    return ok;
  }

  Future<void> disconnectConnection({String? connectionId}) async {
    final id = connectionId ?? connection.currentServer?.id;
    if (id != null) {
      await tab.closeTabsForConnection(id);
    }
    await connection.disconnectConnection(connectionId: connectionId);
  }

  Future<void> changeDatabase(String dbName, {String? connectionId}) async {
    await connection.changeDatabase(dbName, connectionId: connectionId);
  }

  Future<void> useDatabase(String dbName, {String? connectionId}) async {
    await connection.dbService.useDatabase(dbName, connectionId: connectionId);
    await connection.changeDatabase(dbName, connectionId: connectionId);
  }

  Future<void> _syncDatabase(String dbName) async {
    connection.dbService.updateServerDatabase(dbName);
  }

  String? _extractUseDatabaseName(String sql) {
    final trimmed = sql.trim();
    final regex = RegExp(
      r'^[Uu][Ss][Ee]\s+(?:`([^`]+)`|"([^"]+)"|(\S+))\s*;?\s*$',
    );
    final match = regex.firstMatch(trimmed);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }

  // ConnectionProvider 异步方法代理
  Future<Database?> loadDatabaseInfo(
    String connectionId,
    String databaseName, {
    bool forceRefresh = false,
    bool schemasOnly = false,
  }) => connection.loadDatabaseInfo(
    connectionId,
    databaseName,
    forceRefresh: forceRefresh,
    schemasOnly: schemasOnly,
  );

  void invalidateDatabaseCache(String connectionId, String databaseName) =>
      connection.invalidateDatabaseCache(connectionId, databaseName);

  Future<void> loadServerStatus(String connectionId) =>
      connection.loadServerStatus(connectionId);

  Future<void> loadGlobalVariables(String connectionId) =>
      connection.loadGlobalVariables(connectionId);

  Future<void> loadServerUsers(String connectionId) =>
      connection.loadServerUsers(connectionId);

  Future<void> loadProcessList(String connectionId) =>
      connection.loadProcessList(connectionId);

  Map<String, dynamic>? getServerStatus(String connectionId) =>
      connection.getServerStatus(connectionId);

  Map<String, dynamic>? getGlobalVariables(String connectionId) =>
      connection.getGlobalVariables(connectionId);

  List<Map<String, dynamic>>? getServerUsers(String connectionId) =>
      connection.getServerUsers(connectionId);

  List<Map<String, dynamic>>? getProcessList(String connectionId) =>
      connection.getProcessList(connectionId);

  Future<bool> killProcess(String connectionId, int processId) =>
      connection.killProcess(connectionId, processId);

  ReplicationStatus? getReplicationStatus(String connectionId) =>
      connection.getReplicationStatus(connectionId);

  Future<void> loadReplicationStatus(String connectionId) =>
      connection.loadReplicationStatus(connectionId);

  Map<String, dynamic>? getEngineStatus(String connectionId) =>
      connection.getEngineStatus(connectionId);

  Future<void> loadEngineStatus(String connectionId) =>
      connection.loadEngineStatus(connectionId);

  void startProcessListAutoRefresh(String connectionId, {Duration? interval}) =>
      connection.startProcessListAutoRefresh(
        connectionId,
        interval: interval ?? const Duration(seconds: 10),
      );

  void stopProcessListAutoRefresh(String connectionId) =>
      connection.stopProcessListAutoRefresh(connectionId);

  int? getProcessListAutoRefreshInterval(String connectionId) =>
      connection.getProcessListAutoRefreshInterval(connectionId);

  Future<void> loadSavedConnections() => connection.loadSavedConnections();

  Future<void> cloneConnection(DbServer server) =>
      connection.cloneConnection(server);

  Future<void> deleteConnection(String id) async {
    await tab.closeTabsForConnection(id);
    await connection.deleteConnection(id);
  }

  Future<void> cancelConnect({String? connectionId}) async {
    final id = connectionId ?? connection.currentServer?.id;
    if (id != null) {
      await tab.closeTabsForConnection(id);
      // 先达底层取消在途连接（completer 标记 + 清连接态）——否则取消只做了
      // disconnect（对在途连接是 no-op），HTTP 链会跑到 30s 超时才松手
      // （T29 走查：密码弹窗取消后卡死的修复）。
      connection.dbService.cancelConnect(id);
    }
    await connection.disconnectConnection(connectionId: connectionId);
  }

  // ==================== Redis 信息代理 ====================

  Future<void> loadRedisServerInfo(String connectionId) =>
      connection.loadRedisServerInfo(connectionId);

  Future<void> loadRedisMemoryInfo(String connectionId) =>
      connection.loadRedisMemoryInfo(connectionId);

  Future<void> loadRedisClientInfo(String connectionId) =>
      connection.loadRedisClientInfo(connectionId);

  Future<void> loadRedisStats(String connectionId) =>
      connection.loadRedisStats(connectionId);

  Future<void> loadRedisKeyspaceInfo(String connectionId) =>
      connection.loadRedisKeyspaceInfo(connectionId);

  Future<void> loadRedisConfig(String connectionId) =>
      connection.loadRedisConfig(connectionId);

  Future<void> loadRedisSlowLog(String connectionId) =>
      connection.loadRedisSlowLog(connectionId);

  Future<void> loadRedisDatabaseKeyInfo(String connectionId, String dbName) =>
      connection.loadRedisDatabaseKeyInfo(connectionId, dbName);

  Future<void> loadRedisTTLKeys(
    String connectionId,
    String dbName, {
    int thresholdSeconds = 300,
  }) => connection.loadRedisTTLKeys(
    connectionId,
    dbName,
    thresholdSeconds: thresholdSeconds,
  );

  Future<void> loadRedisDBStats(String connectionId, String dbName) =>
      connection.loadRedisDBStats(connectionId, dbName);

  Future<List<String>> searchRedisKeys(
    String pattern, {
    required String connectionId,
  }) => connection.searchRedisKeys(pattern, connectionId: connectionId);

  Map<String, String>? getRedisServerInfo(String connectionId) =>
      connection.getRedisServerInfo(connectionId);

  Map<String, String>? getRedisMemoryInfo(String connectionId) =>
      connection.getRedisMemoryInfo(connectionId);

  Map<String, dynamic>? getRedisClientInfo(String connectionId) =>
      connection.getRedisClientInfo(connectionId);

  Map<String, String>? getRedisStats(String connectionId) =>
      connection.getRedisStats(connectionId);

  Map<String, Map<String, dynamic>>? getRedisKeyspaceInfo(
    String connectionId,
  ) => connection.getRedisKeyspaceInfo(connectionId);

  Map<String, String>? getRedisConfig(String connectionId) =>
      connection.getRedisConfig(connectionId);

  Future<void> loadRedisReplication(String connectionId) =>
      connection.loadRedisReplication(connectionId);

  Map<String, String>? getRedisReplicationInfo(String connectionId) =>
      connection.getRedisReplicationInfo(connectionId);

  Future<bool> setRedisConfig(
    String connectionId,
    Map<String, String> kv,
  ) =>
      connection.setRedisConfig(connectionId, kv);

  List<Map<String, dynamic>>? getRedisSlowLog(String connectionId) =>
      connection.getRedisSlowLog(connectionId);

  Map<String, dynamic>? getRedisDatabaseKeyInfo(
    String connectionId,
    String dbName,
  ) => connection.getRedisDatabaseKeyInfo(connectionId, dbName);

  Map<String, dynamic>? getRedisTTLKeys(
    String connectionId,
    String dbName,
  ) => connection.getRedisTTLKeys(connectionId, dbName);

  Map<String, dynamic>? getRedisDBStats(String connectionId, String dbName) =>
      connection.getRedisDBStats(connectionId, dbName);

  Future<dynamic> evalRedisLua(
    String script, {
    required String connectionId,
    List<String> keys = const [],
    List<String> args = const [],
    String? sha,
  }) {
    return connection.dbService.evalRedisLua(
      script,
      connectionId: connectionId,
      keys: keys,
      args: args,
      sha: sha,
    );
  }

  Future<List<RedisFunctionLibrary>> getRedisFunctions({
    required String connectionId,
  }) {
    return connection.dbService.getRedisFunctions(connectionId: connectionId);
  }

  RedisAdapter? getRedisAdapter(String connectionId) {
    final adapter = connection.dbService.getAdapter(connectionId);
    if (adapter is RedisAdapter) return adapter;
    return null;
  }

  // ==================== 分页查询 ====================

  Future<({List<String> items, int total})> getTablesPaginated({
    String? connectionId,
    String? sessionId,
    String? databaseName,
    int page = 1,
    int pageSize = 100,
    String? search,
  }) {
    return connection.dbService.getTablesPaginated(
      connectionId: connectionId,
      sessionId: sessionId,
      databaseName: databaseName,
      page: page,
      pageSize: pageSize,
      search: search,
    );
  }

  Future<({List<DbTableMetadata> items, int total})>
  getTablesWithMetadataPaginated({
    String? connectionId,
    String? sessionId,
    String? databaseName,
    int page = 1,
    int pageSize = 100,
    String? search,
  }) {
    return connection.dbService.getTablesWithMetadataPaginated(
      connectionId: connectionId,
      sessionId: sessionId,
      databaseName: databaseName,
      page: page,
      pageSize: pageSize,
      search: search,
    );
  }

  // ==================== 查询执行（带历史记录） ====================

  Future<List<ExecutionResult>> executeCurrentQueryAndRecord({
    String? overrideSql,
    bool skipDdlAnalysis = false,
    void Function(int current, int total)? onStatementProgress,
  }) async {
    final currentTab = activeTab;
    if (currentTab == null) return [];

    final sqlToExecute = overrideSql ?? currentTab.sql;
    if (sqlToExecute.isEmpty) return [];

    try {
      final startTime = DateTime.now();
      final results = await tab.executeCurrentQuery(
        overrideSql: sqlToExecute,
        connectionId: currentQueryConnectionId,
        databaseName: currentQueryDatabaseName,
        sessionId: currentQuerySessionId,
        skipDdlAnalysis: skipDdlAnalysis,
        onStatementProgress: onStatementProgress,
      );
      final executionTime = DateTime.now().difference(startTime).inMilliseconds;

      // Sync database state if USE statement was executed successfully
      for (final result in results) {
        if (result.success) {
          final useDb = _extractUseDatabaseName(result.statement.sql);
          if (useDb != null) {
            await _syncDatabase(useDb);
            // Workspace 模式下不切换当前 Tab 的数据库，保持 Workspace 上下文固定
            break;
          }
        }
      }

      // 更新结果到当前 Tab
      final targetIndex = activeTabIndex;
      tab.updateTabExecutionResults(targetIndex, results);
      // 新结果子标签系统（per-tab 隔离，切换 Tab 时各自保留）
      final execDuration = Duration(milliseconds: executionTime);
      tab.addResultToTab(
        currentTab.id,
        results,
        sql: sqlToExecute,
        executionTime: execDuration,
      );

      final totalRows = results
          .where((r) => r.hasData)
          .fold<int>(0, (sum, r) => sum + r.data!.length);

      await queryHistory.addQueryHistory(
        sql: sqlToExecute,
        executionTime: executionTime,
        affectedRows: totalRows,
        database: currentQueryDatabaseName,
        databaseType: connection.currentServer?.type,
        connectionId: connection.currentServer?.id ?? '',
        connectionName: connection.currentServer?.name,
      );

      return results;
    } on DmlWarningRequiredException {
      // 控制流信号：高风险 DML 需弹非阻塞警告横幅，交由 QueryEditor 处理。
      // 非查询错误——若在此记录为错误子标签，结果面板会显示
      // "Query failed, DmlWarningRequiredException(...)"（见 01-diagnose.md RC-1）。
      rethrow;
    } on DmlConfirmationRequiredException {
      // 控制流信号：关键风险 DML 需模态确认，非查询错误。
      rethrow;
    } on DdlConfirmationRequiredException {
      // 控制流信号：DDL 影响分析需确认，非查询错误。
      rethrow;
    } on ReadOnlyBlockedException {
      // 只读连接写拦截：控制流信号，非查询错误——交由 UI catch 显示本地化提示。
      rethrow;
    } catch (e) {
      // 记录错误到结果子标签
      if (currentTab.id.isNotEmpty) {
        tab.addErrorMessageToTab(
          currentTab.id,
          e.toString(),
          sql: sqlToExecute,
        );
      }

      await queryHistory.addQueryHistory(
        sql: sqlToExecute,
        error: e.toString(),
        database: currentQueryDatabaseName,
        databaseType: connection.currentServer?.type,
        connectionId: connection.currentServer?.id ?? '',
        connectionName: connection.currentServer?.name,
      );
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    return tab.executeQuery(
      sql,
      connectionId: connectionId,
      database: database,
      sessionId: sessionId,
    );
  }

  /// 执行表维护命令（ANALYZE / OPTIMIZE / CHECK TABLE for MySQL/Doris，
  /// VACUUM / ANALYZE / REINDEX / CLUSTER for PostgreSQL）。
  Future<List<Map<String, dynamic>>> runTableMaintenance(
    String databaseName,
    String tableName,
    TableMaintenanceCommand command, {
    String? connectionId,
  }) {
    final dbType = connection.currentServer?.type ?? DatabaseType.mysql;
    final sql = command.buildSql(databaseName, tableName, dbType: dbType);
    return executeQuery(
      sql,
      connectionId: connectionId,
      database: databaseName,
    );
  }

  /// 绕过 DDL 检查执行查询并更新结果
  Future<void> executeQueryBypassDdlAndUpdateResults(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    final data = await dbService.executeQueryBypassDdl(
      sql,
      connectionId: connectionId,
      database: database,
      sessionId: sessionId,
    );
    updateTabExecutionResults(activeTabIndex, [
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
        executionTime: Duration.zero,
        dataShape: dbService.lastDataShape,
      ),
    ]);
    if (connectionId != null && database != null) {
      refreshDatabase(connectionId, database);
    }
  }

  /// 绕过 DML 安全检查执行查询（用于用户确认后执行）
  Future<void> executeQueryBypassDmlAndUpdateResults(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    final data = await dbService.executeQueryBypassDml(
      sql,
      connectionId: connectionId,
      database: database,
      sessionId: sessionId,
    );
    updateTabExecutionResults(activeTabIndex, [
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
        dataShape: dbService.lastDataShape,
      ),
    ]);
  }

  // ==================== AI 配置 setter ====================

  void setAiProvider(String provider) {
    aiConfig.setProvider(provider);
  }

  void setAiModel(String model) {
    if (selectedAiModel != model) {
      aiConfig.setModel(model);
    }
  }

  void setAutoExecuteSql(bool value) {
    if (autoExecuteSql != value) {
      aiConfig.setAutoExecuteSql(value);
      // aiConfig 内部已调用 notifyListeners()，此处无需重复
    }
  }

  void setAutocompleteEnabled(bool value) {
    if (autocompleteEnabled != value) {
      aiConfig.setAutocompleteEnabled(value);
      // aiConfig 内部已调用 notifyListeners()，此处无需重复
    }
  }

  bool get autoLimitEnabled => querySettings.autoLimitEnabled;
  int get autoLimitValue => querySettings.autoLimitValue;

  void setAutoLimitEnabled(bool value) {
    if (autoLimitEnabled != value) {
      querySettings.setAutoLimitEnabled(value);
    }
  }

  void setAutoLimitValue(int value) {
    if (autoLimitValue != value) {
      querySettings.setAutoLimitValue(value);
    }
  }

  // ── C21 连接级查询覆盖（编辑器上下文芯片；会话级，转发 dbService）──

  /// 编辑器 tab 的有效连接 id：tab 绑定优先，未绑定时回落活跃连接
  /// （与执行链路 `connectionId ?? activeConnectionId` 同语义——芯片写入
  /// 若只看 tab 绑定，未绑定 tab 上会静默无效）。
  String? effectiveTabConnectionId(int tabIndex) =>
      (tabIndex < tabs.length ? tabs[tabIndex].connectionId : null) ??
      dbService.activeConnectionId;

  /// 有效行限显示值：覆盖优先（0=关），否则全局设置。
  int? queryRowLimitOverride(String connectionId) =>
      dbService.queryOverride(connectionId)?.rowLimit;

  /// 有效超时显示值：覆盖 ?? 连接默认（无连接返回 null）。
  int? queryTimeoutSeconds(String connectionId) {
    final override = dbService.queryOverride(connectionId)?.timeoutSeconds;
    if (override != null) return override;
    try {
      final server = savedConnections.firstWhere((s) => s.id == connectionId);
      return server.timeoutSeconds;
    } catch (_) {
      return null;
    }
  }

  /// 芯片写入入口。rowLimit：null=跟随全局；0=强制关；>0=强制值。
  /// timeoutSeconds：null=跟随连接；>0=覆盖。
  void setConnectionQueryOverride(
    String connectionId, {
    int? rowLimit,
    int? timeoutSeconds,
  }) {
    dbService.setQueryOverride(
      connectionId,
      rowLimit: rowLimit,
      timeoutSeconds: timeoutSeconds,
    );
    notifyListeners();
  }

  /// 清除单项覆盖（芯片「跟随设置/跟随连接」）——set 系合并语义，显式清除
  /// 必须走这里。
  void clearConnectionQueryOverrideField(
    String connectionId, {
    bool rowLimit = false,
    bool timeoutSeconds = false,
  }) {
    if (rowLimit) dbService.clearRowLimitOverride(connectionId);
    if (timeoutSeconds) dbService.clearTimeoutOverride(connectionId);
    notifyListeners();
  }

  void setAiTimeout(Duration timeout) {
    if (aiTimeout != timeout) {
      aiConfig.setAiTimeout(timeout);
      // aiConfig 内部已调用 notifyListeners()，此处无需重复
    }
  }

  Future<void> loadAiConfig() async {
    await aiConfig.load();
    notifyListeners();
  }

  Future<void> saveAiConfig(
    String provider,
    String model,
    Map<String, Map<String, String>> apiConfigs,
  ) async {
    await aiConfig.save(provider: provider, model: model, configs: apiConfigs);
    notifyListeners();
  }

  String? getAiApiKey(String provider) => aiConfig.getApiKey(provider);
  String? getAiBaseUrl(String provider) => aiConfig.getBaseUrl(provider);

  Map<String, List<String>> get fetchedModelLists => aiConfig.fetchedModelLists;

  void saveFetchedModelLists(Map<String, List<String>> modelLists) {
    aiConfig.saveFetchedModelLists(modelLists);
    // aiConfig 内部已调用 notifyListeners()，此处无需重复
  }

  List<String>? getFetchedModelsForProvider(String provider) {
    return aiConfig.getFetchedModelsForProvider(provider);
  }

  // ==================== AI 面板操作 ====================

  void toggleAiPanel() {
    AppLogger.d('AppProvider', 'toggleAiPanel() called');
    aiPanel.toggleAiPanel();
    // 关闭面板时同时退出全屏模式
    if (!aiPanel.aiPanelOpen && aiPanel.aiPanelFullscreen) {
      aiPanel.setAiPanelFullscreen(false);
    }
    AppLogger.d(
      'AppProvider',
      'aiPanel.aiPanelOpen=${aiPanel.aiPanelOpen}, calling notifyListeners()',
    );
    notifyListeners(); // 通知 UI 更新
  }

  void toggleAiPanelFullscreen() {
    AppLogger.d('AppProvider', 'toggleAiPanelFullscreen() called');
    aiPanel.toggleAiPanelFullscreen();
    // 状态变化由 aiPanel 的 notifyListeners 传播
  }

  /// AI 配额门禁（Free 每月 30 次）：超额时面板提示 + 触发升级弹窗，返回 false。
  Future<bool> _checkAiQuota({String locale = 'en'}) async {
    if (await canUseAi()) return true;
    addAiMessage(
      AiMessage(
        id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        content: AiServiceLocalizations(locale).aiQuotaExhaustedUpgradePrompt,
        timestamp: DateTime.now(),
      ),
    );
    setPendingUpgradeFeature('ai_quota');
    return false;
  }

  /// 发送查询结果 AI 分析请求
  Future<void> sendAiAnalysis(
    String query, {
    String? resultSummary,
    String locale = 'en',
  }) async {
    // 打开 AI 面板
    aiPanel.openAiPanel();
    notifyListeners();

    final adapter = connection.dbService.currentAdapter;
    if (adapter == null) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).aiAnalysisNoConnection,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final provider = selectedAiProvider;
    final model = selectedAiModel;
    final apiKey = getAiApiKey(provider);
    final baseUrl = getAiBaseUrl(provider);

    if (apiKey == null || apiKey.isEmpty) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).errorAiApiKeyMissing,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final l10n = AiServiceLocalizations(locale);
    final text = StringBuffer();
    text.writeln(l10n.analyzeQueryHeader);
    text.writeln();
    text.writeln('```sql');
    text.writeln(query);
    text.writeln('```');
    if (resultSummary != null && resultSummary.isNotEmpty) {
      text.writeln();
      text.writeln(l10n.resultSummaryLabel);
      text.writeln(resultSummary);
    }
    text.writeln();
    text.writeln(l10n.analyzeQueryPerformanceAsk);

    if (!await _checkAiQuota(locale: locale)) return;

    await aiPanel.orchestrator.sendUserMessage(
      text: text.toString(),
      adapter: adapter,
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      timeout: aiTimeout,
      thinkingEnabled: AiService.supportsThinking(provider, model),
      selectedDatabase: aiPanel.selectedDatabaseName,
      locale: locale,
      // 高级 AI（Agent 工具调用）为 Pro 专属；Free 纯对话
      allowTools: await _resolveAllowTools(),
    );
    await recordAiUsage();
  }

  /// 慢查询周报 AI 分析（#29 M3 / ADR-0007：客户端侧，复用 AI 面板与
  /// 用户自配 key；server 零 AI 外呼面）。周报内容序列化为自描述结构，
  /// 模型侧无需了解 content v1 契约。
  Future<void> analyzeWeeklyReportWithAi(
    SlowQueryWeeklyReport report, {
    String locale = 'en',
  }) async {
    aiPanel.openAiPanel();
    notifyListeners();

    final adapter = connection.dbService.currentAdapter;
    if (adapter == null) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).aiAnalysisNoConnection,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }
    final provider = selectedAiProvider;
    final model = selectedAiModel;
    final apiKey = getAiApiKey(provider);
    final baseUrl = getAiBaseUrl(provider);
    if (apiKey == null || apiKey.isEmpty) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).errorAiApiKeyMissing,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final l10n = AiServiceLocalizations(locale);
    final s = report.summary;
    final text = StringBuffer();
    text.writeln(l10n.analyzeWeeklyHeader);
    text.writeln();
    text.writeln(
      'Window: ${report.windowFrom} -> ${report.windowTo}'
      '${report.windowTruncated ? ' (partial: older samples rotated out by retention)' : ''}',
    );
    text.writeln(
      'Summary: samples=${s.totalSamples}, distinctQueries=${s.distinctDigests}, '
      'totalMs=${s.totalMs}, errors=${s.errorCount}, cancelled=${s.cancelledCount}, '
      'weekOverWeekPct=${s.weekOverWeekPct?.toStringAsFixed(1) ?? 'n/a'}',
    );
    text.writeln();
    text.writeln('Top queries (by total time):');
    for (final t in report.top) {
      text.writeln(
        '- [${t.count}x, total ${t.totalMs}ms, avg ${t.avgMs}ms, max ${t.maxMs}ms, ${t.dbKind}] ${t.digest}',
      );
    }
    text.writeln();
    text.writeln('By day:');
    for (final d in report.byDay) {
      text.writeln('- ${d.date}: ${d.count}x, ${d.totalMs}ms');
    }
    text.writeln();
    text.writeln('By connection:');
    for (final c in report.byConnection) {
      text.writeln('- ${c.dbKind} ${c.connId}: ${c.count}x, ${c.totalMs}ms');
    }
    text.writeln();
    text.writeln(l10n.analyzeWeeklyAsk);

    if (!await _checkAiQuota(locale: locale)) return;

    await aiPanel.orchestrator.sendUserMessage(
      text: text.toString(),
      adapter: adapter,
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      timeout: aiTimeout,
      thinkingEnabled: AiService.supportsThinking(provider, model),
      selectedDatabase: aiPanel.selectedDatabaseName,
      locale: locale,
      allowTools: await _resolveAllowTools(),
    );
    await recordAiUsage();
  }

  MysqlAiContextCollector? _mysqlAiContextCollector;
  MysqlAiContextCollector get _aiContextCollector {
    return _mysqlAiContextCollector ??= MysqlAiContextCollector(
      connection.dbService,
    );
  }

  /// 对侧边栏树节点（表/库/连接）发起 AI 分析。
  ///
  /// MySQL/Doris 节点使用 MysqlAiContextCollector 获取丰富的上下文信息；
  /// 其他 SQL 数据库通过 AiAdapterMixin.getAiSchemaSummary() 获取基础架构摘要。
  Future<void> analyzeTreeNodeWithAi(
    AiTreeNodeContext ctx, {
    String locale = 'en',
  }) async {
    aiPanel.openAiPanel();
    notifyListeners();

    final adapter = connection.dbService.currentAdapter;
    if (adapter == null) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).aiAnalysisNoConnection,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final provider = selectedAiProvider;
    final model = selectedAiModel;
    final apiKey = getAiApiKey(provider);
    final baseUrl = getAiBaseUrl(provider);

    if (apiKey == null || apiKey.isEmpty) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).errorAiApiKeyMissing,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    // 每次 AI 分析都新建一个会话
    final l10n = AiServiceLocalizations(locale);
    aiPanel.createNewSession(title: l10n.aiSessionTitleNode(ctx.displayLabel));

    // 设置 AI 面板上下文
    setSelectedConnection(ctx.connectionId);
    if (ctx.databaseName case final db?) {
      setSelectedDatabase(db);
    }

    // 收集节点上下文
    String context;
    try {
      context = await _collectNodeContext(ctx, locale);
    } catch (e) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).errorAiCollectNodeContextFailed('$e'),
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final text = StringBuffer();
    text.writeln(
      l10n.analyzeTreeNodeHeader(l10n.nodeTypeLabel(ctx.type), ctx.displayLabel),
    );
    text.writeln();
    text.writeln('```');
    text.writeln(context);
    text.writeln('```');
    text.writeln();
    text.writeln(l10n.analyzeTreeNodeAsk);

    if (!await _checkAiQuota(locale: locale)) return;

    await aiPanel.orchestrator.sendUserMessage(
      text: text.toString(),
      adapter: adapter,
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      timeout: aiTimeout,
      thinkingEnabled: AiService.supportsThinking(provider, model),
      selectedDatabase: aiPanel.selectedDatabaseName,
      locale: locale,
      // 高级 AI（Agent 工具调用）为 Pro 专属；Free 纯对话
      allowTools: await _resolveAllowTools(),
    );
    await recordAiUsage();
  }

  Future<String> _collectNodeContext(AiTreeNodeContext ctx, [String locale = 'en']) async {
    final l = AiServiceLocalizations(locale);
    final dbType = connection.currentServer?.type;
    final isMySqlDialect =
        dbType == DatabaseType.mysql || dbType == DatabaseType.doris;

    // MySQL/Doris uses the rich context collector
    if (isMySqlDialect) {
      final db = ctx.databaseName;
      switch (ctx.type) {
        case AiTreeNodeType.table:
          if (db == null || db.isEmpty) {
            throw Exception('Table analysis requires a database to be specified.');
          }
          return _aiContextCollector.collectTableContext(
            ctx.connectionId,
            db,
            ctx.nodeName,
            locale: locale,
          );
        case AiTreeNodeType.database:
          if (db == null || db.isEmpty) {
            throw Exception('Database analysis requires a database name.');
          }
          return _aiContextCollector.collectDatabaseContext(
            ctx.connectionId,
            db,
            locale: locale,
          );
        case AiTreeNodeType.connection:
          return _aiContextCollector.collectServerContext(
            ctx.connectionId,
            locale: locale,
          );
        default:
          throw Exception('Unsupported node type: ${ctx.type}');
      }
    }

    // Other SQL databases use the adapter's basic schema summary
    final adapter = connection.dbService.currentAdapter;
    if (adapter == null) throw Exception('Not connected to a database.');

    switch (ctx.type) {
      case AiTreeNodeType.table:
        return adapter.getAiSchemaSummary(
          target: ctx.nodeName,
          databaseName: ctx.databaseName,
          locale: locale,
        );
      case AiTreeNodeType.database:
        return adapter.getAiSchemaSummary(
          databaseName: ctx.databaseName ?? ctx.nodeName,
          locale: locale,
        );
      case AiTreeNodeType.connection:
        // Build a basic connection-level summary
        final dbs = await adapter.getDatabases();
        final buffer = StringBuffer();
        buffer.writeln(l.schemaSummaryDbTypeLabel(dbType?.displayName ?? 'Unknown'));
        buffer.writeln(l.aiContextDatabaseCount(dbs.length));
        if (dbs.isNotEmpty) {
          buffer.writeln(l.aiContextDatabaseList(dbs.join(", ")));
        }
        return buffer.toString();
      default:
        throw Exception('Unsupported node type: ${ctx.type}');
    }
  }

  /// 对错误发起 AI 分析（US2）：打开 AI 面板、新建会话、发送脱敏后的错误 + 上下文。
  Future<void> analyzeErrorWithAi({
    required String errorText,
    String? title,
    String? sql,
    String? connectionId,
    String? databaseName,
    String locale = 'en',
  }) async {
    aiPanel.openAiPanel();
    notifyListeners();

    final adapter = connection.dbService.currentAdapter;
    if (adapter == null) {
      addAiMessage(AiMessage(
        id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        content: '未连接到数据库，无法进行分析。',
        timestamp: DateTime.now(),
      ));
      return;
    }

    final provider = selectedAiProvider;
    final model = selectedAiModel;
    final apiKey = getAiApiKey(provider);
    final baseUrl = getAiBaseUrl(provider);

    if (apiKey == null || apiKey.isEmpty) {
      addAiMessage(AiMessage(
        id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        content: '请先配置 AI API Key。',
        timestamp: DateTime.now(),
      ));
      return;
    }

    // 先做配额门禁，再建会话——避免额度耗尽时残留空会话
    if (!await _checkAiQuota(locale: locale)) return;

    final l10n = AiServiceLocalizations(locale);
    aiPanel.createNewSession(title: title ?? l10n.aiSessionTitleError);
    if (connectionId != null) aiPanel.setSelectedConnection(connectionId);
    if (databaseName != null) aiPanel.setSelectedDatabase(databaseName);

    // 组装脱敏后的诊断提示（FR-011）
    final text = StringBuffer();
    text.writeln(l10n.analyzeErrorHeader);
    text.writeln();
    text.writeln(l10n.errorInfoLabel);
    text.writeln('```');
    text.writeln(redactSecrets(errorText));
    text.writeln('```');
    if (sql != null && sql.isNotEmpty) {
      text.writeln();
      text.writeln(l10n.relatedSqlLabel);
      text.writeln('```sql');
      text.writeln(redactSecrets(sql));
      text.writeln('```');
    }

    await aiPanel.orchestrator.sendUserMessage(
      text: text.toString(),
      adapter: adapter,
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      timeout: aiTimeout,
      thinkingEnabled: AiService.supportsThinking(provider, model),
      selectedDatabase: aiPanel.selectedDatabaseName,
      locale: locale,
      allowTools: await _resolveAllowTools(),
    );
    await recordAiUsage();
  }

  /// 对查询结果（成功/空结果/错误）发起 AI 分析。
  Future<void> analyzeExecutionResultWithAi(
    ExecutionResult result, {
    String locale = 'en',
  }) async {
    aiPanel.openAiPanel();
    notifyListeners();

    final adapter = connection.dbService.currentAdapter;
    if (adapter == null) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).aiAnalysisNoConnection,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final provider = selectedAiProvider;
    final model = selectedAiModel;
    final apiKey = getAiApiKey(provider);
    final baseUrl = getAiBaseUrl(provider);

    if (apiKey == null || apiKey.isEmpty) {
      addAiMessage(
        AiMessage(
          id: 'ai_err_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: AiServiceLocalizations(locale).errorAiApiKeyMissing,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final l10n = AiServiceLocalizations(locale);
    // 每次 AI 分析都新建一个会话
    aiPanel.createNewSession(title: l10n.aiSessionTitleQueryResult);

    final text = StringBuffer();
    text.writeln('```sql');
    text.writeln(result.statement.sql);
    text.writeln('```');

    if (!result.success) {
      text.writeln();
      text.writeln(l10n.executionFailedLabel);
      text.writeln('```');
      text.writeln(result.errorMessage ?? l10n.unknownErrorLabel);
      text.writeln('```');
      text.writeln();
      text.writeln(l10n.analyzeSqlErrorAsk);
    } else if (!result.hasData || result.data!.isEmpty) {
      text.writeln();
      text.writeln(l10n.emptyResultHeader);
      text.writeln(l10n.executionTimeLabel(result.executionTime.inMilliseconds));
      text.writeln();
      text.writeln(l10n.analyzeEmptyResultAsk);
    } else {
      final summary = StringBuffer();
      summary.writeln(l10n.rowsReturnedLabel(result.data!.length));
      summary.writeln(
        l10n.executionTimeLabel(result.executionTime.inMilliseconds),
      );
      if (result.isTruncated && result.limitValue != null) {
        summary.writeln(l10n.truncatedLabel(result.limitValue!));
      }
      final columns = result.data!.first.keys.toList();
      if (columns.isNotEmpty) {
        summary.writeln(l10n.columnsLabel(columns));
      }
      text.writeln();
      text.writeln(l10n.resultSummaryLabel);
      text.writeln(summary.toString());
      text.writeln();
      text.writeln(l10n.analyzeQueryPerformanceAsk);
    }

    if (!await _checkAiQuota(locale: locale)) return;

    await aiPanel.orchestrator.sendUserMessage(
      text: text.toString(),
      adapter: adapter,
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      timeout: aiTimeout,
      thinkingEnabled: AiService.supportsThinking(provider, model),
      selectedDatabase: aiPanel.selectedDatabaseName,
      locale: locale,
      // 高级 AI（Agent 工具调用）为 Pro 专属；Free 纯对话
      allowTools: await _resolveAllowTools(),
    );
    await recordAiUsage();
  }

  void setAiPanelFullscreen(bool value) {
    if (aiPanelFullscreen != value) {
      aiPanel.setAiPanelFullscreen(value);
      // 状态变化由 aiPanel 的 notifyListeners 传播
    }
  }

  void setAiPanelOpen(bool open) {
    if (aiPanelOpen != open) {
      if (open) {
        aiPanel.openAiPanel();
      } else {
        aiPanel.closeAiPanel();
      }
      // 状态变化由 aiPanel 的 notifyListeners 传播
    }
  }

  void addAiMessage(AiMessage message) => aiPanel.addAiMessage(message);
  void removeLastAiMessage() => aiPanel.removeLastAiMessage();
  void updateAiMessageContent(String messageId, String content) =>
      aiPanel.updateAiMessageContent(messageId, content);
  void appendAiMessageContent(String messageId, String chunk) =>
      aiPanel.appendAiMessageContent(messageId, chunk);
  void updateAiMessageReasoning(String messageId, String reasoningContent) =>
      aiPanel.updateAiMessageReasoning(messageId, reasoningContent);
  void appendAiMessageReasoning(String messageId, String chunk) =>
      aiPanel.appendAiMessageReasoning(messageId, chunk);
  void updateAiMessageLoading(String messageId, bool isLoading) =>
      aiPanel.updateAiMessageLoading(messageId, isLoading);
  void updateAiMessage({
    required String messageId,
    String? content,
    String? reasoningContent,
    String? code,
    bool? isDangerous,
  }) => aiPanel.updateAiMessage(
    messageId: messageId,
    content: content,
    reasoningContent: reasoningContent,
    code: code,
    isDangerous: isDangerous,
  );
  void clearAiMessages() => aiPanel.clearAiMessages();
  void toggleBookmark(String messageId) => aiPanel.toggleBookmark(messageId);

  void setSelectedTable(String table) {
    aiPanel.setSelectedTable(table);
  }

  void setSelectedConnection(String? connectionId) {
    aiPanel.setSelectedConnection(connectionId);
  }

  void setSelectedDatabase(String? databaseName) {
    aiPanel.setSelectedDatabase(databaseName);
  }

  // ==================== 编辑器焦点管理 ====================

  bool _shouldFocusEditor = false;
  bool get shouldFocusEditor => _shouldFocusEditor;

  void requestEditorFocus() {
    _shouldFocusEditor = true;
    notifyListeners();
  }

  void clearEditorFocusRequest() {
    _shouldFocusEditor = false;
  }

  void setSearchQuery(String query) {
    aiPanel.setSearchQuery(query);
  }

  // ==================== 数据库/表操作（委托给 DatabaseService） ====================

  Future<bool> createDatabase(
    String dbName, {
    String? charset,
    String? collation,
  }) {
    return connection.dbService
        .createDatabase(dbName, charset: charset, collation: collation)
        .then((result) {
          if (result) connection.refreshDatabases();
          return result;
        });
  }

  Future<bool> dropDatabase(String dbName) {
    return connection.dbService.dropDatabase(dbName).then((result) {
      if (result) connection.refreshDatabases();
      return result;
    });
  }

  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) {
    return connection.dbService.getDatabaseProperties(dbName);
  }

  Future<String> getDatabaseSize(String dbName) {
    return connection.dbService.getDatabaseSize(dbName);
  }

  Future<String> getCreateDatabaseSql(String dbName) {
    return connection.dbService.getCreateDatabaseSql(dbName);
  }

  Future<List<String>> getCharsets() {
    return connection.dbService.getCharsets();
  }

  Future<List<Map<String, String>>> getCollations({String? charset}) {
    return connection.dbService.getCollations(charset: charset);
  }

  Future<String> exportDatabaseStructure(String dbName) {
    return connection.dbService.exportDatabaseStructure(dbName);
  }

  Future<bool> executeSqlScript(String script) {
    return connection.dbService.executeSqlScript(script).then((result) {
      if (result) connection.refreshDatabases();
      return result;
    });
  }

  // ==================== Schema 操作 ====================

  /// 获取指定数据库的 schema 列表（PostgreSQL/SQL Server）。
  Future<List<String>> getSchemas(
    String connectionId,
    String databaseName,
  ) async {
    final adapter = connection.dbService.getAdapter(connectionId);
    if (adapter == null || !adapter.supportsSchemaNamespace) return [];
    return adapter.getSchemas(database: databaseName);
  }

  /// 设置当前 schema（PostgreSQL/SQL Server）。
  Future<void> setSchema(String connectionId, String schemaName) async {
    final adapter = connection.dbService.getAdapter(connectionId);
    if (adapter == null || !adapter.supportsSchemaNamespace) return;
    await adapter.setSchema(schemaName);
  }

  // ==================== 表操作 ====================

  Future<bool> createTable(
    String dbName,
    String tableName,
    List<DbColumn> columns, {
    String? comment,
    String? engine,
    Map<String, dynamic>? options,
  }) {
    return connection.dbService
        .createTable(tableName, columns,
            comment: comment, engine: engine, options: options)
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<bool> dropTable(String dbName, String tableName) {
    return connection.dbService.dropTable(tableName, databaseName: dbName).then(
      (result) {
        if (result) connection.changeDatabase(dbName);
        return result;
      },
    );
  }

  Future<bool> renameTable(String dbName, String oldName, String newName) {
    return connection.dbService
        .renameTable(oldName, newName, databaseName: dbName)
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<bool> truncateTable(
    String tableName, {
    String? databaseName,
    TruncateOptions? options,
  }) {
    return connection.dbService.truncateTable(
      tableName,
      databaseName: databaseName,
    );
  }

  Future<List<Map<String, dynamic>>> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
    String? databaseName,
  }) {
    return connection.dbService.getTableData(
      tableName,
      limit: limit,
      offset: offset,
      cursorColumn: cursorColumn,
      cursorValue: cursorValue,
      databaseName: databaseName,
    );
  }

  Future<int> getTableRowCount(String tableName, {String? databaseName}) {
    return connection.dbService.getTableRowCount(
      tableName,
      databaseName: databaseName,
    );
  }

  Future<int> getTableExactRowCount(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) {
    return connection.dbService.getTableExactRowCount(
      tableName,
      connectionId: connectionId,
      sessionId: sessionId,
      databaseName: databaseName,
    );
  }

  Future<Map<String, dynamic>?> getTableProperties(
    String tableName, {
    String? connectionId,
    String? dbName,
  }) {
    return connection.dbService.getTableProperties(
      tableName,
      connectionId: connectionId,
      dbName: dbName,
    );
  }

  Future<String> getCreateTableSql(
    String tableName, {
    String? connectionId,
    String? databaseName,
  }) {
    return connection.dbService.getCreateTableSql(
      tableName,
      connectionId: connectionId,
      databaseName: databaseName,
    );
  }

  Future<List<DbIndex>> getTableIndexes(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) {
    return connection.dbService.getTableIndexes(
      tableName,
      connectionId: connectionId,
      sessionId: sessionId,
      databaseName: databaseName,
    );
  }

  Future<List<ForeignKey>> getForeignKeys(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) {
    return connection.dbService.getForeignKeys(
      tableName,
      connectionId: connectionId,
      sessionId: sessionId,
      databaseName: databaseName,
    );
  }

  /// 懒加载单个表的 schema（列和索引）
  Future<void> loadTableSchema(
    String connectionId,
    String databaseName,
    String tableName,
  ) async {
    final db = connection.getCachedDatabase(connectionId, databaseName);
    if (db == null) return;

    final tableIndex = db.tables.indexWhere((t) => t.name == tableName);
    if (tableIndex < 0) return;

    final table = db.tables[tableIndex];
    if (table.columns.isNotEmpty) return; // 已加载过

    try {
      final columns = await connection.dbService.getTableColumns(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      final indexes = await connection.dbService.getTableIndexes(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );

      // 更新缓存中的表
      db.tables[tableIndex] = DbTable(
        name: table.name,
        columns: columns,
        indexes: indexes,
      );

      notifyListeners();
    } catch (e) {
      AppLogger.e('AppProvider', '加载表结构失败: $tableName', e);
    }
  }

  Future<bool> addColumn(String dbName, String tableName, DbColumn column) {
    return connection.dbService
        .addColumn(tableName, column, databaseName: dbName)
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<bool> dropColumn(String dbName, String tableName, String columnName) {
    return connection.dbService
        .dropColumn(tableName, columnName, databaseName: dbName)
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<bool> modifyColumn(
    String dbName,
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) {
    return connection.dbService
        .modifyColumn(tableName, oldColumnName, newColumn, databaseName: dbName)
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<bool> renameColumn(
    String dbName,
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) {
    return connection.dbService
        .renameColumn(tableName, oldColumnName, newColumnName,
            databaseName: dbName)
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<bool> createIndex(
    String dbName,
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  }) {
    return connection.dbService
        .createIndex(
          tableName,
          indexName,
          columns,
          unique: unique,
          databaseName: dbName,
        )
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<bool> dropIndex(String dbName, String tableName, String indexName) {
    return connection.dbService
        .dropIndex(tableName, indexName, databaseName: dbName)
        .then((result) {
          if (result) connection.changeDatabase(dbName);
          return result;
        });
  }

  Future<String> exportTableData(
    String tableName, {
    int limit = 1000,
    String? databaseName,
  }) {
    return connection.dbService.exportTableData(
      tableName,
      limit: limit,
      databaseName: databaseName,
    );
  }

  // ==================== 保存的查询 ====================

  List<QueryTab> savedQueriesFor(String connectionId, String? databaseName) =>
      tab.savedQueriesFor(connectionId, databaseName);

  List<QueryTab> savedQueriesForConnection(String connectionId) =>
      tab.savedQueriesForConnection(connectionId);

  QueryTab? getSavedQueryById(String queryId) => tab.getSavedQueryById(queryId);

  Future<bool> saveQuery(QueryTab queryTab) => tab.saveQuery(queryTab);

  Future<void> renameSavedQuery(String queryId, String newTitle) =>
      tab.renameSavedQuery(queryId, newTitle);

  Future<void> deleteSavedQuery(String queryId) =>
      tab.deleteSavedQuery(queryId);

  Future<void> openSavedQuery(QueryTab savedQuery) async {
    // 先确保连接存在
    if (savedQuery.connectionId != null &&
        !connection.isConnectionConnected(savedQuery.connectionId!)) {
      final server = connection.savedConnections.firstWhere(
        (s) => s.id == savedQuery.connectionId,
        orElse: () => throw Exception('连接不存在'),
      );
      final connected = await connectToServer(server);
      if (!connected) {
        throw Exception('无法连接到服务器');
      }
    }

    // 使用保存的查询的原始 connectionId + databaseName 打开 Tab
    if (savedQuery.connectionId != null && savedQuery.databaseName != null) {
      await tab.openQueryTab(
        connectionId: savedQuery.connectionId!,
        databaseName: savedQuery.databaseName!,
        sql: savedQuery.sql,
        title: savedQuery.title,
        savedQueryId: savedQuery.savedQueryId ?? savedQuery.id,
      );
      return;
    }

    throw Exception('保存的查询缺少连接信息');
  }

  // ==================== 工具方法 ====================

  Future<void> refreshDatabases({String? connectionId}) =>
      connection.refreshDatabases(connectionId: connectionId);
  Future<String?> testConnection(DbServer server) =>
      connection.testConnection(server);

  // ==================== TDengine 特有操作 ====================

  final Map<String, List<TdSuperTable>> _superTablesCache = {};
  final Set<String> _loadingSuperTables = {};

  List<TdSuperTable>? getSuperTables(String connectionId, String databaseName) {
    final key = '$connectionId:$databaseName';
    return _superTablesCache[key];
  }

  /// 测试注入：直接写入超级表缓存（TD 插件树单测用，绕过真连接加载）。
  @visibleForTesting
  void seedSuperTablesForTest(
    String connectionId,
    String databaseName,
    List<TdSuperTable> tables,
  ) {
    _superTablesCache['$connectionId:$databaseName'] = tables;
  }

  bool isLoadingSuperTables(String connectionId, String databaseName) {
    final key = '$connectionId:$databaseName';
    return _loadingSuperTables.contains(key);
  }

  Future<void> loadSuperTables(String connectionId, String databaseName) async {
    final key = '$connectionId:$databaseName';
    if (_loadingSuperTables.contains(key)) return;

    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );

    if (server.type != DatabaseType.tdengine) return;

    _loadingSuperTables.add(key);
    notifyListeners();

    try {
      final superTables = await connection.dbService.getSuperTables(
        connectionId: connectionId,
        databaseName: databaseName,
      );
      _superTablesCache[key] = superTables;
    } catch (e) {
      AppLogger.e('AppProvider', '加载超级表失败: $e');
    } finally {
      _loadingSuperTables.remove(key);
      notifyListeners();
    }
  }

  Future<void> loadSuperTableDetail(
    String connectionId,
    String databaseName,
    String superTableName,
  ) async {
    final cacheKey = '$connectionId:$databaseName';
    final superTables = _superTablesCache[cacheKey];
    if (superTables == null) return;

    final index = superTables.indexWhere((st) => st.name == superTableName);
    if (index == -1) return;

    try {
      final detail = await connection.dbService.getSuperTableDetail(
        superTableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      if (detail != null) {
        superTables[index] = detail;
        _superTablesCache[cacheKey] = superTables;
        notifyListeners();
      }
    } catch (e) {
      AppLogger.e('AppProvider', '加载超级表详情失败: $e');
    }
  }

  Future<bool> dropSuperTable(
    String connectionId,
    String databaseName,
    String superTableName,
  ) async {
    try {
      final success = await connection.dbService.dropSuperTable(
        superTableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      if (success) {
        final cacheKey = '$connectionId:$databaseName';
        final superTables = _superTablesCache[cacheKey];
        if (superTables != null) {
          _superTablesCache[cacheKey] = superTables
              .where((st) => st.name != superTableName)
              .toList();
          notifyListeners();
        }
      }
      return success;
    } catch (e) {
      AppLogger.e('AppProvider', '删除超级表失败: $e');
      return false;
    }
  }

  // ==================== MongoDB 特有状态 ====================

  final Map<String, Map<String, dynamic>> _mongoCollectionStats = {};
  final Map<String, Map<String, dynamic>> _mongoSchemas = {};
  final Map<String, Map<String, dynamic>> _mongoServerInfo = {};
  final Set<String> _loadingMongoStats = {};
  final Set<String> _loadingMongoSchemas = {};
  final Set<String> _loadingMongoServerInfo = {};
  // #7 — Sharding/ReplicaSet 缓存。null（缓存里没该 key）= 未加载过；
  // 已加载但适配器返回 null 时，缓存存入 {'__loaded': true, 'isShardedCluster': false}
  // 之类的哨兵，避免重复拉取 + 区分「未拉过」vs「拉过了但不是集群」。
  // key = connectionId。
  final Map<String, Map<String, dynamic>> _mongoShardingStatus = {};
  final Map<String, Map<String, dynamic>> _mongoReplicaSetStatus = {};
  final Set<String> _loadingMongoSharding = {};
  final Set<String> _loadingMongoReplicaSet = {};

  /// 获取 MongoDB 集合统计信息
  Map<String, dynamic>? getMongoDBCollectionStats(
    String connectionId,
    String collectionName,
  ) {
    final key = '$connectionId:$collectionName';
    return _mongoCollectionStats[key];
  }

  /// 获取 MongoDB 集合的 Schema
  Map<String, dynamic>? getMongoDBSchema(
    String connectionId,
    String collectionName,
  ) {
    final key = '$connectionId:$collectionName';
    return _mongoSchemas[key];
  }

  /// 获取 MongoDB 服务器信息
  Map<String, dynamic>? getMongoDBServerInfo(String connectionId) {
    return _mongoServerInfo[connectionId];
  }

  /// 是否正在加载集合统计
  bool isLoadingMongoDBCollectionStats(
    String connectionId,
    String collectionName,
  ) {
    final key = '$connectionId:$collectionName';
    return _loadingMongoStats.contains(key);
  }

  /// 是否正在加载 Schema
  bool isLoadingMongoDBSchema(String connectionId, String collectionName) {
    final key = '$connectionId:$collectionName';
    return _loadingMongoSchemas.contains(key);
  }

  /// 是否正在加载服务器信息
  bool isLoadingMongoDBServerInfo(String connectionId) {
    return _loadingMongoServerInfo.contains(connectionId);
  }

  /// 加载 MongoDB 集合统计信息
  Future<void> loadMongoDBCollectionStats(
    String connectionId,
    String databaseName,
    String collectionName,
  ) async {
    final key = '$connectionId:$collectionName';
    if (_loadingMongoStats.contains(key)) return;

    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );

    if (server.type != DatabaseType.mongodb) return;

    _loadingMongoStats.add(key);
    notifyListeners();

    try {
      final adapter = connection.dbService.getAdapter(connectionId);
      if (adapter != null && adapter.databaseType == DatabaseType.mongodb) {
        final stats = await (adapter as MongoDBAdapter).getCollectionStats(
          collectionName,
        );
        _mongoCollectionStats[key] = stats;
      }
    } catch (e) {
      AppLogger.e('AppProvider', '加载 MongoDB 集合统计失败: $e');
    } finally {
      _loadingMongoStats.remove(key);
      notifyListeners();
    }
  }

  /// 加载 MongoDB 集合的 Schema
  Future<void> loadMongoDBSchema(
    String connectionId,
    String databaseName,
    String collectionName, {
    int sampleSize = 100,
  }) async {
    final key = '$connectionId:$collectionName';
    if (_loadingMongoSchemas.contains(key)) return;

    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );

    if (server.type != DatabaseType.mongodb) return;

    _loadingMongoSchemas.add(key);
    notifyListeners();

    try {
      final adapter = connection.dbService.getAdapter(connectionId);
      if (adapter != null && adapter.databaseType == DatabaseType.mongodb) {
        final schema = await (adapter as MongoDBAdapter).inferDocumentSchema(
          collectionName,
          sampleSize: sampleSize,
        );
        _mongoSchemas[key] = schema;
      }
    } catch (e) {
      AppLogger.e('AppProvider', '加载 MongoDB Schema 失败: $e');
    } finally {
      _loadingMongoSchemas.remove(key);
      notifyListeners();
    }
  }

  /// 加载 MongoDB 服务器信息
  Future<void> loadMongoDBServerInfo(String connectionId) async {
    if (_loadingMongoServerInfo.contains(connectionId)) return;

    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );

    if (server.type != DatabaseType.mongodb) return;

    _loadingMongoServerInfo.add(connectionId);
    notifyListeners();

    try {
      final adapter = connection.dbService.getAdapter(connectionId);
      if (adapter != null && adapter.databaseType == DatabaseType.mongodb) {
        final info = await (adapter as MongoDBAdapter).getServerStatus();
        _mongoServerInfo[connectionId] = info;
      }
    } catch (e) {
      AppLogger.e('AppProvider', '加载 MongoDB 服务器信息失败: $e');
    } finally {
      _loadingMongoServerInfo.remove(connectionId);
      notifyListeners();
    }
  }

  /// 向 MongoDB 集合插入单个文档（C17：侧边栏插入文档对话框的 provider 级
  /// 入口，UI 层不再直连 adapter；显式 useDatabase 保证落库 = 树上下文库）。
  Future<bool> insertMongoDocument(
    String connectionId,
    String databaseName,
    String collectionName,
    Map<String, dynamic> document,
  ) async {
    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );

    if (server.type != DatabaseType.mongodb) return false;

    final adapter = connection.dbService.getAdapter(connectionId);
    if (adapter != null && adapter.databaseType == DatabaseType.mongodb) {
      await adapter.useDatabase(databaseName);
      return await (adapter as MongoDBAdapter).insertOne(
        collectionName,
        document,
      );
    }
    return false;
  }

  /// 获取 MongoDB 集合完整选项（含 validator / validationLevel /
  /// validationAction；C17 验证规则查看器数据源）。集合不存在返回 null；
  /// 查询失败上抛（查看器需区分「无验证规则」与「加载失败」）。
  Future<Map<String, dynamic>?> getMongoCollectionOptions(
    String connectionId,
    String databaseName,
    String collectionName,
  ) async {
    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );

    if (server.type != DatabaseType.mongodb) return null;

    final adapter = connection.dbService.getAdapter(connectionId);
    if (adapter != null && adapter.databaseType == DatabaseType.mongodb) {
      await adapter.useDatabase(databaseName);
      final collections = await (adapter as MongoDBAdapter).listCollections(
        databaseName,
      );
      for (final c in collections) {
        if (c['name'] == collectionName) return c;
      }
    }
    return null;
  }

  // #7 — Sharding status（适配器已实现 listShards，仅缺 provider 缓存 + UI 接线）
  Map<String, dynamic>? getMongoDBShardingStatus(String connectionId) {
    return _mongoShardingStatus[connectionId];
  }

  bool isLoadingMongoDBSharding(String connectionId) {
    return _loadingMongoSharding.contains(connectionId);
  }

  Future<void> loadMongoDBShardingStatus(String connectionId) async {
    if (_loadingMongoSharding.contains(connectionId)) return;

    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );
    if (server.type != DatabaseType.mongodb) return;

    _loadingMongoSharding.add(connectionId);
    notifyListeners();

    try {
      final adapter = connection.dbService.getAdapter(connectionId);
      if (adapter != null && adapter.databaseType == DatabaseType.mongodb) {
        final status = await (adapter as MongoDBAdapter).getShardingStatus();
        // status 为 null = 不是分片集群（或拉取失败）；用哨兵区分「未拉过」
        // vs「拉过了但不是集群」。tree builder 据此渲染 placeholder 行。
        _mongoShardingStatus[connectionId] = status ?? {'__loaded': true, 'isShardedCluster': false};
      }
    } catch (e) {
      AppLogger.e('AppProvider', '加载 MongoDB 分片状态失败: $e');
      _mongoShardingStatus[connectionId] = {'__loaded': true, 'error': e.toString()};
    } finally {
      _loadingMongoSharding.remove(connectionId);
      notifyListeners();
    }
  }

  // #7 — ReplicaSet status（适配器已实现 replSetGetStatus，仅缺 provider 缓存）
  Map<String, dynamic>? getMongoDBReplicaSetStatus(String connectionId) {
    return _mongoReplicaSetStatus[connectionId];
  }

  bool isLoadingMongoDBReplicaSet(String connectionId) {
    return _loadingMongoReplicaSet.contains(connectionId);
  }

  Future<void> loadMongoDBReplicaSetStatus(String connectionId) async {
    if (_loadingMongoReplicaSet.contains(connectionId)) return;

    final server = connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );
    if (server.type != DatabaseType.mongodb) return;

    _loadingMongoReplicaSet.add(connectionId);
    notifyListeners();

    try {
      final adapter = connection.dbService.getAdapter(connectionId);
      if (adapter != null && adapter.databaseType == DatabaseType.mongodb) {
        final status = await (adapter as MongoDBAdapter).getReplicaSetStatus();
        _mongoReplicaSetStatus[connectionId] =
            status ?? {'__loaded': true, 'isReplicaSet': false};
      }
    } catch (e) {
      AppLogger.e('AppProvider', '加载 MongoDB 副本集状态失败: $e');
      _mongoReplicaSetStatus[connectionId] = {'__loaded': true, 'error': e.toString()};
    } finally {
      _loadingMongoReplicaSet.remove(connectionId);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _transactionSubscription?.cancel();
    _connectionEventSubscription?.cancel();
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = null;
    // 移除监听器
    aiPanel.removeListener(_onAiPanelChange);
    tab.removeListener(_onTabChange);
    this.proModule.removeListener(_onPurchaseChange);
    aiConfig.removeListener(_onAiConfigChange);
    recentTables.removeListener(_onRecentTablesChange);
    querySettings.removeListener(_onQuerySettingsChange);
    sidebar.removeListener(_onSidebarChange);
    connection.removeListener(_onConnectionChange);
    executionCenter.removeListener(_onExecutionCenterChange);
    // 按逆构造顺序 dispose
    ErrorReporter.instance.detach();
    executionCenter.dispose();
    aiPanel.dispose();
    tab.dispose();
    // ProModule 生命周期由注入方管（OSS NoOp 无资源；Pro 由 Pro 仓持有）。
    aiConfig.dispose();
    recentTables.dispose();
    querySettings.dispose();
    sidebar.dispose();
    queryHistory.dispose();
    connection.dispose();
    super.dispose();
  }
}
