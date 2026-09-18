import 'dart:async';
import '../../utils/app_logger.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/ai_conversation_session.dart';
import '../../models/database_models.dart';
import '../../models/ai_message_type.dart';
import '../../models/agent_checkpoint.dart';
import 'ai_service_localizations.dart';

abstract class ISessionManager {
  List<AiConversationSession> get sessions;
  AiConversationSession? get currentSession;
  List<AiBookmark> get bookmarks;
  List<AiMessage> get currentMessages;

  AiConversationSession createSession({String? title, String? parentMessageId, String locale = 'en'});
  void switchSession(String sessionId);
  void deleteSession(String sessionId);
  void restoreSession(AiConversationSession session);
  void archiveSession(String sessionId);
  void updateSessionTitle(String sessionId, String title);
  void updateSessionMetadata(
    String sessionId, {
    String? goalSummary,
    int? userMessageCount,
    DateTime? lastSummarizedAt,
  });

  void addMessage(AiMessage message);
  void updateMessages(List<AiMessage> messages);
  void appendMessageContent(String messageId, String chunk);
  void appendMessageReasoning(String messageId, String chunk);
  void updateMessage(
    String messageId, {
    String? content,
    String? reasoningContent,
    String? code,
    List<String>? extractedCommands,
    bool? isDangerous,
    bool? isLoading,
    AiMessageStatus? status,
    String? errorMessage,
    String? checkpointId,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
  });

  void setBookmarks(List<AiBookmark> bookmarks);
  void toggleBookmark(String messageId);
  bool isBookmarked(String messageId);

  Future<void> load();
  Future<void> persist();

  void saveCheckpoint(AgentCheckpoint checkpoint);
  AgentCheckpoint? getCheckpoint(String checkpointId);
  void deleteCheckpoint(String checkpointId);
  List<AgentCheckpoint> getSessionCheckpoints(String sessionId);
}

class AiSessionManager extends ChangeNotifier implements ISessionManager {
  final List<AiConversationSession> _sessions = [];
  AiConversationSession? _currentSession;
  int _sessionCounter = 0;

  final Map<String, List<AiMessage>> _sessionMessages = {};
  final List<AiBookmark> _bookmarks = [];
  final Map<String, AgentCheckpoint> _checkpoints = {};

  Directory? _docsDir;
  Timer? _persistDebounceTimer;

  AiSessionManager();

  @override
  List<AiConversationSession> get sessions => List.unmodifiable(_sessions);

  @override
  AiConversationSession? get currentSession => _currentSession;

  @override
  List<AiBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  @override
  List<AiMessage> get currentMessages {
    if (_currentSession == null) return [];
    return List.unmodifiable(_sessionMessages[_currentSession!.id] ?? []);
  }

  Future<void> _ensureInit() async {
    _docsDir ??= await getApplicationDocumentsDirectory();
  }

  void resetForTests() {
    _docsDir = null;
  }

  @override
  AiConversationSession createSession({
    String? title,
    String? parentMessageId,
    String locale = 'en',
  }) {
    _sessionCounter++;
    final session = AiConversationSession(
      id: '${DateTime.now().millisecondsSinceEpoch}_$_sessionCounter',
      title: title ?? AiServiceLocalizations(locale).newChatTitle(_sessions.length + 1),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messageIds: [],
      parentSessionId: parentMessageId != null ? _currentSession?.id : null,
    );
    _sessions.insert(0, session);
    _currentSession = session;
    _sessionMessages[session.id] = [];
    _requestPersist();
    _saveActiveSessionId();
    notifyListeners();
    return session;
  }

