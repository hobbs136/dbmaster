import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/ai_conversation_session.dart';
import '../models/database_models.dart';
import '../models/workbench_context_lock.dart';
import '../services/ai/ai_session_manager.dart';
import '../services/ai/ai_context_builder.dart';
import '../services/ai/agent/agent_gate.dart';
import '../services/ai/agent/agent_gate_analysis.dart';
import '../services/ai/agent/agent_loop_runner.dart';
import '../services/ai/agent/agent_tool_executor.dart';
import '../services/ai_agent_runner.dart';
import '../services/ai_session_orchestrator.dart';
import '../services/database_service.dart';
import '../services/free_chat_runner.dart';
import '../services/query_settings_service.dart';
import 'task_provider.dart';

/// 工作台 agent 运行的上下文快照（T14 / design-ai-agent D15）。
///
/// 由宿主（AiWorkbenchShell）经 [AiPanelProvider.agentContextSnapshotReader]
/// 注入的解析产物——方言（dbType）与连接 readOnly 需查 AppProvider 的
/// savedConnections，provider 层不可直达（跨 Provider 引用禁令），故沿
/// [AiPanelProvider.insertConfirmationCallback] 的「UI 层设置回调」先例由
/// 宿主闭包供给。
typedef WorkbenchAgentContextSnapshot = ({
  String? connectionId,
  String? connectionName,
  String? databaseName,
  DatabaseType dbType,
  bool readOnly,
});

class AiPanelProvider extends ChangeNotifier {
  final AiSessionManager sessionManager;
  final AiContextBuilder contextBuilder;
  final DatabaseService? dbService;
  late final AiSessionOrchestrator orchestrator;

  /// A1 agent 回路运行器（T14 / design-ai-agent §2.2 末段：与 [orchestrator]
  /// 同款持有方式，非新 Provider）。工作台发送路径经 `agentRunner.start` 驱动
  /// （design §2.3）；经典面板 orchestrator 路径零改动。构造器可选注入供测试。
  late final AgentLoopRunner agentRunner;

  /// Callback for requesting user confirmation before executing INSERT statements.
  /// Set by the UI layer (e.g., ai_panel_widget.dart).
  InsertConfirmationCallback? insertConfirmationCallback;

  /// 工作台 agent run 上下文快照读取器（T14，D15 一次快照的解析来源）：由宿主
  /// AiWorkbenchShell 在装配时注入。null 或 connectionId 为空 → 无上下文快照
  /// （AC7.4 纯对话引导态，数据类工具运行时 CONTEXT_REQUIRED）。
  WorkbenchAgentContextSnapshot? Function()? agentContextSnapshotReader;

  /// agent 会话配置读取器（T14）：由宿主注入（provider/model/apiKey/baseUrl/
  /// timeout/locale 读 AppProvider AI 配置面）。null → 空配置（chat 层失败 →
  /// 运行级 failed，不静默）。
  AgentChatConfig? Function()? agentChatConfigReader;

  bool _aiPanelOpen = false;
  bool _aiPanelFullscreen = false;
  String _selectedTable = '';
  String _searchQuery = '';
  String? _selectedConnectionId;
  String? _selectedDatabaseName;
  List<String> _selectedConnectionDatabases = [];

  /// 会话切换检测基准（T14）：sessionManager 对每次消息落地也 notify，只在
  /// currentSession id 变化时才复位 agentRunner（防误杀在途 run）。
  String? _lastAgentSessionId;

  /// L0.5 阈值缓存（T14 装配）：AgentGateAnalysis 的 rowThreshold 是同步 int，
  /// 而 QuerySettingsService 读取是异步 Future——缓存 + 每次构造分析时后台
  /// 刷新（下次判定生效，AC8.7 的异步 prefs 等价）+ 构造时预热。
  int _agentL05Threshold = QuerySettingsService.defaultAgentL05RowThreshold;

