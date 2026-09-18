import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/redis_key_models.dart';

void main() {
  group('RedisKeyInfo', () {
    test('应使用默认值构造', () {
      const info = RedisKeyInfo(name: 'test_key');
      expect(info.name, equals('test_key'));
      expect(info.type, equals(''));
      expect(info.ttl, equals(-2));
      expect(info.size, equals(0));
    });

    test('copyWith 应更新指定字段', () {
      const info = RedisKeyInfo(
        name: 'key1',
        type: 'string',
        ttl: 60,
        size: 100,
      );
      final copied = info.copyWith(type: 'hash', size: 200);
      expect(copied.name, equals('key1'));
      expect(copied.type, equals('hash'));
      expect(copied.ttl, equals(60));
      expect(copied.size, equals(200));
    });

    test('copyWith 不指定字段时保持原值', () {
      const info = RedisKeyInfo(
        name: 'key1',
        type: 'string',
        ttl: 60,
        size: 100,
      );
      final copied = info.copyWith();
      expect(copied.name, equals('key1'));
      expect(copied.type, equals('string'));
      expect(copied.ttl, equals(60));
      expect(copied.size, equals(100));
    });

    test('hasNoExpiry 在 ttl == -1 时为 true', () {
      const info = RedisKeyInfo(name: 'k', ttl: -1);
      expect(info.hasNoExpiry, isTrue);
      expect(info.isExpired, isFalse);
      expect(info.isExpiringSoon, isFalse);
    });

    test('isExpired 在 ttl == -2 时为 true', () {
      const info = RedisKeyInfo(name: 'k', ttl: -2);
      expect(info.isExpired, isTrue);
      expect(info.hasNoExpiry, isFalse);
      expect(info.isExpiringSoon, isFalse);
    });

    test('isExpiringSoon 在 0 <= ttl < 60 时为 true', () {
      const info1 = RedisKeyInfo(name: 'k', ttl: 0);
      const info2 = RedisKeyInfo(name: 'k', ttl: 59);
      const info3 = RedisKeyInfo(name: 'k', ttl: 60);
      expect(info1.isExpiringSoon, isTrue);
      expect(info2.isExpiringSoon, isTrue);
      expect(info3.isExpiringSoon, isFalse);
    });

    test('isShortTtl 在 60 <= ttl < 3600 时为 true', () {
      const info1 = RedisKeyInfo(name: 'k', ttl: 60);
      const info2 = RedisKeyInfo(name: 'k', ttl: 3599);
      const info3 = RedisKeyInfo(name: 'k', ttl: 3600);
      expect(info1.isShortTtl, isTrue);
      expect(info2.isShortTtl, isTrue);
      expect(info3.isShortTtl, isFalse);
    });

    group('ttlDisplay', () {
      test('ttl == -1 返回 No TTL', () {
        const info = RedisKeyInfo(name: 'k', ttl: -1);
        expect(info.ttlDisplay, equals('No TTL'));
      });

      test('ttl == -2 返回 Expired', () {
        const info = RedisKeyInfo(name: 'k', ttl: -2);
        expect(info.ttlDisplay, equals('Expired'));
      });

      test('ttl < 60 返回秒数', () {
        const info = RedisKeyInfo(name: 'k', ttl: 45);
        expect(info.ttlDisplay, equals('45s'));
      });

      test('ttl < 3600 返回分钟数', () {
        const info = RedisKeyInfo(name: 'k', ttl: 1800);
        expect(info.ttlDisplay, equals('30m'));
      });

      test('ttl < 86400 返回小时数', () {
        const info = RedisKeyInfo(name: 'k', ttl: 7200);
        expect(info.ttlDisplay, equals('2h'));
      });

      test('ttl >= 86400 返回天数', () {
        const info = RedisKeyInfo(name: 'k', ttl: 172800);
        expect(info.ttlDisplay, equals('2d'));
      });
    });

    group('sizeDisplay', () {
      test('size <= 0 返回空字符串', () {
        const info = RedisKeyInfo(name: 'k', size: 0);
        expect(info.sizeDisplay, equals(''));
      });

      test('string 类型 size < 1024 显示 B', () {
        const info = RedisKeyInfo(name: 'k', type: 'string', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('string 类型 size < 1MB 显示 KB', () {
        const info = RedisKeyInfo(name: 'k', type: 'string', size: 1536);
        expect(info.sizeDisplay, equals('1.5 KB'));
      });

      test('string 类型 size >= 1MB 显示 MB', () {
        const info = RedisKeyInfo(name: 'k', type: 'string', size: 2097152);
        expect(info.sizeDisplay, equals('2.0 MB'));
      });

      test('hash 类型显示 fields', () {
        const info = RedisKeyInfo(name: 'k', type: 'hash', size: 5);
        expect(info.sizeDisplay, equals('5 fields'));
      });

      test('list 类型显示 items', () {
        const info = RedisKeyInfo(name: 'k', type: 'list', size: 3);
        expect(info.sizeDisplay, equals('3 items'));
      });

      test('set 类型显示 items', () {
        const info = RedisKeyInfo(name: 'k', type: 'set', size: 10);
        expect(info.sizeDisplay, equals('10 items'));
      });

      test('zset 类型显示 items', () {
        const info = RedisKeyInfo(name: 'k', type: 'zset', size: 4);
        expect(info.sizeDisplay, equals('4 items'));
      });

      test('stream 类型显示 entries', () {
        const info = RedisKeyInfo(name: 'k', type: 'stream', size: 100);
        expect(info.sizeDisplay, equals('100 entries'));
      });

      test('bitmap 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'bitmap', size: 2048);
        expect(info.sizeDisplay, equals('2.0 KB'));
      });

      test('geo 类型显示 items', () {
        const info = RedisKeyInfo(name: 'k', type: 'geo', size: 3);
        expect(info.sizeDisplay, equals('3 items'));
      });

      test('bitfield 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'bitfield', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('json 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'json', size: 1024);
        expect(info.sizeDisplay, equals('1.0 KB'));
      });

      test('rejson-rl 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'rejson-rl', size: 256);
        expect(info.sizeDisplay, equals('256 B'));
      });

      test('hyperloglog 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'hyperloglog', size: 10240);
        expect(info.sizeDisplay, equals('10.0 KB'));
      });

      test('bloom 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'bloom', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('cuckoo 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'cuckoo', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('tdigest 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'tdigest', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('topk 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'topk', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('cms 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'cms', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('timeseries 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'timeseries', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('vectorset 类型显示字节', () {
        const info = RedisKeyInfo(name: 'k', type: 'vectorset', size: 512);
        expect(info.sizeDisplay, equals('512 B'));
      });

      test('未知类型返回原始 size 字符串', () {
        const info = RedisKeyInfo(name: 'k', type: 'unknown', size: 42);
        expect(info.sizeDisplay, equals('42'));
      });
    });
  });

  group('RedisScanResult', () {
    test('应正确构造', () {
      const result = RedisScanResult(cursor: 42, keys: ['k1', 'k2']);
      expect(result.cursor, equals(42));
      expect(result.keys, equals(['k1', 'k2']));
    });
  });

  group('RedisTypeUtils', () {
    test('getIcon 应返回对应图标', () {
      expect(RedisTypeUtils.getIcon('string'), equals('🔤'));
      expect(RedisTypeUtils.getIcon('hash'), equals('🗂️'));
      expect(RedisTypeUtils.getIcon('list'), equals('📋'));
      expect(RedisTypeUtils.getIcon('set'), equals('🏷️'));
      expect(RedisTypeUtils.getIcon('zset'), equals('📊'));
      expect(RedisTypeUtils.getIcon('stream'), equals('🌊'));
      expect(RedisTypeUtils.getIcon('bitmap'), equals('🖼️'));
      expect(RedisTypeUtils.getIcon('bitfield'), equals('🔲'));
      expect(RedisTypeUtils.getIcon('hyperloglog'), equals('🔢'));
      expect(RedisTypeUtils.getIcon('geo'), equals('📍'));
      expect(RedisTypeUtils.getIcon('json'), equals('📄'));
      expect(RedisTypeUtils.getIcon('rejson-rl'), equals('📄'));
      expect(RedisTypeUtils.getIcon('bloom'), equals('🌸'));
      expect(RedisTypeUtils.getIcon('cuckoo'), equals('🐦'));
      expect(RedisTypeUtils.getIcon('tdigest'), equals('📉'));
      expect(RedisTypeUtils.getIcon('topk'), equals('🏆'));
      expect(RedisTypeUtils.getIcon('cms'), equals('📊'));
      expect(RedisTypeUtils.getIcon('timeseries'), equals('⏱️'));
      expect(RedisTypeUtils.getIcon('vectorset'), equals('🔍'));
      expect(RedisTypeUtils.getIcon('none'), equals('❓'));
    });

    test('getIcon 未知类型返回默认 🔑', () {
      expect(RedisTypeUtils.getIcon('unknown'), equals('🔑'));
      expect(RedisTypeUtils.getIcon(''), equals('🔑'));
    });

    test('getIcon 应忽略大小写', () {
      expect(RedisTypeUtils.getIcon('STRING'), equals('🔤'));
      expect(RedisTypeUtils.getIcon('Hash'), equals('🗂️'));
    });

    test('getLabel 应返回对应标签', () {
      expect(RedisTypeUtils.getLabel('string'), equals('string'));
      expect(RedisTypeUtils.getLabel('hash'), equals('hash'));
      expect(RedisTypeUtils.getLabel('zset'), equals('zset'));
      expect(RedisTypeUtils.getLabel('stream'), equals('stream'));
      expect(RedisTypeUtils.getLabel('bitmap'), equals('bitmap'));
      expect(RedisTypeUtils.getLabel('bitfield'), equals('bitfield'));
      expect(RedisTypeUtils.getLabel('hyperloglog'), equals('hyperloglog'));
      expect(RedisTypeUtils.getLabel('geo'), equals('geo'));
      expect(RedisTypeUtils.getLabel('json'), equals('json'));
      expect(RedisTypeUtils.getLabel('rejson-rl'), equals('json'));
      expect(RedisTypeUtils.getLabel('bloom'), equals('bloom'));
      expect(RedisTypeUtils.getLabel('cuckoo'), equals('cuckoo'));
      expect(RedisTypeUtils.getLabel('tdigest'), equals('t-digest'));
      expect(RedisTypeUtils.getLabel('topk'), equals('top-k'));
      expect(RedisTypeUtils.getLabel('cms'), equals('cms'));
      expect(RedisTypeUtils.getLabel('timeseries'), equals('time series'));
      expect(RedisTypeUtils.getLabel('vectorset'), equals('vector set'));
      expect(RedisTypeUtils.getLabel('none'), equals('none'));
    });

    test('getLabel 未知类型返回原始类型', () {
      expect(RedisTypeUtils.getLabel('unknown'), equals('unknown'));
      expect(RedisTypeUtils.getLabel(''), equals(''));
    });

    test('getLabel 应忽略大小写', () {
      expect(RedisTypeUtils.getLabel('STRING'), equals('string'));
      expect(RedisTypeUtils.getLabel('Hash'), equals('hash'));
    });
  });
}
