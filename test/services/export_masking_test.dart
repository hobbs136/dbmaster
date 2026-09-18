import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/export_service.dart';

/// ExportService._applyMasking 单测（R4 PII 脱敏导出）。
/// 验证：drop 删列 / mask 局部遮挡 / hash SHA-256 / keep 原值 + 审计只记方式。
/// 测纯函数 applyMaskingForTest（不依赖 context/FilePicker）。
void main() {
  group('ExportService.applyMaskingForTest', () {
    test('drop → 该列从结果移除', () {
      final data = [
        {'name': 'Alice', 'ssn': '123-45-6789'},
      ];
      final masked = ExportService.applyMaskingForTest(
        data,
        {'ssn': PiiMaskAction.drop},
      );
      expect(masked.first.containsKey('ssn'), isFalse);
      expect(masked.first['name'], 'Alice'); // 其它列保留
    });

    test('mask → PIIMasker 局部遮挡（email 列）', () {
      final data = [
        {'email': 'alice@example.com'},
      ];
      final masked = ExportService.applyMaskingForTest(
        data,
        {'email': PiiMaskAction.mask},
      );
      final value = masked.first['email'] as String;
      // email 脱敏后应含 *** 且保留 @domain
      expect(value, contains('***'));
      expect(value, contains('@example.com'));
      // 不含完整原始明文
      expect(value, isNot('alice@example.com'));
    });

    test('mask → phone 列局部遮挡', () {
      final data = [
        {'phone': '13800138000'},
      ];
      final masked = ExportService.applyMaskingForTest(
        data,
        {'phone': PiiMaskAction.mask},
      );
      final value = masked.first['phone'] as String;
      // phone partial：保留前 3 + 后 4，中间 *
      expect(value, contains('***'));
      expect(value, isNot('13800138000'));
    });

    test('hash → SHA-256 单向哈希（不可逆）', () {
      final data = [
        {'token': 'secret123'},
      ];
      final masked = ExportService.applyMaskingForTest(
        data,
        {'token': PiiMaskAction.hash},
      );
      final value = masked.first['token'] as String;
      // SHA-256 是 64 位十六进制
      expect(value.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(value), isTrue);
      // 不含原始明文
      expect(value, isNot('secret123'));
    });

    test('keep → 原值不变', () {
      final data = [
        {'note': 'hello world'},
      ];
      final masked = ExportService.applyMaskingForTest(
        data,
        {'note': PiiMaskAction.keep},
      );
      expect(masked.first['note'], 'hello world');
    });

    test('混合动作：多列不同处理', () {
      final data = [
        {'name': 'Alice', 'email': 'alice@example.com', 'phone': '13800138000', 'note': 'ok'},
      ];
      final masked = ExportService.applyMaskingForTest(data, {
        'name': PiiMaskAction.keep,
        'email': PiiMaskAction.mask,
        'phone': PiiMaskAction.hash,
        'note': PiiMaskAction.drop,
      });
      final row = masked.first;
      expect(row['name'], 'Alice');
      expect((row['email'] as String), contains('***'));
      expect((row['phone'] as String).length, 64); // hash
      expect(row.containsKey('note'), isFalse); // dropped
    });

    test('未在 columnActions 中的列 → keep（默认原值）', () {
      final data = [
        {'a': 1, 'b': 2},
      ];
      final masked = ExportService.applyMaskingForTest(
        data,
        {'a': PiiMaskAction.mask}, // 只指定 a，b 未指定
      );
      expect(masked.first['b'], 2); // b 保持原值
    });

    test('null 值不被脱敏（保持 null）', () {
      final data = [
        {'email': null},
      ];
      final masked = ExportService.applyMaskingForTest(
        data,
        {'email': PiiMaskAction.mask},
      );
      expect(masked.first['email'], isNull);
    });

    test('不改原数据（返回副本）', () {
      final original = [
        {'email': 'alice@example.com'},
      ];
      ExportService.applyMaskingForTest(original, {'email': PiiMaskAction.mask});
      // 原数据不变
      expect(original.first['email'], 'alice@example.com');
    });

    test('空数据 → 空结果', () {
      final masked = ExportService.applyMaskingForTest(
        const [],
        {'a': PiiMaskAction.drop},
      );
      expect(masked, isEmpty);
    });
  });

  group('PiiMaskAction 枚举', () {
    test('有 4 个值（keep/mask/hash/drop）', () {
      expect(PiiMaskAction.values.length, 4);
      expect(PiiMaskAction.values, contains(PiiMaskAction.keep));
      expect(PiiMaskAction.values, contains(PiiMaskAction.mask));
      expect(PiiMaskAction.values, contains(PiiMaskAction.hash));
      expect(PiiMaskAction.values, contains(PiiMaskAction.drop));
    });
  });
}
