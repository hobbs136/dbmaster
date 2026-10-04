/// Agent 工具目录（design-ai-agent.md §4.1）。
///
/// 目录是 agent 的第一道权限边界（req §3.0 / AC1.6 / AC7.3）：模型可调用的
/// 工具全集在编译期一次定义，无运行时注册（镜像 SafetyReviewService 的
/// 「构造时传入」风格）；目录外 name 一律不可寻址，调用方回 `UNKNOWN_TOOL`。
///
/// - 17 工具全集一次定义：A1 六工具（数据 5 + 上下文 1）+ A2 八工具（计划 1
///   + 舞台 5 + 跨经典建议 2）+ T4 客户端本地状态三工具（save_saved_query /
///   save_memory / list_memories，milestone 2），以 [AgentToolSpec.milestone]
///   区分——FC-6 无死占位，milestone 解锁工具才进入
///   [AgentToolCatalog.llmToolsFor] 输出与 [AgentToolCatalog.find] 寻址
///   （计划期发现 #2/#6，tasks-ai-agent.md）；
/// - [AgentToolCatalog.activeMilestone] 为编译期常量（A1 = 1；A2 合龙任务
///   T28 改 2 即解锁 8 个 A2 工具，一行切换，不做运行时开关）；
/// - schema 为 OpenAI function schema 四键子集（D4 裁决：type / properties /
///   required / additionalProperties:false，自持 Map，不引 JSON Schema 校验
///   包）；name 为 snake_case、description 为静态英文，对齐 server MCP 先例
///   （dbmaster-server `crates/mcp/src/tools.rs`，FC-3）；
/// - 工具结果回喂错误码全集（design §4.1）以 [AgentToolErrorCodes] 常量落地，
///   供 AgentToolExecutor（T10）回喂消费。
///
/// 本文件为纯数据结构 + 静态目录：零 IO、零运行时状态；services 层禁 import
/// material（组件级 §0 MUST NOT 2）。
library;

/// 工具类别（design §4.1 枚举原文；T4 加性追加 [clientLocal]——客户端本地
/// 状态工具：不触达数据库、不派发界面动作，落 prefs 类本地存储；枚举只加法，
/// 门侧仅消费 [plan] 一档（readOnly 拒判定），新值对判定序零影响）。
enum AgentToolCategory {
  data,
  uiStage,
  uiClassicSuggest,
  context,
  plan,
  clientLocal,
}

/// 权限门档（design §4.1 枚举原文；有序，FC-5 可插新档——只加法不改序）。
enum AgentGateLevel { l0, l05, l1, l2, suggest }

/// 单个工具的声明规格（design §4.1 代码块原文）。
class AgentToolSpec {
  const AgentToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.category,
    required this.gateLevel,
    required this.requiresConnection,
    required this.requiresDatabase,
    required this.milestone,
  });

  /// snake_case 工具名，对齐 server MCP 先例（FC-3）。
  final String name;

  /// LLM-facing 静态英文 description（同 server tools.rs 风格；语义锁定
  /// design §4.1 行为约束列——`submit_action_plan` 写死「提交零执行、须人
  /// 批准」，风险 6 对策）。
  final String description;

  /// 参数 schema：{type, properties, required, additionalProperties:false}
  /// 四键子集（D4；运行时参数收窄校验由 executor 手写，schema 只是提示）。
  final Map<String, dynamic> inputSchema;

  final AgentToolCategory category;

  /// 声明档；数据读取工具运行时可能升 L0.5（design §4.1 字段注）。
  final AgentGateLevel gateLevel;

  /// 无锁定连接 → CONTEXT_REQUIRED（AC7.4）。
  final bool requiresConnection;

  final bool requiresDatabase;

  /// 所属里程碑：1|2|3（A1/A2/A3，D20）。
  final int milestone;
}

/// 工具目录：唯一来源，编译期固定（design §4.1 代码块原文；无运行时注册）。
class AgentToolCatalog {
  const AgentToolCatalog._();

  /// 当前里程碑（编译期常量，tasks-ai-agent.md §6 计划期发现 #6）。
  /// T28（A2 合龙）已切 2：8 个 A2 工具全量进入 llmToolsFor 输出与 find 寻址。
  static const int activeMilestone = 2;

