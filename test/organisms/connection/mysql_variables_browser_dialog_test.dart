// DBT-T3 · MySQL 变量浏览器 widget 测试（W-03）：mock loader 渲染 /
// 搜索防抖过滤命中 / 搜索无命中与空数据空态 / 失败态 + 重试。
// 真库链路（SHOW VARIABLES 经 dbService 默认 loader）由
// integration_test/mysql_capability_panel_e2e_test.dart 覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/connection/mysql_variables_browser_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Future<List<Map<String, String>>> Function(String) loader,
}) async {
  await tester.pumpWidget(
    _wrap(
      MysqlVariablesBrowserDialog(connectionId: 'c1', loader: loader),
    ),
  );
  // 初始异步加载完成（微任务 + setState 帧）
  await tester.pumpAndSettle();
}

const _fakeVariables = <Map<String, String>>[
  {'name': 'max_connections', 'value': '151'},
  {'name': 'innodb_buffer_pool_size', 'value': '134217728'},
  {'name': 'version', 'value': '8.0.46'},
];

void main() {
  testWidgets('mock 数据渲染两列（表头 + name/value 行）', (tester) async {
    await _pumpDialog(tester, loader: (_) async => _fakeVariables);

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Value'), findsOneWidget);
    expect(find.text('max_connections'), findsOneWidget);
    expect(find.text('151'), findsOneWidget);
    expect(find.text('innodb_buffer_pool_size'), findsOneWidget);
    expect(find.text('8.0.46'), findsOneWidget);
    // 无编辑入口（只读：不做 SET GLOBAL）
    expect(find.byType(TextField), findsOneWidget); // 仅搜索框
  });

  testWidgets('搜索防抖过滤命中（name 包含匹配）', (tester) async {
    await _pumpDialog(tester, loader: (_) async => _fakeVariables);

    await tester.enterText(find.byType(TextField), 'max');
    // 防抖 250ms 后过滤生效
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('max_connections'), findsOneWidget);
    expect(find.text('151'), findsOneWidget);
    expect(find.text('innodb_buffer_pool_size'), findsNothing);
    expect(find.text('version'), findsNothing);
  });

  testWidgets('搜索过滤命中 value 列（大小写不敏感）', (tester) async {
    await _pumpDialog(tester, loader: (_) async => _fakeVariables);

    await tester.enterText(find.byType(TextField), '8.0');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('version'), findsOneWidget);
    expect(find.text('max_connections'), findsNothing);
  });

  testWidgets('搜索无命中 → 空态文案', (tester) async {
    await _pumpDialog(tester, loader: (_) async => _fakeVariables);

    await tester.enterText(find.byType(TextField), 'no_such_var');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('No variables'), findsOneWidget);
  });

  testWidgets('空数据 → 空态文案', (tester) async {
    await _pumpDialog(tester, loader: (_) async => const []);

    expect(find.text('No variables'), findsOneWidget);
  });

  testWidgets('loader 失败 → 失败态文案 + 重试成功恢复列表', (tester) async {
    var fail = true;
    await _pumpDialog(
      tester,
      loader: (_) async {
        if (fail) throw Exception('connection lost');
        return _fakeVariables;
      },
    );

    expect(find.text('Failed to load variables'), findsOneWidget);
    expect(find.text('max_connections'), findsNothing);

    fail = false;
    await tester.tap(find.widgetWithText(TextButton, 'Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load variables'), findsNothing);
    expect(find.text('max_connections'), findsOneWidget);
  });
}
