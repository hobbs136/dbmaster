import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/ai_conversation_session.dart';
import '../models/database_models.dart';

class AiSessionStore {
  static final AiSessionStore _instance = AiSessionStore._internal();
  factory AiSessionStore() => _instance;
  AiSessionStore._internal();

  Directory? _docsDir;

  void resetForTests() {
    _docsDir = null;
  }

  Future<void> _ensureInit() async {
    _docsDir ??= await getApplicationDocumentsDirectory();
  }

  Future<void> saveSessions(List<AiConversationSession> sessions) async {
    await _ensureInit();
    final file = File('${_docsDir!.path}/ai_sessions.json');
    final list = sessions.map((s) => s.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<List<AiConversationSession>> loadSessions() async {
    await _ensureInit();
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

  Future<void> saveMessages(String sessionId, List<AiMessage> messages) async {
    await _ensureInit();
    final file = File('${_docsDir!.path}/ai_messages_$sessionId.json');
    final list = messages.map((m) => m.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<List<AiMessage>> loadMessages(String sessionId) async {
    await _ensureInit();
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

  Future<void> saveBookmarks(List<AiBookmark> bookmarks) async {
    await _ensureInit();
    final file = File('${_docsDir!.path}/ai_bookmarks.json');
    final list = bookmarks.map((b) => b.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<List<AiBookmark>> loadBookmarks() async {
    await _ensureInit();
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

  Future<void> deleteSession(String sessionId) async {
    await _ensureInit();
    final file = File('${_docsDir!.path}/ai_messages_$sessionId.json');
    if (await file.exists()) await file.delete();
  }
}
