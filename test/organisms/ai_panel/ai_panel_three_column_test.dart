// C23.2 · AI 面板三栏响应式单测。
//
// 覆盖：≥700px 宽面（全屏/大 overlay）渲染左技能目录 + 右上下文栏；
// <700px 窄面（停靠侧栏 300-400px）隐藏两栏、header 出 sparkles 入口
// 按钮；点击入口弹 Tab 对话框。用例登记：「C23 AI 面板」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_panel/ai_skill_catalog_panel.dart';
import 'package:dbmaster/organisms/ai_panel/ai_context_panel.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPanel(WidgetTester tester, Size surface) async {
    final app = AppProvider();
    // 种一条已存连接：header 空态分支（无按钮）与有连接分支分流，
    // 窄模式入口按钮在有连接分支。
    app.connection.addSavedServerForTest(
      DbServer(
        id: 'c1',
        name: 'Local MySQL',
        type: DatabaseType.mysql,
        host: '192.0.2.128',
        port: 3306,
      ),
    );
    final layout = LayoutPreferencesProvider();
    await layout.load();

    await tester.binding.setSurfaceSize(surface);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layout,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: AiPanelWidget()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('宽面（1000px）：三栏——技能目录 + 对话 + 上下文', (tester) async {
    await pumpPanel(tester, const Size(1000, 800));

    expect(
      find.byType(AiSkillCatalogPanel),
      findsOneWidget,
      reason: '宽面渲染左栏技能目录',
    );
    expect(
      find.byType(AiContextPanel),
      findsOneWidget,
      reason: '宽面渲染右栏上下文',
    );
    expect(
      find.byIcon(LucideIcons.sparkles),
      findsNothing,
      reason: '宽面不需要窄模式入口按钮（无选中技能时）',
    );
  });

  testWidgets('窄面（400px）：单栏 + header sparkles 入口；点击弹 Tab 对话框',
      (tester) async {
    await pumpPanel(tester, const Size(400, 800));

    expect(
      find.byType(AiSkillCatalogPanel),
      findsNothing,
      reason: '窄面不渲染常驻技能目录',
    );
    expect(find.byType(AiContextPanel), findsNothing);

    final entry = find.byIcon(LucideIcons.sparkles);
    expect(entry, findsOneWidget, reason: 'header 窄模式入口按钮');

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget, reason: '入口弹出 Tab 对话框');
    expect(find.byType(AiSkillCatalogPanel), findsOneWidget);

    // TabBarView 懒构建：切到 Context 标签后右栏内容才挂树
    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    expect(find.byType(AiContextPanel), findsOneWidget);
  });

  testWidgets('窄面入口选技能：对话框关闭并填充输入框', (tester) async {
    await pumpPanel(tester, const Size(400, 800));

    await tester.tap(find.byIcon(LucideIcons.sparkles));
    await tester.pumpAndSettle();

    // 选一个带模板的技能（SQL Explain）
    await tester.tap(find.text('SQL Explain'));
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsNothing, reason: '选择后对话框关闭');

    final inputField = find.descendant(
      of: find.byType(AiInputArea),
      matching: find.byType(TextField),
    );
    final controller =
        tester.widget<TextField>(inputField).controller as TextEditingController;
    expect(
      controller.text,
      contains('SQL'),
      reason: '技能 promptTemplate 已填入输入框',
    );
  });
}
