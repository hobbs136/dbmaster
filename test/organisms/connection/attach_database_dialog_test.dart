// SPDX-License-Identifier: Apache-2.0
//
// spec 050：AttachDatabaseDialog widget 测试。
//
// 测 alias 实时校验逻辑（FilePicker 是平台插件，widget 测试难模拟，
// 故聚焦于 alias 手输触发的校验 + 按钮启停 + Cancel 行为）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/connection/attach_database_dialog.dart';
import 'package:dbmaster/l10n/app_localizations.dart';

void main() {
  // 加载 l10n 委托，让 AppLocalizations.of(context) 能解析。
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.delegate.load(const Locale('en'));
  });

  Widget _wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('初始状态：Attach 按钮禁用（path 和 alias 都空）', (tester) async {
    await tester.pumpWidget(_wrap(const AttachDatabaseDialog(connectionId: 'c1')));

    // 找到 Attach 按钮（FilledButton.icon）
    final attachButton = find.text('Attach');
    expect(attachButton, findsOneWidget);
    // 按钮的 onPressed 应为 null（禁用）
    final button = tester.widget<FilledButton>(
      find.ancestor(of: attachButton, matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('输入合法 alias → 无错误提示', (tester) async {
    await tester.pumpWidget(_wrap(const AttachDatabaseDialog(connectionId: 'c1')));

    // 找到 alias 输入框（第二个 TextField）
    final aliasField = find.byType(TextField).at(1);
    await tester.enterText(aliasField, 'archive');
    await tester.pump();

    // 不应出现错误文案（sqliteAttachAliasInvalid 等）
    expect(find.textContaining('must start with a letter'), findsNothing);
    expect(find.textContaining('reserved'), findsNothing);
  });

  testWidgets('输入非法字符 alias → 显示 invalid 错误', (tester) async {
    await tester.pumpWidget(_wrap(const AttachDatabaseDialog(connectionId: 'c1')));

    final aliasField = find.byType(TextField).at(1);
    await tester.enterText(aliasField, 'a-b');
    await tester.pump();

    expect(find.textContaining('must start with a letter'), findsOneWidget);
  });

  testWidgets('输入保留字 main → 显示 reserved 错误', (tester) async {
    await tester.pumpWidget(_wrap(const AttachDatabaseDialog(connectionId: 'c1')));

    final aliasField = find.byType(TextField).at(1);
    await tester.enterText(aliasField, 'main');
    await tester.pump();

    expect(find.textContaining('reserved'), findsOneWidget);
  });

  testWidgets('输入关键字 table → 显示 keyword 错误', (tester) async {
    await tester.pumpWidget(_wrap(const AttachDatabaseDialog(connectionId: 'c1')));

    final aliasField = find.byType(TextField).at(1);
    await tester.enterText(aliasField, 'table');
    await tester.pump();

    expect(find.textContaining('keyword'), findsOneWidget);
  });

  testWidgets('Cancel → 弹窗返回 null', (tester) async {
    AttachResult? result = AttachResult('__sentinel__', '__sentinel__');

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showDialog<AttachResult?>(
                  context: ctx,
                  builder: (_) => const AttachDatabaseDialog(connectionId: 'c1'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  // 注：path 字段 readOnly（必须经 FilePicker 选择，平台插件 widget 测试无法模拟），
  // 故「合法 path + alias → Attach 返回结果」的完整流程由 E2E 真库测试覆盖
  //（T19 attach_live_test）。这里只验 alias 校验逻辑不阻拦合法值。
  testWidgets('合法 alias 不触发任何错误文案', (tester) async {
    await tester.pumpWidget(_wrap(const AttachDatabaseDialog(connectionId: 'c1')));

    final aliasField = find.byType(TextField).at(1);
    // 测多个合法 alias
    for (final alias in ['archive', 'db1', 'my_db', '_temp_x']) {
      await tester.enterText(aliasField, alias);
      await tester.pump();
      expect(find.textContaining('must start with a letter'), findsNothing,
          reason: '$alias 应合法');
      expect(find.textContaining('reserved'), findsNothing, reason: '$alias 应合法');
      expect(find.textContaining('keyword'), findsNothing, reason: '$alias 应合法');
    }
  });
}
