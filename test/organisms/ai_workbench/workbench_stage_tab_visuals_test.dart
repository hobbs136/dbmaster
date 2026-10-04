// C1 舞台 tab kind 视觉映射注册表测试（AI 工作台先行批任务书 §6.0）。
//
// 覆盖：
// - 映射完备性：4 kind 遍历，icon 非空；label 在 en/zh 两 locale 非空且
//   互不相同（防串 key：两 kind 同文案 = 注册表错行）；
// - 单源一致性（v2 §8-7 回归守卫）：pump 舞台 + pinned tab（沿
//   workbench_stage_test.dart / workbench_artifact_strip_test.dart 既有
//   harness 形态），断言 tab 条与产物条同 kind 项渲染同一 IconData，
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

const _kinds = WorkbenchStageTabKind.values;

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
  group('C1 映射完备性', () {
    test('4 kind 遍历：icon 非空；label en/zh 非空且互不相同', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      final enLabels = <String>{};
      final zhLabels = <String>{};
      for (final kind in _kinds) {
        expect(kind.icon, isNotNull, reason: '$kind icon 缺失');
        final enLabel = kind.label(en);
        final zhLabel = kind.label(zh);
        expect(enLabel, isNotEmpty, reason: '$kind en label 为空');
        expect(zhLabel, isNotEmpty, reason: '$kind zh label 为空');
        enLabels.add(enLabel);
        zhLabels.add(zhLabel);
      }
      // 互不相同（防串 key）。
      expect(enLabels, hasLength(_kinds.length));
      expect(zhLabels, hasLength(_kinds.length));
    });
  });

  group('C1 单源一致性（tab 条 ↔ 产物条，v2 §8-7 回归守卫）', () {
    testWidgets('四类 pinned tab：tab 条与产物条同 kind 项渲染同一 IconData', (
      tester,
    ) async {
      final controller = WorkbenchStageController();
      addTearDown(controller.dispose);

      // 每类 kind 各一 tab 且全部钉入（pinArtifact 自带 pinned 网格 tab，
      // 其余打开后 setPinned——产物条只投影 pinned 子集）。
      controller.pinArtifact(_ref('res_grid'), null);
      controller.openStructure(_structure());
      controller.openEditorSlot('SELECT * FROM orders');
      controller.openChart(_ref('res_chart'), null);
      for (var i = 0; i < controller.tabs.length; i++) {
        controller.setPinned(i, true);
      }

      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      // 全部建出的 tab 都已钉入（自 A2 +sessionList 起本 harness 只覆盖可
      // 钉入的 kind——sessionList 槽需 AppProvider，其映射由上方完备性组
      // 经 .values 遍历覆盖）。
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
          reason: 'kind=${tab.kind}：tab 条未渲染类型图标',
        );
        expect(
          stripIcon,
          isNotNull,
          reason: 'kind=${tab.kind}：产物条未渲染类型图标',
        );
        expect(
          tabIcon,
          stripIcon,
          reason: 'kind=${tab.kind}：tab 条与产物条图标不同',
        );
        // 两投影都来自注册表（任一侧残留私有映射副本即红）。
        expect(tabIcon, tab.kind.icon, reason: 'kind=${tab.kind}：偏离注册表');
      }
    });
  });
}
