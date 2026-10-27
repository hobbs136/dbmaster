// UI35-431~437 红测（v0.3.5 UI 批4 T9 = 生产高危分级拦截 + AI 备份）。
//
// 契约来源：B-07 冻结件（.specs/tasks-v3.5-ui.md §3-B07，逐字）——
// lib/organisms/dialogs/production_guard_dialog.dart 的 showProductionGuardDialog
// / ProductionGuardLevel 尚不存在。本文件按冻结签名直译验收条款：
//   编译红 = 申报形态（不写 lib/ stub、不发明注入契约），
//   由实现批实现后转绿；断言只盯行为/焦点/文本/返回值，不断言视觉细节。
//
// 不变量对照（B-07）：
//   L1 确认钮目标名完全匹配（trim+lowercase）前 opacity .45 且不可聚焦；
//   L1 输入框聚焦时 Enter 不提交；L2 免输入 + 初始焦点锁死 Cancel + Enter=取消；
//   Esc 任意位置取消返回 false + 关闭后焦点回触发点；
//   estimatedRows null → prodGuardUnknownRows（禁 0 冒充）；SQL 预览只读；
//   AI 备份 = onAiBackup 被调 + 返回 false + 弹窗关闭。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/dialogs/production_guard_dialog.dart';

void _setLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// 触发点桩：记录弹窗返回值与 AI 备份回调；FocusNode 用于焦点回归断言。
class _GuardHarness {
  bool aiBackupCalled = false;
  bool? guardResult;
  final FocusNode triggerFocusNode = FocusNode(debugLabel: 'ui35-trigger');

  void dispose() {
    triggerFocusNode.dispose();
  }
}

