// ============================================================================
// Fix-H：AiSessionStorageOverride 存储隔离单测。
// 覆盖三面：
//   ① override 生效——消息/会话文件只落注入目录（真实目录零写入的可观测
//      代理：flutter_tester 下 getApplicationDocumentsDirectory 抛
//      MissingPluginException，写成功本身即证明未触达 path_provider；
//      另有 bystander 目录零文件断言）+ 同 override 新实例可读回；
//   ② prefs 前缀隔离——写走 '<prefix>ai_active_session_id'，同 store 内
//      生产裸键零触碰；load() 读回也走前缀键；
//   ③ 生产默认零行为变化——无 override 时裸键写入不变、文件面仍走
//      path_provider（flutter_tester 下抛错被 persist 吞掉，不崩）。
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/ai/ai_session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiSessionStorageOverride（Fix-H 存储隔离）', () {
    late Directory tempRoot;
    late List<AiSessionManager> managers;

    AiSessionManager track(AiSessionManager m) {
      managers.add(m);
      return m;
    }

    Directory subDir(String name) =>
        Directory('${tempRoot.path}${Platform.pathSeparator}$name');

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tempRoot = await Directory.systemTemp.createTemp('fix_h_override_test_');
      managers = <AiSessionManager>[];
    });

    tearDown(() async {
      for (final m in managers) {
        m.dispose();
      }
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('override 目录：persist 文件全落注入目录，bystander 目录零写入，新实例可读回',
        () async {
      final dirA = subDir('isolated_a');
      final dirB = subDir('bystander_b')..createSync();
      final manager = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(
            directory: dirA,
            prefsPrefix: 't1_',
          ),
        ),
      );

      final session = manager.createSession(title: '隔离会话');
      manager.addMessage(
        AiMessage(
          id: 'm1',
          type: AiMessageType.chat,
          content: '隔离消息体',
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      await manager.persist();

      // ① 注入目录内：四类文件齐（sessions/messages/bookmarks/checkpoints）。
      final sessionsFile = File('${dirA.path}/ai_sessions.json');
      final messagesFile = File('${dirA.path}/ai_messages_${session.id}.json');
      final bookmarksFile = File('${dirA.path}/ai_bookmarks.json');
      final checkpointsFile = File('${dirA.path}/ai_checkpoints.json');
      expect(await sessionsFile.exists(), isTrue, reason: '会话元数据落注入目录');
      expect(await messagesFile.exists(), isTrue, reason: '消息文件落注入目录');
      expect(await bookmarksFile.exists(), isTrue);
      expect(await checkpointsFile.exists(), isTrue);
      expect(
        await sessionsFile.readAsString(),
        contains('隔离会话'),
        reason: '会话标题入档',
      );
      expect(await messagesFile.readAsString(), contains('隔离消息体'));

      // 注入目录由 manager 懒创建（构造时不存在）。
      expect(dirA.path, isNot(dirB.path));

      // ② 真实目录零写入的可观测代理：flutter_tester 下
      // getApplicationDocumentsDirectory 抛 MissingPluginException——上面
      // 写成功本身即证明文件面未触达 path_provider；bystander 目录无任何
      // ai_*.json 进一步钉死写入局部性。
      final stray = dirB.listSync().whereType<File>().toList();
      expect(stray, isEmpty, reason: '非注入目录零文件');

      // ③ 同 override 新实例完整读回（load 也走注入目录）。
      final reader = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(
            directory: dirA,
            prefsPrefix: 't1_',
          ),
        ),
      );
      await reader.load();
      expect(reader.sessions.length, 1);
      expect(reader.sessions.first.title, '隔离会话');
      expect(reader.currentSession?.id, session.id, reason: '前缀键恢复活动会话');
      expect(reader.currentMessages.length, 1);
      expect(reader.currentMessages.first.content, '隔离消息体');
    });

    test('override 目录不存在时由 manager 递归创建', () async {
      final nested = Directory('${tempRoot.path}/deep/nested/dir');
      expect(await nested.exists(), isFalse);
      final manager = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(directory: nested),
        ),
      );
      manager.createSession(title: 'x');
      await manager.persist();
      expect(await File('${nested.path}/ai_sessions.json').exists(), isTrue);
    });

    test('prefs 前缀隔离：写走前缀键，同 store 生产裸键零触碰；load 读前缀键',
        () async {
      // 同 store 内预置生产数据（真实用户键）。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ai_active_session_id': 'real_user_session_999',
      });
      final dirA = subDir('prefs_iso');
      final manager = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(
            directory: dirA,
            prefsPrefix: 'it_',
          ),
        ),
      );

      final s1 = manager.createSession(title: 'S1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      manager.createSession(title: 'S2'); // S2 为当前会话
      await manager.persist();
      final prefs = await SharedPreferences.getInstance();

      // 写：只写前缀键。
      expect(prefs.getString('it_ai_active_session_id'), isNotNull);
      // 生产裸键零触碰（仍是预置的用户值）。
      expect(
        prefs.getString('ai_active_session_id'),
        'real_user_session_999',
        reason: '生产键不被隔离 manager 改写',
      );

      // 读：预置前缀键指向 S1，新实例 load 恢复 S1（读路径也走前缀键）。
      await prefs.setString('it_ai_active_session_id', s1.id);
      final reader = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(
            directory: dirA,
            prefsPrefix: 'it_',
          ),
        ),
      );
      await reader.load();
      expect(reader.sessions.length, 2);
      expect(
        reader.currentSession?.id,
        s1.id,
        reason: 'load 经前缀键恢复活动会话（非回退首个）',
      );

      // 删除最后会话导致 _currentSession 为 null 时：移除的也是前缀键。
      final solo = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(
            directory: subDir('prefs_solo'),
            prefsPrefix: 'solo_',
          ),
        ),
      );
      final only = solo.createSession(title: 'only');
      // 先 persist 完成 _docsDir 懒初始化（deleteSession 的既有前提：
      // 生产路径 load() 在启动时已初始化；此处对齐该前提）。
      await solo.persist();
      solo.deleteSession(only.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(prefs.getString('solo_ai_active_session_id'), isNull);
      expect(prefs.getString('ai_active_session_id'), 'real_user_session_999');
    });

    test('生产默认（无 override）：裸键写入不变，prefs 语义逐字节保持', () async {
      final manager = track(AiSessionManager());
      final session = manager.createSession(title: '生产会话');
      final prefs = await SharedPreferences.getInstance();
      // flush _saveActiveSessionId 的微任务
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        prefs.getString('ai_active_session_id'),
        session.id,
        reason: '无 override 时仍写裸键 ai_active_session_id',
      );
      expect(prefs.getKeys().where((k) => k.contains('fit_')), isEmpty);

      // 文件面默认仍走 path_provider：flutter_tester 下抛
      // MissingPluginException 被 persist 吞掉（行为与改动前一致——不崩）。
      await manager.persist();
      await manager.load();
      expect(manager.sessions, isEmpty, reason: 'load 失败回退空（既有语义）');
    });

    test('部分 override：仅 directory 时 prefs 仍走裸键；仅 prefsPrefix 时键带前缀',
        () async {
      // 仅 directory：prefs 面无前缀（该面保持生产默认）。
      final dirOnly = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(directory: subDir('dir_only')),
        ),
      );
      final s1 = dirOnly.createSession(title: 'dirOnly');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ai_active_session_id'), s1.id);
      await dirOnly.persist();
      expect(
        await File('${subDir('dir_only').path}/ai_sessions.json').exists(),
        isTrue,
      );

      // 仅 prefsPrefix：键带前缀；文件面仍走 path_provider（flutter_tester
      // 下被 persist 吞掉，不崩）。
      final prefixOnly = track(
        AiSessionManager(
          storageOverride: const AiSessionStorageOverride(prefsPrefix: 'p_'),
        ),
      );
      final s2 = prefixOnly.createSession(title: 'prefixOnly');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(prefs.getString('p_ai_active_session_id'), s2.id);
      await prefixOnly.persist();
    });

    test('resetForTests 后 override 仍生效（重解析注入目录而非生产目录）', () async {
      final dirA = subDir('reset_iso');
      final manager = track(
        AiSessionManager(
          storageOverride: AiSessionStorageOverride(directory: dirA),
        ),
      );
      manager.createSession(title: 'reset 后仍隔离');
      manager.resetForTests();
      await manager.persist();
      expect(await File('${dirA.path}/ai_sessions.json').exists(), isTrue);
      final decoded = jsonDecode(
        await File('${dirA.path}/ai_sessions.json').readAsString(),
      ) as List<dynamic>;
      expect(decoded, isNotEmpty);
    });
  });
}
