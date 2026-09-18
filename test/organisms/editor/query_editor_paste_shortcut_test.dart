// T17/T18 · 粘贴键归属守卫（re_editor 迁移后语义）。
//
// T02a/T02b 的 Ctrl+V / Shift+Insert 拦截分流随 EditableText 路径一并退役：
// re_editor 行式渲染 + copy-on-write 使 EditableText.paste 的全文首排冻结
// （958K 2.4s / 3MB 6.4s 单帧）不复存在，粘贴回归 re_editor 原生
// （可撤销、行式插入）。本测试守卫两点：
// 1. 编排层（QueryEditorWidget 的 focusNode.onKeyEvent）**不得**重新拦截
//    粘贴键——那是 re_editor 内建 Shortcuts 的职责，外层再拦会绕开原生
//    undo 语义（回归 T02a 之前的 bug 形态）；
// 2. 编排层仍承接 re_editor 未认领的执行/格式化键（F5 / Ctrl+Enter /
//    Ctrl+Shift+F），防止迁移中误删。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

Future<AppProvider> _pumpEditor(WidgetTester tester) async {
  // widget 测试无平台通道，SharedPreferences 需 mock 否则 load() 永挂。
  SharedPreferences.setMockInitialValues({});
  AppProvider.devBypassGates = true;
  final provider = AppProvider();
  await provider.tab.openQueryTab(
    connectionId: 'paste_shortcut_test',
    databaseName: 'test',
  );
  provider.setActiveTab(0);
  provider.updateTabSql(0, '');

  final themeProvider = ThemeProvider();
  final localeProvider = LocaleProvider();
  final layoutProvider = LayoutPreferencesProvider();
  await themeProvider.load();
  await localeProvider.load();
  await layoutProvider.load();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<LayoutPreferencesProvider>.value(
          value: layoutProvider,
        ),
        Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
      ],
      child: MaterialApp(
        locale: localeProvider.locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(themeProvider.accentColorValue),
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 800,
            child: const QueryEditorWidget(tabIndex: 0),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return provider;
}

/// 直接调用编排层 focusNode 的 onKeyEvent（修饰键状态需先经
/// sendKeyDownEvent 压入 HardwareKeyboard）。
KeyEventResult sendKeyToEditorHandler(
  WidgetTester tester,
  LogicalKeyboardKey logicalKey,
  PhysicalKeyboardKey physicalKey,
) {
  final state = tester.state<QueryEditorWidgetState>(
    find.byType(QueryEditorWidget),
  );
  final focusNode = state.controller.focusNode;
  final handler = focusNode.onKeyEvent!;
  return handler(
    focusNode,
    KeyDownEvent(
      physicalKey: physicalKey,
      logicalKey: logicalKey,
      timeStamp: Duration.zero,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('粘贴键（Ctrl+V / Shift+Insert / 裸 Insert / 裸 V）编排层一律不拦截', (
    tester,
  ) async {
    await _pumpEditor(tester);

    // Ctrl+V —— re_editor 内建 paste 的域，外层拦截会绕开原生 undo
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(
      sendKeyToEditorHandler(
        tester,
        LogicalKeyboardKey.keyV,
        PhysicalKeyboardKey.keyV,
      ),
      KeyEventResult.ignored,
      reason: 'Ctrl+V 归 re_editor 原生 paste，编排层不得重新拦截',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    // Shift+Insert（IBM CUA 粘贴键，T02b 确认框架同样绑定 paste intent）
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      sendKeyToEditorHandler(
        tester,
        LogicalKeyboardKey.insert,
        PhysicalKeyboardKey.insert,
      ),
      KeyEventResult.ignored,
      reason: 'Shift+Insert 归 re_editor 原生 paste，编排层不得重新拦截',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(
      sendKeyToEditorHandler(
        tester,
        LogicalKeyboardKey.insert,
        PhysicalKeyboardKey.insert,
      ),
      KeyEventResult.ignored,
      reason: '裸 Insert 不是粘贴键，不应拦截',
    );
    expect(
      sendKeyToEditorHandler(
        tester,
        LogicalKeyboardKey.keyV,
        PhysicalKeyboardKey.keyV,
      ),
      KeyEventResult.ignored,
      reason: '无修饰键 V 是普通字符输入，不应拦截',
    );

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('F5 与 Ctrl+Enter 仍由编排层承接（执行查询）', (tester) async {
    await _pumpEditor(tester);

    expect(
      sendKeyToEditorHandler(tester, LogicalKeyboardKey.f5, PhysicalKeyboardKey.f5),
      KeyEventResult.handled,
      reason: 'F5 执行查询应仍由编排层处理',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(
      sendKeyToEditorHandler(
        tester,
        LogicalKeyboardKey.enter,
        PhysicalKeyboardKey.enter,
      ),
      KeyEventResult.handled,
      reason: 'Ctrl+Enter 执行查询应仍由编排层处理（re_editor 已摘除其换行绑定）',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    await tester.pump(const Duration(seconds: 1));
  });
}
