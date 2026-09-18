import 'package:flutter/foundation.dart';
import '../models/ai_conversation_session.dart';
import '../models/database_models.dart';
import '../services/ai/ai_session_manager.dart';
import '../services/ai/ai_context_builder.dart';
import '../services/ai_agent_runner.dart';
import '../services/ai_session_orchestrator.dart';
import '../services/database_service.dart';
import '../services/free_chat_runner.dart';
import 'task_provider.dart';

class AiPanelProvider extends ChangeNotifier {
  final AiSessionManager sessionManager;
  final AiContextBuilder contextBuilder;
  final DatabaseService? dbService;
  late final AiSessionOrchestrator orchestrator;

  /// Callback for requesting user confirmation before executing INSERT statements.
  /// Set by the UI layer (e.g., ai_panel_widget.dart).
  InsertConfirmationCallback? insertConfirmationCallback;

  bool _aiPanelOpen = false;
  bool _aiPanelFullscreen = false;
  String _selectedTable = '';
  String _searchQuery = '';
  String? _selectedConnectionId;
  String? _selectedDatabaseName;
  List<String> _selectedConnectionDatabases = [];

  AiPanelProvider({
    AiSessionManager? sessionManager,
    AiContextBuilder? contextBuilder,
    this.dbService,
    TaskProvider? taskProvider,
    AiAgentFactory? agentFactory,
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
    this.sessionManager.addListener(_onSessionChange);
  }

  void _onSessionChange() {
    notifyListeners();
  }

  void updateTaskProvider(TaskProvider taskProvider) {
    orchestrator.updateTaskProvider(taskProvider);
  }

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
    orchestrator.dispose();
    sessionManager.removeListener(_onSessionChange);
    super.dispose();
  }
}