  @override
  void switchSession(String sessionId) {
    _currentSession = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => _sessions.first,
    );
    _saveActiveSessionId();
    notifyListeners();
  }

  @override
  void deleteSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    _sessionMessages.remove(sessionId);
    if (_currentSession?.id == sessionId) {
      _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
    }
    _requestPersist();
    _saveActiveSessionId();
    _deleteSessionFiles(sessionId);
    notifyListeners();
  }

  @override
  void restoreSession(AiConversationSession session) {
    _sessions.insert(0, session);
    _requestPersist();
    _saveActiveSessionId();
    notifyListeners();
  }

  @override
  void archiveSession(String sessionId) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      _sessions[index] = _sessions[index].copyWith(isArchived: true);
      _requestPersist();
      notifyListeners();
    }
  }

  @override
  void updateSessionTitle(String sessionId, String title) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      _sessions[index] = _sessions[index].copyWith(
        title: title,
        updatedAt: DateTime.now(),
      );
      if (_currentSession?.id == sessionId) {
        _currentSession = _sessions[index];
      }
      _requestPersist();
      notifyListeners();
    }
  }

  @override
  void updateSessionMetadata(
    String sessionId, {
    String? goalSummary,
    int? userMessageCount,
    DateTime? lastSummarizedAt,
  }) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;
    _sessions[index] = _sessions[index].copyWith(
      goalSummary: goalSummary,
      userMessageCount: userMessageCount,
      lastSummarizedAt: lastSummarizedAt,
    );
    if (_currentSession?.id == sessionId) {
      _currentSession = _sessions[index];
    }
    _requestPersist();
    notifyListeners();
  }

  @override
  void addMessage(AiMessage message) {
    final session = _currentSession;
    if (session == null) return;
    session.messageIds.add(message.id);
    _sessionMessages.putIfAbsent(session.id, () => []);
    _sessionMessages[session.id]!.add(message);
    final index = _sessions.indexWhere((s) => s.id == session.id);
    if (index != -1) {
      _sessions[index] = session.copyWith(updatedAt: DateTime.now());
      _currentSession = _sessions[index];
    }
    _requestPersist();
    notifyListeners();
  }

  @override
  void updateMessages(List<AiMessage> messages) {
    if (_currentSession == null) return;
    _sessionMessages[_currentSession!.id] = List.from(messages);
    _requestPersist();
    notifyListeners();
  }

  @override
  void appendMessageContent(String messageId, String chunk) {
    final messages = currentMessages.toList();
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      messages[index] = messages[index].copyWith(
        content: messages[index].content + chunk,
      );
      updateMessages(messages);
    }
  }

  @override
  void appendMessageReasoning(String messageId, String chunk) {
    final messages = currentMessages.toList();
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final current = messages[index].reasoningContent ?? '';
      messages[index] = messages[index].copyWith(
        reasoningContent: current + chunk,
      );
      updateMessages(messages);
    }
  }

  @override
  void updateMessage(
    String messageId, {
    String? content,
    String? reasoningContent,
    String? code,
    List<String>? extractedCommands,
    bool? isDangerous,
    bool? isLoading,
    AiMessageStatus? status,
    String? errorMessage,
    String? checkpointId,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
  }) {
    final messages = currentMessages.toList();
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final oldMsg = messages[index];
      final newMsg = oldMsg.copyWith(
        content: content,
        reasoningContent: reasoningContent,
        code: code,
        extractedCommands: extractedCommands,
        isDangerous: isDangerous,
        isLoading: isLoading,
        status: status,
        errorMessage: errorMessage,
        checkpointId: checkpointId,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      );
      AppLogger.d(
        'AiSession',
        '📋 updateMessage[$messageId]: oldReasoning=${oldMsg.reasoningContent?.length ?? 0}, newReasoning=${newMsg.reasoningContent?.length ?? 0}',
      );
      messages[index] = newMsg;
      updateMessages(messages);
    } else {
      AppLogger.d(
        'AiSession',
        '⚠️ updateMessage: message $messageId not found!',
      );
    }
  }

  @override
  void setBookmarks(List<AiBookmark> value) {
    _bookmarks.clear();
    _bookmarks.addAll(value);
    _requestPersist();
    notifyListeners();
  }

  @override
  void toggleBookmark(String messageId) {
    final current = _bookmarks.any((b) => b.messageId == messageId);
    final updated = List<AiBookmark>.from(_bookmarks);
    if (!current) {
      updated.add(
        AiBookmark(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          messageId: messageId,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      updated.removeWhere((b) => b.messageId == messageId);
    }
    setBookmarks(updated);
  }

  @override
  bool isBookmarked(String messageId) {
    return _bookmarks.any((b) => b.messageId == messageId);
  }

  AiConversationSession? branchFromMessage(
    String messageId,
    String messageContent, {
    String locale = 'en',
  }) {
    if (_currentSession == null) return null;

    final preview = messageContent.length > 20
        ? '${messageContent.substring(0, 20)}...'
        : messageContent;
    return createSession(
      title: AiServiceLocalizations(locale).branchSessionTitle(preview),
      parentMessageId: messageId,
      locale: locale,
    );
  }

  @override
  Future<void> load() async {
    try {
      await _ensureInit();

      final sessions = await _loadSessions();
      final bookmarks = await _loadBookmarks();

      _sessions.clear();
      _sessions.addAll(
        sessions.where((s) => !s.isArchived).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );
      _sessions.addAll(
        sessions.where((s) => s.isArchived).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );

      _sessionMessages.clear();
      for (final s in sessions) {
        final messages = await _loadMessages(s.id);
        _sessionMessages[s.id] = messages;
      }

      _bookmarks.clear();
      _bookmarks.addAll(bookmarks);

      final checkpoints = await _loadCheckpoints();
      _checkpoints.clear();
      for (final cp in checkpoints) {
        _checkpoints[cp.id] = cp;
      }

      final prefs = await SharedPreferences.getInstance();
      final activeId = prefs.getString('ai_active_session_id');
      if (activeId != null && _sessions.any((s) => s.id == activeId)) {
        _currentSession = _sessions.firstWhere((s) => s.id == activeId);
      } else {
        _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
      }
      notifyListeners();
    } catch (e) {
      _sessions.clear();
      _sessionMessages.clear();
      _currentSession = null;
      notifyListeners();
    }
  }

  void _requestPersist() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await persist();
    });
  }

  @override
  Future<void> persist() async {
    try {
      await _ensureInit();
      await _saveSessions(_sessions);
      await _saveBookmarks(_bookmarks);
      for (final entry in _sessionMessages.entries) {
        await _saveMessages(entry.key, entry.value);
      }
      await _saveCheckpoints();
    } catch (e) {
      AppLogger.d('AiSession', 'AiSessionManager persistence failed: $e');
    }
  }

  Future<void> _saveActiveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentSession != null) {
      await prefs.setString('ai_active_session_id', _currentSession!.id);
    } else {
      await prefs.remove('ai_active_session_id');
    }
  }

  Future<void> _saveSessions(List<AiConversationSession> sessions) async {
    final file = File('${_docsDir!.path}/ai_sessions.json');
    final list = sessions.map((s) => s.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<List<AiConversationSession>> _loadSessions() async {
    final file = File('${_docsDir!.path}/ai_sessions.json');
    if (!await file.exists()) return [];
    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((e) => AiConversationSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveMessages(String sessionId, List<AiMessage> messages) async {
    final file = File('${_docsDir!.path}/ai_messages_$sessionId.json');
    final list = messages.map((m) => m.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<List<AiMessage>> _loadMessages(String sessionId) async {
    final file = File('${_docsDir!.path}/ai_messages_$sessionId.json');
    if (!await file.exists()) return [];
    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveBookmarks(List<AiBookmark> bookmarks) async {
    final file = File('${_docsDir!.path}/ai_bookmarks.json');
    final list = bookmarks.map((b) => b.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<List<AiBookmark>> _loadBookmarks() async {
    final file = File('${_docsDir!.path}/ai_bookmarks.json');
    if (!await file.exists()) return [];
    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((e) => AiBookmark.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _deleteSessionFiles(String sessionId) async {
    final file = File('${_docsDir!.path}/ai_messages_$sessionId.json');
    if (await file.exists()) await file.delete();
  }

  Future<void> _saveCheckpoints() async {
    final file = File('${_docsDir!.path}/ai_checkpoints.json');
    final list = _checkpoints.values.map((c) => c.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<List<AgentCheckpoint>> _loadCheckpoints() async {
    final file = File('${_docsDir!.path}/ai_checkpoints.json');
    if (!await file.exists()) return [];
    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((e) => AgentCheckpoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  void saveCheckpoint(AgentCheckpoint checkpoint) {
    _checkpoints[checkpoint.id] = checkpoint;
    _requestPersist();
  }

  @override
  AgentCheckpoint? getCheckpoint(String checkpointId) {
    return _checkpoints[checkpointId];
  }

  @override
  void deleteCheckpoint(String checkpointId) {
    _checkpoints.remove(checkpointId);
    _requestPersist();
  }

  @override
  List<AgentCheckpoint> getSessionCheckpoints(String sessionId) {
    return _checkpoints.values.where((cp) => cp.sessionId == sessionId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  void dispose() {
    _persistDebounceTimer?.cancel();
    super.dispose();
  }
}
