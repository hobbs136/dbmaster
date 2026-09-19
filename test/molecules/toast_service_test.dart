// ToastService 时长策略测试（连接失败 UX 重构 T10）。
//
// 覆盖：error 类默认时长 3s → 8s（4s 仍可见、8s 后消失）；success 类 3s
// 不变（4s 已消失）；显式传 duration 仍可覆盖；X 点击即时关闭。
// 纯 widget 测试（Overlay 展示，无数据库 / 平台通道依赖）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/molecules/toast_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  tearDown(() {
    // ToastService 为静态 overlay 队列，用例间隔离。
    ToastService.dismissAll();
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('error 类 pump(4s) 仍可见，pump(8s) 后消失', (tester) async {
    final context = await pumpHost(tester);

    ToastService.error(context, 'boom');
    await tester.pump(); // overlay entry 挂载
    await tester.pump(); // entry 首帧构建
    expect(find.text('boom'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('boom'), findsOneWidget, reason: '8s 前错误必须持久可见');

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('boom'), findsOneWidget, reason: '7s 时仍在');

    await tester.pump(const Duration(seconds: 1)); // 8s 定时触发退场（300ms）
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('boom'), findsNothing);
  });

  testWidgets('success 类 pump(4s) 已消失（3s 默认不变）', (tester) async {
    final context = await pumpHost(tester);

    ToastService.success(context, 'ok');
    await tester.pump();
    await tester.pump();
    expect(find.text('ok'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4)); // 3s + 300ms 退场已过
    expect(find.text('ok'), findsNothing);
  });

  testWidgets('error 类显式传 duration 仍可覆盖', (tester) async {
    final context = await pumpHost(tester);

    ToastService.error(context, 'short', duration: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('short'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1, milliseconds: 500));
    expect(find.text('short'), findsNothing);
  });

  testWidgets('X 点击即时消失（error 8s 内手动关闭）', (tester) async {
    final context = await pumpHost(tester);

    ToastService.error(context, 'close-me');
    await tester.pump();
    await tester.pump();
    expect(find.text('close-me'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pump(); // 退场动画开始
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('close-me'), findsNothing);

    // X 关闭是即时移除，但 _ToastWidget 的时长定时器仍会到点（no-op 调
    // _dismiss），冲刷之以免 flutter_test 的 pending-timer 断言拦截。
    await tester.pump(const Duration(seconds: 8));
  });
}
