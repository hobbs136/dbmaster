// T2 保存查询链路：命名对话框组件测试（save_query_naming_dialog.dart）。
//
// 覆盖：初始名预填 / 空输入禁用确认（U17 先例：空名不可提交）/ 确认返回
// trim 后名称 / 取消返回 null。断言结构与行为，不断言视觉样式。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_workbench/save_query_naming_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// 对话框返回值容器（onResult 在对话框 pop 时才触发，需可变盒承接）。
class _ResultBox {
  String? value;
}

/// 打开对话框的宿主按钮（捕获 showXxxDialog 的返回值到 [_ResultBox]）。
Widget _host({required String initialName, required _ResultBox box}) => Builder(
  builder: (context) => Center(
    child: ElevatedButton(
      onPressed: () async {
        box.value = await showSaveQueryNamingDialog(
          context,
          initialName: initialName,
        );
      },
      child: const Text('open-dialog'),
    ),
  ),
);

Future<_ResultBox> _open(WidgetTester tester, String initialName) async {
  final box = _ResultBox();
  await tester.pumpWidget(_wrap(_host(initialName: initialName, box: box)));
  await tester.tap(find.text('open-dialog'));
  await tester.pumpAndSettle();
  return box;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('初始名预填输入框（默认名建议由调用方生成）', (tester) async {
    await _open(tester, 'SELECT * FROM users');

    expect(find.byType(SaveQueryNamingDialog), findsOneWidget);
    expect(find.byKey(SaveQueryNamingDialog.fieldKey), findsOneWidget);
    expect(find.text('SELECT * FROM users'), findsOneWidget);
  });

  testWidgets('确认返回输入名（trim）并关闭对话框', (tester) async {
    final box = await _open(tester, 'seed');

    await tester.enterText(
      find.byKey(SaveQueryNamingDialog.fieldKey),
      '  my query  ',
    );
    await tester.pump();

    await tester.tap(find.byKey(SaveQueryNamingDialog.confirmButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(SaveQueryNamingDialog), findsNothing);
    expect(box.value, 'my query', reason: '确认返回去除首尾空白的名称');
  });

  testWidgets('空输入禁用确认：点击不关闭、无返回值（U17 先例）', (tester) async {
    final box = await _open(tester, 'to-be-cleared');

    await tester.enterText(find.byKey(SaveQueryNamingDialog.fieldKey), '');
    await tester.pump();

    final confirm = tester.widget<ElevatedButton>(
      find.byKey(SaveQueryNamingDialog.confirmButtonKey),
    );
    expect(confirm.onPressed, isNull, reason: '空名时确认钮禁用');

    await tester.tap(find.byKey(SaveQueryNamingDialog.confirmButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(SaveQueryNamingDialog), findsOneWidget);
    expect(box.value, isNull, reason: '禁用确认不产生返回值');
  });

  testWidgets('纯空白输入同样禁用确认（trim 判定）', (tester) async {
    await _open(tester, 'x');

    await tester.enterText(find.byKey(SaveQueryNamingDialog.fieldKey), '   ');
    await tester.pump();

    final confirm = tester.widget<ElevatedButton>(
      find.byKey(SaveQueryNamingDialog.confirmButtonKey),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('取消返回 null 并关闭对话框', (tester) async {
    final box = await _open(tester, 'seed');

    await tester.tap(find.byKey(SaveQueryNamingDialog.cancelButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(SaveQueryNamingDialog), findsNothing);
    expect(box.value, isNull);
  });
}
