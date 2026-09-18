import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/services/tab_session_store.dart';

import '../helpers/fake_pro_module.dart';

QueryTab _tab(String id, {String? connectionId}) => QueryTab(
      id: id,
      title: 'Tab $id',
      sql: 'SELECT $id',
      connectionId: connectionId,
      databaseName: 'db',
      databaseType: DatabaseType.mysql,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TabSessionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('app_provider_session');
    store = TabSessionStore(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('AppProvider 崩溃会话恢复（U16）', () {
    test('异常退出 → 恢复标签页（失效连接过滤）+ 提示计数', () async {
      // 模拟上次崩溃：会话文件留存 + running 标记未被 clean 收尾。
      await store.save([
        _tab('1', connectionId: null),
        _tab('2', connectionId: 'stale-conn'),
        _tab('3', connectionId: null),
      ], 2);
      await store.markRunning();

      final fakePro = FakeProModule(isPro: true);
      final provider = AppProvider(proModule: fakePro)
        ..testSessionStore = store;
      await provider.initialize();

      expect(provider.tabs.length, 2,
          reason: 'stale 连接的 tab 应被过滤');
      expect(provider.tabs.map((t) => t.id), ['1', '3']);
      expect(provider.tabs.first.sql, 'SELECT 1');
      expect(provider.lastCrashRestoreTabCount, 2);
      // initialize 末尾重写了 running=true（本次运行同样受崩溃保护）。
      expect(await store.wasUncleanExit(), isTrue);
      fakePro.dispose();
    });

    test('正常退出过 → 不恢复、无提示', () async {
      await store.save([_tab('1', connectionId: null)], 0);
      await store.markCleanExit();

      final fakePro = FakeProModule(isPro: true);
      final provider = AppProvider(proModule: fakePro)
        ..testSessionStore = store;
      await provider.initialize();

      expect(provider.tabs, isEmpty);
      expect(provider.lastCrashRestoreTabCount, isNull);
      fakePro.dispose();
    });

    test('prepareForCleanExit：标记 clean + 清空会话', () async {
      final fakePro = FakeProModule(isPro: true);
      final provider = AppProvider(proModule: fakePro)
        ..testSessionStore = store;
      await provider.initialize();
      provider.tab.addTab(_tab('9', connectionId: null));
      await Future<void>.delayed(
          const Duration(milliseconds: 1000)); // 防抖落盘

      expect((await store.load())?.tabs, isNotEmpty,
          reason: '运行中变更应已防抖落盘');

      await provider.prepareForCleanExit();
      expect(await store.wasUncleanExit(), isFalse);
      expect(await store.load(), isNull);
      fakePro.dispose();
    });

    test('标签页变更防抖落盘（800ms 合并）', () async {
      final fakePro = FakeProModule(isPro: true);
      final provider = AppProvider(proModule: fakePro)
        ..testSessionStore = store;
      await provider.initialize();

      provider.tab.addTab(_tab('a', connectionId: null));
      provider.tab.addTab(_tab('b', connectionId: null));
      // 防抖窗口内未到期 → 文件应仍为空/无内容
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final early = await store.load();
      expect(early?.tabs ?? const [], isEmpty,
          reason: '防抖期内不应落盘');

      await Future<void>.delayed(const Duration(milliseconds: 900));
      final snapshot = await store.load();
      expect(snapshot, isNotNull);
      expect(snapshot!.tabs.length, 2);
      fakePro.dispose();
    });
  });
}
