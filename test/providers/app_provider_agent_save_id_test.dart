//! F-03 · agent save_saved_query 落点 id 去重用例。
//!
//! `_saveAgentSavedQuery` 生成 `agent_save_<毫秒时间戳>` tab id——同毫秒
//! 两次保存原样会撞 id。修复后追加进程内递增序号（仿 AiMemoryService
//! `mem_<ms>_<n>` 先例）。本用例并发触发两次保存（id 在首个 await 前同步
//! 生成，同毫秒场景成立），钉住两次产生两个不同 id，且都落进
//! TabProvider.saveQuery 既有管线（savedQueries 两条、状态 saved）。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart'
    show AgentSavedQuerySaveStatus;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('同毫秒两次 agent 保存产生两个不同 id（F-03 去重后缀）', () async {
    final provider = AppProvider();
    addTearDown(provider.dispose);

    // 并发发起：两次调用的 id 均在各自首个 await 前同步生成——同一事件循环
    // 内 ⇒ 同一毫秒；去重序号保证两 id 必不相同。
    final Future<AgentSavedQuerySaveStatus> first = provider
        .saveAgentSavedQueryForTest(name: 'q1', sql: 'SELECT 1');
    final Future<AgentSavedQuerySaveStatus> second = provider
        .saveAgentSavedQueryForTest(name: 'q2', sql: 'SELECT 2');
    expect(await first, AgentSavedQuerySaveStatus.saved);
    expect(await second, AgentSavedQuerySaveStatus.saved);

    final saved = provider.tab.savedQueries;
    expect(saved, hasLength(2));
    expect(saved.map((q) => q.id).toSet(), hasLength(2)); // id 互不相同
    for (final q in saved) {
      expect(q.id, startsWith('agent_save_'));
    }
  });

  test('先后两次（跨毫秒）保存 id 同样互不相同', () async {
    final provider = AppProvider();
    addTearDown(provider.dispose);

    expect(
      await provider.saveAgentSavedQueryForTest(name: 'a', sql: 'SELECT 1'),
      AgentSavedQuerySaveStatus.saved,
    );
    expect(
      await provider.saveAgentSavedQueryForTest(name: 'b', sql: 'SELECT 2'),
      AgentSavedQuerySaveStatus.saved,
    );

    final saved = provider.tab.savedQueries;
    expect(saved, hasLength(2));
    expect(saved[0].id, isNot(saved[1].id));
  });
}
