import '../../models/database_models.dart';
import '../../models/ai_message_type.dart';
import 'ai_client.dart';
import 'ai_service_localizations.dart';

class BuildContextResult {
  final String systemPrompt;
  final List<Map<String, dynamic>> messages;
  BuildContextResult({required this.systemPrompt, required this.messages});
}

class AiContextBuilder {
  final Map<String, List<String>> _tableContextCache = {};
  final Map<String, String> _tableSchemaCache = {};
  String? _currentTable;
  String? _currentConnectionId;
  String? _currentDatabaseName;
  final List<String> _recentQueries = [];

  static const int _defaultTokenBudget = 8000;
  static const int _tokensPerMessage = 50;
  static const int _retainedRounds = 4;

  static final Map<String, int> _modelContextWindows = {
    'moonshot-v1-8k': 8192,
    'moonshot-v1-32k': 32768,
    'moonshot-v1-128k': 128000,
    'deepseek-chat': 64000,
    'deepseek-coder': 64000,
    'deepseek-reasoner': 64000,
    'gpt-4o': 128000,
    'gpt-4o-mini': 128000,
    'gpt-3.5-turbo': 16385,
    'claude-3-5-sonnet': 200000,
    'glm-4': 128000,
    'glm-4-flash': 128000,
    'glm-4-coder': 128000,
  };

  static final RegExp _chineseCharRegex = RegExp(r'[\u4e00-\u9fa5]');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  void setCurrentTable(String? table) {
    _currentTable = table;
  }

  void setCurrentConnection(String? connId) {
    _currentConnectionId = connId;
  }

  void setCurrentDatabase(String? db) {
    _currentDatabaseName = db;
    clearCache();
  }

  String? getCachedTableSchema(String tableName) =>
      _tableSchemaCache[tableName];

  void cacheTableSchema(String tableName, String schema) {
    _tableSchemaCache[tableName] = schema;
  }

  void clearCache() {
    _tableSchemaCache.clear();
  }

  String? get currentTable => _currentTable;
  String? get currentConnection => _currentConnectionId;
  String? get currentDatabase => _currentDatabaseName;

  void addRecentQuery(String query) {
    _recentQueries.insert(0, query);
    if (_recentQueries.length > 20) _recentQueries.removeLast();
  }

  List<String> get recentQueries => List.unmodifiable(_recentQueries);

  String buildContextPrompt({String locale = 'en'}) {
    final l10n = AiServiceLocalizations(locale);
    final buffer = StringBuffer();
    if (_currentDatabaseName != null) {
      buffer.writeln(l10n.contextCurrentDatabase(_currentDatabaseName!));
    }
    if (_currentTable != null) {
      buffer.writeln(l10n.contextCurrentTable(_currentTable!));
    }
    if (_recentQueries.isNotEmpty) {
      buffer.writeln(
        l10n.contextRecentQueries(_recentQueries.take(3).join('; ')),
      );
    }
    return buffer.toString();
  }

  void clear() {
    _tableContextCache.clear();
    _currentTable = null;
    _currentConnectionId = null;
    _currentDatabaseName = null;
    _recentQueries.clear();
  }

  static int _estimateTokens(String text, {String model = ''}) {
    if (text.isEmpty) return 0;

    final chineseChars = _chineseCharRegex.allMatches(text).length;
    final words = text
        .split(_whitespaceRegex)
        .where((w) => w.isNotEmpty)
        .toList();
    int englishWordCount = 0;
    int otherCharCount = 0;

    for (final word in words) {
      if (!_chineseCharRegex.hasMatch(word)) {
        englishWordCount++;
      }
    }

    otherCharCount = text.length - chineseChars;

    final baseTokens =
        (chineseChars * 1.5 + englishWordCount * 1.3 + otherCharCount * 0.25)
            .ceil();

    return _adjustForModel(baseTokens, model);
  }

