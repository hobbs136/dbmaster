import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/redis_script_service.dart';
import 'package:dbmaster/models/redis_script.dart';

void main() {
  group('RedisScriptService', () {
    late RedisScriptService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = RedisScriptService();
      await service.init();
    });

    test('saveScript 和 getScripts 应保存并读取脚本', () async {
      final script = RedisScript(
        id: 'script-1',
        name: 'Cache Warmup',
        code: 'return redis.call("SET", KEYS[1], ARGV[1])',
        tags: ['cache', 'warmup'],
        isGlobal: true,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      await service.saveScript(script);
      final scripts = await service.getScripts();

      expect(scripts.length, equals(1));
      expect(scripts[0].id, equals('script-1'));
      expect(scripts[0].name, equals('Cache Warmup'));
      expect(scripts[0].tags, equals(['cache', 'warmup']));
    });

    test('getScripts 应正确过滤全局和连接级脚本', () async {
      final globalScript = RedisScript(
        id: 'global-1',
        name: 'Global Script',
        code: 'return 1',
        isGlobal: true,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      final connScript = RedisScript(
        id: 'conn-1',
        name: 'Conn Script',
        code: 'return 2',
        isGlobal: false,
        connectionId: 'conn1',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      await service.saveScript(globalScript);
      await service.saveScript(connScript);

      final conn1Scripts = await service.getScripts(connectionId: 'conn1');
      expect(conn1Scripts.length, equals(2));

      final conn2Scripts = await service.getScripts(connectionId: 'conn2');
      expect(conn2Scripts.length, equals(1));
      expect(conn2Scripts[0].id, equals('global-1'));
    });

    test('deleteScript 应移除脚本', () async {
      final script = RedisScript(
        id: 'delete-me',
        name: 'To Delete',
        code: 'return 1',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      await service.saveScript(script);
      await service.deleteScript('delete-me');
      final scripts = await service.getScripts();

      expect(scripts, isEmpty);
    });

    test('searchScripts 应按名称/代码/tag搜索', () async {
      await service.saveScript(
        RedisScript(
          id: 's1',
          name: 'Cache Warmup',
          code: 'redis.call("SET", key, value)',
          tags: ['cache'],
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        ),
      );
      await service.saveScript(
        RedisScript(
          id: 's2',
          name: 'Rate Limit',
          code: 'redis.call("INCR", counter)',
          tags: ['rate-limit'],
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        ),
      );

      final byName = await service.searchScripts('Cache');
      expect(byName.length, equals(1));
      expect(byName[0].id, equals('s1'));

      final byTag = await service.searchScripts('rate-limit');
      expect(byTag.length, equals(1));
      expect(byTag[0].id, equals('s2'));

      final byCode = await service.searchScripts('INCR');
      expect(byCode.length, equals(1));
      expect(byCode[0].id, equals('s2'));
    });

    test('duplicateScript 应创建副本', () async {
      final script = RedisScript(
        id: 'original',
        name: 'Original',
        code: 'return 1',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      await service.saveScript(script);
      await service.duplicateScript('original');
      final scripts = await service.getScripts();

      expect(scripts.length, equals(2));
      final copy = scripts.firstWhere((s) => s.id != 'original');
      expect(copy.name, equals('Original (Copy)'));
      expect(copy.code, equals('return 1'));
    });

    test('getAllTags 应返回所有不重复的 tags', () async {
      await service.saveScript(
        RedisScript(
          id: 't1',
          name: 'Script 1',
          code: '',
          tags: ['cache', 'util'],
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        ),
      );
      await service.saveScript(
        RedisScript(
          id: 't2',
          name: 'Script 2',
          code: '',
          tags: ['cache', 'lock'],
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        ),
      );

      final tags = await service.getAllTags();
      expect(tags.length, equals(3));
      expect(tags.contains('cache'), isTrue);
      expect(tags.contains('util'), isTrue);
      expect(tags.contains('lock'), isTrue);
    });

    test('不应超过最大脚本数量限制', () async {
      for (var i = 0; i < 100; i++) {
        await service.saveScript(
          RedisScript(
            id: 'script-$i',
            name: 'Script $i',
            code: 'return $i',
            createdAt: DateTime.now(),
            modifiedAt: DateTime.now(),
          ),
        );
      }

      expect(
        () => service.saveScript(
          RedisScript(
            id: 'overflow',
            name: 'Overflow',
            code: 'return 0',
            createdAt: DateTime.now(),
            modifiedAt: DateTime.now(),
          ),
        ),
        throwsStateError,
      );
    });
  });
}