/// pump 触发点按钮并打开弹窗（每用例独立 harness；FocusNode 自动 addTearDown）。
Future<_GuardHarness> _pumpGuardDialog(
  WidgetTester tester, {
  required ProductionGuardLevel level,
  String sqlPreview = 'DROP TABLE orders',
  String targetObjectName = 'orders',
  int? estimatedRows,
  bool withAiBackup = true,
}) async {
  final harness = _GuardHarness();
  addTearDown(harness.dispose);
  _setLargeScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => TextButton(
          focusNode: harness.triggerFocusNode,
          onPressed: () {
            unawaited(
              showProductionGuardDialog(
                context,
                connectionId: 'conn-ui35',
                level: level,
                sqlPreview: sqlPreview,
                targetObjectName: targetObjectName,
                estimatedRows: estimatedRows,
                onAiBackup:
                    withAiBackup ? () => harness.aiBackupCalled = true : null,
              ).then((confirmed) => harness.guardResult = confirmed),
            );
          },
          child: const Text('UI35 Trigger'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('UI35 Trigger'));
  await tester.pumpAndSettle();
  return harness;
}

Finder _confirmLabel(AppLocalizations l10n) =>
    find.text(l10n.prodGuardConfirmDrop);

Finder _cancelLabel(AppLocalizations l10n) => find.text(l10n.commonCancel);

Finder _aiBackupLabel(AppLocalizations l10n) =>
    find.text(l10n.prodGuardAiBackup);

/// 目标名输入框：排除承载 SQL 预览文本的可编辑件（预览若以只读 TextField
/// 实现时不误选；预览为纯文本时天然唯一）。
Finder _nameFieldFinder(String sqlPreview) => find.byWidgetPredicate(
      (w) => w is TextField && (w.controller?.text ?? '') != sqlPreview,
    );

/// 取包裹 label 的最近 Focus 节点；label 找不到时返回 null（调用方先断言 label 存在）。
FocusNode? _focusNodeOf(Finder labelFinder) {
  final elements = labelFinder.evaluate();
  if (elements.isEmpty) return null;
  return Focus.maybeOf(elements.first);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('ProductionGuardDialog（B-07，UI35-431~437）', () {
    testWidgets(
      'UI35-431: L1 打开后确认钮不可聚焦；目标名 trim+lowercase 完全匹配后解锁可聚焦',
      (tester) async {
        const sqlPreview = 'DROP TABLE orders';
        await _pumpGuardDialog(
          tester,
          level: ProductionGuardLevel.l1Destructive,
          sqlPreview: sqlPreview,
          targetObjectName: 'orders',
        );

        // 锁定态：确认钮 Focus 节点不可聚焦（无节点包装 = 遍历不可达，同样满足）。
        final confirmNode = _focusNodeOf(_confirmLabel(l10n));
        if (confirmNode != null) {
          expect(
            confirmNode.canRequestFocus,
            isFalse,
            reason: '锁定态确认钮必须不可聚焦（canRequestFocus == false）',
          );
        }
        // 遍历不可达兜底：连按 Tab 扫过全部焦点节点，焦点不得落在确认钮上。
        for (var i = 0; i < 8; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        if (confirmNode != null) {
          expect(
            confirmNode.hasFocus,
            isFalse,
            reason: 'Tab 遍历 8 次不应落在锁定的确认钮上',
          );
        }

        // 未匹配前缀 → 仍锁定。
        await tester.enterText(_nameFieldFinder(sqlPreview), 'order');
        await tester.pump();
        final stillLocked = _focusNodeOf(_confirmLabel(l10n));
        if (stillLocked != null) {
          expect(
            stillLocked.canRequestFocus,
            isFalse,
            reason: '未完全匹配必须保持锁定',
          );
        }

        // 大小写 + 首尾空格变体完全匹配（targetObjectName='orders'）→ 解锁。
        await tester.enterText(_nameFieldFinder(sqlPreview), '  ORDERS ');
        await tester.pump();
        final unlockedNode = _focusNodeOf(_confirmLabel(l10n));
        if (unlockedNode == null) {
          fail('匹配后确认钮必须存在可聚焦的 Focus 节点');
        }
        expect(
          unlockedNode.canRequestFocus,
          isTrue,
          reason: '目标名完全匹配后确认钮解锁可聚焦',
        );
      },
    );

    testWidgets(
      'UI35-432: L1 输入框聚焦连按 Enter 不提交（弹窗仍开、Future 未完成）',
      (tester) async {
        const sqlPreview = 'DROP TABLE orders';
        final harness = await _pumpGuardDialog(
          tester,
          level: ProductionGuardLevel.l1Destructive,
          sqlPreview: sqlPreview,
          targetObjectName: 'orders',
        );

        await tester.tap(_nameFieldFinder(sqlPreview));
        await tester.pump();
        await tester.enterText(_nameFieldFinder(sqlPreview), 'not-matching');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          harness.guardResult,
          isNull,
          reason: 'L1 输入框聚焦时连按 Enter 不得提交（Future 未完成）',
        );
        expect(
          find.text(l10n.prodGuardTitleL1),
          findsOneWidget,
          reason: '弹窗仍开',
        );
      },
    );

    testWidgets(
      'UI35-433: L1 未匹配确认钮不可激活；匹配后确认返回 true',
      (tester) async {
        const sqlPreview = 'DROP TABLE orders';
        final harness = await _pumpGuardDialog(
          tester,
          level: ProductionGuardLevel.l1Destructive,
          sqlPreview: sqlPreview,
          targetObjectName: 'orders',
        );

        // 未匹配：点确认钮 → 不激活、弹窗仍开。
        await tester.tap(_confirmLabel(l10n));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          harness.guardResult,
          isNull,
          reason: '未匹配时确认钮不可激活（点按无效果）',
        );
        expect(find.text(l10n.prodGuardTitleL1), findsOneWidget);

        // 匹配后确认 → Future 完成 true + 弹窗关闭。
        await tester.enterText(_nameFieldFinder(sqlPreview), 'ORDERS');
        await tester.pump();
        await tester.tap(_confirmLabel(l10n));
        await tester.pumpAndSettle();
        expect(harness.guardResult, isTrue, reason: '匹配后确认返回 true');
        expect(find.text(l10n.prodGuardTitleL1), findsNothing, reason: '弹窗关闭');
      },
    );

    testWidgets(
      'UI35-434: estimatedRows null → prodGuardUnknownRows 且禁 0 冒充；SQL 预览只读',
      (tester) async {
        const sqlPreview = 'DROP TABLE orders';
        await _pumpGuardDialog(
          tester,
          level: ProductionGuardLevel.l1Destructive,
          sqlPreview: sqlPreview,
          targetObjectName: 'orders',
          estimatedRows: null,
        );

        expect(
          find.text(l10n.prodGuardUnknownRows),
          findsOneWidget,
          reason: '未知行数必须显示 prodGuardUnknownRows 专用文案',
        );
        expect(
          find.textContaining('0'),
          findsNothing,
          reason: 'estimatedRows null 时禁止用 0 冒充未知行数',
        );

        // SQL 预览可见。
        expect(find.text(sqlPreview), findsOneWidget, reason: 'SQL 预览展示');
        // 只读：若预览以可编辑件承载，必须 readOnly（纯文本承载则天然只读）。
        final editables =
            tester.widgetList<EditableText>(find.byType(EditableText));
        for (final editable in editables) {
          if (editable.controller.text == sqlPreview) {
            expect(
              editable.readOnly,
              isTrue,
              reason: 'SQL 预览必须只读',
            );
          }
        }
      },
    );

    testWidgets(
      'UI35-435: L2 免输入；初始焦点锁死 Cancel；Enter = 取消（返回 false）',
      (tester) async {
        final harness = await _pumpGuardDialog(
          tester,
          level: ProductionGuardLevel.l2UnboundedWrite,
          sqlPreview: 'DELETE FROM orders',
          targetObjectName: 'orders',
          estimatedRows: 12000,
        );

        // 初始焦点位置：Cancel 按钮持有焦点（确认钮可见但不聚焦由此得证）。
        final cancelNode = _focusNodeOf(_cancelLabel(l10n));
        if (cancelNode == null) {
          fail('L2 打开后必须能定位 Cancel 按钮的 Focus 节点');
        }
        expect(
          cancelNode.hasFocus,
          isTrue,
          reason: 'L2 打开时默认焦点锁死 [取消 (Esc)]',
        );

        // Enter 直接取消（焦点在 Cancel 上）。
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(harness.guardResult, isFalse, reason: 'L2 Enter = 取消，返回 false');
        expect(find.text(l10n.prodGuardTitleL2), findsNothing, reason: '弹窗关闭');
      },
    );

    testWidgets(
      'UI35-436: Esc 任意位置（含 L1 输入框聚焦）取消 → 返回 false + 焦点回触发点',
      (tester) async {
        const sqlPreview = 'DROP TABLE orders';
        final harness = await _pumpGuardDialog(
          tester,
          level: ProductionGuardLevel.l1Destructive,
          sqlPreview: sqlPreview,
          targetObjectName: 'orders',
        );

        // 从 L1 输入框聚焦位置触发 Esc（「任意位置取消」的最难分支）。
        await tester.tap(_nameFieldFinder(sqlPreview));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(harness.guardResult, isFalse, reason: 'Esc 取消必须返回 false（非 null）');
        expect(find.text(l10n.prodGuardTitleL1), findsNothing, reason: '弹窗关闭');
        expect(
          harness.triggerFocusNode.hasFocus,
          isTrue,
          reason: '关闭后焦点回触发点',
        );
      },
    );

    testWidgets(
      'UI35-437: AI 备份 → onAiBackup 被调、Future 完成 false、弹窗关闭',
      (tester) async {
        final harness = await _pumpGuardDialog(
          tester,
          level: ProductionGuardLevel.l1Destructive,
          sqlPreview: 'DROP TABLE orders',
          targetObjectName: 'orders',
          withAiBackup: true,
        );

        await tester.tap(_aiBackupLabel(l10n));
        await tester.pumpAndSettle();

        expect(harness.aiBackupCalled, isTrue, reason: 'AI 备份回调被调');
        expect(
          harness.guardResult,
          isFalse,
          reason: 'AI 分流 = 取消，弹窗 Future 独立完成 false',
        );
        expect(find.text(l10n.prodGuardTitleL1), findsNothing, reason: '弹窗关闭');
      },
    );
  });
}
