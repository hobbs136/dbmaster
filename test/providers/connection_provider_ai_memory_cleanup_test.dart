//! T3 · ConnectionProvider.deleteConnection 的 AI 记忆清理钩子用例（AI-MEM-009）。
//!
//! 钩子是 unawaited fire-and-forget：用例轮询 prefs 直到连接分键被移除
//! （上限 ~1s）。sqlite 为 AdapterBacking（T29 豁免），persistConnection
//! 无网络副作用；secure storage 走 method-channel mock（先例
//! connection_provider_test.dart）。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/ai_memory_item.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/ai/ai_memory_service.dart';
import 'package:dbmaster/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const clearedConnId = 'conn_t3_a';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiMemoryService().resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          switch (call.method) {
            case 'readAll':
              return <String, String>{};
            default:
              return null; // read/write/delete/deleteAll 静默成功
          }
        });
  });

  tearDown(() {
    AiMemoryService().resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('deleteConnection 清空该连接的 AI 记忆且不影响其它作用域', () async {
    final service = AiMemoryService();
    await service.initialize();
    await service.add(
      scope: AiMemoryScope.connection,
      connectionId: clearedConnId,
      content: 'doomed rule',
    );
    await service.add(
      scope: AiMemoryScope.connection,
      connectionId: 'conn_t3_b',
      content: 'surviving rule',
    );
    await service.add(scope: AiMemoryScope.global, content: 'global rule');
    await service.flush();

    final provider = ConnectionProvider(dbService: DatabaseService());
    addTearDown(provider.dispose);

    await provider.saveConnection(
      DbServer(
        id: clearedConnId,
        name: 'T3 Target',
        type: DatabaseType.sqlite,
        host: 'localhost',
        port: 5432,
      ),
    );
    expect(provider.savedConnections, hasLength(1));

    await provider.deleteConnection(clearedConnId);

    // unawaited 钩子：轮询等待 prefs 键移除（确定性落盘信号）。
    final prefs = await SharedPreferences.getInstance();
    var cleared = false;
    for (var i = 0; i < 50 && !cleared; i++) {
      cleared = !prefs.getKeys().contains('ai_memory_conn_$clearedConnId');
      if (!cleared) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    expect(cleared, isTrue);

    // 内存态同步清空；其它连接作用域与全局作用域不受影响。
    expect(service.listForConnection(clearedConnId), isEmpty);
    expect(service.listForConnection('conn_t3_b'), hasLength(1));
    expect(service.listGlobal(), hasLength(1));
  });

  test('删除不存在的连接不抛错（钩子同样安全）', () async {
    final provider = ConnectionProvider(dbService: DatabaseService());
    addTearDown(provider.dispose);

    // deleteConnection 失败会 rethrow —— 能正常返回即未抛错。
    await provider.deleteConnection('conn_never_existed');
  });
}
