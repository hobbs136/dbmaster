// 2b.4 — AppProvider.analyzeTreeNodeInWorkbench 引流门面测试。
//
// 覆盖：开工作台状态翻转 / ensureSession 后锁定落 session metadata /
// 预填 intent 内容正确（en/zh server 健康问句）/ **零 send 调用断言**
// （消息流零新增 = 预填零执行）/ 不校验 API key / _collectNodeContext
// 非 MySQL 分支 getAdapter 按 ctx.connectionId 取 adapter（防张冠李戴）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/ai_tree_node_context.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/workbench_entry_intent.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/ai/ai_service_localizations.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';

/// 记录 getAdapter 入参的 DatabaseService 桩（断言 adapter 解析按
/// ctx.connectionId 走，而非 currentAdapter/侧栏当前连接）。
class _SpyDbService extends DatabaseService {
  _SpyDbService(this.adapterFor);

  final DatabaseAdapter? adapterFor;
  final List<String> adapterRequests = <String>[];

  @override
  DatabaseAdapter? getAdapter(String connectionId) {
    adapterRequests.add(connectionId);
    return adapterFor;
  }
}

/// 非 MySQL 分支的 canned adapter（只覆盖 _collectNodeContext 消费的两面）。
class _FakeAdapter extends Fake implements DatabaseAdapter {
  @override
  Future<String> getAiSchemaSummary({
    String? target,
    String? databaseName,
    String locale = 'en',
  }) async => 'canned:$target';

  @override
  Future<List<String>> getDatabases() async => <String>['db1', 'db2'];
}

