import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/message_time_formatter.dart';

void main() {
  group('MessageTimeFormatter.formatTime', () {
    test('小于60秒应返回 刚刚', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final time = now.subtract(const Duration(seconds: 30));
      expect(MessageTimeFormatter.formatTime(time, now: now), '刚刚');
    });

    test('1-59分钟应返回 N分钟前', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final time = now.subtract(const Duration(minutes: 5));
      expect(MessageTimeFormatter.formatTime(time, now: now), '5分钟前');
    });

    test('1-23小时应返回 N小时前', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final time = now.subtract(const Duration(hours: 3));
      expect(MessageTimeFormatter.formatTime(time, now: now), '3小时前');
    });

    test('1-6天应返回 N天前', () {
      final now = DateTime(2024, 1, 8, 12, 0, 0);
      final time = now.subtract(const Duration(days: 3));
      expect(MessageTimeFormatter.formatTime(time, now: now), '3天前');
    });

    test('超过7天应返回 HH:mm', () {
      final now = DateTime(2024, 1, 15, 12, 0, 0);
      final time = now.subtract(const Duration(days: 10));
      expect(MessageTimeFormatter.formatTime(time, now: now), '12:00');
    });

    test('边界：正好60秒应返回 1分钟前', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final time = now.subtract(const Duration(seconds: 60));
      expect(MessageTimeFormatter.formatTime(time, now: now), '1分钟前');
    });
  });

  group('MessageTimeFormatter.formatFullTime', () {
    test('应返回 yyyy-MM-dd HH:mm:ss', () {
      final time = DateTime(2024, 3, 15, 9, 30, 45);
      expect(MessageTimeFormatter.formatFullTime(time), '2024-03-15 09:30:45');
    });
  });

  group('MessageTimeFormatter.formatShortTime', () {
    test('应返回 HH:mm', () {
      final time = DateTime(2024, 1, 1, 14, 5);
      expect(MessageTimeFormatter.formatShortTime(time), '14:05');
    });

    test('应补零', () {
      final time = DateTime(2024, 1, 1, 9, 5);
      expect(MessageTimeFormatter.formatShortTime(time), '09:05');
    });
  });
}
