// spec 044 US3 / PD-7 / T023 — parseConnectionString 14 例单测。
// 覆盖：多 host+端口、SRV、%40 %23 %2F %3A 解码、仅用户名、无凭据、空密码、
// 空白、非法 scheme 拒绝、SRV+多 host 拒绝、ssl/tls；并断言 credentialFreeUri 不含 @。
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/adapters/mongodb_adapter.dart';

void main() {
  group('MongoDBAdapter.parseConnectionString (spec 044 US3 / PD-7)', () {
    test('1. 多 host+端口（无凭据）', () {
      const raw = 'mongodb://h1:27018,h2:27019,h3:27020/db?replicaSet=rs0';
      final p = MongoDBAdapter.parseConnectionString(raw);
      expect(p.username, isNull);
      expect(p.password, isNull);
      expect(p.isSrv, isFalse);
      expect(p.credentialFreeUri, raw);
      expect(p.credentialFreeUri.contains('@'), isFalse);
    });

    test('2. SRV（Atlas 风格）', () {
      const raw = 'mongodb+srv://user:pass@cluster.example.net/?authSource=admin';
      final p = MongoDBAdapter.parseConnectionString(raw);
      expect(p.isSrv, isTrue);
      expect(p.username, 'user');
      expect(p.password, 'pass');
      expect(p.authSource, 'admin');
      expect(
        p.credentialFreeUri,
        'mongodb+srv://cluster.example.net/?authSource=admin',
      );
      expect(p.credentialFreeUri.contains('@'), isFalse);
    });

    test('3. %40 解码（密码含编码 @）', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://u:p%40ss@h/db');
      expect(p.password, 'p@ss');
      expect(p.credentialFreeUri, 'mongodb://h/db');
    });

    test('4. %23 解码（密码含编码 #）', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://u:p%23ss@h/db');
      expect(p.password, 'p#ss');
    });

    test('5. %2F 解码（密码含编码 /）', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://u:p%2Fss@h/db');
      expect(p.password, 'p/ss');
    });

    test('6. %3A 解码（密码含编码 :，不干扰切分）', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://u:p%3Ass@h/db');
      expect(p.username, 'u');
      expect(p.password, 'p:ss');
    });

    test('7. 仅用户名（无密码）', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://user@host:27017');
      expect(p.username, 'user');
      expect(p.password, isNull);
      expect(p.credentialFreeUri, 'mongodb://host:27017');
    });

    test('8. 无凭据', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://host:27017');
      expect(p.username, isNull);
      expect(p.password, isNull);
      expect(p.credentialFreeUri, 'mongodb://host:27017');
    });

    test('9. 空密码（user:）', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://user:@host');
      expect(p.username, 'user');
      expect(p.password, '');
    });

    test('10. 首尾空白被 trim', () {
      final p = MongoDBAdapter.parseConnectionString('  mongodb://host:27017  ');
      expect(p.credentialFreeUri, 'mongodb://host:27017');
    });

    test('11. 非法 scheme 拒绝', () {
      expect(
        () => MongoDBAdapter.parseConnectionString('postgres://host'),
        throwsA(isA<FormatException>()),
      );
    });

    test('12. SRV + 多 host（逗号）拒绝', () {
      expect(
        () => MongoDBAdapter.parseConnectionString('mongodb+srv://h1,h2/db'),
        throwsA(isA<FormatException>()),
      );
    });

    test('13. ssl=true → useSSL', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://host?ssl=true');
      expect(p.useSSL, isTrue);
    });

    test('14. tls=true → useSSL', () {
      final p = MongoDBAdapter.parseConnectionString('mongodb://host?tls=true');
      expect(p.useSSL, isTrue);
    });

    test('FR-007：所有含凭据用例的 credentialFreeUri 均无 @', () {
      const samples = [
        'mongodb://u:p@h',
        'mongodb://u:p%40ss@h/db',
        'mongodb+srv://u:p@cluster.net/?authSource=admin',
        'mongodb://u:p%23ss@h',
      ];
      for (final raw in samples) {
        final p = MongoDBAdapter.parseConnectionString(raw);
        expect(
          p.credentialFreeUri.contains('@'),
          isFalse,
          reason: '$raw 的 credentialFreeUri 仍含 @',
        );
      }
    });
  });
}
