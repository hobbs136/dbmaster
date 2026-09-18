import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/services/tab_session_store.dart';

QueryTab _tab({
  required String id,
  String sql = 'SELECT 1',
  String? connectionId = 'conn-1',
  String? sessionId,
  bool isSaved = false,
}) =>
    QueryTab(
      id: id,
      title: 'Tab $id',
      sql: sql,
      connectionId: connectionId,
      databaseName: 'db',
      databaseType: DatabaseType.mysql,
      sessionId: sessionId,
      isSaved: isSaved,
      isModified: false,
      originalSql: isSaved ? sql : null,
    );

void main() {
  late Directory tempDir;
  late TabSessionStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tab_session_test');
    store = TabSessionStore(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('TabSessionStore（U16）', () {
    test('save/load 往返：瘦字段还原', () async {
      final tabs = [
        _tab(id: '1', sql: 'SELECT * FROM t'),
        _tab(id: '2', connectionId: null, isSaved: true),
      ];
      await store.save(tabs, 1);

      final snapshot = await store.load();
      expect(snapshot, isNotNull);
      expect(snapshot!.tabs.length, 2);
      expect(snapshot.tabs[0].sql, 'SELECT * FROM t');
      expect(snapshot.tabs[0].connectionId, 'conn-1');
      expect(snapshot.tabs[0].databaseType, DatabaseType.mysql);
      expect(snapshot.tabs[1].connectionId, isNull);
      expect(snapshot.tabs[1].isSaved, isTrue);
      expect(snapshot.activeTabIndex, 1);
    });

    test('运行态不落盘：sessionId 不进会话文件', () async {
      await store.save([_tab(id: '1', sessionId: 'sess-9')], 0);

      // 文件内容层面断言（瘦序列化根本不写这些 key）
      final raw = await File(
              '${tempDir.path}${Platform.pathSeparator}tab_session.json')
          .readAsString();
      expect(raw, isNot(contains('sessionId')));
      expect(raw, isNot(contains('executionResults')));

      final snapshot = await store.load();
      expect(snapshot!.tabs.single.sessionId, isNull);
    });

    test('重复 save 覆盖（原子写替换）', () async {
      await store.save([_tab(id: '1')], 0);
      await store.save([_tab(id: '1'), _tab(id: '2')], 1);

      final snapshot = await store.load();
      expect(snapshot!.tabs.length, 2);
      expect(snapshot.activeTabIndex, 1);
    });

    test('损坏 JSON → load null 不抛', () async {
      final f = File(
          '${tempDir.path}${Platform.pathSeparator}tab_session.json');
      await f.writeAsString('{not json');
      expect(await store.load(), isNull);
    });

    test('未知 schema → null', () async {
      final f = File(
          '${tempDir.path}${Platform.pathSeparator}tab_session.json');
      await f.writeAsString(jsonEncode({
        'schema': 99,
        'activeTabIndex': 0,
        'tabs': [],
      }));
      expect(await store.load(), isNull);
    });

    test('退出标记状态机：缺失→false / running→true / clean→false', () async {
      expect(await store.wasUncleanExit(), isFalse,
          reason: '首跑无文件应为 clean');

      await store.markRunning();
      expect(await store.wasUncleanExit(), isTrue,
          reason: 'running 未被 clean 收尾即异常退出');

      await store.save([_tab(id: '1')], 0);
      await store.markCleanExit();
      expect(await store.wasUncleanExit(), isFalse);
      expect(await store.load(), isNull, reason: 'clean exit 清空会话文件');
    });
  });
}
