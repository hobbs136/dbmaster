// =============================================================================
// 通用数据库 Agent · 跨轮工具记忆（_buildPreviousHistory）单元测试。
// =============================================================================
// 验证：toolCall/toolResult 不再被整体过滤，而是以自描述摘要附到所属轮次
// 的 assistant 消息；仅保留最近 3 轮工具记忆；用户消息照常透传。
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/ai/ai_session_manager.dart';
import 'package:dbmaster/services/ai_session_orchestrator.dart';

AiMessage _user(String id, String text) =>
    AiMessage(id: id, isUser: true, content: text, timestamp: DateTime.now());

AiMessage _assistant(String id, String text) =>
    AiMessage(id: id, isUser: false, content: text, timestamp: DateTime.now());

AiMessage _toolCall(String id, String tool, Map<String, dynamic> args) =>
    AiMessage(
      id: id,
      isUser: false,
      content: '',
      timestamp: DateTime.now(),
      type: AiMessageType.toolCall,
      toolName: tool,
      toolArguments: args,
    );

AiMessage _toolResult(String id, String tool, String summary) => AiMessage(
  id: id,
  isUser: false,
  content: 'full output…',
  timestamp: DateTime.now(),
  type: AiMessageType.toolResult,
  toolName: tool,
  toolResultSummary: summary,
);

void main() {
  late AiSessionManager manager;
  late AiSessionOrchestrator orchestrator;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    manager = AiSessionManager();
    manager.createSession(locale: 'en');
    orchestrator = AiSessionOrchestrator(sessionManager: manager);
  });

  tearDown(() {
    orchestrator.dispose();
  });

  test('工具调用与结果以摘要附到所属轮次的 assistant 消息', () {
    manager.addMessage(_user('u1', '删除 tasks 里的数据'));
    manager.addMessage(
      _toolCall('tc1', 'get_table_relationships', {'table': 'tasks'}),
    );
    manager.addMessage(
      _toolResult(
        'tr1',
        'get_table_relationships',
        '{"incoming_references":[{"table":"task_comments","on_delete":"CASCADE"}]}',
      ),
    );
    manager.addMessage(_assistant('a1', '方案如下…'));

    final history = orchestrator.buildPreviousHistoryForTesting(
      _user('u2', '继续'),
    );

    expect(history, hasLength(2));
    expect(history[0]['role'], 'user');
    expect(history[1]['role'], 'assistant');
    final assistantContent = history[1]['content'] as String;
    expect(assistantContent, contains('方案如下…'));
    expect(
      assistantContent,
      contains('call get_table_relationships(table=tasks)'),
    );
    expect(
      assistantContent,
      contains('result get_table_relationships: {"incoming_references"'),
    );
  });

  test('仅保留最近 3 轮工具记忆，更早轮次剥离摘要', () {
    // 4 轮：每轮 user → toolCall → assistant
    for (var round = 1; round <= 4; round++) {
      manager.addMessage(_user('u$round', 'q$round'));
      manager.addMessage(
        _toolCall('tc$round', 'run_readonly_query', {'sql': 'SELECT $round'}),
      );
      manager.addMessage(
        _toolResult('tr$round', 'run_readonly_query', 'result payload $round'),
      );
      manager.addMessage(_assistant('a$round', 'answer$round'));
    }

    final history = orchestrator.buildPreviousHistoryForTesting(
      _user('u5', 'next'),
    );

    // 4 user + 4 assistant = 8 条
    expect(history, hasLength(8));
    final withMemory = history
        .where((h) => (h['content'] as String).contains('[Tools used'))
        .toList();
    // 最近 3 轮（round 2/3/4）保留
    expect(withMemory, hasLength(3));
    for (final h in withMemory) {
      expect(h['content'], isNot(contains('answer1')));
    }
    // 最早一轮的工具摘要被剥离
    final firstAssistant = history[1]['content'] as String;
    expect(firstAssistant, contains('answer1'));
    expect(firstAssistant, isNot(contains('[Tools used')));
  });

  test('无工具消息时行为与旧逻辑一致（仅 chat 透传）', () {
    manager.addMessage(_user('u1', 'hello'));
    manager.addMessage(_assistant('a1', 'hi'));

    final history = orchestrator.buildPreviousHistoryForTesting(
      _user('u2', 'next'),
    );

    expect(history, hasLength(2));
    expect(history[0], {'role': 'user', 'content': 'hello'});
    expect(history[1], {'role': 'assistant', 'content': 'hi'});
  });

  test('超长工具结果摘要截断到预算内', () {
    manager.addMessage(_user('u1', 'q'));
    manager.addMessage(
      _toolCall('tc1', 'run_readonly_query', {'sql': 'SELECT 1'}),
    );
    manager.addMessage(_toolResult('tr1', 'run_readonly_query', 'x' * 2000));
    manager.addMessage(_assistant('a1', 'done'));

    final history = orchestrator.buildPreviousHistoryForTesting(
      _user('u2', 'next'),
    );
    final content = history[1]['content'] as String;
    expect(content, contains('result run_readonly_query:'));
    // 摘要行被压到 ~400 字符 + 前缀，远小于 2000
    final line = content
        .split('\n')
        .firstWhere((l) => l.contains('result run_readonly_query:'));
    expect(line.length, lessThan(500));
  });
}
