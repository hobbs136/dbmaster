// T26 AgentSuggestionCard 组件测试（ui 规格 design-ai-agent-ui.md §4.2 五条
// 验收 + §4.1 结构 / 区隔四件套 / 三态）。
//
// 覆盖：§4.2-2 chip 恒显于决策前（决策后 findsNothing）+ 无 chevron /
// §4.2-3 键盘序（Tab 进卡后 [忽略] → [应用]，Enter 激活）/ §4.2-4 卡总高
// 几何探针 / §4.2-5 卡框描边色与圆角 = 同一 borderStrong / radiusMd +
// 区隔四件套（accentBlue 色条 / lightbulb / 「未执行」chip / 「应用」动词）/
// 三态徽标（未应用 / 已应用 / 已忽略）/ 正文两形态（SQL code 块 mono 11
// maxLines 3 / 定位目标 12px）/ 动作回调仅未决可发。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_suggestion_card.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/theme/design_system.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      locale: const Locale('en'),
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
            constraints: const BoxConstraints(maxWidth: 420),
            child: child,
          ),
        ),
      ),
    );

const String testSql =
    'SELECT o.id, o.total FROM orders o WHERE o.total > 1000';

const String longSql =
    'SELECT a very long column list that will certainly wrap onto multiple '
    'lines even in a wide card, FROM a_table WHERE x = 1 AND y = 2 AND z = 3';

