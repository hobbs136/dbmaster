import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/redis_script.dart';

void main() {
  group('RedisScript', () {
    final now = DateTime(2026, 5, 24, 10, 30, 0);

    test('应使用默认值构造', () {
      final script = RedisScript(
        id: '1',
        name: 'test',
        code: 'return 1',
        createdAt: now,
        modifiedAt: now,
      );
      expect(script.id, equals('1'));
      expect(script.name, equals('test'));
      expect(script.code, equals('return 1'));
      expect(script.tags, isEmpty);
      expect(script.isGlobal, isTrue);
      expect(script.connectionId, isNull);
    });

    test('应使用全部字段构造', () {
      final script = RedisScript(
        id: '2',
        name: 'warmup',
        code: "redis.call('SET', KEYS[1], ARGV[1])",
        tags: ['cache', 'warmup'],
        isGlobal: false,
        connectionId: 'conn1',
        createdAt: now,
        modifiedAt: now,
      );
      expect(script.tags, equals(['cache', 'warmup']));
      expect(script.isGlobal, isFalse);
      expect(script.connectionId, equals('conn1'));
    });

    test('copyWith 应更新指定字段', () {
      final script = RedisScript(
        id: '1',
        name: 'test',
        code: 'return 1',
        createdAt: now,
        modifiedAt: now,
      );
      final copied = script.copyWith(name: 'updated', isGlobal: false);
      expect(copied.id, equals('1'));
      expect(copied.name, equals('updated'));
      expect(copied.code, equals('return 1'));
      expect(copied.isGlobal, isFalse);
      expect(copied.createdAt, equals(now));
    });

    test('copyWith 不指定字段时保持原值', () {
      final script = RedisScript(
        id: '1',
        name: 'test',
        code: 'return 1',
        tags: ['a'],
        isGlobal: false,
        connectionId: 'c1',
        createdAt: now,
        modifiedAt: now,
      );
      final copied = script.copyWith();
      expect(copied.id, equals('1'));
      expect(copied.name, equals('test'));
      expect(copied.code, equals('return 1'));
      expect(copied.tags, equals(['a']));
      expect(copied.isGlobal, isFalse);
      expect(copied.connectionId, equals('c1'));
      expect(copied.createdAt, equals(now));
      expect(copied.modifiedAt, equals(now));
    });

    test('toJson 应正确序列化', () {
      final script = RedisScript(
        id: '1',
        name: 'test',
        code: 'return 1',
        tags: ['a', 'b'],
        isGlobal: false,
        connectionId: 'conn1',
        createdAt: now,
        modifiedAt: now,
      );
      final json = script.toJson();
      expect(json['id'], equals('1'));
      expect(json['name'], equals('test'));
      expect(json['code'], equals('return 1'));
      expect(json['tags'], equals(['a', 'b']));
      expect(json['isGlobal'], isFalse);
      expect(json['connectionId'], equals('conn1'));
      expect(json['createdAt'], equals('2026-05-24T10:30:00.000'));
      expect(json['modifiedAt'], equals('2026-05-24T10:30:00.000'));
    });

    test('toJson 空 tags 应序列化为空列表', () {
      final script = RedisScript(
        id: '1',
        name: 'test',
        code: 'return 1',
        createdAt: now,
        modifiedAt: now,
      );
      final json = script.toJson();
      expect(json['tags'], isEmpty);
      expect(json['connectionId'], isNull);
    });

    test('fromJson 应正确反序列化', () {
      final json = {
        'id': '2',
        'name': 'warmup',
        'code': 'return 2',
        'tags': ['cache'],
        'isGlobal': false,
        'connectionId': 'conn2',
        'createdAt': '2026-05-24T10:30:00.000',
        'modifiedAt': '2026-05-24T11:00:00.000',
      };
      final script = RedisScript.fromJson(json);
      expect(script.id, equals('2'));
      expect(script.name, equals('warmup'));
      expect(script.code, equals('return 2'));
      expect(script.tags, equals(['cache']));
      expect(script.isGlobal, isFalse);
      expect(script.connectionId, equals('conn2'));
      expect(script.createdAt, equals(now));
      expect(script.modifiedAt, equals(DateTime(2026, 5, 24, 11, 0, 0)));
    });

    test('fromJson 缺失可选字段时应使用默认值', () {
      final json = {
        'id': '3',
        'name': 'minimal',
        'code': 'return 3',
        'createdAt': '2026-05-24T10:30:00.000',
        'modifiedAt': '2026-05-24T10:30:00.000',
      };
      final script = RedisScript.fromJson(json);
      expect(script.tags, isEmpty);
      expect(script.isGlobal, isTrue);
      expect(script.connectionId, isNull);
    });

    test('fromJson tags 为 null 时应使用默认值', () {
      final json = {
        'id': '3',
        'name': 'minimal',
        'code': 'return 3',
        'tags': null,
        'isGlobal': null,
        'connectionId': null,
        'createdAt': '2026-05-24T10:30:00.000',
        'modifiedAt': '2026-05-24T10:30:00.000',
      };
      final script = RedisScript.fromJson(json);
      expect(script.tags, isEmpty);
      expect(script.isGlobal, isTrue);
      expect(script.connectionId, isNull);
    });
  });
}
