import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_panel/ai_table_mention_menu.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildInputArea({
  required bool isSending,
  required ValueChanged<String> onSend,
  required VoidCallback onStop,
  VoidCallback? onShowApiSettings,
  required ValueChanged<String> onSlashCommand,
  bool enableTableMention = false,
  Future<List<String>> Function(
    String connectionId,
    String databaseName,
    String prefix,
  )?
  onTableMentionQuery,
}) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: AppProvider(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: AiInputArea(
            isSending: isSending,
            onSend: onSend,
            onStop: onStop,
            onShowApiSettings: onShowApiSettings ?? () {},
            onSlashCommand: onSlashCommand,
            enableTableMention: enableTableMention,
            onTableMentionQuery: onTableMentionQuery,
          ),
        ),
      ),
    ),
  );
}

/// 推进假时钟越过 300ms 防抖窗口，并多 pump 一帧等候选 Future 续体落地。
Future<void> _pumpPastMentionDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  group('AiInputArea', () {
    testWidgets('renders input field and send button', (tester) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsOneWidget);
    });

    testWidgets('typing text enables send button', (tester) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // 初始状态发送按钮应禁用（颜色较淡）
      await tester.enterText(find.byType(TextField), 'hello ai');
      await tester.pumpAndSettle();

      expect(find.text('hello ai'), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsOneWidget);
    });

    testWidgets('tapping send button calls onSend with input text', (
      tester,
    ) async {
      String? sentText;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (text) => sentText = text,
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'explain this query');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(sentText, 'explain this query');
      expect(find.text('explain this query'), findsNothing);
    });

    testWidgets('send button is disabled while isSending', (tester) async {
      String? sentText;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: true,
          onSend: (text) => sentText = text,
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsNothing);

      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(sentText, isNull);
    });

    testWidgets('stop button calls onStop while sending', (tester) async {
      var stopped = false;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: true,
          onSend: (_) {},
          onStop: () => stopped = true,
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(stopped, isTrue);
    });

    testWidgets('settings button calls onShowApiSettings', (tester) async {
      var settingsShown = false;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onShowApiSettings: () => settingsShown = true,
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.settings));
      await tester.pumpAndSettle();

      expect(settingsShown, isTrue);
    });
  });

  group('AiInputArea table mention (@)', () {
    testWidgets('default off: typing @ shows no menu and never queries', (
      tester,
    ) async {
      var queryCount = 0;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          onTableMentionQuery: (c, d, p) {
            queryCount++;
            return Future.value(<String>['users']);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@users');
      await _pumpPastMentionDebounce(tester);

      expect(find.byType(AiTableMentionMenu), findsNothing);
      expect(queryCount, 0);
    });

    testWidgets('enabled: typing @ triggers debounced query with prefix', (
      tester,
    ) async {
      final queries = <String>[];
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) {
            queries.add('$c|$d|$p');
            return Future.value(<String>['users']);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@us');
      // 未过防抖窗口：不应查询；候选未到，浮层无可见项
      await tester.pump(const Duration(milliseconds: 100));
      expect(queries, isEmpty);
      expect(find.text('users'), findsNothing);

      await _pumpPastMentionDebounce(tester);
      // AppProvider 默认无选中上下文 → 连接/库为空串
      expect(queries, <String>['||us']);
      expect(find.byType(AiTableMentionMenu), findsOneWidget);
      expect(find.text('users'), findsOneWidget);
    });

    testWidgets('rapid typing merges into a single debounced query', (
      tester,
    ) async {
      final queries = <String>[];
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) {
            queries.add(p);
            return Future.value(<String>[]);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@u');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '@us');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '@users');
      await _pumpPastMentionDebounce(tester);

      expect(queries, <String>['users']);
    });

    testWidgets('candidates are prefix-filtered in the menu', (tester) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) =>
              Future.value(<String>['users', 'user_roles', 'orders']),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@us');
      await _pumpPastMentionDebounce(tester);

      expect(find.text('users'), findsOneWidget);
      expect(find.text('user_roles'), findsOneWidget);
      expect(find.text('orders'), findsNothing);
    });

    testWidgets('tapping a candidate inserts the reference into the input', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) =>
              Future.value(<String>['users', 'orders']),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@us');
      await _pumpPastMentionDebounce(tester);

      await tester.tap(find.text('users'));
      await tester.pumpAndSettle();

      final TextField field = tester.widget(find.byType(TextField));
      expect(field.controller, isNotNull);
      final TextEditingController controller = field.controller!;
      expect(controller.text, '@users ');
      expect(controller.selection.baseOffset, '@users '.length);
      expect(find.text('orders'), findsNothing);
    });

    testWidgets('arrow down + enter accepts the second candidate', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) =>
              Future.value(<String>['users', 'orders']),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@');
      await _pumpPastMentionDebounce(tester);
      expect(find.text('users'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final TextField field = tester.widget(find.byType(TextField));
      expect(field.controller!.text, '@orders ');
      // Enter 被采纳动作消费，不应插入换行
      expect(field.controller!.text.contains('\n'), isFalse);
      expect(find.text('orders'), findsNothing);
    });

    testWidgets('enter accepts the first candidate by default', (tester) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) =>
              Future.value(<String>['users', 'orders']),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@');
      await _pumpPastMentionDebounce(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final TextField field = tester.widget(find.byType(TextField));
      expect(field.controller!.text, '@users ');
    });

    testWidgets('escape closes the menu and keeps the text', (tester) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) =>
              Future.value(<String>['users', 'orders']),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@us');
      await _pumpPastMentionDebounce(tester);
      expect(find.text('users'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('users'), findsNothing);
      final TextField field = tester.widget(find.byType(TextField));
      expect(field.controller!.text, '@us');
    });

    testWidgets('whitespace terminates the mention token', (tester) async {
      var queryCount = 0;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) {
            queryCount++;
            return Future.value(<String>['users']);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@us trailing');
      await _pumpPastMentionDebounce(tester);

      expect(find.byType(AiTableMentionMenu), findsNothing);
      expect(queryCount, 0);
    });

    testWidgets('@ preceded by a word char does not trigger', (tester) async {
      var queryCount = 0;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) {
            queryCount++;
            return Future.value(<String>['users']);
          },
        ),
      );
      await tester.pumpAndSettle();

      // user@example.com 场景：@ 前是字母 → 不触发
      await tester.enterText(find.byType(TextField), 'user@example.com');
      await _pumpPastMentionDebounce(tester);

      expect(find.byType(AiTableMentionMenu), findsNothing);
      expect(queryCount, 0);
    });

    testWidgets('query failure degrades to no candidates without crashing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) => Future.error('boom'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@us');
      await _pumpPastMentionDebounce(tester);

      expect(find.text('users'), findsNothing);
      // 输入仍可用
      await tester.enterText(find.byType(TextField), '@users done');
      await tester.pumpAndSettle();
      final TextField field = tester.widget(find.byType(TextField));
      expect(field.controller!.text, '@users done');
    });

    testWidgets('stale query responses are discarded', (tester) async {
      final first = Completer<List<String>>();
      final second = Completer<List<String>>();
      final pending = <Completer<List<String>>>[first, second];
      final queryPrefixes = <String>[];
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) {
            queryPrefixes.add(p);
            final Completer<List<String>> completer = pending.removeAt(0);
            return completer.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      // 第一次查询（prefix 'a'）挂在 first 上
      await tester.enterText(find.byType(TextField), '@a');
      await _pumpPastMentionDebounce(tester);
      // 第二次查询（prefix 'ab'）挂在 second 上
      await tester.enterText(find.byType(TextField), '@ab');
      await _pumpPastMentionDebounce(tester);
      expect(queryPrefixes, <String>['a', 'ab']);

      // 先返回新查询，再返回旧查询 → 旧响应必须被丢弃
      second.complete(<String>['absolute_table']);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('absolute_table'), findsOneWidget);

      first.complete(<String>['apple_table']);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      // 若旧响应未被丢弃，候选会被覆写为 apple_table 且被 'ab' 前缀滤空
      expect(find.text('absolute_table'), findsOneWidget);
      expect(find.text('apple_table'), findsNothing);
    });

    testWidgets('no trigger while isSending', (tester) async {
      var queryCount = 0;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: true,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
          enableTableMention: true,
          onTableMentionQuery: (c, d, p) {
            queryCount++;
            return Future.value(<String>['users']);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@us');
      await _pumpPastMentionDebounce(tester);

      expect(find.byType(AiTableMentionMenu), findsNothing);
      expect(queryCount, 0);
    });
  });
}
