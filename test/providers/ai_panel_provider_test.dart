import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart';
import 'package:dbmaster/models/database_models.dart';

AiMessage _testUserMessage(String content) {
  return AiMessage(
    id: 'msg_${DateTime.now().millisecondsSinceEpoch}_$content',
    isUser: true,
    content: content,
    timestamp: DateTime.now(),
  );
}

AiMessage _testAssistantMessage(String content) {
  return AiMessage(
    id: 'msg_${DateTime.now().millisecondsSinceEpoch}_$content',
    isUser: false,
    content: content,
    timestamp: DateTime.now(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiPanelProvider', () {
    late AiPanelProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      provider = AiPanelProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    group('初始状态', () {
      test('AI 面板初始关闭', () {
        expect(provider.aiPanelOpen, isFalse);
      });

      test('AI 面板初始非全屏', () {
        expect(provider.aiPanelFullscreen, isFalse);
      });

      test('初始无消息', () {
        expect(provider.aiMessages, isEmpty);
      });

      test('初始无书签', () {
        expect(provider.aiBookmarks, isEmpty);
      });

      test('初始选中表为空', () {
        expect(provider.selectedTable, isEmpty);
      });

      test('初始搜索查询为空', () {
        expect(provider.searchQuery, isEmpty);
      });

      test('初始连接和数据库为空', () {
        expect(provider.selectedConnectionId, isNull);
        expect(provider.selectedDatabaseName, isNull);
        expect(provider.selectedConnectionDatabases, isEmpty);
      });
    });

    group('面板开关', () {
      test('toggleAiPanel 切换打开', () {
        provider.toggleAiPanel();
        expect(provider.aiPanelOpen, isTrue);
      });

      test('toggleAiPanel 切换关闭', () {
        provider.toggleAiPanel();
        provider.toggleAiPanel();
        expect(provider.aiPanelOpen, isFalse);
      });

      test('openAiPanel 打开', () {
        provider.openAiPanel();
        expect(provider.aiPanelOpen, isTrue);
      });

      test('openAiPanel 重复调用不改变状态', () {
        provider.openAiPanel();
        provider.openAiPanel();
        expect(provider.aiPanelOpen, isTrue);
      });

      test('closeAiPanel 关闭', () {
        provider.openAiPanel();
        provider.closeAiPanel();
        expect(provider.aiPanelOpen, isFalse);
      });

      test('toggleAiPanelFullscreen 切换全屏', () {
        provider.toggleAiPanelFullscreen();
        expect(provider.aiPanelFullscreen, isTrue);
      });

      test('setAiPanelFullscreen 设置值', () {
        provider.setAiPanelFullscreen(true);
        expect(provider.aiPanelFullscreen, isTrue);
        provider.setAiPanelFullscreen(false);
        expect(provider.aiPanelFullscreen, isFalse);
      });

      test('setAiPanelFullscreen 相同值不重复通知', () {
        provider.setAiPanelFullscreen(true);
        provider.setAiPanelFullscreen(true);
        expect(provider.aiPanelFullscreen, isTrue);
      });
    });

    group('会话管理', () {
      test('ensureSession 创建默认会话', () {
        provider.ensureSession();
        expect(provider.aiConversationService.currentSession, isNotNull);
      });

      test('createNewSession 创建指定标题的新会话', () {
        provider.ensureSession();
        final previousSession = provider.aiConversationService.currentSession;
        provider.createNewSession(title: 'AI 分析：test_table');
        final currentSession = provider.aiConversationService.currentSession;
        expect(currentSession, isNotNull);
        expect(currentSession!.id, isNot(equals(previousSession!.id)));
        expect(currentSession.title, equals('AI 分析：test_table'));
      });

      test('switchSession 切换会话', () {
        provider.ensureSession();
        final session1 = provider.aiConversationService.currentSession!;
        provider.aiConversationService.createSession();
        final session2 = provider.aiConversationService.currentSession!;
        expect(session1.id, isNot(equals(session2.id)));

        provider.switchSession(session1.id);
        expect(
          provider.aiConversationService.currentSession!.id,
          equals(session1.id),
        );
      });
    });

    group('消息操作', () {
      test('addAiMessage 添加消息', () {
        provider.ensureSession();
        final message = _testUserMessage('Hello AI');
        provider.addAiMessage(message);
        expect(provider.aiMessages.length, equals(1));
        expect(provider.aiMessages[0].content, equals('Hello AI'));
      });

      test('clearAiMessages 清空消息', () {
        provider.ensureSession();
        provider.addAiMessage(_testUserMessage('Hello'));
        provider.clearAiMessages();
        expect(provider.aiMessages, isEmpty);
      });

      test('removeLastAiMessage 移除最后一条', () {
        provider.ensureSession();
        provider.addAiMessage(_testUserMessage('First'));
        provider.addAiMessage(_testUserMessage('Second'));
        provider.removeLastAiMessage();
        expect(provider.aiMessages.length, equals(1));
        expect(provider.aiMessages[0].content, equals('First'));
      });

      test('updateAiMessageContent 更新内容', () {
        provider.ensureSession();
        final message = _testUserMessage('Original');
        provider.addAiMessage(message);
        provider.updateAiMessageContent(message.id, 'Updated');
        expect(provider.aiMessages[0].content, equals('Updated'));
      });

      test('appendAiMessageContent 追加内容', () {
        provider.ensureSession();
        final message = _testAssistantMessage('Hello');
        provider.addAiMessage(message);
        provider.appendAiMessageContent(message.id, ' World');
        expect(provider.aiMessages[0].content, equals('Hello World'));
      });
    });

    group('书签操作', () {
      test('toggleBookmark 添加书签', () {
        provider.ensureSession();
        final message = _testAssistantMessage('Important');
        provider.addAiMessage(message);
        provider.toggleBookmark(message.id);
        expect(provider.isMessageBookmarked(message.id), isTrue);
      });

      test('toggleBookmark 取消书签', () {
        provider.ensureSession();
        final message = _testAssistantMessage('Important');
        provider.addAiMessage(message);
        provider.toggleBookmark(message.id);
        provider.toggleBookmark(message.id);
        expect(provider.isMessageBookmarked(message.id), isFalse);
      });
    });

    group('搜索与选择', () {
      test('setSearchQuery 设置查询', () {
        provider.setSearchQuery('test query');
        expect(provider.searchQuery, equals('test query'));
      });

      test('setSelectedTable 设置表', () {
        provider.setSelectedTable('users');
        expect(provider.selectedTable, equals('users'));
      });

      test('setSelectedConnection 设置连接', () {
        provider.setSelectedConnection('conn_1');
        expect(provider.selectedConnectionId, equals('conn_1'));
      });

      test('setSelectedDatabase 设置数据库', () {
        provider.setSelectedDatabase('test_db');
        expect(provider.selectedDatabaseName, equals('test_db'));
      });

      test('setSelectedConnectionDatabases 设置数据库列表', () {
        provider.setSelectedConnectionDatabases(['db1', 'db2', 'db3']);
        expect(
          provider.selectedConnectionDatabases,
          equals(['db1', 'db2', 'db3']),
        );
      });
    });
  });
}
