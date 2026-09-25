// T27 AgentUiPortImpl 组件测试（design-ai-agent.md §4.5 D8 + T27 任务书
// 「port 各方法」验收）。
//
// 覆盖：
// - 界面五工具转发：openResultGrid / showTableStructure / openSqlEditor /
//   renderChart（适配路径）→ controller 对应 open + outcome ok；
// - AC5.3：renderChart 列型不适配 → outcome 失败回喂（message 非空）且
//   **不建图表 tab**（自纠通路，不产噪音）；
// - ui 规格 §6.3：pinArtifact 建 pinned tab 且不改舞台可见性；
// - suggest 两方法：落 agent_suggest 消息（T26 payload 契约：kind + action +
//   payload + applied:false）+ 返回 ok；
// - AC15.1 通路：实现侧异常（取数失败 / 落账回调抛出）→ outcome 失败，
//   不向调用方抛（guard）。
//
// 纯 Dart 组件测试（controller 是 ChangeNotifier、impl 无 widget 依赖），
// 不泵 widget 树。
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/agent_ui_port_impl.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';

AgentResultRef _ref(
  String refId, {
  String sql = 'SELECT 1',
  List<String> columns = const ['id', 'amount'],
  List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[],
  int? rowCount,
}) => AgentResultRef(
  refId: refId,
  sql: sql,
  rowCount: rowCount ?? rows.length,
  columns: columns,
  rows: rows,
);

const List<Map<String, dynamic>> _numericRows = <Map<String, dynamic>>[
  {'id': 1, 'amount': 100},
  {'id': 2, 'amount': 200},
];

const List<Map<String, dynamic>> _textRows = <Map<String, dynamic>>[
  {'name': 'alice', 'city': 'springfield'},
  {'name': 'bob', 'city': 'shelbyville'},
];

StageStructureData _structure() => StageStructureData(
  tableName: 'orders',
  columns: [
    DbColumn(name: 'id', type: 'bigint', isPrimaryKey: true, isNullable: false),
  ],
  indexes: const <DbIndex>[],
  foreignKeys: const <ForeignKey>[],
  ddl: null,
);

/// 落账回调记录桩。
class _LandRecorder {
  final List<AiMessage> landed = <AiMessage>[];
  void call(AiMessage message) => landed.add(message);
}

