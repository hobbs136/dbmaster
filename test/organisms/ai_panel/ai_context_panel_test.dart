// C23.2 · AI 面板右栏上下文面板单测。
//
// 覆盖：无连接空态、连接卡显示、当前库显示、Schema 上下文 toggle 回调。
// 用例登记：docs/test/unified_test_spec.md 「C23 AI 面板」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_context_panel.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

DbServer _mysql() => DbServer(
      id: 'c1',
      name: 'Local MySQL',
      type: DatabaseType.mysql,
      host: '192.0.2.128',
      port: 3306,
    );

void main() {
  group('C23.2 · AiContextPanel', () {
    testWidgets('无连接：显示空态卡', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AiContextPanel(
            connection: null,
            databaseName: null,
            schemaContextEnabled: true,
            onSchemaContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No connection selected'), findsOneWidget);
    });

    testWidgets('有连接：显示连接名 + host 副行', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AiContextPanel(
            connection: _mysql(),
            databaseName: 'chinook',
            schemaContextEnabled: true,
            onSchemaContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Local MySQL'), findsOneWidget);
      expect(find.text('192.0.2.128'), findsAtLeastNWidgets(1));
      expect(find.text('chinook'), findsOneWidget);
    });

    testWidgets('未选库：显示 All databases 回退文案', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AiContextPanel(
            connection: _mysql(),
            databaseName: null,
            schemaContextEnabled: true,
            onSchemaContextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All Databases'), findsOneWidget);
    });

    testWidgets('Schema 上下文 toggle：点击回调新值', (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        _wrap(
          AiContextPanel(
            connection: _mysql(),
            databaseName: null,
            schemaContextEnabled: true,
            onSchemaContextChanged: changes.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byType(Switch);
      expect(toggle, findsOneWidget);
      expect(
        tester.widget<Switch>(toggle).value,
        isTrue,
        reason: '初始态由宿主传入（默认开）',
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(changes, [false], reason: '点击后回调关闭值');
    });
  });
}
