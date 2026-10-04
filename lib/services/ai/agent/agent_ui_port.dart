/// Agent 界面派发端口与结果引用（design-ai-agent.md §4.5，D8）。
///
/// services 层只定义抽象契约：AgentLoopRunner（T11）经可选 `uiPort` 参数持有
/// 本接口，使回路与门可脱离 UI 单测（NF5.3）；organisms 侧实现（A2 T27
/// `agent_ui_port_impl`）经 shell 装配注入；外部 MCP 复用 agent 回路时换实现
/// 即可（FC-4）。
///
/// 本文件为纯 Dart 契约面：禁 import material（组件级 §0 MUST NOT 2 / T09
/// 约束）；抽象接口 + 值对象 only，零实现、零 IO（tasks-ai-agent.md §3 T09）。
library;

import '../../../models/query_optimizer/execution_plan.dart'
    show PerformanceReport;

/// 数据引用：工具结果不重复传全量，以 run 内引用 ID 寻址（舞台/图表/产物条
/// 消费；design §4.5 原文）。
///
/// 「内存引用，不复制」：构造不做防御性拷贝，[rows] 与执行侧持有同一 List
/// 实例（行限内全量）。相等性取默认恒等语义——[refId] 仅在单次 run 内唯一
/// （`res_<stepNo>`，由 executor 工具执行时登记，T10/T28），跨 run 的同
/// refId 不代表同一结果，故不以 refId 实现结构相等。
class AgentResultRef {
  /// 常量构造；字段不可变。
  const AgentResultRef({
    required this.refId,
    required this.sql,
    required this.rowCount,
    required this.columns,
    required this.rows,
  });

  /// run 内引用 ID：`res_<stepNo>`。
  final String refId;

  /// 产生该结果的语句（重执行/打开经典用）。
  final String sql;

  /// 结果总行数（[rows] 可能被行限截断，本字段保留全量口径）。
  final int rowCount;

  /// 结果列名。
  final List<String> columns;

  /// 行限内全量行数据（内存引用，不复制）。
  final List<Map<String, dynamic>> rows;
}

/// 界面动作执行结论（design §4.5：`{ok, message?}`——失败回喂 LLM 自纠，
/// AC15.1 通路）。
///
/// 形态取小类而非 record（tasks T09 允许自决项；对外字段名 `ok`/`message`
/// 锁定），理由：
/// ① 字段可挂文档注释（[message] 的「自纠通路」语义需要承载处）；
/// ② [AgentUiOutcome.failure] 具名构造在构造点强制携带 message——失败无
/// message 则 LLM 无从自纠；字段仍按设计保持可空；
/// ③ 沿代码库值对象先例（const 构造 + final 字段，同文件族 T04 风格），
/// services 层无 record 先例。
class AgentUiOutcome {
  /// 成功结论；[message] 可选附加信息。
  const AgentUiOutcome.ok({this.message}) : ok = true;

  /// 失败结论；[failureMessage] 必填——回喂 LLM 供自纠（AC15.1）。
  const AgentUiOutcome.failure(String failureMessage)
    : ok = false,
      message = failureMessage;

  /// 动作是否成功。
  final bool ok;

  /// 附加信息；失败时为给 LLM 的可读原因（自纠通路）。
  final String? message;

  /// 值相等：按 (ok, message) 判等，供 fake 实现与测试比对。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentUiOutcome && other.ok == ok && other.message == message;

  @override
  int get hashCode => Object.hash(ok, message);

  @override
  String toString() => 'AgentUiOutcome(ok: $ok, message: $message)';
}

/// Agent → 工作台界面的派发端口（design §4.5 七方法，签名一字不改；
/// 2b.3 加性扩展第八方法 [openOptimization]——只读推送零执行，R6）。
///
/// - D8：本抽象由 services 层定义、organisms 侧（T27）实现注入；A1 期 runner
///   的 `uiPort` 参数可空（计划期发现 #7），无实现即不派发界面动作；
/// - FC-4：接口为 UI 无关纯 Dart（禁 material import），外部 MCP 复用 agent
///   回路时换实现即可；
/// - 全部方法返回 [AgentUiOutcome]：实现侧须把自身异常转化为失败 outcome
///   回喂（T27 边界清单「port 方法异常 → outcome 失败回喂，不崩 run」），
///   不得向 runner 抛出未处理异常。
abstract class AgentUiPort {
  /// 舞台网格呈现工具结果全量行（行限内，[AgentResultRef.refId] 寻址）。
  Future<AgentUiOutcome> openResultGrid(AgentResultRef ref, String? title);

  /// 舞台结构卡呈现表结构。
  Future<AgentUiOutcome> showTableStructure(String table);

  /// 舞台编辑器槽载入 SQL（不自动执行，AC5.2；未保存保护由实现侧负责）。
  Future<AgentUiOutcome> openSqlEditor(String sql);

  /// 舞台图表呈现；列型不适配等失败经 outcome 回喂（AC5.3）。
  Future<AgentUiOutcome> renderChart(AgentResultRef ref, String? chartKind);

  /// 产物条钉住引用（建 pinned tab，不改舞台可见性，ui 规格 §6.3）。
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label);

  /// 建议卡：在经典界面打开 SQL（零自动副作用，应用由人触发，AC6.2）。
  Future<AgentUiOutcome> suggestOpenInClassic(String sql);

  /// 建议卡：侧栏定位（库/表；应用落审计，AC6.4）。
  Future<AgentUiOutcome> suggestFocusSidebar({String? database, String? table});

  /// 舞台 optimization tab 推送（2b.3，R6 加性方法）：executor `explain_plan`
  /// 只读通道成功取到 plan 行后组装 [PerformanceReport] 经本方法推入舞台
  /// （[sql] = 原 SQL 精确串，去重键）。**只读推送、零执行**——报告纯展示
  /// 渲染（计划树/瓶颈/索引推荐/重写建议），本方法不触发任何 SQL 执行；
  /// 「应用此索引」由 UI 层用户动作触发且只填编辑器槽。调用方约定：
  /// uiPort 为 null（未装配）时**跳过本方法不失败**（结果照常回模型，
  /// fail-closed 语义同 [_DetachedUiPort] 缺席占位）。
  Future<AgentUiOutcome> openOptimization(PerformanceReport report, String sql);
}

/// design §4.3 UI 决策结果类型，T11 runner 与卡面共同消费。
///
/// 原定落 T11 runner 文件；因 organisms（T12 确认卡）先行需要该类型、且
/// services 不得反向 import organisms（依赖单向），按主代理裁决改落本文件
/// 尾部（纯加法）。runner 在途 Completer 的解决值与门卡消息的结论值共用
/// 本枚举；「已随运行取消」与用户取消的呈现区分由卡面按交互记忆处理
/// （`agent_confirm_card.dart` 类注释），枚举本身不增第四值。
enum GateCardResult {
  /// 用户允许本次调用（单次授权）。
  approved,

  /// 用户勾选会话放行后主动作的结论：本连接整个会话同档读取不再询问。
  approvedForSession,

  /// 用户拒绝；运行停止时 runner 亦以本值解决在途 Completer（§6.4）。
  rejected,
}