/// 泵一张卡：回调记账（applied/dismissed 由宿主重建驱动，测三态时手工换
/// 传入参数重建）。
Future<(List<String>, List<String>)> _pumpCard(
  WidgetTester tester, {
  String action = 'open_in_classic',
  Map<String, dynamic> payload = const <String, dynamic>{'sql': testSql},
  bool applied = false,
  bool dismissed = false,
  Brightness brightness = Brightness.light,
}) async {
  final applies = <String>[];
  final dismisses = <String>[];
  await tester.pumpWidget(
    _wrap(
      AgentSuggestionCard(
        action: action,
        payload: payload,
        applied: applied,
        dismissed: dismissed,
        onApply: () => applies.add('apply'),
        onDismiss: () => dismisses.add('dismiss'),
      ),
      brightness: brightness,
    ),
  );
  await tester.pumpAndSettle();
  return (applies, dismisses);
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

/// 卡外框 Container 的 BoxDecoration（§4.2-5 断言用）。
BoxDecoration? _cardDecoration(WidgetTester tester) {
  final containers = tester.widgetList<Container>(
    find.descendant(
      of: find.byType(AgentSuggestionCard),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    ),
  );
  for (final Container c in containers) {
    final BoxDecoration d = c.decoration! as BoxDecoration;
    if (d.border is Border) return d;
  }
  return null;
}

void main() {
  final l10n = AppLocalizationsEn();

  group('§4.1 区隔四件套 + 未应用默认态', () {
    testWidgets(
      'lightbulb 图标 + 「建议 · Open in Classic」标题 + 「未执行」chip + 「应用」动词',
      (tester) async {
        await _pumpCard(tester);

        expect(
          find.byIcon(LucideIcons.lightbulb),
          findsOneWidget,
          reason: '四件套②：lightbulb（非数据库/结果类图标）',
        );
        expect(
          find.text(l10n.agentSuggestTitle(l10n.workbenchActionOpenInClassic)),
          findsOneWidget,
          reason: '标题 = 建议 · {动作名}（open_in_classic 复用 M1 动作名）',
        );
        expect(
          find.text(l10n.agentSuggestBadgeNotApplied),
          findsOneWidget,
          reason: '四件套③：「未执行」chip 恒显（决策前）',
        );
        expect(
          find.byTooltip(l10n.agentSuggestNotAppliedHint),
          findsOneWidget,
          reason: 'chip tooltip = 「应用前不会产生任何副作用」',
        );
        expect(
          find.text(l10n.agentSuggestApply),
          findsOneWidget,
          reason: '四件套④：动词 = 「应用」（非「执行」）',
        );
        expect(find.text(l10n.agentSuggestDismiss), findsOneWidget);
        expect(
          find.byIcon(LucideIcons.chevronDown),
          findsNothing,
          reason: '无 chevron（建议卡不展开，§4.1）',
        );
        expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
      },
    );

    testWidgets('focus_sidebar 动作名 + 定位目标正文（database · table）', (tester) async {
      await _pumpCard(
        tester,
        action: 'focus_sidebar',
        payload: const <String, dynamic>{'database': 'db1', 'table': 'users'},
      );

      expect(
        find.text(l10n.agentSuggestTitle(l10n.agentSuggestFocusSidebar)),
        findsOneWidget,
      );
      expect(
        find.text('db1 · users'),
        findsOneWidget,
        reason: '定位目标形态：12px 文本（数据拼接，非 l10n）',
      );
      expect(
        find.byType(SelectableText),
        findsNothing,
        reason: '定位目标不走 SQL code 块形态',
      );
    });

    testWidgets('SQL 形态正文：SelectableText（maxLines 3）+ tooltip 全文', (
      tester,
    ) async {
      await _pumpCard(tester, payload: const <String, dynamic>{'sql': longSql});

      final SelectableText body = tester.widget<SelectableText>(
        find.descendant(
          of: find.byKey(AgentSuggestionCard.bodyKey),
          matching: find.byType(SelectableText),
        ),
      );
      expect(body.data, longSql);
      expect(body.maxLines, 3, reason: '正文 maxLines 3（§4.1）');
      expect(
        find.byTooltip(longSql),
        findsOneWidget,
        reason: 'tooltip 承载全文（§0.4）',
      );
    });

    testWidgets('§4.2-5 卡框描边色与圆角 = 同一 borderStrong / radiusMd', (tester) async {
      await _pumpCard(tester);

      final BoxDecoration? decoration = _cardDecoration(tester);
      expect(decoration, isNotNull);
      final BuildContext ctx = tester.element(find.byType(AgentSuggestionCard));
      expect(
        (decoration!.border! as Border).top.color,
        ThemeColors(ctx).borderStrong,
        reason: '与同流卡同一描边 token',
      );
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AppDesignSystem.radiusMd),
        reason: '与同流卡同一圆角 token',
      );
    });
  });

  group('§4.2 键盘与几何', () {
    testWidgets('§4.2-3 Tab 进卡后 [忽略] → [应用]；Enter 激活应用；无 chevron', (
      tester,
    ) async {
      final (applies, _) = await _pumpCard(tester);

      expect(primaryFocusWithin(AgentSuggestionCard.applyButtonKey), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentSuggestionCard.dismissButtonKey),
        isTrue,
        reason: 'Tab#1 = [忽略]（键盘序与视觉序一致）',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentSuggestionCard.applyButtonKey),
        isTrue,
        reason: 'Tab#2 = [应用]',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(applies, hasLength(1), reason: 'Enter 激活主动作');
    });

    testWidgets(
      '§4.2-4 卡总高 ≤ 34 + 10×2 + 3 行正文 + 32 + 描边 2（单行 SQL + 码块 chrome）',
      (tester) async {
        await _pumpCard(tester);

        final Size size = tester.getSize(find.byType(AgentSuggestionCard));
        // 预算合成：34 header + 10 内容顶 + 3×(11×1.4) 三行正文 + 32 动作 +
        // 10 内容底 + 2 描边 = 134.2；加 §0.1 锁定的码块内边距 space2×2 = 16
        // （SQL 形态的码块 chrome，正文预算内不可省）。
        const double bound = 34 + 10 + 3 * (11 * 1.4) + 32 + 10 + 2 + 16;
        expect(
          size.height,
          lessThanOrEqualTo(bound),
          reason: '几何探针：单行 SQL 未决卡不超预算',
        );
      },
    );
  });

  group('三态（§4.1 状态行）', () {
    testWidgets('未应用：chip「未执行」+ 动作行在；点击各回调恰一次', (tester) async {
      final (applies, dismisses) = await _pumpCard(tester);

      await tester.tap(find.byKey(AgentSuggestionCard.applyButtonKey));
      await tester.tap(find.byKey(AgentSuggestionCard.dismissButtonKey));
      await tester.pumpAndSettle();

      expect(applies, hasLength(1));
      expect(dismisses, hasLength(1));
    });

    testWidgets('已应用：chip「已应用」+ circleCheck success；动作行消失；「未执行」findsNothing', (
      tester,
    ) async {
      await _pumpCard(tester, applied: true);

      expect(find.text(l10n.agentSuggestBadgeApplied), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
      expect(
        find.text(l10n.agentSuggestBadgeNotApplied),
        findsNothing,
        reason: '§4.2-2：决策后「未执行」findsNothing',
      );
      expect(find.text(l10n.agentSuggestApply), findsNothing, reason: '动作行消失');
      expect(find.text(l10n.agentSuggestDismiss), findsNothing);
    });

    testWidgets('已忽略：chip「已忽略」+ ban textMuted；动作行消失；正文降为 textMuted', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        action: 'focus_sidebar',
        payload: const <String, dynamic>{'database': 'db1', 'table': 'users'},
        dismissed: true,
      );

      expect(find.text(l10n.agentSuggestBadgeDismissed), findsOneWidget);
      expect(find.byIcon(LucideIcons.ban), findsOneWidget);
      expect(find.text(l10n.agentSuggestBadgeNotApplied), findsNothing);
      expect(find.text(l10n.agentSuggestApply), findsNothing);

      final BuildContext ctx = tester.element(
        find.byKey(AgentSuggestionCard.bodyKey),
      );
      final Text body = tester.widget<Text>(
        find.byKey(AgentSuggestionCard.bodyKey),
      );
      expect(
        body.style?.color,
        ThemeColors(ctx).textMuted,
        reason: '已忽略正文降为 textMuted（§4.1 状态行）',
      );
    });

    testWidgets('亮暗主题均可构建（§10.2）', (tester) async {
      await _pumpCard(tester, brightness: Brightness.dark);
      expect(find.byType(AgentSuggestionCard), findsOneWidget);
      await _pumpCard(tester, brightness: Brightness.light);
      expect(find.byType(AgentSuggestionCard), findsOneWidget);
    });
  });
}
