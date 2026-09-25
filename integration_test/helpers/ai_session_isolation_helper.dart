// ============================================================================
// Fix-H：integration test 会话存储隔离助手。
//
// 背景（P1 数据污染缺陷）：AiSessionManager 生产默认把会话/消息/收藏/检查点
// JSON 写入 getApplicationDocumentsDirectory()（Windows = 真实用户 Documents
// 目录），活动会话指针写入 SharedPreferences 裸键 'ai_active_session_id'。
// integration test 在真机模式（flutter test -d windows / flutter drive）下
// path_provider 解析到真实目录——测试会话直接落进用户真实存储（实报缺陷：
// perf/agent_long_run_smoke_test.dart 的「历史提问 N/历史回答 N」种子 +
// 50+ 步 agent 消息污染用户会话流）。prefs 面 setMockInitialValues 拦得住
// （真机实测：即使 getInstance 先于 mock 完成也生效），但 mock 管不到文件面，
// 且未调 mock 的文件（workbench_mysql_e2e / ai_deepseek_end_to_end）prefs 也
// 裸奔——故隔离 override 双面都带：临时目录 + prefs 键前缀。
//
// 用法：凡 integration_test 下构造 AiSessionManager（直接或经 AppProvider
// 注入）的装配点，一律改用本助手建隔离 manager：
//   final m = createIsolatedAiSessionManager()..createSession();
//   // 或 AppProvider(aiSessionManager: createIsolatedAiSessionManager())
// 临时目录经 addTearDown 自动递归删除；prefs 键带 'fit_<n>_' 前缀，
// 即使未 mock prefs 也碰不到生产键。
// ============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show addTearDown;

import 'package:dbmaster/services/ai/ai_session_manager.dart';

int _isolationCounter = 0;

/// 建存储隔离的 AiSessionManager：
/// - 消息/会话/收藏/检查点文件落 `Directory.systemTemp` 下独立临时目录
///   （addTearDown 自动递归删除；目录由 manager 懒创建）；
/// - SharedPreferences 键加 `fit_<n>_` 前缀（与生产裸键零冲突，未 mock
///   prefs 时也不污染真实 store）。
/// 必须在 test/testWidgets/setUp 上下文中调用（addTearDown 需要活动测试）。
AiSessionManager createIsolatedAiSessionManager() {
  final Directory dir = Directory.systemTemp.createTempSync('dbm_fix_h_it_');
  addTearDown(() async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 清理失败不翻测试（临时目录残留由 OS 回收）。
    }
  });
  return AiSessionManager(
    storageOverride: AiSessionStorageOverride(
      directory: dir,
      prefsPrefix: 'fit_${_isolationCounter++}_',
    ),
  );
}
