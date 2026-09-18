import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/pii_masker.dart';

/// PIIMasker.detectColumnPii 单测（R4 列级 PII 检测）。
/// 覆盖：列名启发式（强信号）、采样值内容检测（弱信号+阈值）、敏感度分级。
void main() {
  late PIIMasker masker;

  setUp(() {
    masker = PIIMasker();
  });

  group('detectColumnPii - 列名启发式（强信号）', () {
    test('email 列名 → 命中 email pattern', () {
      final d = masker.detectColumnPii(
        columnName: 'user_email',
        sampleValues: const [],
      );
      expect(d.hasPii, isTrue);
      expect(d.patternKey, 'email');
      expect(d.sensitivity, PiiSensitivity.normal);
    });

    test('phone 列名 → 命中 phone pattern', () {
      final d = masker.detectColumnPii(
        columnName: 'mobile_number',
        sampleValues: const [],
      );
      expect(d.hasPii, isTrue);
      expect(d.patternKey, 'phone');
    });

    test('id_card 列名 → 高敏感', () {
      final d = masker.detectColumnPii(
        columnName: 'id_card_no',
        sampleValues: const [],
      );
      expect(d.hasPii, isTrue);
      expect(d.patternKey, 'id_card');
      expect(d.sensitivity, PiiSensitivity.high);
    });

    test('bank_card 列名 → 高敏感', () {
      final d = masker.detectColumnPii(
        columnName: 'bank_account',
        sampleValues: const [],
      );
      expect(d.sensitivity, PiiSensitivity.high);
    });

    test('credit_card 列名 → 高敏感', () {
      final d = masker.detectColumnPii(
        columnName: 'credit_card_number',
        sampleValues: const [],
      );
      expect(d.sensitivity, PiiSensitivity.high);
    });

    test('password 列名 → 高敏感', () {
      final d = masker.detectColumnPii(
        columnName: 'pwd',
        sampleValues: const [],
      );
      expect(d.patternKey, 'password');
      expect(d.sensitivity, PiiSensitivity.high);
    });
  });

  group('detectColumnPii - 采样值内容检测（弱信号）', () {
    test('普通列名 + email 格式值（>20% 命中）→ 检出 PII', () {
      final d = masker.detectColumnPii(
        columnName: 'contact',
        sampleValues: [
          'alice@example.com',
          'bob@test.com',
          'charlie@demo.org',
        ],
      );
      expect(d.hasPii, isTrue);
      expect(d.patternKey, 'email');
      expect(d.sampleHitRatio, greaterThan(0.2));
    });

    test('普通列名 + 个别巧合值（<20% 命中）→ 不检出', () {
      // 10 个值里只有 1 个像 phone（10% < 20% 阈值）
      final d = masker.detectColumnPii(
        columnName: 'note',
        sampleValues: [
          '13800138000', // 巧合命中 phone
          'hello',
          'world',
          'foo',
          'bar',
          'baz',
          'qux',
          'quux',
          'corge',
          'grault',
        ],
      );
      expect(d.hasPii, isFalse);
    });

    test('身份证值（高比例命中）→ 高敏感', () {
      final d = masker.detectColumnPii(
        columnName: 'id_number', // 列名其实会先命中，这里测值路径用中性列名
        sampleValues: const [],
      );
      // 列名 id_number 含 'id'... 实际 _getColumnHint 检查 'id_card'/'idcard'/'identity'
      // 'id_number' 不含这些 → 走不到列名，但列名测试已覆盖，这里确认中性列名不误报
      // 改用真正中性的列名测身份证值
      final d2 = masker.detectColumnPii(
        columnName: 'extra',
        sampleValues: const [
          '110101199003071234',
          '110101199003072345',
          '110101199003073456',
        ],
      );
      expect(d2.hasPii, isTrue);
      expect(d2.patternKey, 'id_card');
      expect(d2.sensitivity, PiiSensitivity.high);
    });

    test('空采样 → 不检出', () {
      final d = masker.detectColumnPii(
        columnName: 'anything',
        sampleValues: const [],
      );
      expect(d.hasPii, isFalse);
    });

    test('中性列名 + 无 PII 值 → 不检出', () {
      // 注意：避免用含 'ip'/'email' 等子串的列名（如 description 含 ip），
      // 那会触发列名启发式误报——属既有 _getColumnHint 的已知宽松匹配。
      final d = masker.detectColumnPii(
        columnName: 'note',
        sampleValues: const ['hello', 'world', 'foo bar'],
      );
      expect(d.hasPii, isFalse);
    });
  });

  group('PiiColumnDetection 模型', () {
    test('默认 sensitivity 为 normal', () {
      const d = PiiColumnDetection(columnName: 'x', hasPii: false);
      expect(d.sensitivity, PiiSensitivity.normal);
      expect(d.patternKey, isNull);
      expect(d.sampleHitRatio, isNull);
    });
  });

  group('PiiSensitivity', () {
    test('有两个值', () {
      expect(PiiSensitivity.values.length, 2);
      expect(PiiSensitivity.values, contains(PiiSensitivity.high));
      expect(PiiSensitivity.values, contains(PiiSensitivity.normal));
    });
  });
}
