// T12 AgentConfirmCard 组件测试（ui 规格 design-ai-agent-ui.md §2.5 九条验收
// + §2.2/§2.4 结构与状态清单）。
//
// 覆盖：§2.5-1 决策前无 chevron 不可折叠 / §2.5-2 不可用+保守档同现（AC8.6）
// / §2.5-3 扫描形态行渲染条件 / §2.5-4 空值行不渲染 / §2.5-5 标签列 104
// （token 探针 + maxLines 2 结构断言，de locale 兜底）/ §2.5-6 键盘序
// （勾选行→取消→本次允许；Space 勾选；Enter 提交；Esc 交还上级）/
// §2.5-7 勾选翻转主动作返回值 / §2.5-8 停止翻转「已随运行取消」 vs 用户
// 「已取消」（rejected 双形态）/ 复制一致 + 结论行五态 + 暗亮主题可构建。
// （§2.5-9 未决自动滚入视口 + 轨迹卡强制展开为 T13 嵌块宿主职责，不在本
// 组件测试面。）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_confirm_card.dart';
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';
import 'package:dbmaster/theme/design_system.dart';

Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double width = 720,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness, useMaterial3: true),
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    ),
  ),
);

const testSql = 'SELECT o.id, o.total FROM orders o WHERE o.status = 1';

ReadImpactAnalysis impact({
  int? estimatedRows = 800000,
  bool fullScan = true,
  List<String> scannedTables = const ['orders', 'order_items'],
  String? indexSummary = 'orders: no index (ALL)',
  bool analysisUnavailable = false,
}) => ReadImpactAnalysis(
  estimatedRows: estimatedRows,
  fullScan: fullScan,
  scannedTables: scannedTables,
  indexSummary: indexSummary,
  analysisUnavailable: analysisUnavailable,
);

/// 可控宿主：持有 outcome 并可外部触发重建，模拟 T13 嵌块宿主「按消息结论
/// 重建确认卡」（§2.5-8 停止翻转用例的驱动器）。宿主重建不换
/// AgentConfirmCard 的树位/类型 → 卡内 State 存活（rejected 双形态记忆前提）。
class _OutcomeHolder {
  GateCardResult? outcome;
  StateSetter? _setState;

  void Function() get refresh =>
      () => _setState?.call(() {});
}

