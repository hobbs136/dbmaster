import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/ai_quota_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiQuotaService', () {
    late AiQuotaService service;
    bool isProUser = false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      isProUser = false;
      service = AiQuotaService(isPro: () async => isProUser);
    });

    tearDown(() async {
      await service.resetForTesting();
    });

    test('Pro 用户无配额限制', () async {
      isProUser = true;
      expect(await service.hasQuota(), isTrue);
      expect(await service.getRemainingCount(), equals(-1));
    });

    test('Free 用户初始有 30 次配额', () async {
      expect(await service.hasQuota(), isTrue);
      expect(await service.getRemainingCount(), equals(30));
      expect(await service.getUsedCount(), equals(0));
    });

    test('Free 用户使用配额后递减', () async {
      await service.recordUsage();
      expect(await service.getUsedCount(), equals(1));
      expect(await service.getRemainingCount(), equals(29));
    });

    test('Free 用户使用 30 次后无配额', () async {
      for (var i = 0; i < 30; i++) {
        await service.recordUsage();
      }
      expect(await service.hasQuota(), isFalse);
      expect(await service.getRemainingCount(), equals(0));
    });

    test('跨月自动重置配额', () async {
      await service.recordUsage();
      expect(await service.getUsedCount(), equals(1));

      // 模拟下一个月：手动修改存储的月份
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dbmaster_ai_quota_last_month', '1999-01');

      expect(await service.getUsedCount(), equals(0));
      expect(await service.getRemainingCount(), equals(30));
    });
  });
}
