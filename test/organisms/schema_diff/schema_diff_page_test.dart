import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/organisms/connection/schema_diff/schema_diff_page.dart';
import 'package:dbmaster/providers/app_provider.dart';

/// SchemaDiffPage widget 测试。
///
/// 仅覆盖无需真实数据库的可渲染面：空状态。键盘导航的选择移动逻辑由
/// SchemaDiffTree.moveSelection / objectKeys 的纯函数测试覆盖（见
/// schema_diff_tree_test.dart）；端到端键盘走查需加载 diff 报告（依赖真实
/// DB captureSnapshot），属桌面手动验证范围。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  //AppProvider 构造会触发 in_app_purchase Pigeon 通道与
  // SharedPreferences，必须先安装桩，否则单测会挂起。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi',
      (message) async =>
          const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
    );
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchaseApi',
      (message) async =>
          const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
    );
  });

  testWidgets('未加载报告时显示空状态提示', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: AppProvider(),
        child: const MaterialApp(
          home: Scaffold(body: SchemaDiffPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').contains('Select source and target databases'),
      ),
      findsOneWidget,
    );
    expect(find.text('Compare'), findsOneWidget);
  });
}
