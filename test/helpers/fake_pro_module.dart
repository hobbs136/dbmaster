import 'package:dbmaster/services/pro_module.dart';

/// 测试用 [ProModule]（isPro 可控）。
///
/// Phase A（open-core 双仓拆分，ADR 0001）后 AppProvider 注入 ProModule，
/// 默认 [NoOpProModule].isPro 恒 false。门禁测试需可控 Pro 状态时，用此 fake
/// 替代原 `PurchaseService.debugSetProForTesting`（NoOpProModule 不订阅 PurchaseService）。
///
/// 用法：
/// ```dart
/// final fakePro = FakeProModule();
/// final provider = AppProvider(proModule: fakePro);
/// fakePro.isPro = true; // 翻转 → notifyListeners → AppProvider 重评估门禁
/// ```
class FakeProModule extends ProModule {
  bool _isPro;

  FakeProModule({bool isPro = false}) : _isPro = isPro;

  @override
  bool get isPro => _isPro;

  /// 翻转 Pro 状态并通知监听者（AppProvider._onPurchaseChange → notifyListeners）。
  // ignore: avoid_setters_without_getters
  set isPro(bool value) {
    _isPro = value;
    notifyListeners();
  }

  @override
  Future<void> initialize() async {}
}
