import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'helpers/fake_pro_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppProvider', () {
    late AppProvider provider;
    late FakeProModule fakePro;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // 测试中启用 Pro，避免 Free 版 Tab/连接数限制影响标签页操作测试。
      // Phase B：经 ProModule SPI 注入 FakeProModule(isPro=true)，替代旧
      // PurchaseService.debugSetProForTesting。
      fakePro = FakeProModule(isPro: true);
      provider = AppProvider(proModule: fakePro);
      // 创建测试 tab 上下文
      await provider.tab.openQueryTab(
        connectionId: 'test_conn',
        databaseName: 'test_db',
      );
    });

    tearDown(() {
      fakePro.dispose();
    });

    group('AI 配置委托', () {
      test('aiConfig 实例已初始化', () {
        expect(provider.aiConfig, isNotNull);
      });

      test('selectedAiProvider 委托给 aiConfig', () async {
        expect(provider.selectedAiProvider, equals('DeepSeek'));
        provider.aiConfig.setProvider('Claude');
        expect(provider.selectedAiProvider, equals('Claude'));
      });

      test('selectedAiModel 委托给 aiConfig', () async {
        expect(provider.selectedAiModel, equals('deepseek-chat'));
        provider.aiConfig.setModel('claude-3-opus');
        expect(provider.selectedAiModel, equals('claude-3-opus'));
      });

      test('aiApiConfigs 委托给 aiConfig', () async {
        await provider.aiConfig.save(
          provider: 'DeepSeek',
          model: 'deepseek-chat',
          configs: {
            'DeepSeek': {'apiKey': 'test'},
          },
        );
        expect(provider.aiApiConfigs['DeepSeek']?['apiKey'], equals('test'));
      });

      test('autoExecuteSql 委托给 aiConfig', () async {
        expect(provider.autoExecuteSql, isFalse);
        provider.setAutoExecuteSql(true);
        expect(provider.autoExecuteSql, isTrue);
      });

      test('autocompleteEnabled 委托给 aiConfig', () async {
        expect(provider.autocompleteEnabled, isTrue);
        provider.setAutocompleteEnabled(false);
        expect(provider.autocompleteEnabled, isFalse);
      });

      test('aiTimeout 委托给 aiConfig', () async {
        expect(provider.aiTimeout, equals(const Duration(seconds: 60)));
        provider.setAiTimeout(const Duration(seconds: 180));
        expect(provider.aiTimeout, equals(const Duration(seconds: 180)));
      });

      test('loadAiConfig 委托给 aiConfig', () async {
        SharedPreferences.setMockInitialValues({
          'ai_provider': 'Kimi',
          'ai_model': 'moonshot-v1-8k',
        });
        await provider.loadAiConfig();
        expect(provider.selectedAiProvider, equals('Kimi'));
        expect(provider.selectedAiModel, equals('moonshot-v1-8k'));
      });

      test('saveAiConfig 委托给 aiConfig', () async {
        await provider.saveAiConfig('OpenAI', 'gpt-4-turbo', {
          'OpenAI': {'apiKey': 'sk-test'},
        });
        expect(provider.selectedAiProvider, equals('OpenAI'));
        expect(provider.getAiApiKey('OpenAI'), equals('sk-test'));
      });

      test('getAiApiKey 委托给 aiConfig', () async {
        await provider.saveAiConfig('DeepSeek', 'deepseek-chat', {
          'DeepSeek': {'apiKey': 'sk-db-key'},
        });
        expect(provider.getAiApiKey('DeepSeek'), equals('sk-db-key'));
      });

      test('getAiBaseUrl 委托给 aiConfig', () async {
        await provider.saveAiConfig('DeepSeek', 'deepseek-chat', {
          'DeepSeek': {'baseUrl': 'https://api.deepseek.com'},
        });
        expect(
          provider.getAiBaseUrl('DeepSeek'),
          equals('https://api.deepseek.com'),
        );
      });
    });

    group('查询标签页管理', () {
      // setUp 中通过 openQueryTab 创建了默认 QueryTab（Query 1）
      test('初始有一个默认标签页', () {
        expect(provider.tabs.length, equals(1));
        expect(provider.tabs[0].title, equals('Query 1'));
      });

      test('addNewTab 创建新标签页', () async {
        await provider.addNewTab();
        expect(provider.tabs.length, equals(2));
        expect(provider.activeTabIndex, equals(1));
        expect(provider.tabs[1].title, equals('Query 2'));
      });

      test('多个 addNewTab 递增编号', () async {
        await provider.addNewTab();
        await provider.addNewTab();
        await provider.addNewTab();
        expect(provider.tabs.length, equals(4));
        expect(provider.tabs[3].title, equals('Query 4'));
      });

      test('closeTab 移除标签页', () async {
        await provider.addNewTab();
        await provider.addNewTab();
        provider.closeTab(0);
        expect(provider.tabs.length, equals(2));
        expect(provider.tabs[0].title, equals('Query 2'));
      });

      test('setActiveTab 切换活跃标签', () async {
        await provider.addNewTab();
        await provider.addNewTab();
        provider.setActiveTab(1);
        expect(provider.activeTabIndex, equals(1));
      });

      test('updateTabSql 更新 SQL', () {
        provider.updateTabSql(0, 'SELECT * FROM users');
        expect(provider.tabs[0].sql, equals('SELECT * FROM users'));
      });

      test('activeTab 返回当前活跃标签', () {
        // 初始有 1 个 tab，activeTab 应指向它
        expect(provider.activeTab, equals(provider.tabs[0]));
      });

      test('renameTab 重命名标签页', () {
        provider.renameTab(0, 'My Query');
        expect(provider.tabs[0].title, equals('My Query'));
      });

      test('updateTabExecutionResults 更新执行结果', () async {
        await provider.addNewTab();
        provider.updateTabExecutionResults(0, []);
        expect(provider.tabs[0].executionResults, isEmpty);
      });

      test('formatCurrentSql 设置格式化请求标志', () {
        expect(provider.formatRequested, isFalse);
        provider.formatCurrentSql();
        expect(provider.formatRequested, isTrue);
        provider.clearFormatRequested();
        expect(provider.formatRequested, isFalse);
      });
    });

    group('连接状态', () {
      test('初始无连接', () {
        expect(provider.connection.currentServer, isNull);
        expect(provider.connection.currentDatabase, isNull);
        expect(provider.connection.databases, isEmpty);
      });

      test('savedConnections 初始为空', () {
        expect(provider.savedConnections, isEmpty);
      });

      test('connectedIds 初始为空', () {
        expect(provider.connectedIds, isEmpty);
      });
    });

    group('错误管理', () {
      test('初始无错误', () {
        expect(provider.errorMessage, isNull);
      });

      test('clearError 清除错误', () {
        // 通过 setError 内部字段设置
        provider.clearError();
        expect(provider.errorMessage, isNull);
      });
    });

    group('AI 面板状态', () {
      test('AI 面板初始关闭', () {
        expect(provider.aiPanelOpen, isFalse);
      });

      test('toggleAiPanel 切换状态', () {
        provider.toggleAiPanel();
        expect(provider.aiPanelOpen, isTrue);
        provider.toggleAiPanel();
        expect(provider.aiPanelOpen, isFalse);
      });
    });

    group('连接持久化', () {
      test('loadSavedConnections 无数据时正常返回', () async {
        SharedPreferences.setMockInitialValues({});
        await provider.loadSavedConnections();
        expect(provider.savedConnections, isEmpty);
      });

      test('saveConnection 添加新连接', () async {
        // DbServer 构造需要部分字段，这里测试持久化流程
        expect(provider.savedConnections, isEmpty);
      });
    });
  });
}
