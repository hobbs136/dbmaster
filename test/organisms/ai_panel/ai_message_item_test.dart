import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildMessageItem({
  required AiMessage message,
  Function(String sql, bool isDangerous)? onExecuteSql,
  Function(String sql)? onOpenInNewQuery,
  Function(String messageId)? onToggleBookmark,
  Function(String messageId, String content)? onBranchFromMessage,
  VoidCallback? onRegenerate,
  VoidCallback? onContinue,
  double? readableMaxWidth,
  double? hostWidth,
}) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: AppProvider(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          // AI-CW cap 用例：收窄宿主（LayoutBuilder 取 SizedBox 宽求 0.82 比例）；
          // ListView 提供无界主轴（同生产聊天列表），长文本气泡不触发高度 overflow。
          width: hostWidth,
          child: ListView(
            children: [
              AiMessageItem(
                message: message,
                onExecuteSql: onExecuteSql ?? (a, b) {},
                onOpenInNewQuery: onOpenInNewQuery ?? (_) {},
                onToggleBookmark: onToggleBookmark ?? (_) {},
                onBranchFromMessage: onBranchFromMessage ?? (a, b) {},
                onRegenerate: onRegenerate,
                onContinue: onContinue,
                readableMaxWidth: readableMaxWidth,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

AiMessage _message({
  required String id,
  required bool isUser,
  required String content,
  AiMessageStatus status = AiMessageStatus.sent,
  bool isDangerous = false,
}) {
  return AiMessage(
    id: id,
    isUser: isUser,
    content: content,
    timestamp: DateTime.now(),
    status: status,
    isDangerous: isDangerous,
  );
}

void main() {
  group('AiMessageItem', () {
    testWidgets('renders user message with person avatar', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(id: 'm1', isUser: true, content: 'Hello AI'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello AI'), findsOneWidget);
      expect(find.byIcon(LucideIcons.user), findsOneWidget);
    });

    testWidgets('renders AI message with robot avatar', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(id: 'm2', isUser: false, content: 'Hello user'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello user'), findsOneWidget);
      expect(find.byIcon(LucideIcons.bot), findsOneWidget);
    });

    testWidgets('shows completed status indicator', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm3',
            isUser: false,
            content: 'Done',
            status: AiMessageStatus.completed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.circleCheckBig), findsOneWidget);
    });

    testWidgets('shows failed status indicator', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm4',
            isUser: false,
            content: 'Oops',
            status: AiMessageStatus.failed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.circleAlert), findsWidgets);
    });

    testWidgets('shows regenerate button and invokes callback', (tester) async {
      var regenerated = false;
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(id: 'm5', isUser: false, content: 'Need retry'),
          onRegenerate: () => regenerated = true,
        ),
      );
      await tester.pumpAndSettle();

      final regenerateButton = find.widgetWithText(InkWell, 'Regenerate');
      expect(regenerateButton, findsOneWidget);

      await tester.tap(regenerateButton);
      await tester.pumpAndSettle();

      expect(regenerated, isTrue);
    });

    testWidgets('shows continue button for interrupted message', (
      tester,
    ) async {
      var continued = false;
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm6',
            isUser: false,
            content: 'Interrupted',
            status: AiMessageStatus.interrupted,
          ),
          onContinue: () => continued = true,
        ),
      );
      await tester.pumpAndSettle();

      final continueButton = find.widgetWithText(InkWell, 'Continue');
      expect(continueButton, findsOneWidget);

      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(continued, isTrue);
    });

    testWidgets('shows danger badge for dangerous operation', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm7',
            isUser: false,
            content: 'DROP TABLE users;',
            isDangerous: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    });
  });

  // AI-CW 批（2026-09-29）：纯文本气泡可读宽内层封顶。min 次序 = 先 0.82
  // 比例后 cap——默认参数（null）不封顶（经典面板路径），窄宿主比例照常。
  group('AiMessageItem readableMaxWidth 气泡可读宽内层封顶（AI-CW）', () {
    /// 长单段文本（Ahem 测试字体下定宽换行，气泡实得 = 约束宽）。
    AiMessage longTextMessage(String id) => _message(
      id: id,
      isUser: false,
      content: List<String>.filled(200, 'lorem ipsum dolor sit amet').join(' '),
    );

    /// 定位气泡 ConstrainedBox（maxWidth 唯一匹配 → 量实得渲染宽；
    /// 容差 0.5 吸收 0.82 比例的浮点误差，如 300×0.82≈246.00000000000003）。
    Finder bubbleAtMaxWidth(double maxWidth) => find.descendant(
      of: find.byType(AiMessageItem),
      matching: find.byWidgetPredicate(
        (w) =>
            w is ConstrainedBox &&
            (w.constraints.maxWidth - maxWidth).abs() < 0.5,
      ),
    );

    testWidgets('默认不传参：800 宽宿主气泡 = 0.82×800=656（经典路径不封顶）', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(message: longTextMessage('cw1')),
      );
      await tester.pumpAndSettle();

      final bubble = bubbleAtMaxWidth(656.0);
      expect(bubble, findsOneWidget);
      expect(
        tester.getSize(bubble).width,
        closeTo(656, 1),
        reason: '无 cap 时气泡实得 656（+0/−1）——readableMaxWidth 缺省零行为变化',
      );
    });

    testWidgets('传参 640：800 宽宿主气泡封顶 640（min 次序：0.82×800 > cap）', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: longTextMessage('cw2'),
          readableMaxWidth: 640.0,
        ),
      );
      await tester.pumpAndSettle();

      final bubble = bubbleAtMaxWidth(640.0);
      expect(bubble, findsOneWidget);
      expect(
        tester.getSize(bubble).width,
        closeTo(640, 1),
        reason: 'cap 生效：min(656, 640) = 640（次序写反成 max 时本例得 656 必失败）',
      );
    });

    testWidgets('窄域守卫：300 宽宿主默认气泡 = 0.82×300=246（cap 若误加必失败）', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(message: longTextMessage('cw3'), hostWidth: 300),
      );
      await tester.pumpAndSettle();

      final bubble = bubbleAtMaxWidth(246.0);
      expect(bubble, findsOneWidget);
      expect(
        tester.getSize(bubble).width,
        closeTo(246, 1),
        reason: '窄域 0.82 比例照常（246 < 640）；若实现把 cap 误加成直接钳宽则得 300 必失败',
      );
    });
  });
}
