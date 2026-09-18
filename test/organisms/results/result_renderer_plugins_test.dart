// C11 · 渲染器注册化单测：table/chart/card 三渲染器 + 注册表接线。
//
// 覆盖：viewModeId 命名（对齐原 ResultViewMode 枚举名）、形态过滤、
// build 渲染目标 widget、表格交互桥参数转发、默认注册（bootstrap）。
// 宿主切换条/切换行为的 widget 级验证在 results_view_mode_test.dart。
//
// 用例登记：docs/test/unified_test_spec.md 「C11 渲染器注册化」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/result_filter.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/card_view.dart';
import 'package:dbmaster/organisms/results/chart_view.dart';
import 'package:dbmaster/organisms/results/plugins/card_result_renderer.dart';
import 'package:dbmaster/organisms/results/plugins/chart_result_renderer.dart';
import 'package:dbmaster/organisms/results/plugins/table_result_renderer.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/plugin_registry.dart';
import 'package:dbmaster/plugins/result_renderer_plugin.dart';

void main() {
  const statement = SQLStatement(
    index: 0,
    sql: 'SELECT id, name FROM users',
    type: SQLType.select,
    lineStart: 1,
    lineEnd: 1,
  );

  final result = ExecutionResult(
    statement: statement,
    success: true,
    data: const <Map<String, dynamic>>[
      {'id': 1, 'name': 'Alice'},
      {'id': 2, 'name': 'Bob'},
    ],
    executionTime: const Duration(milliseconds: 5),
  );

  ResultRenderContext contextWith({
    TableViewInteraction? tableView,
    Future<String> Function()? onAiTrendRequest,
  }) => ResultRenderContext(
        result: result,
        rows: const <Map<String, dynamic>>[
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ],
        columns: const <String>['id', 'name'],
        columnTypes: const <String, ColumnDataType>{
          'id': ColumnDataType.numeric,
          'name': ColumnDataType.string,
        },
        onAiTrendRequest: onAiTrendRequest,
        tableView: tableView,
      );

  Widget host(WidgetBuilder builder) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: builder)),
      );

  /// pumpWidget 包装：把 builder context 交给渲染器 build（渲染器接口
  /// 要求 BuildContext，经 Builder 提供）。
  Future<void> pumpRenderer(
    WidgetTester tester,
    ResultRendererPlugin renderer,
    ResultRenderContext renderContext,
  ) {
    return tester.pumpWidget(
      host((context) => renderer.build(context, renderContext)),
    );
  }

  group('C11 · 三渲染器 viewModeId 与形态声明', () {
    test('viewModeId 与原 ResultViewMode 枚举名逐一对齐', () {
      expect(const TableResultRenderer().viewModeId, 'table');
      expect(const ChartResultRenderer().viewModeId, 'chart');
      expect(const CardResultRenderer().viewModeId, 'card');
    });

    test('chart/card 仅声明 sqlRows；table 兼声明 nosqlDocument/redisKeyValue（C12 兜底）', () {
      expect(
        const TableResultRenderer().supportedShapes,
        const {
          ResultDataShape.sqlRows,
          ResultDataShape.nosqlDocument,
          ResultDataShape.redisKeyValue,
        },
      );
      expect(
        const ChartResultRenderer().supportedShapes,
        const {ResultDataShape.sqlRows},
      );
      expect(
        const CardResultRenderer().supportedShapes,
        const {ResultDataShape.sqlRows},
      );
    });

    test('descriptor：core 来源 + 空类型集（全类型通用件）+ id 唯一', () {
      final renderers = <ResultRendererPlugin>[
        const TableResultRenderer(),
        const ChartResultRenderer(),
        const CardResultRenderer(),
      ];
      final ids = renderers.map((r) => r.descriptor.id).toSet();
      expect(ids.length, 3, reason: 'descriptor id 必须互异（全局 id 空间）');
      for (final r in renderers) {
        expect(r.descriptor.source, PluginSource.core);
        expect(r.descriptor.supportedTypes, isEmpty);
        // 空类型集 = 全类型适用
        expect(r.descriptor.supports(DatabaseType.mysql), isTrue);
        expect(r.descriptor.supports(DatabaseType.redis), isTrue);
      }
    });

    test('descriptor displayName 消费既有 viewMode* l10n 键（en 值锁定）', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        const TableResultRenderer().descriptor.displayName!(l10n),
        'Table',
      );
      expect(
        const ChartResultRenderer().descriptor.displayName!(l10n),
        'Chart',
      );
      expect(const CardResultRenderer().descriptor.displayName!(l10n), 'Card');
    });
  });

  group('C11 · build 渲染目标', () {
    testWidgets('table 渲染器 → VirtualizedDataTable（无桥亦可构建）', (
      tester,
    ) async {
      await pumpRenderer(
        tester,
        const TableResultRenderer(),
        contextWith(),
      );
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      expect(find.byType(CardView), findsNothing);
    });

    testWidgets('chart 渲染器 → ChartView', (tester) async {
      await pumpRenderer(
        tester,
        const ChartResultRenderer(),
        contextWith(onAiTrendRequest: () async => 'trend'),
      );
      expect(find.byType(ChartView), findsOneWidget);
      expect(find.byType(VirtualizedDataTable), findsNothing);
    });

    testWidgets('card 渲染器 → CardView', (tester) async {
      await pumpRenderer(tester, const CardResultRenderer(), contextWith());
      expect(find.byType(CardView), findsOneWidget);
      expect(find.byType(VirtualizedDataTable), findsNothing);
    });

    testWidgets('表格交互桥参数逐项转发到 VirtualizedDataTable', (tester) async {
      final filterService = ResultFilterService();
      var filterChanged = 0;
      var sortToggled = 0;
      final bridge = TableViewInteraction(
        filterService: filterService,
        onFilterChanged: (_) => filterChanged++,
        onFilterCleared: (_) {},
        onSortToggle: (_) => sortToggled++,
      );
      await pumpRenderer(
        tester,
        const TableResultRenderer(),
        contextWith(tableView: bridge),
      );
      final table = tester.widget<VirtualizedDataTable>(
        find.byType(VirtualizedDataTable),
      );
      expect(table.filterService, same(filterService));
      expect(table.columns, const <String>['id', 'name']);
      expect(
        table.data,
        const <Map<String, dynamic>>[
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ],
      );
      expect(table.columnTypes, const <String, ColumnDataType>{
        'id': ColumnDataType.numeric,
        'name': ColumnDataType.string,
      });

      // 回调经桥下发可触发
      table.onFilterChanged!(ColumnFilter(columnName: 'id'));
      table.onSortToggle!('id');
      expect(filterChanged, 1);
      expect(sortToggled, 1);
    });
  });

  group('C11 · 注册表接线', () {
    test('registerDefaultUiPlugins 注册三渲染器（独立 registry）', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);
      final renderers = registry.resultRenderersFor(
        shape: ResultDataShape.sqlRows,
      );
      expect(
        renderers.map((r) => r.viewModeId).toList(),
        <String>['table', 'chart', 'card'],
      );
    });

    test('defaultPluginRegistry 同样就位（e2e 不经 main 也能取到）', () {
      final renderers = defaultPluginRegistry.resultRenderersFor(
        shape: ResultDataShape.sqlRows,
      );
      expect(renderers.map((r) => r.viewModeId), containsAll(<String>[
        'table',
        'chart',
        'card',
      ]));
    });

    test('形态过滤：nosqlDocument/redisKeyValue 命中 C12 渲染器（详单测见 C12 文件）', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);
      expect(
        registry.resultRenderersFor(shape: ResultDataShape.nosqlDocument),
        isNotEmpty,
      );
      expect(
        registry.resultRenderersFor(shape: ResultDataShape.redisKeyValue),
        isNotEmpty,
      );
    });

    test('类型过滤：空类型集渲染器对任意类型命中', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);
      expect(
        registry
            .resultRenderersFor(
              type: DatabaseType.mongodb,
              shape: ResultDataShape.sqlRows,
            )
            .length,
        3,
      );
    });
  });
}
