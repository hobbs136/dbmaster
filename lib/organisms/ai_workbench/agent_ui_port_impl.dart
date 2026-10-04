//! Agent 界面派发端口的 organisms 侧实现（T27，design-ai-agent.md §4.5 D8；
//! 命名裁决见 tasks-ai-agent.md §6 计划期发现 #11）。
//!
//! 职责：AgentUiPort 七方法的 UI 落点——前五方法（openResultGrid /
//! showTableStructure / openSqlEditor / renderChart / pinArtifact）操作
//! [WorkbenchStageController]（布局语义已由 T24 在 controller 内执法：
//! openXxx 自动开舞台 + 激活、openEditorSlot 脏槽新开 AC5.5、pinArtifact
//! 不改舞台可见性 ui 规格 §6.3）；suggest 两方法 = 落建议卡消息进当前会话
//! （payload 契约 = T26：`agent_suggest` kind + action + payload +
//! applied:false）后返回 ok——消息落账经注入回调（避免 services→UI 反向；
//! runId/stepNo 审计上下文由宿主回调侧补写）。2b.3（R6）加性第八方法
//! [AgentUiPortImpl.openOptimization]：explain_plan 旁挂推送的舞台落点——
//! 只读推送零执行（「应用此索引」由内容槽填编辑器槽，本端口不触发任何
//! SQL 执行）。
//!
//! AC15.1 通路：全部方法经 [_guard] 包裹，实现侧自身异常一律转
//! [AgentUiOutcome.failure] 回喂 LLM 自纠，**不得向 runner 抛出未处理异常**
//! （T09 契约注释 / T27 边界清单）。outcome message 为模型向技术串（非用户
//! 可见文案），不入 l10n。
//!
//! 依赖注入（构造，全部经 shell 装配）：舞台 controller / 结构取数回调
//! （describe 四件，绑定 AppProvider.dbService 与工作台上下文解析）/ 建议
//! 消息落账回调（绑定 sessionManager）。本类为纯 Dart（无 material import，
//! 与 T09 契约面同语汇），可脱离 widget 树单测。

import '../../models/ai_message_type.dart';
import '../../models/database_models.dart' show AiMessage;
import '../../models/query_optimizer/execution_plan.dart'
    show PerformanceReport;
import '../../services/ai/agent/agent_ui_port.dart';
import '../../utils/app_logger.dart';
import 'workbench_stage.dart';

/// 建议消息落账回调（shell 装配）：入参为 port 侧组装完成的 `agent_suggest`
/// 消息；宿主补写 runId/stepNo（审计对账，T26 `_applySuggestion` 消费）后
/// 经 sessionManager.addMessage 落当前会话。T28 交接签名。
typedef AgentSuggestionLandCallback = void Function(AiMessage message);

/// 结构取数回调（shell 装配）：按表名取 describe 四件（列/索引/外键/DDL）。
/// 取数失败以异常抛出（由 [_guard] 转 outcome 失败回喂）；方言能力面
/// （索引/外键/DDL）取不到由实现侧置空，不视为失败（沿 executor
/// describe_table 的容忍口径）。
typedef StageStructureFetcher =
    Future<StageStructureData> Function(String table);

/// [AgentUiPort] 的 organisms 实现（T27；经 shell 构造注入 runner.start）。
class AgentUiPortImpl implements AgentUiPort {
  /// 建议消息序列（id 唯一性）。
  int _suggestSeq = 0;

  final WorkbenchStageController _stage;
  final StageStructureFetcher _structureFetcher;
  final AgentSuggestionLandCallback _landSuggestionMessage;

  AgentUiPortImpl({
    required WorkbenchStageController stageController,
    required StageStructureFetcher structureFetcher,
    required AgentSuggestionLandCallback landSuggestionMessage,
  }) : _stage = stageController,
       _structureFetcher = structureFetcher,
       _landSuggestionMessage = landSuggestionMessage;

  // ── 界面五工具（舞台操作；打开时机语义 = T24 controller 内执法）──────

  @override
  Future<AgentUiOutcome> openResultGrid(AgentResultRef ref, String? title) {
    return _guard(() async {
      _stage.openGrid(ref, title);
      return const AgentUiOutcome.ok();
    });
  }