  /// 阈值缓存的测试观测面（Fix-B P2-3 用例：设置翻转经装配面即时生效）。
  /// 生产读经 [_createAgentAnalysis] 工厂，不读本 getter。
  @visibleForTesting
  int get agentL05ThresholdForTest => _agentL05Threshold;

  AiPanelProvider({
    AiSessionManager? sessionManager,
    AiContextBuilder? contextBuilder,
    this.dbService,
    TaskProvider? taskProvider,
    AiAgentFactory? agentFactory,
    AgentLoopRunner? agentRunner,
  }) : sessionManager = sessionManager ?? AiSessionManager(),
       contextBuilder = contextBuilder ?? AiContextBuilder() {
    orchestrator = AiSessionOrchestrator(
      sessionManager: this.sessionManager,
      dbService: dbService,
      taskProvider: taskProvider,
      agentFactory: agentFactory ?? FreeChatRunner.new,
    );
    orchestrator.onInsertConfirmationRequested =
        ({required tableName, required count, required statements}) async {
          if (insertConfirmationCallback != null) {
            return await insertConfirmationCallback!(
              tableName: tableName,
              count: count,
              statements: statements,
            );
          }
          return false;
        };
    this.agentRunner = agentRunner ?? _buildAgentRunner();
    _lastAgentSessionId = this.sessionManager.currentSession?.id;
    unawaited(_refreshAgentL05Threshold());
    this.sessionManager.addListener(_onSessionChange);
  }

  void _onSessionChange() {
    // T14：会话切换（含新建/分支/删除导致的 currentSession 变更）→ 账本清空
    // （AC8.5/AC9.3「会话结束失效」，D12）；在途 run 才全量复位（终局不落新
    // 会话）。idle 态只清账本：runner.start 内部建会话也走本 notify（start
    // 置 running 之前），全量复位会误清刚就位的 activeRunId/代数。
    final String? currentId = sessionManager.currentSession?.id;
    if (currentId != _lastAgentSessionId) {
      _lastAgentSessionId = currentId;
      if (agentRunner.isRunning) {
        agentRunner.resetForSessionSwitch();
      } else {
        agentRunner.ledger.clearAll();
      }
    }
    notifyListeners();
  }

  void updateTaskProvider(TaskProvider taskProvider) {
    orchestrator.updateTaskProvider(taskProvider);
  }

  // ==================== A1 agent 装配（T14，design §2.3）====================
  // executor + gate + dbAccess 在此闭包装配：dbService / QuerySettingsService
  // 为 provider 可达的既有服务；runner 不 import providers（services 层纪律）。

  AgentLoopRunner _buildAgentRunner() => AgentLoopRunner(
    executor: AgentToolExecutor(
      gate: AgentGate(createAnalysis: _createAgentAnalysis),
      db: _buildAgentDbAccess(),
    ),
    sessionManager: sessionManager,
    resolveRunContext: _resolveAgentRunContext,
    resolveChatConfig: _resolveAgentChatConfig,
    // Fix-B P2-3：L0.5 阈值刷新挂到 run 启动的 await 点（start 的
    // resolveMaxSteps 读取处同步等待）——设置修改后下一个 run 的首次判定
    // 即用新值（AC8.7 字面：修改后下次判定生效）。此前刷新只在分析构造时
    // 后台进行，首判定用旧缓存值（一步延迟）。工厂侧后台刷新保留，覆盖长
    // run 运行中修改设置的场景（判定 N 刷新、N+1 生效）。
    resolveMaxSteps: () async {
      await _refreshAgentL05Threshold();
      return _resolveAgentMaxSteps();
    },
  );

  /// maxSteps 读取（镜像 runner 默认解析 `_defaultMaxSteps` 的容错逻辑：
  /// 读失败回默认值——配置面异常不阻断运行；runner 侧函数文件私有，不可
  /// 引用，故镜像）。
  Future<int> _resolveAgentMaxSteps() async {
    try {
      return await QuerySettingsService().getAgentMaxSteps();
    } catch (_) {
      return QuerySettingsService.defaultAgentMaxSteps;
    }
  }

