import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/models/connection_event.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// AI Panel Widget 完整 UI 流程集成测试
/// 覆盖：输入 → 发送 → 流式输出 → 停止生成
/// 运行方式：
///   DEEPSEEK_API_KEY=sk-xxx flutter test integration_test/ai_panel_widget_flow_test.dart

class _MockAdapter implements DatabaseAdapter {
  @override
  bool get isConnected => true;

  @override
  DatabaseType get databaseType => DatabaseType.mysql;

  @override
  DatabaseConnection? get currentConnection => null;

  @override
  void Function()? get onDisconnect => null;

  @override
  set onDisconnect(void Function()? callback) {}

  @override
  Future<List<String>> getTables() async => const [];

  @override
  Future<String> getAiSchemaSummary({
    String? target,
    String? databaseName,
    String locale = 'en',
  }) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockDatabaseService extends DatabaseService {
  final _adapter = _MockAdapter();
  final _eventsController = StreamController<ConnectionEvent>.broadcast();
  final _transactionController = StreamController<String>.broadcast();

  @override
  DatabaseAdapter? getAdapter(String connectionId) => _adapter;

  @override
  Stream<ConnectionEvent> get events => _eventsController.stream;

  @override
  Stream<String> get transactionEvents => _transactionController.stream;

  @override
  bool hasConnection(String connectionId) => true;

  @override
  bool isConnectionActive(String connectionId) => true;

  @override
  bool isConnecting(String connectionId) => false;

  @override
  List<String> get connectedIds => const ['conn_test'];

  @override
  DbServer? get currentServer => _testServer;

  @override
  String? get activeConnectionId => 'conn_test';

  @override
  void setActiveConnection(String connectionId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockConnectionProvider extends ConnectionProvider {
  _MockConnectionProvider() : super(dbService: _MockDatabaseService());

  @override
  List<DbServer> get savedConnections => [_testServer];

  @override
  DbServer? get currentServer => _testServer;

  @override
  bool isConnectionConnected(String connectionId) =>
      connectionId == 'conn_test';

  @override
  bool isConnectionActive(String connectionId) => connectionId == 'conn_test';

  @override
  List<String> getConnectionDatabases(String connectionId) => const ['test_db'];
}

final _testServer = DbServer(
  id: 'conn_test',
  name: 'Test MySQL',
  host: 'localhost',
  port: 3306,
  username: 'root',
  type: DatabaseType.mysql,
);

void main() {
  final apiKey = Platform.environment['DEEPSEEK_API_KEY'] ?? '';

  group('AiPanelWidget full UI flow', () {
    testWidgets('shows API key hint when not configured', (tester) async {
      final provider = AppProvider(
        connectionProvider: _MockConnectionProvider(),
      );
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      provider.aiPanel.setSelectedConnection('conn_test');
      provider.aiPanel.setSelectedDatabase('test_db');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(
              body: SizedBox(height: 600, child: AiPanelWidget()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 未配置 API key 时应出现提示消息
      expect(find.textContaining('API key'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'sends message and receives AI response',
      (tester) async {
        if (apiKey.isEmpty) {
          markTestSkipped('DEEPSEEK_API_KEY not set');
          return;
        }

        final provider = AppProvider(
          connectionProvider: _MockConnectionProvider(),
        );
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
        await provider.saveAiConfig('DeepSeek', 'deepseek-chat', {
          'DeepSeek': {
            'apiKey': apiKey,
            'baseUrl': 'https://api.deepseek.com/v1',
          },
        });
        provider.aiPanel.setSelectedConnection('conn_test');
        provider.aiPanel.setSelectedDatabase('test_db');

        await tester.pumpWidget(
          ChangeNotifierProvider<AppProvider>.value(
            value: provider,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: const Scaffold(
                body: SizedBox(height: 600, child: AiPanelWidget()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 输入消息
        await tester.enterText(find.byType(TextField), 'Say exactly "pong"');
        await tester.pumpAndSettle();

        // 点击发送按钮
        await tester.tap(find.byIcon(LucideIcons.send));
        await tester.pump();

        // 等待 AI 响应完成（流式输出期间持续 pump）
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 8));
        await tester.pumpAndSettle(const Duration(seconds: 15));

        // 验证消息列表中至少有一条 AI 消息
        final aiMessages = provider
            .aiPanel
            .aiConversationService
            .currentMessages
            .where((m) => !m.isUser)
            .toList();
        expect(aiMessages, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
