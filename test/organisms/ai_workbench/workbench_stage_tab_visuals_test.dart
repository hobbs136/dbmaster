// C1 舞台容器/子态视觉映射注册表测试（AI 工作台先行批任务书 §6.0；
// 批3 T7 容器收敛重构，.specs/tasks-v3.5-ui.md §3-B01）。
//
// 覆盖：
// - 容器映射完备性：4 容器遍历，icon 非空；label 在 en/zh 两 locale 非空
//   且互不相同（防串 key：两容器同文案 = 注册表错行）；
// - 子态映射完备性：四容器子枚举全值 label 非空（en/zh）；
// - 单源一致性（v2 §8-7 回归守卫）：pump 舞台 + pinned tab（沿
//   workbench_stage_test.dart / workbench_artifact_strip_test.dart 既有
//   harness 形态），断言 tab 条与产物条同容器项渲染同一 IconData，
//   且两者都与注册表取值一致（防任何一侧再落私有映射副本）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_artifact_strip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage_tab_visuals.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';

const _containers = WorkbenchStageContainerKind.values;

AgentResultRef _ref(String refId) => AgentResultRef(
  refId: refId,
  sql: 'SELECT 1',
  rowCount: 2,
  columns: const ['id', 'amount'],
  rows: const [
    {'id': 1, 'amount': 100},
    {'id': 2, 'amount': 200},
  ],
);

StageStructureData _structure() => StageStructureData(
  tableName: 'orders',
  columns: [
    DbColumn(name: 'id', type: 'bigint', isPrimaryKey: true, isNullable: false),
    DbColumn(name: 'status', type: 'varchar(20)', isNullable: true),
  ],
  indexes: [
    DbIndex(name: 'idx_status', columns: ['status'], isUnique: false),
  ],
  foreignKeys: [
    ForeignKey(
      name: 'fk_customer',
      table: 'orders',
      column: 'customer_id',
      referencedTable: 'customers',
      referencedColumn: 'id',
    ),
  ],
  ddl: 'CREATE TABLE orders (id bigint NOT NULL PRIMARY KEY);',
);

/// 舞台 + 产物条同树共享同一 controller（§6.3：条 = pinned 子集投影，
/// 两投影同源是单源一致性的被测前提；条高由自身决定，不紧高度包裹）。
Widget _wrap(WorkbenchStageController controller) => MaterialApp(
  theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
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
      child: SizedBox(
        width: 1024,
        height: 768,
        child: Column(
          children: [
            Expanded(child: WorkbenchStage(controller: controller)),
            WorkbenchArtifactStrip(controller: controller),
          ],
        ),
      ),
    ),
  ),
);

/// keyed 容器内首个 Icon 的图形（类型图标：tab 项 / 产物项的 Row 首位，
/// 均先于关闭 / 取消钉住的 × 图标）。
IconData? _firstIconIn(WidgetTester tester, Finder scope) =>
    tester.widgetList<Icon>(
      find.descendant(of: scope, matching: find.byType(Icon)),
    ).first.icon;

void main() {
  group('C1 容器映射完备性（批3 B-01）', () {
    test('4 容器遍历：icon 非空；label en/zh 非空且互不相同', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      final enLabels = <String>{};
      final zhLabels = <String>{};
      for (final container in _containers) {
        expect(container.icon, isNotNull, reason: '$container icon 缺失');
        final enLabel = container.label(en);
        final zhLabel = container.label(zh);
        expect(enLabel, isNotEmpty, reason: '$container en label 为空');
        expect(zhLabel, isNotEmpty, reason: '$container zh label 为空');
        enLabels.add(enLabel);
        zhLabels.add(zhLabel);
      }
      // 互不相同（防串 key）。
      expect(enLabels, hasLength(_containers.length));
      expect(zhLabels, hasLength(_containers.length));
    });

    test('子态映射完备性：四容器子枚举全值 label 非空（en/zh）', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      for (final v in SqlStudioSubKind.values) {
        expect(v.label(en), isNotEmpty, reason: 'SqlStudio.$v en label 空');
        expect(v.label(zh), isNotEmpty, reason: 'SqlStudio.$v zh label 空');
      }
      for (final v in DataVizSubKind.values) {
        expect(v.label(en), isNotEmpty, reason: 'DataViz.$v en label 空');
        expect(v.label(zh), isNotEmpty, reason: 'DataViz.$v zh label 空');
      }
      for (final v in SchemaSubKind.values) {
        expect(v.label(en), isNotEmpty, reason: 'Schema.$v en label 空');
        expect(v.label(zh), isNotEmpty, reason: 'Schema.$v zh label 空');
      }
      for (final v in DiagnosticsSubKind.values) {
        expect(v.label(en), isNotEmpty, reason: 'Diagnostics.$v en label 空');
        expect(v.label(zh), isNotEmpty, reason: 'Diagnostics.$v zh label 空');
      }
    });
  });

  group('C1 单源一致性（tab 条 ↔ 产物条，v2 §8-7 回归守卫；批3 容器口径）', () {
    testWidgets('四容器 pinned tab：tab 条与产物条同容器项渲染同一 IconData', (
      tester,
    ) async {
      final controller = WorkbenchStageController();
      addTearDown(controller.dispose);

      // 每容器各一 tab 且全部钉入（pinArtifact 自带 pinned dataViz tab，
      // 其余打开后 setPinned——产物条只投影 pinned 子集）。
      controller.pinArtifact(_ref('res_grid'), null); // dataViz
      controller.openStructure(_structure()); // schema
      controller.openEditorSlot('SELECT * FROM orders'); // sqlStudio
      controller.openExecution(
        // diagnostics（explainPlan 子态）。
        StageExecutionData(
          tabKey: 'manual',
          title: 'E',
          rows: const [
            StageExecutionRow(
              sql: 'INSERT 1',
              status: StageExecutionStatus.done,
            ),
          ],
        ),
      );
      for (var i = 0; i < controller.tabs.length; i++) {
        controller.setPinned(i, true);
      }

      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      expect(controller.pinnedTabs, hasLength(controller.tabs.length));
      for (final tab in controller.tabs) {
        final tabIcon = _firstIconIn(
          tester,
          find.byKey(WorkbenchStage.tabItemKey(tab.id)),
        );
        final stripIcon = _firstIconIn(
          tester,
          find.byKey(WorkbenchArtifactStrip.itemKey(tab.id)),
        );
        expect(
          tabIcon,
          isNotNull,
          reason: 'container=${tab.container}：tab 条未渲染类型图标',
        );
        expect(
          stripIcon,
          isNotNull,
          reason: 'container=${tab.container}：产物条未渲染类型图标',
        );
        expect(
          tabIcon,
          stripIcon,
          reason: 'container=${tab.container}：tab 条与产物条图标不同',
        );
        // 两投影都来自注册表（任一侧残留私有映射副本即红）。
        expect(
          tabIcon,
          tab.container.icon,
          reason: 'container=${tab.container}：偏离注册表',
        );
      }
    });
  });
}