/// 泵一张交互卡：决策回调记账 + 宿主按决策更新 outcome（模拟 T13 接线）。
Future<(List<GateCardResult>, _OutcomeHolder)> _pumpInteractive(
  WidgetTester tester, {
  ReadImpactAnalysis? imp,
}) async {
  final decisions = <GateCardResult>[];
  final holder = _OutcomeHolder();
  await tester.pumpWidget(
    _wrap(
      StatefulBuilder(
        builder: (context, setState) {
          holder._setState = setState;
          return AgentConfirmCard(
            impact: imp ?? impact(),
            sql: testSql,
            outcome: holder.outcome,
            onDecision: (d) {
              decisions.add(d);
              holder.outcome = d;
              setState(() {});
            },
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (decisions, holder);
}

/// 断言主焦点当前落在 [key] 子树内。
bool primaryFocusWithin(Key key) {
  final focus = FocusManager.instance.primaryFocus;
  final ctx = focus?.context;
  if (ctx == null) return false;
  var within = false;
  ctx.visitAncestorElements((Element el) {
    if (el.widget.key == key) {
      within = true;
      return false;
    }
    return true;
  });
  return within;
}

void main() {
  group('§2.5-1 决策前无 chevron / 不可折叠 + header 结构', () {
    testWidgets('未决：无折叠开关、全内容恒在、header 34（token 探针）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      expect(find.text(l10n.agentConfirmReadTitle), findsOneWidget);
      expect(find.text(l10n.agentTrajectoryAwaiting), findsOneWidget);
      // §2.5-1：决策前无任何折叠开关（本卡无折叠语义）。
      expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
      expect(find.byIcon(LucideIcons.chevronUp), findsNothing);
      // 未决全内容齐备。
      expect(find.byKey(AgentConfirmCard.contentKey), findsOneWidget);
      expect(find.byKey(AgentConfirmCard.sessionCheckboxKey), findsOneWidget);
      expect(find.byKey(AgentConfirmCard.cancelButtonKey), findsOneWidget);
      expect(find.byKey(AgentConfirmCard.allowButtonKey), findsOneWidget);
      // header 高 34 恒显（沿 M1 token 探针口径）。
      final header = tester.widget<SizedBox>(
        find.byKey(AgentConfirmCard.headerKey),
      );
      expect(header.height, AppDesignSystem.toolCardHeaderHeight);
    });

    testWidgets('点击 header 不折叠；决策后收为 header+结论行、chip 消失', (tester) async {
      final holder = _OutcomeHolder();
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              holder._setState = setState;
              return AgentConfirmCard(
                impact: impact(),
                sql: testSql,
                outcome: holder.outcome,
                onDecision: (d) => holder.outcome = d,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentConfirmCard.headerKey));
      await tester.pumpAndSettle();
      // 阻塞决策卡：点击 header 不得折叠内容。
      expect(find.byKey(AgentConfirmCard.contentKey), findsOneWidget);

      holder.outcome = GateCardResult.approved;
      holder.refresh();
      await tester.pumpAndSettle();
      // 决策后收为 header + 结论行（§2.4），未决 chip 消失。
      expect(find.byKey(AgentConfirmCard.contentKey), findsNothing);
      expect(find.byKey(AgentConfirmCard.conclusionKey), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().agentTrajectoryAwaiting),
        findsNothing,
      );
    });
  });

  group('§2.5-2/3/4 影响字段行渲染条件（AC8.4/AC8.6 视觉可证）', () {
    testWidgets('§2.5-2 estimatedRows null + analysisUnavailable → 双文案同现', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(
              estimatedRows: null,
              fullScan: false,
              scannedTables: const [],
              indexSummary: null,
              analysisUnavailable: true,
            ),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizationsEn();
      expect(find.text(l10n.agentConfirmValueUnavailable), findsOneWidget);
      expect(find.text(l10n.agentConfirmAnalysisUnavailable), findsOneWidget);
      // 保守档行同格承载 warning 标记图标。
      expect(find.byIcon(LucideIcons.triangleAlert), findsWidgets);
    });

    testWidgets('§2.5-3 fullScan true → 扫描形态行 + warning 图标；false → 行缺', (
      tester,
    ) async {
      final l10n = AppLocalizationsEn();
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(fullScan: true),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmFullScanNoIndex), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsWidgets);

      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(fullScan: false, analysisUnavailable: false),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmScanShape), findsNothing);
      expect(find.text(l10n.agentConfirmFullScanNoIndex), findsNothing);
    });

    testWidgets('§2.5-4 indexSummary null / scannedTables 空 → 对应行不渲染', (
      tester,
    ) async {
      final l10n = AppLocalizationsEn();
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(
              indexSummary: null,
              scannedTables: const [],
              fullScan: false,
            ),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmIndexRow), findsNothing);
      expect(find.text(l10n.agentConfirmTablesRow), findsNothing);

      // 有值时渲染且扫描表按 ` · ` 连接。
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(fullScan: false),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmIndexRow), findsOneWidget);
      expect(find.text('orders · order_items'), findsOneWidget);
    });

    testWidgets('估算行数千分位格式化（800,000；§0.6 数字 mono 等宽）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizationsEn();
      expect(
        find.text(l10n.agentConfirmEstimatedRows('800,000')),
        findsOneWidget,
      );
    });
  });

  group('§2.5-5 标签列 104 / 德语标签不截断', () {
    testWidgets('标签列宽 = agentImpactLabelWidth token + maxLines 2 结构断言', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      final labelText = tester.widget<Text>(
        find.text(l10n.agentConfirmScanRows),
      );
      expect(labelText.maxLines, 2, reason: '标签允许 2 行换行、不截断（§0.6）');

      final labelBox = tester.getSize(find.text(l10n.agentConfirmScanRows));
      expect(
        labelBox.width,
        AppDesignSystem.agentImpactLabelWidth,
        reason: '标签列消费 agentImpactLabelWidth(104) token',
      );
    });

    testWidgets('de locale：结构不变、标签 maxLines 2（untranslated 回退英文）', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
          locale: const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();
      final cardCtx = tester.element(find.byType(AgentConfirmCard));
      final l10n = AppLocalizations.of(cardCtx)!;
      final labelText = tester.widget<Text>(
        find.text(l10n.agentConfirmScanRows),
      );
      expect(labelText.maxLines, 2);
      expect(labelText.overflow, isNull, reason: '标签不设 ellipsis（不截断）');
    });
  });

  group('§2.5-6/7 决策交互与键盘序', () {
    testWidgets('§2.5-7 未勾选主动作 → approved；新卡勾选后 → approvedForSession', (
      tester,
    ) async {
      // 阶段一：未勾选 → approved（决策后卡翻转，故第二阶段需新卡）。
      final (decisions, _) = await _pumpInteractive(tester);
      await tester.tap(find.byKey(AgentConfirmCard.allowButtonKey));
      await tester.pump();
      expect(decisions, [GateCardResult.approved]);
      expect(
        find.text(AppLocalizationsEn().agentConfirmResultAllowedOnce),
        findsOneWidget,
      );

      // 阶段二：勾选会话放行 → 主动作返回 approvedForSession。
      final (decisions2, _) = await _pumpInteractive(tester);
      await tester.tap(find.byKey(AgentConfirmCard.sessionCheckboxKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentConfirmCard.allowButtonKey));
      await tester.pump();
      expect(decisions2, [GateCardResult.approvedForSession]);
      expect(
        find.text(AppLocalizationsEn().agentConfirmResultAllowedSession),
        findsOneWidget,
      );
    });

    testWidgets('取消 → rejected（回调断言）', (tester) async {
      final (decisions, _) = await _pumpInteractive(tester);
      await tester.tap(find.byKey(AgentConfirmCard.cancelButtonKey));
      await tester.pump();
      expect(decisions, [GateCardResult.rejected]);
      expect(
        find.text(AppLocalizationsEn().agentConfirmResultCanceled),
        findsOneWidget,
      );
    });

    testWidgets('§2.5-6 Tab 序 = 勾选行 → 取消 → 本次允许；Space 切勾选', (tester) async {
      await _pumpInteractive(tester);
      final checkboxKey = AgentConfirmCard.sessionCheckboxKey;
      final cancelKey = AgentConfirmCard.cancelButtonKey;
      final allowKey = AgentConfirmCard.allowButtonKey;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(checkboxKey), isTrue, reason: 'Tab#1 落勾选行');
      // Space 切换勾选（行为由 Enter 提交后的结论证明：勾选态 →
      // approvedForSession）。
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(cancelKey), isTrue, reason: 'Tab#2 落取消');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(allowKey), isTrue, reason: 'Tab#3 落本次允许');

      // Enter 提交（主动作上 Enter 同点击）；勾选态 → approvedForSession。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byKey(AgentConfirmCard.conclusionKey), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().agentConfirmResultAllowedSession),
        findsOneWidget,
      );
    });

    testWidgets('§2.5-6 Esc：勾选行/动作钮焦点交还上级（离开卡内控件）', (tester) async {
      await _pumpInteractive(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(AgentConfirmCard.sessionCheckboxKey), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentConfirmCard.sessionCheckboxKey),
        isFalse,
        reason: 'Esc 后焦点不得停留在卡内控件（输入区重聚焦由宿主接线）',
      );
    });
  });

  group('§2.5-8 rejected 双形态（已取消 vs 已随运行取消）', () {
    testWidgets('停止翻转（未交互置 rejected）→ 已随运行取消；用户点取消 → 已取消', (tester) async {
      final l10n = AppLocalizationsEn();
      final holder = _OutcomeHolder();
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              holder._setState = setState;
              return AgentConfirmCard(
                impact: impact(),
                sql: testSql,
                outcome: holder.outcome,
                onDecision: (d) {
                  holder.outcome = d;
                  setState(() {});
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 场景一：停止翻转——宿主未经用户交互把 outcome 置 rejected。
      holder.outcome = GateCardResult.rejected;
      holder.refresh();
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmResultCanceledByRun), findsOneWidget);
      expect(find.text(l10n.agentConfirmResultCanceled), findsNothing);
      expect(find.byIcon(LucideIcons.square), findsOneWidget);

      // 场景二：复位未决后用户点取消（同卡内 State 存活，记忆被点击登记）。
      holder.outcome = null;
      holder.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentConfirmCard.cancelButtonKey));
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmResultCanceled), findsOneWidget);
      expect(find.byIcon(LucideIcons.ban), findsOneWidget);
    });

    testWidgets('五态结论行：approved / approvedForSession 文案、图标与 tooltip', (
      tester,
    ) async {
      final l10n = AppLocalizationsEn();
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: testSql,
            outcome: GateCardResult.approved,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmResultAllowedOnce), findsOneWidget);
      expect(find.byIcon(LucideIcons.shieldCheck), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: testSql,
            outcome: GateCardResult.approvedForSession,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentConfirmResultAllowedSession), findsOneWidget);
      expect(find.byIcon(LucideIcons.shieldCheck), findsOneWidget);
      // 会话放行结论的 tooltip = 作用域说明（§2.4）。
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, l10n.agentConfirmAllowSessionHint);
    });
  });

  group('SQL 块 + 复制 + 主题可构建', () {
    testWidgets('SQL 全文块可选中 + 复制内容一致（复制语汇沿 M1）', (tester) async {
      String? clipText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          clipText = args?['text'] as String?;
          return null;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: testSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text(testSql), findsOneWidget);

      await tester.tap(find.byKey(AgentConfirmCard.copyButtonKey));
      await tester.pump();
      expect(clipText, testSql);
      expect(find.text(AppLocalizationsEn().messageCopied), findsOneWidget);
      // 推进 2s 让复制反馈复位，避免测试结束 pending timer 断言。
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('暗/亮主题均可构建（异常为空；不断言具体色值）', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _wrap(
            AgentConfirmCard(
              impact: impact(),
              sql: testSql,
              outcome: null,
              onDecision: (_) {},
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(AgentConfirmCard.headerKey), findsOneWidget);
      }
    });

    testWidgets('卡体上限 360 内部滚动（长 SQL 不截断）', (tester) async {
      final longSql = List.generate(80, (i) => '-- line $i').join('\n');
      await tester.pumpWidget(
        _wrap(
          AgentConfirmCard(
            impact: impact(),
            sql: longSql,
            outcome: null,
            onDecision: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(AgentConfirmCard.contentKey),
      );
      expect(scroll.scrollDirection, Axis.vertical);
      final constrained = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.byKey(AgentConfirmCard.contentKey),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(
        constrained.constraints.maxHeight,
        AppDesignSystem.toolCardContentMaxHeight,
      );
    });
  });
}
