import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/connection_encryption_util.dart';

void main() {
  group('ConnectionEncryptionUtil', () {
    test('encrypt/decrypt roundtrip', () {
      final plain = '{"connections":[]}';
      final password = 'MyBackup2025!';
      final encrypted = ConnectionEncryptionUtil.encrypt(plain, password);
      final decrypted = ConnectionEncryptionUtil.decrypt(encrypted, password);
      expect(decrypted, plain);
    });

    test('wrong password throws', () {
      final plain = '{"connections":[]}';
      final encrypted = ConnectionEncryptionUtil.encrypt(plain, 'correct');
      expect(
        () => ConnectionEncryptionUtil.decrypt(encrypted, 'wrong'),
        throwsA(isA<Exception>()),
      );
    });

    test('tampered ciphertext throws', () {
      final encrypted = ConnectionEncryptionUtil.encrypt('hello', 'pw');
      final tampered = '${encrypted.substring(0, encrypted.length - 4)}abcd';
      expect(
        () => ConnectionEncryptionUtil.decrypt(tampered, 'pw'),
        throwsA(isA<Exception>()),
      );
    });

    test('empty content roundtrip', () {
      final encrypted = ConnectionEncryptionUtil.encrypt('', 'pw');
      final decrypted = ConnectionEncryptionUtil.decrypt(encrypted, 'pw');
      expect(decrypted, '');
    });
  });
}
