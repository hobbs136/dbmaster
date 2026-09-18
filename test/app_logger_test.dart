import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/app_logger.dart';

void main() {
  group('AppLogger', () {
    test('d() should not throw', () {
      expect(() => AppLogger.d('TestTag', 'debug message'), returnsNormally);
    });

    test('i() should not throw', () {
      expect(() => AppLogger.i('TestTag', 'info message'), returnsNormally);
    });

    test('w() should not throw', () {
      expect(() => AppLogger.w('TestTag', 'warning message'), returnsNormally);
    });

    test('e() should not throw without error', () {
      expect(() => AppLogger.e('TestTag', 'error message'), returnsNormally);
    });

    test('e() should not throw with error', () {
      expect(
        () => AppLogger.e('TestTag', 'error with exception', Exception('test')),
        returnsNormally,
      );
    });
  });
}
