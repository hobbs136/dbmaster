import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/redis_function.dart';

void main() {
  group('RedisFunctionInfo', () {
    test('应使用必填字段构造', () {
      final info = RedisFunctionInfo(name: 'myfunc');
      expect(info.name, equals('myfunc'));
      expect(info.description, isNull);
      expect(info.flags, isEmpty);
    });

    test('应使用全部字段构造', () {
      final info = RedisFunctionInfo(
        name: 'myfunc',
        description: 'My function',
        flags: ['no-writes'],
      );
      expect(info.name, equals('myfunc'));
      expect(info.description, equals('My function'));
      expect(info.flags, equals(['no-writes']));
    });
  });

  group('RedisFunctionLibrary', () {
    test('应正确构造', () {
      final lib = RedisFunctionLibrary(
        name: 'mylib',
        engine: 'LUA',
        functions: [],
      );
      expect(lib.name, equals('mylib'));
      expect(lib.engine, equals('LUA'));
      expect(lib.functions, isEmpty);
    });

    test('应包含函数列表', () {
      final lib = RedisFunctionLibrary(
        name: 'mylib',
        engine: 'LUA',
        functions: [
          RedisFunctionInfo(name: 'f1'),
          RedisFunctionInfo(
            name: 'f2',
            description: 'Func 2',
            flags: ['no-writes'],
          ),
        ],
      );
      expect(lib.functions.length, equals(2));
      expect(lib.functions[0].name, equals('f1'));
      expect(lib.functions[1].name, equals('f2'));
      expect(lib.functions[1].flags, equals(['no-writes']));
    });
  });
}
