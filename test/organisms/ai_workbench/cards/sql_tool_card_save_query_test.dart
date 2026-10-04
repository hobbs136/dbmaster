// T2 保存查询链路：SQL 工具卡「保存为查询」动作测试。
//
// 覆盖：新按钮渲染（l10n 文案，key = SqlToolCard.saveQueryButtonKey）/
// 回调注入携带卡内 SQL 全文 / 回调未注入时照常渲染不禁用（组件「只渲染
// 不禁用」不变式）。既有 sql_tool_card_test.dart 的键序/懒构建不变式不在
// 本文件重复。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';

Widget _wrap(Widget child) => MaterialApp(
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
        constraints: const BoxConstraints(maxWidth: 720),
        child: child,
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testSql = 'SELECT id, name FROM users WHERE id > 10';

  Widget pumpCard({void Function(String sql)? onSaveQuery}) => SqlToolCard(
    sql: testSql,
    statementType: 'SELECT',
    isWrite: false,
    onSaveQuery: onSaveQuery,
  );

  testWidgets('「保存为查询」按钮渲染（文案走 l10n）', (tester) async {
    await tester.pumpWidget(_wrap(pumpCard()));
    await tester.pumpAndSettle();

    expect(find.byKey(SqlToolCard.saveQueryButtonKey), findsOneWidget);
    expect(
      find.text(AppLocalizationsEn().workbenchActionSaveAsQuery),
      findsOneWidget,
    );
  });

  testWidgets('回调注入：点击携带卡内 SQL 全文', (tester) async {
    String? savedSql;
    await tester.pumpWidget(
      _wrap(pumpCard(onSaveQuery: (sql) => savedSql = sql)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
    await tester.pump();

    expect(savedSql, testSql, reason: '保存出口参数 = 卡内 SQL 全文');
  });

  testWidgets('回调未注入时按钮照常渲染不禁用（点击不抛错）', (tester) async {
    await tester.pumpWidget(_wrap(pumpCard()));
    await tester.pumpAndSettle();

    expect(find.byKey(SqlToolCard.saveQueryButtonKey), findsOneWidget);
    await tester.tap(find.byKey(SqlToolCard.saveQueryButtonKey));
    await tester.pump();
  });
}
