import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/query_editor_status_bar.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// C21 · QueryEditorStatusBar（原型 editor-workspace / editor-executing
/// 底部状态条三段式：状态 / 行列 / 编码|语言|类型）。
void main() {
  group('QueryEditorStatusBar (C21)', () {
    final cursor = ValueNotifier<({int line, int column})>(
      (line: 1, column: 1),
    );
    final elapsed = ValueNotifier<Duration?>(null);

    tearDown(() {
      cursor.value = (line: 1, column: 1);
      elapsed.value = null;
    });

    Widget buildBar({
      required bool isExecuting,
      String languageLabel = 'SQL',
      String? dbTypeLabel = 'MySQL',
    }) {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        locale: const Locale('en'),
        home: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Scaffold(
            body: QueryEditorStatusBar(
              cursorPosition: cursor,
              isExecuting: isExecuting,
              elapsed: elapsed,
              languageLabel: languageLabel,
              dbTypeLabel: dbTypeLabel,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'SBAR-001 就绪态：success 图标 + Ready + 行列 + UTF-8 | SQL | MySQL',
      (tester) async {
        cursor.value = (line: 5, column: 12);
        await tester.pumpWidget(buildBar(isExecuting: false));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byIcon(LucideIcons.circleCheckBig), findsOneWidget);
        expect(find.text('Ready'), findsOneWidget);
        // 中段行列（en locale = Ln/Col 格式）
        expect(find.text('Ln 5, Col 12'), findsOneWidget);
        // 右段上下文
        expect(find.text('UTF-8 | SQL | MySQL'), findsOneWidget);
      },
    );

    testWidgets(
      'SBAR-002 执行中：spinner + Executing，elapsed 到位后显示已耗时',
      (tester) async {
        elapsed.value = null;
        await tester.pumpWidget(buildBar(isExecuting: true));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byIcon(LucideIcons.circleCheckBig), findsNothing);
        expect(find.text('Executing'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // elapsed 由 null → 值：ValueListenableBuilder 局部更新
        elapsed.value = const Duration(seconds: 3, milliseconds: 200);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Elapsed 0:03.2'), findsOneWidget);
      },
    );

    testWidgets(
      'SBAR-003 无数据库类型上下文：右段仅 UTF-8 | 语言',
      (tester) async {
        await tester.pumpWidget(
          buildBar(isExecuting: false, dbTypeLabel: null, languageLabel: 'JavaScript'),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('UTF-8 | JavaScript'), findsOneWidget);
      },
    );

    testWidgets(
      'SBAR-004 光标移动经 ValueNotifier 更新行列显示',
      (tester) async {
        cursor.value = (line: 1, column: 1);
        await tester.pumpWidget(buildBar(isExecuting: false));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Ln 1, Col 1'), findsOneWidget);

        cursor.value = (line: 42, column: 7);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Ln 42, Col 7'), findsOneWidget);
      },
    );
  });
}