  /// 读前分析工厂（每次判定重新构造；后台刷新阈值缓存——run 内修改设置的
  /// 补充通道，run 启动点的主刷新见 [_buildAgentRunner] 的 resolveMaxSteps
  /// 包装，Fix-B P2-3 / AC8.7）。
  AgentGateAnalysis _createAgentAnalysis(AgentRunContext runCtx) {
    unawaited(_refreshAgentL05Threshold());
    final DatabaseService? db = dbService;
    return AgentGateAnalysis(
      // dbService 缺席（测试/未注入）→ 抛错闭包：T05 分析内核 fail-closed
      // 收敛为需确认，不静默放行。
      getExplainPlan: db == null
          ? (String sql) => Future<List<Map<String, dynamic>>>.error(
              StateError('AiPanelProvider: dbService not available'),
            )
          : (String sql) =>
                db.getExplainPlan(sql, connectionId: runCtx.connectionId),
      rowThreshold: _agentL05Threshold,
      dbType: runCtx.dbType,
    );
  }

  Future<void> _refreshAgentL05Threshold() async {
    try {
      _agentL05Threshold = await QuerySettingsService()
          .getAgentL05RowThreshold();
    } catch (_) {
      // prefs 不可达（测试环境）：保持缓存值——分析侧自有 fail-closed 兜底。
    }
  }

  /// dbService 访问函数集（T10 契约；组件级 MUST NOT 3——经注入函数触达
  /// DatabaseService）。dbService 缺席时 fail-loud 闭包 → executor 捕获为
  /// EXECUTION_FAILED（生产 AppProvider 恒注入 dbService，测试注入 runner
  /// 或闭包 spy）。
  AgentDbAccess _buildAgentDbAccess() {
    final DatabaseService? db = dbService;
    if (db == null) {
      final StateError err = StateError(
        'AiPanelProvider: dbService not available',
      );
      return AgentDbAccess(
        getTables: (String? connectionId) => throw err,
        getTableColumns:
            (
              String tableName, {
              String? connectionId,
              String? databaseName,
            }) => throw err,
        getTableIndexes:
            (
              String tableName, {
              String? connectionId,
              String? databaseName,
            }) => throw err,
        getForeignKeys:
            (
              String tableName, {
              String? connectionId,
              String? databaseName,
            }) => throw err,
        getCreateTableSql:
            (
              String tableName, {
              String? connectionId,
              String? databaseName,
            }) => throw err,
        getExplainPlan:
            (String sql, {String? connectionId}) => throw err,
        executeQuery:
            (
              String sql, {
              String? connectionId,
              String? database,
            }) => throw err,
      );
    }
    return AgentDbAccess(
      // getTables 为全命名参数签名（AgentDbAccess 是 positional）——包一层；
      // 其余方法签名兼容直接 tear-off（多出的可选命名参数不影响子型赋值）。
      getTables: (String? connectionId) =>
          db.getTables(connectionId: connectionId),
      getTableColumns: db.getTableColumns,
      getTableIndexes: db.getTableIndexes,
      getForeignKeys: db.getForeignKeys,
      getCreateTableSql: db.getCreateTableSql,
      getExplainPlan: db.getExplainPlan,
      executeQuery: db.executeQuery,
    );
  }

