// UIRV-B4 T4b · 换壳渐隐：BootShell → 真实工作区 150ms opacity 渐隐
// （任务书：v0.3.5 批1 返工 T4b）。
//
// 红测先行：用例从验收条款直译——①换壳存在 150ms 过渡（curveDefault）；
// ②`MediaQuery.disableAnimations` 时过渡时长 0（无中间帧）。
//
// 受限导入说明：MUST NOT #7 禁止单测 import main.dart（Pigeon 挂起）。
// 本文件沿用既有先例 test/main/window_close_guard_test.dart 的受限导入
// 方式——`show` 仅暴露被测公开件 BootShellCrossFade，不触碰 DbmasterApp /
// ProModuleImpl 等重依赖路径；换壳动画本身与子树内容无关（子树用纯 Text
// 替身），不实例化真实 DbmasterApp。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/main.dart' show BootShellCrossFade;
import 'package:dbmaster/theme/design_system.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool ready,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: BootShellCrossFade(
          ready: ready,
          bootChild: const Text('boot'),
          appChild: const Text('app'),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('UI-T4B-201 · 换壳点存在 150ms 渐隐过渡：AnimatedSwitcher + curveDefault，子树按 phase 区分 key', (
    tester,
  ) async {
    await _pump(tester, ready: false);

    final switcherFinder = find.byKey(const ValueKey('boot-shell-switcher'));
    expect(switcherFinder, findsOneWidget, reason: '换壳点应挂 boot-shell-switcher 可测 key');
    final switcher =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(
      switcher.duration,
      const Duration(milliseconds: 150),
      reason: '换壳过渡时长应为 150ms',
    );
    expect(switcher.switchInCurve, AppDesignSystem.curveDefault);
    expect(switcher.switchOutCurve, AppDesignSystem.curveDefault);

    // 初始态：boot 子树在场（KeyedSubtree 按 phase 携带区分 key）。
    expect(find.byKey(const ValueKey('boot-shell-boot')), findsOneWidget);
    expect(find.byKey(const ValueKey('boot-shell-app')), findsNothing);
  });

  testWidgets('UI-T4B-202 · 换壳时旧壳渐隐、新壳渐入：过渡中间帧两者并存，150ms 后仅剩真实工作区', (
    tester,
  ) async {
    await _pump(tester, ready: false);

    // 切换 phase（等价 _BootRootState 里 ready 置位后的重建）。
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: BootShellCrossFade(
            ready: true,
            bootChild: const Text('boot'),
            appChild: const Text('app'),
          ),
        ),
      ),
    );
    // 过渡中间帧：新旧子树并存（out 渐隐 + in 渐入）。
    await tester.pump();
    expect(find.text('boot'), findsOneWidget, reason: '过渡中间帧应保留旧壳（渐隐中）');
    expect(find.text('app'), findsOneWidget, reason: '过渡中间帧应出现新壳（渐入中）');

    // 过渡结束后：仅剩真实工作区。
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('boot'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('UI-T4B-203 · 系统减少动态效果：过渡时长 0ms，切换帧直出真实工作区（无中间帧、无动画回调）', (
    tester,
  ) async {
    await _pump(tester, ready: false, disableAnimations: true);

    // disableAnimations 下 AnimatedSwitcher duration 应为 0。
    final switcher =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(
      switcher.duration,
      Duration.zero,
      reason: 'reduced-motion 下换壳过渡应为 0ms',
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: BootShellCrossFade(
            ready: true,
            bootChild: const Text('boot'),
            appChild: const Text('app'),
          ),
        ),
      ),
    );
    // 单帧后直接是终态：无并存中间帧。
    await tester.pump();
    expect(find.text('boot'), findsNothing, reason: '0ms 过渡不应有旧壳中间帧');
    expect(find.text('app'), findsOneWidget);
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'reduced-motion 下换壳不应残留动画回调',
    );
  });
}
