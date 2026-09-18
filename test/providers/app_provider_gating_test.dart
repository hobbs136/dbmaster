import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import '../helpers/fake_pro_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(secureChannel, (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(secureChannel, null);
  });

  group('AppProvider Free/Pro 门禁', () {
    late AppProvider provider;
    late FakeProModule fakePro;

    setUp(() {
      // Phase A: 注入 FakeProModule 替代 PurchaseService.debugSetProForTesting
      fakePro = FakeProModule();
      provider = AppProvider(proModule: fakePro);
    });

    tearDown(() {
      fakePro.dispose();
    });

    Future<void> becomePro() async {
      // Phase A: FakeProModule.isPro=true 触发 notifyListeners → AppProvider 重评估门禁
      fakePro.isPro = true;
    }

    test('Free：功能门全关，开放项保持开放', () {
      expect(provider.canSyncSchemaDiff, isFalse);
      expect(provider.canUseDataImport, isFalse);
      expect(provider.canUseDataSync, isFalse);
      // 有意 Free 开放
      expect(provider.canViewSchemaDiff, isTrue);
      expect(provider.isDatabaseTypeAllowed(DatabaseType.mysql), isTrue);
      expect(provider.isDatabaseTypeAllowed(DatabaseType.redis), isTrue);
    });

    test('Pro：功能门全开', () async {
      await becomePro();
      expect(provider.canSyncSchemaDiff, isTrue);
      expect(provider.canUseDataImport, isTrue);
      expect(provider.canUseDataSync, isTrue);
    });

    test('AI 配额：Free 30 次后拒绝，Pro 无限', () async {
      expect(await provider.canUseAi(), isTrue);
      expect(await provider.getAiQuotaRemaining(), 30);

      for (var i = 0; i < 30; i++) {
        await provider.recordAiUsage();
      }
      expect(await provider.canUseAi(), isFalse);
      expect(await provider.getAiQuotaRemaining(), 0);

      await becomePro();
      expect(await provider.canUseAi(), isTrue);
      expect(await provider.getAiQuotaRemaining(), -1);
    });

    test('devBypassGates：debug 下绕过全部门禁', () async {
      AppProvider.devBypassGates = true;
      addTearDown(() => AppProvider.devBypassGates = false);

      expect(provider.canSyncSchemaDiff, isTrue);
      expect(provider.canUseDataSync, isTrue);
      expect(await provider.canUseAi(), isTrue);
    });
  });
}
