// Regression test for hotfix/error-snackbar-persist-autodismiss.
//
// Bug (user report): 连接数据库失败时，底部红色错误 SnackBar「一直存在，只有点 Copy 才
// 消失」。根因：Flutter 3.41 的 SnackBar 构造函数 `persist = persist ?? action != null`
// ——**带 action 的 SnackBar 默认 persist=true（不自动消失）**。`showErrorSnackBar` 的
// SnackBar 带 Copy action 且未显式 persist，故 persist 默认 true → 永不自动消失，直到
// 用户点 Copy（点 action 会关闭，见 snack_bar.dart:154）。
//
// Fix: 显式 `persist: false`——错误通知应到期自动消失；Copy 仍可点击立即关闭。
//
// ⚠️ 测试时序要点：**不可用 pumpAndSettle**——SnackBar 控制器 duration 即 widget.duration
// （5s），pumpAndSettle 会跑完整段显示动画。用入场帧 pump（pump() + pump(~300ms)）保持
// 5s 计时器未到期，再推进过 5s。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/connection/error_boundary.dart';

Widget _wrapWithTrigger(void Function(BuildContext) onTrigger) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onTrigger(context),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test 默认未处理 Clipboard 平台通道，setData 会永久挂起。
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // 主回归用例：带 Copy action 的错误 SnackBar 应在 5s 后自动消失。
  // 修复前：persist 默认 true（因有 action）→ 不自动消失 → 6s 后仍在（FAIL）。
  // 修复后：persist: false → 5s 自动消失 → 6s 后已无（PASS）。
  testWidgets('error SnackBar auto-dismisses after its duration despite the Copy action',
      (tester) async {
    await tester.pumpWidget(
      _wrapWithTrigger((c) => AppErrorHandler.showErrorSnackBar(c, 'boom')),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 入场完成；5s 计时器在跑
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    // 推进过 5s 时长（小步递增，让退场动画落地）。32 × 200ms = 6.4s。
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.text('boom'),
      findsNothing,
      reason: '带 Copy 的错误 SnackBar 应在 5s 后自动消失（persist:false）；'
          '修复前 persist 默认 true 致永不自动消失',
    );
  });

  // 守卫：点 Copy 仍能立即关闭（persist:false 不得破坏 action 点击关闭）。
  testWidgets('tapping Copy still dismisses the error SnackBar', (tester) async {
    await tester.pumpWidget(
      _wrapWithTrigger((c) => AppErrorHandler.showErrorSnackBar(c, 'boom')),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Copy'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('boom'), findsNothing, reason: '点 Copy 应立即关闭');
  });
}