  /// run 启动快照解析（D15）：宿主注入的读取器优先；无读取器或无连接 →
  /// 无上下文快照（AC7.4）。dbType 占位仅填构造必填——无连接时数据工具被
  /// 判定序 ② CONTEXT_REQUIRED 先行拦截，方言不参与判定。
  AgentRunContext _resolveAgentRunContext(String runId) {
    final WorkbenchAgentContextSnapshot? snapshot =
        agentContextSnapshotReader?.call();
    final String? connectionId = snapshot?.connectionId;
    if (snapshot == null || connectionId == null || connectionId.isEmpty) {
      return AgentRunContext(
        runId: runId,
        dbType: DatabaseType.mysql,
        readOnly: false,
      );
    }
    return AgentRunContext(
      runId: runId,
      connectionId: connectionId,
      connectionName: snapshot.connectionName,
      databaseName: snapshot.databaseName,
      dbType: snapshot.dbType,
      readOnly: snapshot.readOnly,
    );
  }

  AgentChatConfig _resolveAgentChatConfig() =>
      agentChatConfigReader?.call() ??
      const AgentChatConfig(provider: '', model: '', apiKey: '');

  bool get aiPanelOpen => _aiPanelOpen;
  bool get aiPanelFullscreen => _aiPanelFullscreen;
  List<AiMessage> get aiMessages => sessionManager.currentMessages;
  List<AiBookmark> get aiBookmarks => sessionManager.bookmarks;
  String get selectedTable => _selectedTable;
  String get searchQuery => _searchQuery;
  String? get selectedConnectionId => _selectedConnectionId;
  String? get selectedDatabaseName => _selectedDatabaseName;
  List<String> get selectedConnectionDatabases =>
      List.unmodifiable(_selectedConnectionDatabases);

  AiSessionManager get aiConversationService => sessionManager;

  void toggleAiPanel() {
    _aiPanelOpen = !_aiPanelOpen;
    notifyListeners();
  }

  void openAiPanel() {
    if (!_aiPanelOpen) {
      _aiPanelOpen = true;
      notifyListeners();
    }
  }

  void closeAiPanel() {
    if (_aiPanelOpen) {
      _aiPanelOpen = false;
      notifyListeners();
    }
  }

  void toggleAiPanelFullscreen() {
    _aiPanelFullscreen = !_aiPanelFullscreen;
    notifyListeners();
  }

  void setAiPanelFullscreen(bool value) {
    if (_aiPanelFullscreen != value) {
      _aiPanelFullscreen = value;
      notifyListeners();
    }
  }

  void setAiPanelOpen(bool value) {
    if (_aiPanelOpen != value) {
      _aiPanelOpen = value;
      notifyListeners();
    }
  }

  void switchSession(String sessionId) {
    sessionManager.switchSession(sessionId);
  }

  void ensureSession() {
    if (sessionManager.currentSession == null) {
      sessionManager.createSession();
    }
  }

  /// 创建一个全新的 AI 会话，用于独立的分析任务。
  void createNewSession({String? title}) {
    sessionManager.createSession(title: title);
  }

  // ==================== 工作台上下文锁定（design-ai-workbench §4.3，T08）====================

  /// 当前会话的工作台上下文锁定快照；null = 跟随态（design §5.1）。
  /// 锁定存于 session.metadata['workbench.contextLock']，随会话持久化，
  /// 切换会话各带各的锁定（AC3.5），随会话删除而消亡。
  WorkbenchContextLock? get workbenchContextLock =>
      WorkbenchContextLock.fromMetadata(
        sessionManager.currentSession?.metadata,
      );

  /// 将上下文锁定到当前会话（写入 workbench.context 命名空间并写穿落盘）。
  /// 会话为空时不生效（无会话即无处可存）。
  void lockWorkbenchContext(String connectionId, String? databaseName) {
    final session = sessionManager.currentSession;
    if (session == null) return;
    final lock = WorkbenchContextLock(
      connectionId: connectionId,
      databaseName: databaseName,
      lockedAt: DateTime.now(),
    );
    // 就地写入会话 metadata（AiSessionManager 无整 map 更新路径，锁定作为
    // 数据透传不进 manager；初始化见 AiConversationSession.metadata 注释）。
    session.metadata ??= <String, dynamic>{};
    session.metadata![WorkbenchContextLock.metadataKey] = lock.toJson();
    // 就地变更不触发 manager 的防抖持久化，显式走既有 persist() 写穿
    // （persist 全程 try/catch，无文档目录环境失败仅记日志）。
    unawaited(sessionManager.persist());
    // D12（T14）：上下文锁定变更 → 会话放行账本失效（运行中不中断——
    // D15 快照保证在途 run 读取来源不漂移）。
    agentRunner.ledger.clearAll();
    notifyListeners();
  }