  /// 17 工具全集，声明序 = design §4.1 表序（A1 读面在前、计划/界面殿后）+
  /// T4 客户端本地状态三工具尾追加（契约只加不删，既有序不动）。
  static const List<AgentToolSpec> _specs = <AgentToolSpec>[
    AgentToolSpec(
      name: 'execute_readonly_sql',
      description:
          'Execute one read-only SQL statement against the database '
          'this run is locked to. The statement passes a read-only SQL gate '
          'before execution; write statements (INSERT / UPDATE / DELETE / DDL) '
          'are rejected with WRITE_REJECTED_READONLY_CHANNEL and never reach '
          'the database. Row limits and safety interception match manual '
          'execution in the editor, and the read may be escalated to a '
          'confirmation gate when the pre-read impact analysis flags an '
          'expensive scan. Args: sql — a single SQL statement (multi-statement '
          'scripts are rejected).',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'sql': <String, dynamic>{
            'type': 'string',
            'description': 'Single read-only SQL statement to execute',
          },
        },
        'required': <String>['sql'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.data,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: true,
      requiresDatabase: true,
      milestone: 1,
    ),
    AgentToolSpec(
      name: 'list_tables',
      description:
          'List the tables and views of the database this run is '
          'locked to. The scope comes from the context snapshot taken at run '
          'start and does not drift when the user switches context mid-run. '
          'Start here, then drill down with describe_table / get_sample_data. '
          'Args: none.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
        'additionalProperties': false,
      },
      category: AgentToolCategory.data,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: true,
      requiresDatabase: true,
      milestone: 1,
    ),
    AgentToolSpec(
      name: 'describe_table',
      description:
          'Describe one table of the current database: columns, '
          'indexes, foreign keys and the CREATE TABLE DDL where the dialect '
          'provides it. Dialect differences are reported as-is. Args: table — '
          'table name as returned by list_tables.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'table': <String, dynamic>{
            'type': 'string',
            'description': 'Table name as returned by list_tables',
          },
        },
        'required': <String>['table'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.data,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: true,
      requiresDatabase: true,
      milestone: 1,
    ),
    AgentToolSpec(
      name: 'get_sample_data',
      description:
          'Fetch sample rows from one table (SELECT * ... LIMIT n). '
          'The read passes the same read-only validation and pre-read impact '
          'analysis as execute_readonly_sql; NoSQL connections reject this '
          'tool with UNSUPPORTED_DIALECT. Args: table — table name as '
          'returned by list_tables; limit — optional row count, clamped to '
          '1-100, default 10.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'table': <String, dynamic>{
            'type': 'string',
            'description': 'Table name as returned by list_tables',
          },
          'limit': <String, dynamic>{
            'type': 'integer',
            'description': 'Optional row count, clamped to 1-100, default 10',
          },
        },
        'required': <String>['table'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.data,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: true,
      requiresDatabase: true,
      milestone: 1,
    ),
    AgentToolSpec(
      name: 'explain_plan',
      description:
          'Return the execution plan for a SQL statement WITHOUT '
          'running it (EXPLAIN only — the statement itself never executes; '
          'unsupported dialects fail with UNSUPPORTED_DIALECT). Use it to '
          'check scan shape and cost before execute_readonly_sql. Args: sql — '
          'the statement to explain.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'sql': <String, dynamic>{
            'type': 'string',
            'description': 'SQL statement to explain (never executed)',
          },
        },
        'required': <String>['sql'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.data,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: true,
      requiresDatabase: true,
      milestone: 1,
    ),
    AgentToolSpec(
      name: 'get_current_context',
      description:
          'Report the context snapshot this run is bound to: '
          'connection name, current database, database type and read-only '
          'flag — the same values the workbench context chips show. Works '
          'when no connection is locked (the fields are then reported as '
          'empty). Args: none.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
        'additionalProperties': false,
      },
      category: AgentToolCategory.context,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 1,
    ),
    AgentToolSpec(
      name: 'submit_action_plan',
      description:
          'Submit a multi-step write plan for human approval. This '
          'tool SUBMITS ONLY and never executes anything: execution starts '
          'exclusively after the user approves the plan card. Each step must '
          'carry either rollback_sql (the inverse statement) or irreversible: '
          'true — exactly one of the two; missing both or giving both is '
          'rejected with INVALID_ARGUMENTS. Read-only connections reject plan '
          'submission with READONLY_CONNECTION. Args: steps — ordered write '
          'steps, exactly one SQL statement per step; rationale — optional '
          'short explanation of the intent.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'steps': <String, dynamic>{
            'type': 'array',
            'description':
                'Ordered write steps; executed in order only '
                'after user approval',
            'items': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'sql': <String, dynamic>{
                  'type': 'string',
                  'description':
                      'Single SQL statement (one statement per '
                      'step)',
                },
                'rollback_sql': <String, dynamic>{
                  'type': 'string',
                  'description':
                      'Inverse statement that undoes this step '
                      '(mutually exclusive with irreversible)',
                },
                'irreversible': <String, dynamic>{
                  'type': 'boolean',
                  'description':
                      'Declare the step has no rollback (mutually '
                      'exclusive with rollback_sql)',
                },
                'note': <String, dynamic>{
                  'type': 'string',
                  'description': 'Short human-readable note about this step',
                },
              },
              'required': <String>['sql'],
              'additionalProperties': false,
            },
          },
          'rationale': <String, dynamic>{
            'type': 'string',
            'description': 'Short explanation of the plan intent',
          },
        },
        'required': <String>['steps'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.plan,
      gateLevel: AgentGateLevel.l1,
      requiresConnection: true,
      requiresDatabase: true,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'open_result_grid',
      description:
          'Open a result produced earlier in this run as a full grid '
          'tab in the workbench stage (all rows within the row limit — no '
          're-execution). Args: result_ref — reference id (resultRef) of an '
          'earlier tool result in this run; title — optional tab title.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'result_ref': <String, dynamic>{
            'type': 'string',
            'description':
                'Reference id (resultRef) of an earlier tool '
                'result in this run',
          },
          'title': <String, dynamic>{
            'type': 'string',
            'description': 'Optional tab title',
          },
        },
        'required': <String>['result_ref'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.uiStage,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'show_table_structure',
      description:
          'Show the structure of one table as a structure card in '
          'the workbench stage (columns / indexes / keys, fetched live from '
          'the current connection). Args: table — table name as returned by '
          'list_tables.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'table': <String, dynamic>{
            'type': 'string',
            'description': 'Table name as returned by list_tables',
          },
        },
        'required': <String>['table'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.uiStage,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: true,
      requiresDatabase: true,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'open_sql_editor',
      description:
          'Load SQL into a workbench editor slot WITHOUT executing '
          'it. If the target slot has unsaved changes, a new slot is opened '
          'instead — user edits are never overwritten. Args: sql — the SQL '
          'text to load.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'sql': <String, dynamic>{
            'type': 'string',
            'description':
                'SQL text to load into an editor slot (not '
                'executed)',
          },
        },
        'required': <String>['sql'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.uiStage,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'render_chart',
      description:
          'Render a result produced earlier in this run as a chart '
          'in the workbench stage. Data that does not fit a chart fails with '
          'a clear error so another presentation can be chosen. Args: '
          'result_ref — reference id of an earlier tool result in this run; '
          'chart_kind — optional chart type hint.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'result_ref': <String, dynamic>{
            'type': 'string',
            'description':
                'Reference id of an earlier tool result in this '
                'run',
          },
          'chart_kind': <String, dynamic>{
            'type': 'string',
            'description': 'Optional chart type hint',
          },
        },
        'required': <String>['result_ref'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.uiStage,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'pin_artifact',
      description:
          'Pin a result produced earlier in this run (SQL + context '
          '+ row snapshot) to the artifact strip so it stays reachable as the '
          'conversation advances. Args: result_ref — reference id of an '
          'earlier tool result in this run; label — optional short label.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'result_ref': <String, dynamic>{
            'type': 'string',
            'description':
                'Reference id of an earlier tool result in this '
                'run',
          },
          'label': <String, dynamic>{
            'type': 'string',
            'description': 'Optional short label for the artifact strip',
          },
        },
        'required': <String>['result_ref'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.uiStage,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'open_in_classic',
      description:
          'Suggest opening a SQL statement in the classic editor. '
          'Producing the suggestion has no side effect; nothing happens '
          'unless the user clicks the card — clicking opens a NEW classic '
          'query tab (never overwrites existing tabs) and is audited. Args: '
          'sql — the SQL text to open.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'sql': <String, dynamic>{
            'type': 'string',
            'description': 'SQL text to open in the classic editor',
          },
        },
        'required': <String>['sql'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.uiClassicSuggest,
      gateLevel: AgentGateLevel.suggest,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'focus_sidebar',
      description:
          'Suggest locating a database or table in the sidebar. '
          'Producing the suggestion has no side effect; nothing happens '
          'unless the user clicks the card — clicking moves the sidebar '
          'selection and is audited. Args: database — optional database name; '
          'table — optional table name.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'database': <String, dynamic>{
            'type': 'string',
            'description': 'Optional database name to locate',
          },
          'table': <String, dynamic>{
            'type': 'string',
            'description': 'Optional table name to locate',
          },
        },
        'required': <String>[],
        'additionalProperties': false,
      },
      category: AgentToolCategory.uiClassicSuggest,
      gateLevel: AgentGateLevel.suggest,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
    // ── T4 客户端本地状态三工具（clientLocal：不触达 DB、不派界面动作）──
    AgentToolSpec(
      name: 'save_saved_query',
      description:
          'Save a SQL statement as a named saved query for the '
          'connection this run is locked to. This is a local client storage '
          'operation — nothing is sent to the database. The saved query '
          'appears in the classic editor saved-queries list with the locked '
          'connection/database binding taken from the run context. Names must '
          'be unique per connection: a conflicting name fails with '
          'SAVED_QUERY_CONFLICT — pick another name or ask the user to '
          'rename/delete the existing entry. At most 20 saved queries are '
          'kept; when the limit is exceeded the oldest entry is dropped '
          'automatically. Throttled to at most 3 saves per agent run: '
          'further save attempts in the same run fail with '
          'SAVED_QUERY_LIMIT_EXCEEDED — stop saving and tell the user they '
          'can organize saved queries manually in the editor. Args: name — '
          'saved query name; sql — the SQL text to store.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'name': <String, dynamic>{
            'type': 'string',
            'description': 'Saved query name (unique per connection)',
          },
          'sql': <String, dynamic>{
            'type': 'string',
            'description': 'SQL text to store',
          },
        },
        'required': <String>['name', 'sql'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.clientLocal,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: true,
      requiresDatabase: false,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'save_memory',
      description:
          'Remember a short fact for future conversations (persisted '
          'locally, never sent to the database): table/column semantics, '
          'business rules, user preferences. Args: scope — "connection" '
          '(visible only with the locked connection) or "global" (visible '
          'with every connection); when omitted, defaults to "connection" if '
          'a connection is locked, otherwise "global". scope "connection" '
          'without a locked connection fails with CONTEXT_REQUIRED. subject — '
          'optional short topic tag; use the "table.column" shape for field '
          'semantics so describe_table can surface the note next to the '
          'table structure. content — the fact itself (truncated to 500 '
          'characters).',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'scope': <String, dynamic>{
            'type': 'string',
            'description':
                '"connection" (default when a connection is '
                'locked) or "global"',
          },
          'subject': <String, dynamic>{
            'type': 'string',
            'description': 'Optional topic tag, e.g. "orders.status"',
          },
          'content': <String, dynamic>{
            'type': 'string',
            'description':
                'The fact to remember (truncated to 500 '
                'characters)',
          },
        },
        'required': <String>['content'],
        'additionalProperties': false,
      },
      category: AgentToolCategory.clientLocal,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
    AgentToolSpec(
      name: 'list_memories',
      description:
          'List the memories already saved: global entries plus the '
          'entries of the locked connection (if any), with id, subject and a '
          'content excerpt each. Check this before save_memory to avoid '
          'duplicates. Args: none.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
        'additionalProperties': false,
      },
      category: AgentToolCategory.clientLocal,
      gateLevel: AgentGateLevel.l0,
      requiresConnection: false,
      requiresDatabase: false,
      milestone: 2,
    ),
  ];

  /// 返回 milestone <= [milestone] 的工具规格（design §4.1：「≤ 当前里程碑」；
  /// 显式传参供 runner 传 [activeMilestone] 与测试注入其他里程碑）。
  static List<AgentToolSpec> specsFor({required int milestone}) => _specs
      .where((AgentToolSpec spec) => spec.milestone <= milestone)
      .toList();

  /// 按名查找当前里程碑内可寻址的工具；目录外或尚未解锁（milestone >
  /// [activeMilestone]）的 name 一律返回 null → 调用方回 UNKNOWN_TOOL
  /// （AC1.6/AC7.3；A1 期计划/界面工具不可寻址——D5「A1 目录无此工具」，
  /// 幻觉调用不进门判定）。全集定义仍在 [_specs]，specsFor(milestone: 2+) 可查。
  static AgentToolSpec? find(String name) {
    for (final AgentToolSpec spec in _specs) {
      if (spec.name == name && spec.milestone <= activeMilestone) {
        return spec;
      }
    }
    return null;
  }

  /// OpenAI function schema 形态的工具列表（design §4.1：→ AiClient.chat
  /// (tools:)；Anthropic 路径由 AnthropicConverter.convertTools 协议转换）。
  /// parameters 复用 [AgentToolSpec.inputSchema] 同一 const 实例（零拷贝）。
  static List<Map<String, dynamic>> llmToolsFor({required int milestone}) =>
      specsFor(milestone: milestone).map(_toLlmTool).toList();

  /// 单 spec → OpenAI tool 条目（type: function + function 三键）。
  static Map<String, dynamic> _toLlmTool(AgentToolSpec spec) =>
      <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': spec.name,
          'description': spec.description,
          'parameters': spec.inputSchema,
        },
      };
}

