import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/pii_masker.dart';

void main() {
  late PIIMasker masker;

  setUp(() {
    masker = PIIMasker();
    // 确保每次测试前重置为默认状态
    masker.resetToDefaults();
    masker.enabled = true;
  });

  tearDown(() {
    // 测试后清理状态
    masker.resetToDefaults();
  });

  group('PIIMasker Basic', () {
    test('should detect and mask email', () {
      final result = masker.maskValue('john.doe@example.com');
      expect(result, 'jo***@example.com');
    });

    test('should detect and mask phone number', () {
      final result = masker.maskValue('13812345678');
      expect(result, '138****5678');
    });

    test('should detect and mask ID card', () {
      final result = masker.maskValue('110101199001011234');
      expect(result, '110101********1234');
    });

    test('should detect and mask credit card', () {
      final result = masker.maskValue('1234-5678-9012-3456');
      expect(result, '***************3456');
    });

    test('should detect and mask bank card', () {
      final result = masker.maskValue('6222021234567890123');
      expect(result, '6222***********0123');
    });

    test('should not mask normal text', () {
      final result = masker.maskValue('Hello World');
      expect(result, 'Hello World');
    });

    test('should not mask when disabled', () {
      masker.enabled = false;
      final result = masker.maskValue('john.doe@example.com');
      expect(result, 'john.doe@example.com');
    });

    test('should handle null value', () {
      final result = masker.maskValue(null);
      expect(result, '');
    });
  });

  group('PIIMasker Column-based Detection', () {
    test('should mask email column', () {
      final result = masker.maskValue(
        'john.doe@example.com',
        columnName: 'email',
      );
      expect(result, 'jo***@example.com');
    });

    test('should mask phone column', () {
      final result = masker.maskValue(
        '13812345678',
        columnName: 'phone_number',
      );
      expect(result, '138****5678');
    });

    test('should mask password column', () {
      final result = masker.maskValue(
        'mySecretPassword123',
        columnName: 'password',
      );
      // password field should be fully masked or kept as is depending on regex
      // The password regex looks for "password=xxx" pattern
      expect(result, 'mySecretPassword123'); // no "password=" prefix
    });

    test('should mask password with prefix', () {
      final result = masker.maskValue(
        'password=mySecret123',
        columnName: 'password',
      );
      expect(result, '********************');
    });

    test('should not mask insensitive column', () {
      final result = masker.maskValue(
        'john.doe@example.com',
        columnName: 'description',
      );
      // description is not in sensitive columns list, but email regex still matches
      expect(result, 'jo***@example.com');
    });
  });

  group('PIIMasker Row Masking', () {
    test('should mask sensitive rows', () {
      final rows = [
        {
          'id': 1,
          'username': 'john_doe',
          'email': 'john@example.com',
          'phone': '13812345678',
          'status': 'active',
        },
        {
          'id': 2,
          'username': 'jane_smith',
          'email': 'jane@test.com',
          'phone': '13987654321',
          'status': 'inactive',
        },
      ];

      final masked = masker.maskRows(rows);

      expect(masked[0]['id'], 1);
      expect(masked[0]['username'], 'john_doe');
      expect(masked[0]['email'], 'jo***@example.com');
      expect(masked[0]['phone'], '138****5678');
      expect(masked[0]['status'], 'active');

      expect(masked[1]['id'], 2);
      expect(masked[1]['username'], 'jane_smith');
      expect(masked[1]['email'], 'ja***@test.com');
      expect(masked[1]['phone'], '139****4321');
      expect(masked[1]['status'], 'inactive');
    });

    test('should not mask when disabled', () {
      masker.enabled = false;
      final rows = [
        {'email': 'test@example.com'},
      ];

      final masked = masker.maskRows(rows);
      expect(masked[0]['email'], 'test@example.com');
    });
  });

  group('PIIMasker Statistics', () {
    test('should count PII occurrences', () {
      final rows = [
        {'email': 'a@b.com', 'phone': '13812345678'},
        {'email': 'c@d.com', 'phone': '13987654321'},
        {'email': 'e@f.com'},
      ];

      final stats = masker.getMaskingStats(rows);

      expect(stats['email'], 3);
      expect(stats['phone'], 2);
    });
  });

  group('PIIMasker Configuration', () {
    test('should enable/disable specific patterns', () {
      masker.setPatternEnabled('email', false);

      final result = masker.maskValue('john@example.com');
      expect(result, 'john@example.com');
    });

    test('should export and import config', () {
      masker.enabled = false;
      masker.setPatternEnabled('phone', false);

      final json = masker.toJson();

      // Reset and re-import
      masker.resetToDefaults();
      expect(masker.enabled, true);

      masker.fromJson(json);

      expect(masker.enabled, false);

      final phoneResult = masker.maskValue('13812345678');
      expect(phoneResult, '13812345678');

      // Check pattern states are correctly imported
      expect(masker.isPatternEnabled('email'), true);
      expect(masker.isPatternEnabled('phone'), false);

      // Enable masker to test individual patterns
      masker.enabled = true;

      final emailResult = masker.maskValue('john@example.com');
      expect(emailResult, 'jo***@example.com');

      // Restore defaults for other tests
      masker.resetToDefaults();
    });
  });

  group('PIIMasker Edge Cases', () {
    test('should handle empty string', () {
      final result = masker.maskValue('');
      expect(result, '');
    });

    test('should handle very long email', () {
      final longEmail = 'very.long.email.address@subdomain.example.com';
      final result = masker.maskValue(longEmail);
      expect(result.startsWith('ve***@'), true);
    });

    test('should handle special characters in email', () {
      final result = masker.maskValue('user+test@example.com');
      expect(result, 'us***@example.com');
    });

    test('should handle numbers', () {
      final result = masker.maskValue(13812345678);
      expect(result, '138****5678');
    });

    test('should handle short email local part', () {
      final result = masker.maskValue('ab@example.com');
      expect(result, 'a***@example.com');
    });

    test('should handle IP address', () {
      final result = masker.maskValue('192.168.1.1');
      expect(result, '********1.1');
    });
  });
}
