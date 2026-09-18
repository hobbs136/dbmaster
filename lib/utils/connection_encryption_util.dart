import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 加密/解密工具，用于导出/导入连接信息。
///
/// 使用 PBKDF2-HMAC-SHA256 从用户密码派生 AES-256 密钥，
/// 并采用 AES-256-GCM 进行加密，输出格式为：
/// salt(16) + nonce(12) + ciphertext + tag(16)，最后 Base64 编码。
class ConnectionEncryptionUtil {
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int _keyLength = 32;
  static const int _iterations = 100000;

  /// 使用 [password] 派生密钥，加密 [plaintext]，返回 Base64 字符串。
  ///
  /// [password] 不能为空。
  static String encrypt(String plaintext, String password) {
    if (password.isEmpty) throw ArgumentError('password cannot be empty');
    final salt = _secureRandom(_saltLength);
    final nonce = _secureRandom(_nonceLength);
    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagLength * 8, nonce, Uint8List(0)),
      );

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final ciphertext = cipher.process(input);

    final output = BytesBuilder()
      ..add(salt)
      ..add(nonce)
      ..add(ciphertext);

    return base64Encode(output.toBytes());
  }

  /// 使用 [password] 解密 [encryptedBase64]，返回原始字符串。
  ///
  /// [password] 不能为空。
  static String decrypt(String encryptedBase64, String password) {
    if (password.isEmpty) throw ArgumentError('password cannot be empty');
    final bytes = base64Decode(encryptedBase64);
    if (bytes.length < _saltLength + _nonceLength + _tagLength) {
      throw FormatException('Invalid encrypted content');
    }

    final salt = bytes.sublist(0, _saltLength);
    final nonce = bytes.sublist(_saltLength, _saltLength + _nonceLength);
    final ciphertextAndTag = bytes.sublist(_saltLength + _nonceLength);

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _tagLength * 8, nonce, Uint8List(0)),
      );

    final output = cipher.process(ciphertextAndTag);
    return utf8.decode(output);
  }

  static Uint8List _deriveKey(String password, Uint8List salt) {
    final params = Pbkdf2Parameters(salt, _iterations, _keyLength);
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(params);
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _secureRandom(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
}