  @override
  Future<AgentUiOutcome> showTableStructure(String table) {
    return _guard(() async {
      final StageStructureData data = await _structureFetcher(table);
      _stage.openStructure(data);
      return const AgentUiOutcome.ok();
    });
  }

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) {
    return _guard(() async {
      // AC5.2/AC5.5：载入不自动执行；目标槽有未保存修改 → 新开槽
      // （controller.openEditorSlot 内单点执法，本层不重复判定）。
      _stage.openEditorSlot(sql);
      return const AgentUiOutcome.ok();
    });
  }

  @override
  Future<AgentUiOutcome> renderChart(AgentResultRef ref, String? chartKind) {
    return _guard(() async {
      // AC5.3：列型不适配 → outcome 失败回喂自纠（不建 tab，避免噪音）；
      // 失败信息给出可自纠方向（换结果 / 换图表类型 / 转建议在经典打开）。
      // 舞台内容槽另有同源判定兜底（T24 `_StageChartContent` 内联错误 +
      // 出口），覆盖不经本端口的图表 tab 入口。
      if (!WorkbenchStageController.isChartable(ref)) {
        return AgentUiOutcome.failure(
          'chart data mismatch: the result has no numeric column, so no chart '
          'kind can render it; query a result with numeric columns, or '
          'suggest opening this SQL in the classic view instead',
        );
      }
      _stage.openChart(ref, chartKind);
      return const AgentUiOutcome.ok();
    });
  }

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) {
    return _guard(() async {
      // ui 规格 §6.3：仅钉入产物条，不改舞台可见性（controller 内执法）。
      _stage.pinArtifact(ref, label);
      return const AgentUiOutcome.ok();
    });
  }

  // ── optimization 旁挂推送（2b.3，R6）──────────────────────────────────

  @override
  Future<AgentUiOutcome> openOptimization(
    PerformanceReport report,
    String sql,
  ) {
    return _guard(() async {
      // 只读推送零执行：optimization tab 纯展示渲染，「应用此索引」由内容
      // 槽回调填编辑器槽（openEditorSlot 载入不自动执行，AC5.2/AC5.5 既有
      // 语义），本端口不触发任何 SQL 执行。
      _stage.openOptimization(StageOptimizationData(sql: sql, report: report));
      return const AgentUiOutcome.ok();
    });
  }

  // ── 跨经典两建议（R6 零自动副作用：只落建议卡消息，应用由人触发）────

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) {
    return _guard(() async {
      _landSuggestionMessage(
        _buildSuggestionMessage('open_in_classic', <String, dynamic>{
          'sql': sql,
        }),
      );
      return const AgentUiOutcome.ok();
    });
  }

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) {
    return _guard(() async {
      _landSuggestionMessage(
        _buildSuggestionMessage('focus_sidebar', <String, dynamic>{
          if (database != null && database.isNotEmpty) 'database': database,
          if (table != null && table.isNotEmpty) 'table': table,
        }),
      );
      return const AgentUiOutcome.ok();
    });
  }

  // ── 内部 ─────────────────────────────────────────────────────────────

  /// 建议卡消息（T26 payload 契约：`agent_suggest` kind + action + payload +
  /// applied:false；runId/stepNo 由宿主落账回调补写）。id 前缀 `agent_sg_`
  /// 与步消息对（`agent_tc_`/`agent_tr_`）区分；type=toolResult +
  /// toolResultData.agent 载荷沿 executor 步消息落账形态（渲染层
  /// `agentPayloadOf` 同源解析）。
  AiMessage _buildSuggestionMessage(
    String action,
    Map<String, dynamic> payload,
  ) {
    return AiMessage(
      id: 'agent_sg_${DateTime.now().millisecondsSinceEpoch}_${_suggestSeq++}',
      isUser: false,
      content: 'agent suggest: $action',
      timestamp: DateTime.now(),
      type: AiMessageType.toolResult,
      toolName: action,
      toolResultSummary: 'agent suggest: $action',
      toolResultData: <String, dynamic>{
        'agent': <String, dynamic>{
          'kind': 'agent_suggest',
          'action': action,
          'payload': payload,
          'applied': false,
        },
      },
      status: AiMessageStatus.completed,
    );
  }

  /// AC15.1 通路：实现侧异常 → 失败 outcome 回喂，不向 runner 抛（T09 契约）。
  Future<AgentUiOutcome> _guard(
    Future<AgentUiOutcome> Function() action,
  ) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      AppLogger.e('AgentUiPortImpl', 'ui dispatch failed', e, stackTrace);
      return AgentUiOutcome.failure('ui action failed: $e');
    }
  }
}