/// 工具结果回喂错误码全集（design §4.1 末段：静态码 + 脱敏 detail，镜像
/// server `write.rs` 审计纪律）。与目录同文件落地（本任务裁决），供
/// AgentToolExecutor（T10）回喂与审计消费；码值不改——LLM 依赖码名自纠。
class AgentToolErrorCodes {
  const AgentToolErrorCodes._();

  /// 目录外工具名（AC1.6）。
  static const String unknownTool = 'UNKNOWN_TOOL';

  /// 参数缺失 / 类型不符 / 语义校验不过（如 rollback 与 irreversible 二选一）。
  static const String invalidArguments = 'INVALID_ARGUMENTS';

  /// requiresConnection 且 run 快照无锁定连接（AC7.4）。
  static const String contextRequired = 'CONTEXT_REQUIRED';

  /// readOnly 连接 × 写形态动作（NF2.3）。
  static const String readonlyConnection = 'READONLY_CONNECTION';

  /// 写语句走只读通道（AC4.2；detail 含计划路径指引）。
  static const String writeRejectedReadonlyChannel =
      'WRITE_REJECTED_READONLY_CHANNEL';

  /// 方言不支持该能力（sample/explain 于 NoSQL、EXPLAIN 于网关壳等）。
  static const String unsupportedDialect = 'UNSUPPORTED_DIALECT';

  /// L0.5 确认卡被人拒（含停止时 Completer 以取消解决）。
  static const String gateRejected = 'GATE_REJECTED';

  /// 行动计划被人拒（AC9.2：零副作用，对话继续）。
  static const String planRejected = 'PLAN_REJECTED';

  /// 终态计划 planId 重放（AC11.4 防重）。
  static const String planAlreadyExecuted = 'PLAN_ALREADY_EXECUTED';

  /// 步数预算耗尽的占位回喂（AC2.2，保持协议完整）。
  static const String stepLimitReached = 'STEP_LIMIT_REACHED';

  /// handler 执行异常（detail 过 redactSecrets，NF2.2；模型可据此自纠）。
  static const String executionFailed = 'EXECUTION_FAILED';

  /// save_saved_query 同连接同名冲突（T4 加性扩展；模型自纠：换名或请
  /// 用户整理既有条目）。
  static const String savedQueryConflict = 'SAVED_QUERY_CONFLICT';

  /// save_saved_query 单 run 调用超限（F-01 安全审查加性扩展；模型自纠：
  /// 停止保存并转告用户可在编辑器手动整理）。
  static const String savedQueryLimitExceeded = 'SAVED_QUERY_LIMIT_EXCEEDED';
}