void main() {
  late WorkbenchStageController controller;
  late _LandRecorder landRecorder;

  AgentUiPortImpl mkPort({
    StageStructureFetcher? structureFetcher,
    AgentSuggestionLandCallback? landSuggestionMessage,
  }) => AgentUiPortImpl(
    stageController: controller,
    structureFetcher:
        structureFetcher ?? (_) async => throw StateError('unset in test'),
    landSuggestionMessage:
        landSuggestionMessage ?? landRecorder.call,
  );

  setUp(() {
    controller = WorkbenchStageController();
    landRecorder = _LandRecorder();
  });

  tearDown(() {
    controller.dispose();
  });

  group('界面五工具（controller 转发 + outcome 形态）', () {
    test('openResultGrid：ok + 网格 tab + 舞台可见 + 标题透传', () async {
      final port = mkPort();
      final outcome = await port.openResultGrid(
        _ref('res_1', rows: _numericRows),
        '查询结果',
      );

      expect(outcome, const AgentUiOutcome.ok());
      expect(controller.tabs, hasLength(1));
      expect(controller.tabs.single.kind, WorkbenchStageTabKind.grid);
      expect(controller.tabs.single.title, '查询结果');
      expect(controller.activeTab?.resultRef?.refId, 'res_1');
      expect(controller.stageVisible, isTrue, reason: '§5.3 openXxx 自动开舞台');
    });

    test('showTableStructure：取数回调收到表名 + 结构卡 tab + ok', () async {
      final fetched = <String>[];
      final port = mkPort(
        structureFetcher: (table) async {
          fetched.add(table);
          return _structure();
        },
      );
      final outcome = await port.showTableStructure('orders');

      expect(outcome.ok, isTrue);
      expect(fetched, equals(<String>['orders']));
      expect(controller.tabs.single.kind, WorkbenchStageTabKind.structure);
      expect(controller.tabs.single.structure?.tableName, 'orders');
    });

    test('showTableStructure：取数失败 → outcome 失败回喂，不建 tab', () async {
      final port = mkPort(
        structureFetcher: (table) async => throw Exception('no connection'),
      );
      final outcome = await port.showTableStructure('orders');

      expect(outcome.ok, isFalse, reason: 'AC15.1：失败回喂自纠');
      expect(outcome.message, isNotNull);
      expect(outcome.message, contains('no connection'));
      expect(controller.tabs, isEmpty, reason: '失败不产半开 tab');
    });

    test('openSqlEditor：编辑器槽装载 SQL + ok', () async {
      final port = mkPort();
      final outcome = await port.openSqlEditor('SELECT 1');

      expect(outcome.ok, isTrue);
      expect(controller.tabs.single.kind, WorkbenchStageTabKind.editor);
      expect(controller.tabs.single.initialSql, 'SELECT 1');
      // AC5.2 载入不自动执行：编辑器槽无执行语义（T24 组件面已测，这里只断
      // 装载形态）。
    });

    test('renderChart 适配：图表 tab + chartKind 透传 + ok', () async {
      final port = mkPort();
      final outcome = await port.renderChart(
        _ref('res_2', rows: _numericRows),
        'bar',
      );

      expect(outcome.ok, isTrue);
      expect(controller.tabs.single.kind, WorkbenchStageTabKind.chart);
      expect(controller.tabs.single.chartKind, 'bar');
    });

    test('renderChart 不适配（AC5.3）：outcome 失败 + 不建图表 tab', () async {
      final port = mkPort();
      final outcome = await port.renderChart(
        _ref('res_3', columns: const ['name', 'city'], rows: _textRows),
        'line',
      );

      expect(outcome.ok, isFalse, reason: 'AC5.3：列型不适配回喂自纠');
      expect(outcome.message, isNotNull);
      expect(outcome.message, contains('chart data mismatch'));
      expect(controller.tabs, isEmpty, reason: '不适配不建 tab（避免噪音）');
      expect(controller.stageVisible, isFalse);
    });

    test('pinArtifact（§6.3）：pinned 网格 tab + 舞台可见性不变', () async {
      final port = mkPort();
      final outcome = await port.pinArtifact(
        _ref('res_4', rows: _numericRows),
        'Orders result',
      );

      expect(outcome.ok, isTrue);
      expect(controller.pinnedTabs, hasLength(1));
      expect(controller.pinnedTabs.single.title, 'Orders result');
      expect(
        controller.stageVisible,
        isFalse,
        reason: 'ui 规格 §6.3：pin 不改舞台可见性',
      );
    });
  });

  group('suggest 两方法（落建议卡消息 + 返回 ok；T26 payload 契约）', () {
    test('suggestOpenInClassic：agent_suggest 消息形态 + ok', () async {
      final port = mkPort();
      final outcome = await port.suggestOpenInClassic('SELECT * FROM orders');

      expect(outcome, const AgentUiOutcome.ok());
      expect(landRecorder.landed, hasLength(1));
      final AiMessage message = landRecorder.landed.single;
      expect(message.type, AiMessageType.toolResult);
      final Map<String, dynamic> agent =
          message.toolResultData!['agent'] as Map<String, dynamic>;
      expect(agent['kind'], 'agent_suggest');
      expect(agent['action'], 'open_in_classic');
      expect(
        (agent['payload'] as Map<String, dynamic>)['sql'],
        'SELECT * FROM orders',
      );
      expect(agent['applied'], isFalse, reason: 'R6：建议级初值未应用');
    });

    test('suggestFocusSidebar：database/table 进 payload + ok', () async {
      final port = mkPort();
      final outcome = await port.suggestFocusSidebar(
        database: 'sales',
        table: 'orders',
      );

      expect(outcome.ok, isTrue);
      final Map<String, dynamic> agent =
          landRecorder.landed.single.toolResultData!['agent']
              as Map<String, dynamic>;
      expect(agent['action'], 'focus_sidebar');
      final Map<String, dynamic> payload =
          agent['payload'] as Map<String, dynamic>;
      expect(payload['database'], 'sales');
      expect(payload['table'], 'orders');
      expect(agent['applied'], isFalse);
    });

    test('suggestFocusSidebar：空目标不进 payload（空串滤除）', () async {
      final port = mkPort();
      await port.suggestFocusSidebar(database: '', table: null);

      final Map<String, dynamic> payload =
          (landRecorder.landed.single.toolResultData!['agent']
                  as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      expect(payload, isEmpty);
    });

    test('消息 id 唯一（连续落两条不撞）', () async {
      final port = mkPort();
      await port.suggestOpenInClassic('SELECT 1');
      await port.suggestOpenInClassic('SELECT 2');

      expect(landRecorder.landed.map((m) => m.id).toSet(), hasLength(2));
    });
  });

  group('AC15.1 通路：实现侧异常不外抛', () {
    test('落账回调抛出 → outcome 失败（guard 捕获）', () async {
      final port = mkPort(
        landSuggestionMessage: (_) => throw Exception('session gone'),
      );
      final outcome = await port.suggestOpenInClassic('SELECT 1');

      expect(outcome.ok, isFalse);
      expect(outcome.message, contains('session gone'));
    });
  });
}