  static int _adjustForModel(int baseTokens, String model) {
    if (model.isEmpty) return baseTokens;

    final modelLower = model.toLowerCase();
    if (modelLower.contains('glm') ||
        modelLower.contains('moonshot') ||
        modelLower.contains('kimi')) {
      return (baseTokens * 1.1).ceil();
    }
    if (modelLower.contains('deepseek')) {
      return (baseTokens * 1.05).ceil();
    }
    return baseTokens;
  }

  static int _tokenBudgetForModel(String model) {
    final window = _modelContextWindows[model];
    if (window == null) return _defaultTokenBudget;
    final budget = (window * 0.6).toInt();
    return budget.clamp(4000, 100000);
  }

  static BuildContextResult buildContext({
    required String fixedSystemPrompt,
    required List<AiMessage> allMessages,
    required String? goalSummary,
    required String model,
    String locale = 'en',
  }) {
    final l10n = AiServiceLocalizations(locale);
    final budget = _tokenBudgetForModel(model);
    final dynamicSystem = goalSummary != null && goalSummary.isNotEmpty
        ? '$fixedSystemPrompt\n\n${l10n.contextGoalSummary(goalSummary)}'
        : fixedSystemPrompt;

    final retainedStart = allMessages.length - (_retainedRounds * 2);
    final retainedMessages = retainedStart > 0
        ? allMessages.sublist(retainedStart)
        : allMessages;

    final history = <Map<String, dynamic>>[];
    if (goalSummary != null && goalSummary.isNotEmpty) {
      history.add({
        'role': 'assistant',
        'content': l10n.earlierContext(goalSummary),
      });
    }

    for (final msg in retainedMessages) {
      if (msg.type == AiMessageType.toolCall ||
          msg.type == AiMessageType.toolResult) {
        continue;
      }
      if (msg.type == AiMessageType.chat) {
        final entry = <String, dynamic>{
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.content,
        };
        if (!msg.isUser &&
            msg.reasoningContent != null &&
            msg.reasoningContent!.isNotEmpty) {
          entry['reasoning_content'] = msg.reasoningContent;
        }
        history.add(entry);
      }
    }

    int tokens = _estimateTokens(dynamicSystem, model: model);
    tokens += history.length * _tokensPerMessage;
    for (final m in history) {
      tokens += _estimateTokens((m['content'] ?? '') as String, model: model);
    }
    while (tokens > budget && history.length > 2) {
      history.removeAt(0);
      tokens = _estimateTokens(dynamicSystem, model: model);
      tokens += history.length * _tokensPerMessage;
      for (final m in history) {
        tokens += _estimateTokens((m['content'] ?? '') as String, model: model);
      }
    }

    return BuildContextResult(systemPrompt: dynamicSystem, messages: history);
  }

  static Future<String?> summarizeGoal({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required List<AiMessage> messages,
    String locale = 'en',
  }) async {
    if (messages.isEmpty) return null;
    final l10n = AiServiceLocalizations(locale);
    final buffer = StringBuffer();
    for (final msg in messages) {
      if (msg.type != AiMessageType.chat) continue;
      buffer.writeln('${msg.isUser ? "User" : "Assistant"}: ${msg.content}');
    }
    final prompt = l10n.summarizePrompt.replaceAll(
      '{messages}',
      buffer.toString(),
    );
    final summaryModel = pickFastModel(model);
    try {
      final aiClient = AiClient();
      final response = await aiClient.chat(
        provider: provider,
        model: summaryModel,
        apiKey: apiKey,
        baseUrl: baseUrl,
        message: prompt,
        timeout: const Duration(seconds: 15),
      );
      return response.content?.trim();
    } catch (_) {
      return null;
    }
  }

  static String pickFastModel(String currentModel) {
    if (currentModel.contains('moonshot')) return 'moonshot-v1-8k';
    if (currentModel.contains('deepseek')) return 'deepseek-chat';
    if (currentModel.contains('glm')) return 'glm-4-flash';
    if (currentModel.contains('gpt')) return 'gpt-4o-mini';
    return currentModel;
  }
}
