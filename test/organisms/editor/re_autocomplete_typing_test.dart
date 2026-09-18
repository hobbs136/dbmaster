// T18 · 真实打字路径的补全回归测试（fork 补丁守卫）。
//
// re_editor 的文本输入走 TextInput delta 通道（非按键事件），本测试经
// `TextInputClient.updateEditingStateWithDeltas` 平台消息注入真实输入管线。
//
// 守卫的 fork 补丁（third_party/re_editor，_code_field.dart 的
// calculateTextPositionScreenOffsetForAutocomplete）：编辑后异步高亮 span
// 未返回时显示段落仍是旧文本，上游 0.10.0 会在第二次起每次击键时拿到
// null 光标位置而误关补全弹窗。补丁夹紧偏移到段落末尾后弹窗应随打字
// 持续刷新。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/editor/re_code_autocomplete.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// 经 delta 通道注入一次插入（= 平台 IME 真实打字的管线；
/// 注意 delta 分支不校验 client id，走 _currentConnection）。
void _typeInsertion(String oldText, int start, int end, String inserted) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.textInput.name,
    SystemChannels.textInput.codec.encodeMethodCall(
      MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
        -1,
        <String, dynamic>{
          'deltas': <Map<String, dynamic>>[
            <String, dynamic>{
              'oldText': oldText,
              'deltaStart': start,
              'deltaEnd': end,
              'deltaText': inserted,
              'selectionBase': start + inserted.length,
              'selectionExtent': start + inserted.length,
              'selectionAffinity': 'TextAffinity.downstream',
              'selectionIsDirectional': false,
              'composingBase': -1,
              'composingExtent': -1,
            },
          ],
        },
      ]),
    ),
    (data) {},
  );
}

void main() {
  testWidgets('连续打字补全弹窗持续在线（fork 夹紧补丁回归守卫）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();
    provider.connection.saveConnection(DbServer(
      id: 'c1', name: 'T', host: 'localhost', port: 8123, type: DatabaseType.sqlite));
    await provider.tab.openQueryTab(connectionId: 'c1', databaseName: 'd');
    provider.setActiveTab(0);

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<LayoutPreferencesProvider>.value(value: layoutProvider),
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
          body: SizedBox(width: 1280, height: 800, child: const QueryEditorWidget(tabIndex: 0)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final state = tester.state<QueryEditorWidgetState>(find.byType(QueryEditorWidget));
    await tester.tap(find.byType(ReSqlEditor));
    await tester.pump(const Duration(milliseconds: 200));

    // 连续打 "s" → "se" → "sel"：上游 bug 在第二次起每次击键都会关掉弹窗。
    _typeInsertion('', 0, 0, 's');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReAutocompleteView), findsOneWidget,
        reason: '首键后补全弹窗应出现');

    _typeInsertion('s', 1, 1, 'e');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReAutocompleteView), findsOneWidget,
        reason: '第二键后弹窗不应被误关（fork 夹紧补丁）');

    _typeInsertion('se', 2, 2, 'l');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReAutocompleteView), findsOneWidget,
        reason: '第三键后弹窗仍在线');
    expect(state.controller.text, 'sel');

    // 异步刷新到位后应显示真实关键字建议（无连接时走静态关键字路径）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('SELECT'), findsWidgets,
        reason: 'sel 应匹配 SELECT 关键字建议');
  });

  testWidgets('片段触发：/sel 经真实输入管线弹出片段列表', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();
    provider.connection.saveConnection(DbServer(
      id: 'c1', name: 'T', host: 'localhost', port: 8123, type: DatabaseType.sqlite));
    await provider.tab.openQueryTab(connectionId: 'c1', databaseName: 'd');
    provider.setActiveTab(0);

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<LayoutPreferencesProvider>.value(value: layoutProvider),
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
          body: SizedBox(width: 1280, height: 800, child: const QueryEditorWidget(tabIndex: 0)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReSqlEditor));
    await tester.pump(const Duration(milliseconds: 200));

    _typeInsertion('', 0, 0, '/');
    await tester.pump(const Duration(milliseconds: 400));
    _typeInsertion('/', 1, 1, 's');
    await tester.pump(const Duration(milliseconds: 400));
    _typeInsertion('/s', 2, 2, 'e');
    await tester.pump(const Duration(milliseconds: 400));
    _typeInsertion('/se', 3, 3, 'l');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ReAutocompleteView), findsOneWidget,
        reason: '/sel 触发后片段弹窗应出现');
    expect(find.text('/sel'), findsOneWidget,
        reason: '片段列表应展示 /sel 命令（SELECT statement）');
  });
}