DbServer _server(String id, String name, DatabaseType type) {
  return DbServer(
    id: id,
    type: type,
    name: name,
    host: '192.0.2.10',
    port: 5432,
    username: 'u',
    password: 'p',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('analyzeTreeNodeInWorkbench（2b.4 R7）', () {
    test('开工作台：aiPanelOpen + aiPanelFullscreen 翻转', () async {
      final provider = AppProvider();
      expect(provider.aiPanelOpen, isFalse);
      expect(provider.aiPanelFullscreen, isFalse);

      await provider.analyzeTreeNodeInWorkbench(
        AiTreeNodeContext(
          type: AiTreeNodeType.table,
          connectionId: 'conn-a',
          databaseName: 'db_a',
          nodeName: 'users',
        ),
      );

      expect(provider.aiPanelOpen, isTrue);
      expect(provider.aiPanelFullscreen, isTrue);
    });

    test('ensureSession 后锁定落 session metadata', () async {
      final provider = AppProvider();
      // 调用前无会话；锁定依赖会话（会话为空锁定静默失败）。
      expect(provider.aiPanel.aiConversationService.currentSession, isNull);

      await provider.analyzeTreeNodeInWorkbench(
        AiTreeNodeContext(
          type: AiTreeNodeType.database,
          connectionId: 'conn-a',
          databaseName: 'db_a',
          nodeName: 'db_a',
        ),
      );

      final session = provider.aiPanel.aiConversationService.currentSession;
      expect(session, isNotNull, reason: 'ensureSession 建默认会话');
      final lock = provider.aiPanel.workbenchContextLock;
      expect(lock, isNotNull);
      expect(lock!.connectionId, equals('conn-a'));
      expect(lock.databaseName, equals('db_a'));
    });

    test('table 型预填 intent 内容正确（header + 上下文 + ask；tabTarget none）',
        () async {
      final adapter = _FakeAdapter();
      final dbService = _SpyDbService(adapter);
      final conn = ConnectionProvider(dbService: dbService);
      conn.setCurrentServerForTest(
        _server('conn-current', 'Current', DatabaseType.postgresql),
      );
      final app = AppProvider(connectionProvider: conn);

      await app.analyzeTreeNodeInWorkbench(
        AiTreeNodeContext(
          type: AiTreeNodeType.table,
          connectionId: 'conn-target',
          databaseName: 'db_a',
          nodeName: 'users',
        ),
        locale: 'en',
      );

      final intent = app.aiPanel.workbenchEntryIntent;
      expect(intent, isNotNull);
      expect(intent!.tabTarget, equals(WorkbenchEntryTabTarget.none));
      final l10n = AiServiceLocalizations('en');
      expect(intent.prompt, contains('db_a.users'));
      expect(intent.prompt, contains('canned:users'));
      expect(intent.prompt, contains(l10n.analyzeTreeNodeAsk));
      // 非 MySQL 分支 adapter 解析按 ctx.connectionId（非侧栏当前连接）。
      expect(dbService.adapterRequests, equals(<String>['conn-target']));
    });

    test('connection 型：tabTarget observe + server 健康问句（zh 锁定文案）',
        () async {
      final provider = AppProvider();
      provider.connection.setCurrentServerForTest(
        _server('conn-a', 'Alpha', DatabaseType.mysql),
      );

      await provider.analyzeTreeNodeInWorkbench(
        AiTreeNodeContext(
          type: AiTreeNodeType.connection,
          connectionId: 'conn-a',
          nodeName: 'Alpha',
        ),
        locale: 'zh',
      );

      final intent = provider.aiPanel.workbenchEntryIntent;
      expect(intent, isNotNull);
      expect(intent!.tabTarget, equals(WorkbenchEntryTabTarget.observe));
      expect(
        intent.prompt,
        contains('汇总这个实例的健康状况（进程/引擎状态/资源占用）'),
      );
      expect(intent.prompt, contains(AiServiceLocalizations('zh').analyzeTreeNodeHeader('服务器', 'Alpha')));
    });

    test('零 send 调用：调用后消息流零新增（预填零执行）', () async {
      final provider = AppProvider();

      await provider.analyzeTreeNodeInWorkbench(
        AiTreeNodeContext(
          type: AiTreeNodeType.connection,
          connectionId: 'conn-a',
          nodeName: 'Alpha',
        ),
      );

      expect(provider.aiMessages, isEmpty, reason: '无 send 路径调用');
      expect(
        provider.aiPanel.workbenchEntryIntent,
        isNotNull,
        reason: 'prompt 停在预填槽（发送账归用户）',
      );
    });

    test('不校验 API key：无 key 配置不报错、intent 照常挂载', () async {
      final provider = AppProvider();
      // 默认无 API key——经典路径会落 errorAiApiKeyMissing 消息；本路径
      // 零校验（预填不执行）。

      await provider.analyzeTreeNodeInWorkbench(
        AiTreeNodeContext(
          type: AiTreeNodeType.table,
          connectionId: 'conn-a',
          databaseName: 'db_a',
          nodeName: 'users',
        ),
      );

      expect(provider.aiMessages, isEmpty);
      expect(provider.aiPanel.workbenchEntryIntent, isNotNull);
    });

    test('上下文收集失败降级：仍开台 + 预填 header + 问句（零执行不阻塞）',
        () async {
      // 非 MySQL 分支 + getAdapter 返回 null → 收集抛错 → 降级纯问句
      // （预填零执行路径无失败语义）。
      final dbService = _SpyDbService(null);
      final conn = ConnectionProvider(dbService: dbService);
      conn.setCurrentServerForTest(
        _server('conn-a', 'Alpha', DatabaseType.postgresql),
      );
      final app = AppProvider(connectionProvider: conn);

      await app.analyzeTreeNodeInWorkbench(
        AiTreeNodeContext(
          type: AiTreeNodeType.table,
          connectionId: 'conn-a',
          databaseName: 'db_a',
          nodeName: 'users',
        ),
        locale: 'en',
      );

      expect(app.aiPanelOpen, isTrue);
      final intent = app.aiPanel.workbenchEntryIntent;
      expect(intent, isNotNull);
      expect(intent!.prompt, contains('db_a.users'));
      expect(
        intent.prompt,
        contains(AiServiceLocalizations('en').analyzeTreeNodeAsk),
      );
      expect(intent.prompt, isNot(contains('```')), reason: '无上下文块');
    });
  });
}