  /// 解除当前会话的锁定（仅移除锁定键，保留 metadata 其它条目）。
  void unlockWorkbenchContext() {
    final session = sessionManager.currentSession;
    final metadata = session?.metadata;
    if (session == null || metadata == null) return;
    if (!metadata.containsKey(WorkbenchContextLock.metadataKey)) return;
    metadata.remove(WorkbenchContextLock.metadataKey);
    unawaited(sessionManager.persist());
    // D12（T14）：同 lockWorkbenchContext——锁定变更即失效放行。
    agentRunner.ledger.clearAll();
    notifyListeners();
  }

  void toggleBookmark(String messageId) {
    sessionManager.toggleBookmark(messageId);
  }

  bool isMessageBookmarked(String messageId) {
    return sessionManager.isBookmarked(messageId);
  }

  void addAiMessage(AiMessage message) {
    sessionManager.addMessage(message);
  }

  void removeLastAiMessage() {
    final messages = sessionManager.currentMessages.toList();
    if (messages.isNotEmpty) {
      messages.removeLast();
      sessionManager.updateMessages(messages);
    }
  }

  void updateAiMessageContent(String messageId, String content) {
    sessionManager.updateMessage(messageId, content: content);
  }

  void appendAiMessageContent(String messageId, String chunk) {
    sessionManager.appendMessageContent(messageId, chunk);
  }

  void updateAiMessageReasoning(String messageId, String reasoningContent) {
    sessionManager.updateMessage(messageId, reasoningContent: reasoningContent);
  }

  void appendAiMessageReasoning(String messageId, String chunk) {
    sessionManager.appendMessageReasoning(messageId, chunk);
  }

  void updateAiMessageLoading(String messageId, bool isLoading) {
    sessionManager.updateMessage(messageId, isLoading: isLoading);
  }

  void updateAiMessage({
    required String messageId,
    String? content,
    String? reasoningContent,
    String? code,
    bool? isDangerous,
  }) {
    sessionManager.updateMessage(
      messageId,
      content: content,
      reasoningContent: reasoningContent,
      code: code,
      isDangerous: isDangerous,
    );
  }

  void clearAiMessages() {
    sessionManager.updateMessages([]);
  }

  void setSearchQuery(String query) {
    if (_searchQuery != query) {
      _searchQuery = query;
      notifyListeners();
    }
  }

  void setSelectedTable(String table) {
    if (_selectedTable != table) {
      _selectedTable = table;
      contextBuilder.setCurrentTable(table);
      notifyListeners();
    }
  }

  void setSelectedConnection(String? connectionId) {
    if (_selectedConnectionId != connectionId) {
      _selectedConnectionId = connectionId;
      contextBuilder.setCurrentConnection(connectionId);
      notifyListeners();
    }
  }

  void setSelectedDatabase(String? databaseName) {
    if (_selectedDatabaseName != databaseName) {
      _selectedDatabaseName = databaseName;
      contextBuilder.setCurrentDatabase(databaseName);
      notifyListeners();
    }
  }

  void setSelectedConnectionDatabases(List<String> databases) {
    _selectedConnectionDatabases = List.from(databases);
    notifyListeners();
  }

  @override
  void dispose() {
    agentRunner.dispose();
    orchestrator.dispose();
    sessionManager.removeListener(_onSessionChange);
    super.dispose();
  }
}
