// 验证"双击列名 → 经 AppProvider.insertIntoActiveEditor 桥接 → 插入活动编辑器"。
// 覆盖本次改动最关键的跨 widget 链路：tree_utils.buildInteractiveTableSchemaLeaves
// 产出的交互式列 TreeItem → 双击 → onInsert → provider.insertIntoActiveEditor →
// QueryEditorWidgetState.insertAtCursor → 编辑器 controller 文本更新。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/sidebar/builders/tree_utils.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// 同时挂载一个真实 [QueryEditorWidget] 与扁平交互式列叶子，模拟侧栏 + 编辑器共存。
class _BridgeHarness extends StatelessWidget {
  final AppProvider provider;
  final GlobalKey<QueryEditorWidgetState> editorKey;

  const _BridgeHarness({required this.provider, required this.editorKey});

  @override
  Widget build(BuildContext context) {
    final schema = DbTable(
      name: 'users',
      columns: <DbColumn>[
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true),
        DbColumn(name: 'email', type: 'VARCHAR(100)'),
      ],
    );
    final leaves = buildInteractiveTableSchemaLeaves(
      context: context,
      schema: schema,
      foreignKeys: const <ForeignKey>[],
      indexesLabel: 'Indexes',
      foreignKeysLabel: 'Foreign Keys',
      colKeyOf: (c) => 'col:conn:db:users:${c.name}',
      idxKeyOf: (i) => 'idx:conn:db:users:${i.name}',
      fkKeyOf: (f) => 'fk:conn:db:users:${f.name}',
      isSelected: (_) => false,
      onSelect: (_) {},
      // onInsert 接桥接，与 SidebarTree._insertSchemaName 的核心调用一致
      onInsert: (name) => provider.insertIntoActiveEditor?.call(name),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 120,
          child: QueryEditorWidget(key: editorKey, tabIndex: 0),
        ),
        ...leaves,
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('双击列名经桥接插入到活动编辑器', (tester) async {
    final provider = AppProvider();
    final editorKey = GlobalKey<QueryEditorWidgetState>();
    // 注册桥接，镜像 _EditorResultsSplitState._insertIntoActiveEditor
    // （在调用时解析 currentState，故可在 pump 前注册）。
    provider.insertIntoActiveEditor = (String text) {
      editorKey.currentState?.insertAtCursor(text);
    };

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider()..load(),
          ),
          ChangeNotifierProvider<LayoutPreferencesProvider>(
            create: (_) => LayoutPreferencesProvider()..load(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: const <LocalizationsDelegate>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('zh')],
          locale: const Locale('en'),
          home: Scaffold(
            body: _BridgeHarness(provider: provider, editorKey: editorKey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 编辑器已挂载且初始为空
    expect(editorKey.currentState, isNotNull);
    expect(editorKey.currentState!.controller.text, '');

    // 双击 email 列（项目内验证过的两次快速点击模式，见 tree_item_kb_test）
    expect(find.text('email'), findsOneWidget);
    await tester.tap(find.text('email'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('email'));
    await tester.pumpAndSettle();

    // 列名经桥接插入到编辑器光标处
    expect(editorKey.currentState!.controller.text, 'email');
    expect(tester.takeException(), isNull);
  });

  testWidgets('无桥接时双击列不会崩溃（no-op）', (tester) async {
    final provider = AppProvider();
    final editorKey = GlobalKey<QueryEditorWidgetState>();
    // insertIntoActiveEditor 保持 null（编辑器未挂载/桥接未注册的情形）

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider()..load(),
          ),
          ChangeNotifierProvider<LayoutPreferencesProvider>(
            create: (_) => LayoutPreferencesProvider()..load(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: const <LocalizationsDelegate>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('zh')],
          locale: const Locale('en'),
          home: Scaffold(
            body: _BridgeHarness(provider: provider, editorKey: editorKey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('email'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('email'));
    await tester.pumpAndSettle();

    // 桥接为 null → onInsert 走 ?.call 安全 no-op，不崩溃
    expect(editorKey.currentState, isNotNull);
    expect(editorKey.currentState!.controller.text, '');
    expect(tester.takeException(), isNull);
  });
}
