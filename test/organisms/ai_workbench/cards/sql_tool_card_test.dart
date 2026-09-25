// T12 阶段二 SQL 工具卡组件测试（design-ai-workbench §8【三】/§11.1）。
//
// 覆盖：AC4.1 卡出现 / AC4.2 折叠展开 + NF1.3 懒构建守护 / AC4.3 复制一致
// / 写徽标判定（payload.isWrite，语义 = AiToolClassifier.isWriteSql）
// / 动作回调注入（执行/在经典中打开）/ 键盘（Space/Enter 折叠、Esc 回
// header）/ NF3.3 token 消费（暗亮主题卡描边 = ThemeColors.borderStrong，
// 断言用 token 引用非色值）/ header 高度 34 token / 正文上限 360 内部滚动。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/theme/design_system.dart';

Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 720,
}) => MaterialApp(
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
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? clipText;

  setUp(() {
    clipText = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          clipText = args?['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipText == null ? null : <String, dynamic>{'text': clipText};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  const testSql = 'SELECT id, name FROM users WHERE id > 10 ORDER BY id';

  Widget pumpCard({
    bool isWrite = false,
    void Function(String sql)? onExecute,
    void Function(String sql)? onOpenInClassic,
  }) => SqlToolCard(
    sql: testSql,
    statementType: 'SELECT',
    isWrite: isWrite,
    onExecute: onExecute,
    onOpenInClassic: onOpenInClassic,
  );

  group('AC4.1 卡出现 + header 结构', () {
    testWidgets('header 34 恒显（token 引用断言）+ 标题/类型徽标', (tester) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      expect(find.byType(SqlToolCard), findsOneWidget);
      expect(find.text(l10n.workbenchSqlCardTitle), findsOneWidget);
      expect(find.text(l10n.workbenchSqlTypeBadge('SELECT')), findsOneWidget);

      // header 高度 = toolCardHeaderHeight token（§8【三】header 34）。
      final header = tester.widget<SizedBox>(find.byKey(SqlToolCard.headerKey));
      expect(header.height, AppDesignSystem.toolCardHeaderHeight);
    });

    testWidgets('写徽标判定：isWrite=true 出现、false 不出现（AC4 写徽标面）', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(pumpCard(isWrite: true)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(SqlToolCard.writeBadgeKey),
        findsOneWidget,
        reason: '写 SQL 必须出现「危险」徽标',
      );
      expect(find.text(AppLocalizationsEn().workbenchSqlWriteBadge), findsOneWidget);

      await tester.pumpWidget(_wrap(pumpCard(isWrite: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.writeBadgeKey), findsNothing);
    });
  });

  group('AC4.2 折叠 + NF1.3 懒构建守护', () {
    testWidgets('折叠态正文不构建；点击 header 展开再折叠', (tester) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      // NF1.3：折叠态 content `findsNothing`（懒构建写死，禁改预构建）。
      expect(find.byKey(SqlToolCard.contentKey), findsNothing);
      expect(find.byType(SelectableText), findsNothing);

      await tester.tap(find.byKey(SqlToolCard.titleTapKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsOneWidget);
      expect(find.text(testSql), findsOneWidget);

      await tester.tap(find.byKey(SqlToolCard.titleTapKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsNothing);
    });

    testWidgets('正文块上限 360 内部滚动不截断（长 SQL）', (tester) async {
      final longSql = List.generate(80, (i) => '-- line $i').join('\n');
      await tester.pumpWidget(
        _wrap(
          SqlToolCard(sql: longSql, statementType: 'SELECT', isWrite: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SqlToolCard.titleTapKey));
      await tester.pumpAndSettle();

      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(SqlToolCard.contentKey),
      );
      expect(scroll.scrollDirection, Axis.vertical);

      final constrained = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.byKey(SqlToolCard.contentKey),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(
        constrained.constraints.maxHeight,
        AppDesignSystem.toolCardContentMaxHeight,
        reason: '正文块高度上限消费 toolCardContentMaxHeight token',
      );
    });
  });

  group('AC4.3 复制一致 + 动作注入', () {
    testWidgets('复制按钮 → 剪贴板内容 == 卡内 SQL 全文', (tester) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SqlToolCard.copyButtonKey));
      await tester.pump(); // 让 Clipboard.setData + setState 完成
      final data = await Clipboard.getData('text/plain');
      expect(data?.text, testSql, reason: 'AC4.3 复制内容一致');
      expect(find.text(AppLocalizationsEn().messageCopied), findsOneWidget);
      // 推进 2s 让复制反馈复位定时器触发，避免测试结束 pending timer 断言。
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(AppLocalizationsEn().messageCopied), findsNothing);
    });

    testWidgets('执行/在经典中打开回调注入（携带卡内 SQL）', (tester) async {
      String? executedSql;
      String? openedSql;
      await tester.pumpWidget(
        _wrap(
          pumpCard(
            onExecute: (sql) => executedSql = sql,
            onOpenInClassic: (sql) => openedSql = sql,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pump();
      expect(executedSql, testSql);

      await tester.tap(find.byKey(SqlToolCard.openInClassicButtonKey));
      await tester.pump();
      expect(openedSql, testSql);
    });

    testWidgets('回调未注入时按钮照常渲染不禁用（接口预留，T13 接线）', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      expect(find.byKey(SqlToolCard.executeButtonKey), findsOneWidget);
      expect(find.byKey(SqlToolCard.openInClassicButtonKey), findsOneWidget);
      // 未接线时点击不抛错（无假实现、无禁用态写死）。
      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pump();
    });
  });

  group('键盘（§8【三】焦点序/折叠/Esc）', () {
    testWidgets('Space/Enter 在 header 上折叠展开（与点击同效）', (tester) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      // 点击 header：展开 + 焦点落 header。
      await tester.tap(find.byKey(SqlToolCard.titleTapKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsOneWidget);
    });

    testWidgets('动作钮持焦点时 Space 不触发 header 折叠（Esc 回 header）', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SqlToolCard.titleTapKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsOneWidget);

      // Tab 进入动作钮（header → copy → execute）。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Space 落在动作钮上：不冒泡触发 header 折叠。
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        find.byKey(SqlToolCard.contentKey),
        findsOneWidget,
        reason: '动作钮上的 Space 不得折叠卡（header 只在自身持焦点时响应）',
      );

      // Esc：从动作钮退回 header；随后 Space 可折叠（证明焦点回到 header）。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsNothing);
    });

    testWidgets('content 滚动区 Esc 回 header', (tester) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SqlToolCard.titleTapKey));
      await tester.pumpAndSettle();

      // 依次穿过 header → copy → execute → openInClassic → content。
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // 焦点回 header 的行为证明：Space 能折叠。
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(SqlToolCard.contentKey), findsNothing);
    });
  });

  group('NF3.3 token 消费（暗亮主题卡描边可构建，断言用 token 引用）', () {
    testWidgets('暗/亮主题卡描边 = ThemeColors.borderStrong（1px）', (
      tester,
    ) async {
      Future<Color> cardBorderColor(Brightness brightness) async {
        await tester.pumpWidget(
          _wrap(pumpCard(), brightness: brightness),
        );
        await tester.pumpAndSettle();
        final ctx = tester.element(find.byType(SqlToolCard));
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(SqlToolCard),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        return border.top.color;
      }

      final darkColor = await cardBorderColor(Brightness.dark);
      final lightColor = await cardBorderColor(Brightness.light);

      // 分别断言（token 引用，非色值字面量）：与当前主题 borderStrong 一致。
      await tester.pumpWidget(_wrap(pumpCard(), brightness: Brightness.dark));
      await tester.pumpAndSettle();
      var ctx = tester.element(find.byType(SqlToolCard));
      expect(darkColor, ThemeColors(ctx).borderStrong);

      await tester.pumpWidget(_wrap(pumpCard(), brightness: Brightness.light));
      await tester.pumpAndSettle();
      ctx = tester.element(find.byType(SqlToolCard));
      expect(lightColor, ThemeColors(ctx).borderStrong);

      // 暗亮分发确实不同（证明走了 _isDark 分支）。
      expect(darkColor, isNot(lightColor));
    });

    testWidgets('header 聚焦时描边 1.5px accentBlue（无发光无位移）', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(pumpCard()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SqlToolCard.titleTapKey));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(SqlToolCard));
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SqlToolCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, ThemeColors(ctx).accentBlue);
      expect(decoration.boxShadow, isNull, reason: '无发光');
    });
  });
}
