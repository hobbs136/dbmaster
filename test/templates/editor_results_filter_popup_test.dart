import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbColumn;
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/filter_condition.dart';
import 'package:dbmaster/models/panel_layout.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/editor/filter_bar_strip.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:dbmaster/templates/editor_results_split.dart';

/// UIRV-A41：FilterBarStrip 弹层化（编辑器数据模式宿主）。
///
/// 从任务书验收条款直译：
/// - 条款 1 后半：Filter 入口显示激活条件数（0 时无徽标）。
/// - 条款 2：点击展开（宽 ≤400 上限、窄窗取可用宽），Esc 关闭归还焦点到
///   Filter 入口；Apply 后弹层收起。
/// - 条款 3：per-tab 条件/combinator/执行路径零改动（宿主只换呈现容器）。
/// - 条款 4：无列在弹层内呈现，不用空白顶替。
/// - 条款 6：弹层覆盖式（不推挤网格滚动布局）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi',
    (message) async =>
        const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
  );
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchaseApi',
    (message) async =>
        const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
  );

  const filterEntryKey = ValueKey('uirv-a41-filter-entry');
  const popupKey = ValueKey('uirv-a41-filter-popup');

  group('UIRV-A41 · 过滤弹层宿主', () {

  /// Ahem 测试字体下标签宽度失真，统一放大测试视口消除无关 overflow 噪音。
  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
    late AppProvider appProvider;
    late LayoutPreferencesProvider layoutProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      layoutProvider = LayoutPreferencesProvider();
      tabId = 'tab-popup-${Random().nextInt(1000000)}';
    });

    /// 造一个数据模式（browse）tab：SQL 系类型 + filterBarVisible + browse
    /// 目标 + 一条有数据结果。connectionId 留空 → 列加载返回空（真实路径，
    /// 弹层内呈现「No columns」）。
    void seedDataModeTab([AppProvider? target]) {
      final p = target ?? appProvider;
      p.tab.addTab(
        QueryTab(id: tabId, title: 'users', databaseType: DatabaseType.mysql),
      );
      p.tab.setPanelLayout(tabId, PanelLayout.browse);
      p.tab.setBrowseTarget(tabId, 'db.users');
      p.tab.addResultToTab(
        tabId,
        [
          ExecutionResult(
            statement: const SQLStatement(
              index: 0,
              sql: 'SELECT * FROM users',
              type: SQLType.select,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: <Map<String, dynamic>>[
              <String, dynamic>{'id': 1, 'name': 'Alice'},
            ],
            executionTime: const Duration(milliseconds: 5),
          ),
        ],
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 5),
      );
    }

    Widget buildHostBody([AppProvider? providerOverride]) {
      final p = providerOverride ?? appProvider;
      return EditorResultsSplit(
        provider: p,
        layoutProvider: layoutProvider,
        isResizing: false,
        onResizeStart: () {},
        onResizeEnd: () {},
        resultsWidgetKey: GlobalKey<ResultsWidgetState>(),
      );
    }

    Widget buildHost({double? width, AppProvider? providerOverride}) {
      return ChangeNotifierProvider<AppProvider>.value(
        value: providerOverride ?? appProvider,
        child: ChangeNotifierProvider<LayoutPreferencesProvider>.value(
          value: layoutProvider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SizedBox.expand(
                child: width != null
                    ? Center(
                        child: SizedBox(
                          width: width,
                          child: buildHostBody(providerOverride),
                        ),
                      )
                    : buildHostBody(providerOverride),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openPopup(WidgetTester tester) async {
      await tester.tap(find.byKey(filterEntryKey));
      await tester.pumpAndSettle();
    }

    testWidgets('条款 1：数据模式默认即单一工具栏 + Filter 入口；0 条件无徽标', (
      tester,
    ) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.byKey(filterEntryKey), findsOneWidget);
      expect(find.text('AI Analyze'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.byIcon(LucideIcons.search), findsOneWidget);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      // 旧常驻 FilterBarStrip 不再占布局
      expect(find.byType(FilterBarStrip), findsNothing);
    });

    testWidgets('条款 1：条件数徽标随 per-tab 条件出现（>0 显示数量）', (tester) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      appProvider.setFilterConditions(tabId, [
        FilterCondition(
          field: 'name',
          op: FilterOperator.eq,
          value: 'Alice',
        ),
      ]);
      await tester.pumpAndSettle();

      // 徽标 = 条件数文本「1」位于 Filter 入口按钮内
      final badgeFinder = find.descendant(
        of: find.byKey(filterEntryKey),
        matching: find.text('1'),
      );
      expect(badgeFinder, findsOneWidget);

      appProvider.setFilterConditions(tabId, const []);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(filterEntryKey), matching: find.text('1')),
        findsNothing,
      );
    });

    testWidgets('条款 2：点 Filter 展开弹层（FilterBarStrip 呈现于弹层容器）', (
      tester,
    ) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await openPopup(tester);
      expect(find.byKey(popupKey), findsOneWidget);
      expect(find.byType(FilterBarStrip), findsOneWidget);
      // 无列状态在弹层内呈现（connectionId 空 → 真实加载路径返回空列）
      expect(find.text('No columns'), findsOneWidget);
    });

    testWidgets('条款 2：Esc 关闭弹层且焦点归还 Filter 入口', (tester) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await openPopup(tester);
      expect(find.byKey(popupKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(popupKey), findsNothing);
      // 焦点归还到 Filter 入口
      final entryElement = tester.element(find.byKey(filterEntryKey));
      expect(Focus.of(entryElement).hasFocus, isTrue);
    });

    testWidgets('条款 2：弹层宽 ≤400px 上限；窄窗取可用宽', (tester) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await openPopup(tester);
      expect(tester.getSize(find.byKey(popupKey)).width, 400);

      // 窄容器：宿主可用宽 620 → 弹层取可用宽（620 - 左右内距）
      await tester.pumpWidget(buildHost(width: 620));
      await tester.pumpAndSettle();
      await openPopup(tester);
      expect(tester.getSize(find.byKey(popupKey)).width, lessThanOrEqualTo(620));
    });

    testWidgets('条款 6：弹层覆盖式——网格位置不被推挤，弹层外网格仍可交互', (
      tester,
    ) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      final gridBefore = tester.getTopLeft(find.byType(VirtualizedDataTable));
      await openPopup(tester);
      final gridAfter = tester.getTopLeft(find.byType(VirtualizedDataTable));

      expect(gridAfter, gridBefore, reason: '覆盖式弹层不改变网格布局位置');
      // 弹层不吞滚动：网格仍在树上且底部统计条等非弹层区域保持原位
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
    });

    testWidgets('条款 2：Apply 后弹层收起（执行结果时间戳推进触发）', (tester) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await openPopup(tester);
      expect(find.byKey(popupKey), findsOneWidget);

      // 模拟 Apply 完成的真实信号：per-tab 条件写入 + 新结果时间戳推进
      //（FilterBarStrip._apply 的收尾两步，宿主只观察不复制逻辑）。
      appProvider.setFilterConditions(tabId, [
        FilterCondition(field: 'id', op: FilterOperator.eq, value: '1'),
      ]);
      appProvider.tab.addResultToTab(
        tabId,
        [
          ExecutionResult(
            statement: const SQLStatement(
              index: 0,
              sql: 'SELECT * FROM users WHERE id = 1',
              type: SQLType.select,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: <Map<String, dynamic>>[
              <String, dynamic>{'id': 1, 'name': 'Alice'},
            ],
            executionTime: const Duration(milliseconds: 5),
          ),
        ],
        sql: 'SELECT * FROM users WHERE id = 1',
        executionTime: const Duration(milliseconds: 5),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(popupKey), findsNothing, reason: 'Apply 成功后弹层收起');
      expect(find.byType(FilterBarStrip), findsNothing);
    });

    testWidgets('条款 4：应用失败弹层不空白——保持展开并呈现失败提示', (tester) async {
      useLargeSurface(tester);
      seedDataModeTab();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await openPopup(tester);

      // 模拟 Apply 执行失败的真实信号：错误结果子标签（错误文案已在子标签）
      appProvider.tab.addErrorMessageToTab(tabId, 'execute failed', sql: 'bad');
      await tester.pumpAndSettle();

      expect(find.byKey(popupKey), findsOneWidget, reason: '失败时弹层保持展开');
      expect(find.textContaining('Filter apply failed'), findsOneWidget);
    });

    testWidgets('打回修复：未 Apply 草稿条件 → 关闭弹层 → 重开，草稿仍在（Offstage 保活）', (
      tester,
    ) async {
      // 评审打回：关闭即卸载丢失未 Apply 草稿（旧实现 IndexedStack 常驻保活）。
      // 修复 = Offstage 常驻挂载；本用例从验收条款直译，修复前红（关闭卸载）。
      final fakeApp = _FakeColumnsProvider();
      seedDataModeTab(fakeApp);
      await tester.pumpWidget(buildHost(providerOverride: fakeApp));
      await tester.pumpAndSettle();

      // 展开弹层：列经 fake 返回（id/name）→ 首条草稿行含值输入框。
      await openPopup(tester);
      expect(find.byKey(popupKey), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // 输入未 Apply 的草稿值，随后 Esc 关闭。
      await tester.enterText(find.byType(TextField), 'draft-42');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(popupKey), findsNothing);
      // find 默认跳过 offstage 子树：关闭态下弹层不在常规可命中结果中。
      expect(find.text('draft-42'), findsNothing);

      // 重开：草稿行与输入值原样保留（同一 FilterBarStrip 状态未卸载）。
      await openPopup(tester);
      expect(find.byKey(popupKey), findsOneWidget);
      expect(find.text('draft-42'), findsOneWidget,
          reason: '未 Apply 草稿条件行在关闭再开后保留');
    });

    testWidgets('返工 2：400px 弹层 + 多条件行长类型标签——零 overflow、控件可达', (
      tester,
    ) async {
      // 打回评审核实的真实缺陷：弹层宽 ≤400px（窄窗取可用宽）时，条件行
      // Row 被字段/操作符下拉的长标签（如 varchar(255)）挤出 ≈50px overflow。
      // 修复 = 条件行内两下拉 Flexible + isExpanded 收缩（仅布局容器）。
      final fakeApp = _FakeColumnsProvider();
      seedDataModeTab(fakeApp);
      await tester.pumpWidget(buildHost(providerOverride: fakeApp));
      await tester.pumpAndSettle();

      await openPopup(tester);
      expect(tester.getSize(find.byKey(popupKey)).width, 400,
          reason: '本用例锁定 400px 上限宽度下的布局');

      // 增补第二条条件行（默认 1 行 + Add condition 按钮）→ 两行长标签行。
      await tester.tap(find.byIcon(LucideIcons.circlePlus));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));

      // 渲染断言：长标签下两行均无 overflow 异常。
      expect(tester.takeException(), isNull,
          reason: '400px 弹层内多条件行长类型标签不得溢出');

      // 控件可达：两行值输入均可聚焦输入（收缩布局不吞命中区）。
      await tester.enterText(find.byType(TextField).first, 'row-one');
      await tester.enterText(find.byType(TextField).last, 'row-two');
      await tester.pumpAndSettle();
      expect(find.text('row-one'), findsOneWidget);
      expect(find.text('row-two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('UI35-141~144 · Filter 草稿状态感知（Epic 4.1）', () {
      const draftDotKey = ValueKey('uirv-a41-filter-draft-dot');

      /// 有草稿的公共前置：fake 列 + 展开弹层 + 输入草稿值。
      Future<void> seedDraft(WidgetTester tester, AppProvider fakeApp) async {
        seedDataModeTab(fakeApp);
        await tester.pumpWidget(buildHost(providerOverride: fakeApp));
        await tester.pumpAndSettle();
        await openPopup(tester);
        await tester.enterText(find.byType(TextField), 'draft-42');
        await tester.pumpAndSettle();
      }

      testWidgets('UI35-141: 有草稿 → 6px warning 圆点存在；无草稿 findsNothing', (
        tester,
      ) async {
        useLargeSurface(tester);
        final fakeApp = _FakeColumnsProvider();
        seedDataModeTab(fakeApp);
        await tester.pumpWidget(buildHost(providerOverride: fakeApp));
        await tester.pumpAndSettle();

        // 无草稿：初始空行（空值条件在投影中等价于无条件）不显示圆点。
        expect(find.byKey(draftDotKey), findsNothing);

        await openPopup(tester);
        await tester.enterText(find.byType(TextField), 'draft-42');
        await tester.pumpAndSettle();
        final dot = tester.widget<Container>(find.byKey(draftDotKey));
        expect(dot.constraints?.maxWidth, 6, reason: '圆点 6px');
        expect(dot.constraints?.maxHeight, 6, reason: '圆点 6px');
        final decoration = dot.decoration! as BoxDecoration;
        // warning 语义色按主题分发：暗色 0xFFFF8A30 / 亮色 warningLight 0xFFD97706。
        expect(
          decoration.color,
          anyOf(const Color(0xFFFF8A30), const Color(0xFFD97706)),
          reason: '圆点用 warning 语义色',
        );
      });

      testWidgets('UI35-142: 0 生效 + 有草稿 → 仅圆点、无数字徽标', (tester) async {
        useLargeSurface(tester);
        final fakeApp = _FakeColumnsProvider();
        await seedDraft(tester, fakeApp);

        expect(find.byKey(draftDotKey), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(filterEntryKey),
            matching: find.text('1'),
          ),
          findsNothing,
          reason: '0 生效条件时不显示数字徽标',
        );
      });

      testWidgets('UI35-143: Apply 后圆点消失、数字更新', (tester) async {
        useLargeSurface(tester);
        final fakeApp = _NoExecProvider();
        await seedDraft(tester, fakeApp);
        expect(find.byKey(draftDotKey), findsOneWidget);

        // 走真实 Apply 路径（执行替身 no-op，不触真库）。
        await tester.tap(find.byIcon(LucideIcons.play));
        await tester.pumpAndSettle();

        expect(find.byKey(draftDotKey), findsNothing, reason: 'Apply 清点');
        expect(
          find.descendant(
            of: find.byKey(filterEntryKey),
            matching: find.text('1'),
          ),
          findsOneWidget,
          reason: '数字徽标更新为生效条件数',
        );
      });

      testWidgets('UI35-144: 关闭弹层再开——草稿与圆点保持（保活回归锁）', (tester) async {
        useLargeSurface(tester);
        final fakeApp = _FakeColumnsProvider();
        await seedDraft(tester, fakeApp);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(draftDotKey), findsOneWidget,
            reason: '关闭弹层不清草稿，圆点保持');

        await openPopup(tester);
        expect(find.byKey(draftDotKey), findsOneWidget);
        expect(find.text('draft-42'), findsOneWidget,
            reason: '重开后草稿值保留');
      });

      testWidgets('UI35-附加: tooltip 追加 filterDraftDotTooltip + accent 边框同现', (
        tester,
      ) async {
        useLargeSurface(tester);
        final fakeApp = _FakeColumnsProvider();
        seedDataModeTab(fakeApp);
        await tester.pumpWidget(buildHost(providerOverride: fakeApp));
        await tester.pumpAndSettle();

        // 无草稿：无草稿 tooltip。
        expect(
          find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Unapplied filter changes',
          ),
          findsNothing,
        );

        await seedDraft(tester, fakeApp);
        expect(
          find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Unapplied filter changes',
          ),
          findsOneWidget,
        );
        // 不只靠颜色：草稿态按钮带 accent 边框。
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Filter'),
        );
        final side = button.style?.side?.resolve({});
        expect(side, isNotNull, reason: '草稿态出现 accent 边框');
      });

      testWidgets('探针: 加一条再删同一条 → 回到无草稿（顺序不敏感等价）', (tester) async {
        useLargeSurface(tester);
        final fakeApp = _FakeColumnsProvider();
        seedDataModeTab(fakeApp);
        await tester.pumpWidget(buildHost(providerOverride: fakeApp));
        await tester.pumpAndSettle();
        await openPopup(tester);

        // 加一条（空值，不改变有效投影）再删掉 → 回无草稿。
        await tester.tap(find.byIcon(LucideIcons.circlePlus));
        await tester.pumpAndSettle();
        expect(find.byKey(draftDotKey), findsNothing,
            reason: '新增空值行不改变有效投影（空值条件在拼 SQL 时被跳过）');
        await tester.tap(find.byIcon(LucideIcons.circleMinus).last);
        await tester.pumpAndSettle();
        expect(find.byKey(draftDotKey), findsNothing, reason: '加删同条回无草稿');

        // 输入值（真实草稿）→ 圆点出现；清空该值 → 投影回无草稿 → 圆点消失。
        await tester.enterText(find.byType(TextField), 'x');
        await tester.pumpAndSettle();
        expect(find.byKey(draftDotKey), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(find.byKey(draftDotKey), findsNothing,
            reason: '清空草稿值后回到无草稿');
      });
    });
  });
}

/// 执行替身：Apply 路径可走通但不触真库（仅服务 UI35-143 圆点清点断言）。
class _NoExecProvider extends _FakeColumnsProvider {
  @override
  Future<List<ExecutionResult>> executeCurrentQueryAndRecord({
    String? overrideSql,
    bool skipDdlAnalysis = false,
    void Function(int current, int total)? onStatementProgress,
  }) async => const [];
}

/// 列加载替身：绕开真实库连接（本批纯呈现层无真库依赖），令 FilterBarStrip
/// 渲染出条件行与值输入框，承载草稿保活断言。
class _FakeColumnsProvider extends AppProvider {
  @override
  Future<List<DbColumn>> getTableColumnsForBrowse(String tabId) async => [
        // 真实长标签（返工 2：不再用短名替身绕开溢出）。
        DbColumn(name: 'full_name', type: 'varchar(255)'),
        DbColumn(name: 'created_at', type: 'datetime'),
      ];
}
