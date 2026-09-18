import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/version_compare.dart';

void main() {
  group('compareVersions（U15）', () {
    test('日期式（CalVer）：字典序 = 时间序', () {
      expect(compareVersions('v2026-07-27', 'v2026-08-17'), -1);
      expect(compareVersions('2026-08-17', '2026-07-27'), 1);
      expect(compareVersions('v2026-08-17', 'v2026-08-17'), 0);
      expect(compareVersions('2025-12-31', '2026-01-01'), -1);
    });

    test('SemVer：逐段数值比较（0.2.0 < 0.10.0）', () {
      expect(compareVersions('0.1.0', '0.1.1'), -1);
      expect(compareVersions('0.2.0', '0.10.0'), -1);
      expect(compareVersions('v1.7.1', '1.7.1'), 0);
      expect(compareVersions('1.7.0', '1.7.1'), -1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
      // 缺段补 0
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1', '1.0.1'), -1);
    });

    test('剥 v 前缀与 +build 号', () {
      expect(compareVersions('v1.0.0', '1.0.0'), 0);
      expect(compareVersions('0.0.1+1', '0.0.1'), 0);
      expect(compareVersions('v2026-07-27+5', 'v2026-07-27'), 0);
    });

    test('跨风格（日期 vs SemVer）不可判定 → null', () {
      expect(compareVersions('1.7.0', '2026-07-27'), isNull);
      expect(compareVersions('v2026-08-17', 'v1.7.0'), isNull);
    });

    test('空串 → null', () {
      expect(compareVersions('', '1.0.0'), isNull);
      expect(compareVersions('v', '1.0.0'), isNull); // 剥前缀后为空
    });

    test('非数字段退回字符串比较', () {
      expect(compareVersions('1.0.0-beta', '1.0.0-rc'), isNotNull);
      expect(compareVersions('1.0.0-a', '1.0.0-b'), -1);
    });
  });

  group('isDateVersion', () {
    test('识别日期式', () {
      expect(isDateVersion('v2026-07-27'), isTrue);
      expect(isDateVersion('2026-08-17'), isTrue);
      expect(isDateVersion('1.7.0'), isFalse);
      expect(isDateVersion(''), isFalse);
    });
  });
}
