import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/rfc3339.dart';

void main() {
  group('formatRfc3339Local（U17）', () {
    test('RFC3339 UTC → 本地时区 yyyy-MM-dd HH:mm', () {
      final utc = DateTime.utc(2026, 8, 13, 10, 30, 0);
      final local = utc.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      final expectLocal =
          '${local.year}-${two(local.month)}-${two(local.day)} '
          '${two(local.hour)}:${two(local.minute)}';
      expect(formatRfc3339Local('2026-08-13T10:30:00Z'), expectLocal);
    });

    test('withSeconds 带秒', () {
      final out = formatRfc3339Local('2026-08-13T10:30:45Z', withSeconds: true);
      expect(out, contains(':'));
      // 长度 = "yyyy-MM-dd HH:mm:ss"（19）
      expect(out.length, 19);
    });

    test('与本地手写 toLocal 实现一致（此前两处直接显示 UTC 值）', () {
      final iso = '2026-01-02T03:04:05Z';
      final manual = DateTime.parse(iso).toLocal();
      final out = formatRfc3339Local(iso, withSeconds: true);
      expect(out, manual.toString().substring(0, 19));
    });

    test('非法输入原样返回', () {
      expect(formatRfc3339Local('not-a-date'), 'not-a-date');
      expect(formatRfc3339Local(''), '');
    });
  });
}
