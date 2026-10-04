// QueryHistorySource.agent 序列化回归（AI 执行查询历史，任务 T1）。
//
// 序列化口径（lib/models/query_history.dart）：toJson 写 `source.name`
// 字符串；fromJson 名称匹配 + 未知值回落 executed。新增 agent 值的兼容
// 契约（本文件锁定）：
// ① 旧数据（无 source 键 / 'executed' / 'saved'）解析零影响；
// ② agent 值 JSON 往返一致；
// ③ 未来未知来源字符串回落 executed（向后兼容语义）；
// ④ addQueryHistory 缺省 source 仍为 executed（既有调用零影响），
//    source: agent 经 prefs 持久化往返不丢。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/models/query_history.dart';
import 'package:dbmaster/providers/query_history_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueryHistorySource.agent 序列化回归', () {
    group('旧格式 JSON 兼容（加载零影响）', () {
      test('无 source 键 → executed', () {
        final history = QueryHistory.fromJson(<String, dynamic>{
          'id': '1',
          'sql': 'SELECT 1',
          'timestamp': '2026-09-25T00:00:00.000',
          'connectionId': 'conn-1',
        });
        expect(history.source, QueryHistorySource.executed);
      });

      test("source='executed' → executed（解析不变）", () {
        final history = QueryHistory.fromJson(<String, dynamic>{
          'id': '1',
          'sql': 'SELECT 1',
          'timestamp': '2026-09-25T00:00:00.000',
          'source': 'executed',
        });
        expect(history.source, QueryHistorySource.executed);
      });

      test("source='saved' → saved（解析不变）", () {
        final history = QueryHistory.fromJson(<String, dynamic>{
          'id': '2',
          'sql': 'SELECT 2',
          'timestamp': '2026-09-25T00:00:00.000',
          'source': 'saved',
        });
        expect(history.source, QueryHistorySource.saved);
      });

      test('未知来源字符串 → 回落 executed（向后兼容）', () {
        final history = QueryHistory.fromJson(<String, dynamic>{
          'id': '4',
          'sql': 'SELECT 3',
          'timestamp': '2026-09-25T00:00:00.000',
          'source': 'something_new_in_a_future_version',
        });
        expect(history.source, QueryHistorySource.executed);
      });
    });

    group('agent 值往返', () {
      test('toJson/fromJson 往返一致', () {
        final history = QueryHistory(
          id: '3',
          sql: 'UPDATE t SET a = 1',
          timestamp: DateTime(2026, 9, 25),
          connectionId: 'conn-1',
          source: QueryHistorySource.agent,
        );

        final restored = QueryHistory.fromJson(history.toJson());

        expect(restored.source, QueryHistorySource.agent);
        expect(restored.sql, 'UPDATE t SET a = 1');
        expect(restored.connectionId, 'conn-1');
      });
    });

    group('QueryHistoryProvider.addQueryHistory source 参数', () {
      test('source: agent → 内存记录带 agent 且 prefs 持久化往返不丢', () async {
        SharedPreferences.setMockInitialValues({});
        final provider = QueryHistoryProvider();
        await provider.addQueryHistory(
          sql: 'SELECT 9',
          connectionId: 'conn-1',
          databaseType: DatabaseType.mysql,
          source: QueryHistorySource.agent,
        );
        expect(
          provider.queryHistory.single.source,
          QueryHistorySource.agent,
        );

        // 持久化往返：新 provider 从同一 prefs 加载 → agent 不丢。
        final reloaded = QueryHistoryProvider();
        await reloaded.loadQueryHistory();
        expect(reloaded.queryHistory.single.source, QueryHistorySource.agent);
      });

      test('缺省 source 保持 executed（既有调用零影响）', () async {
        SharedPreferences.setMockInitialValues({});
        final provider = QueryHistoryProvider();
        await provider.addQueryHistory(sql: 'SELECT 8', connectionId: 'conn-1');
        expect(
          provider.queryHistory.single.source,
          QueryHistorySource.executed,
        );
      });

      test('saveQueryToHistory（Ctrl+S）仍记 saved（既有语义不受 agent 影响）', () async {
        SharedPreferences.setMockInitialValues({});
        final provider = QueryHistoryProvider();
        await provider.saveQueryToHistory(
          sql: 'SELECT 7',
          connectionId: 'conn-1',
        );
        expect(provider.queryHistory.single.source, QueryHistorySource.saved);
      });
    });
  });
}
