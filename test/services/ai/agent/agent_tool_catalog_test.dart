/// T04 AgentToolCatalog 单测（tasks-ai-agent.md §3 T04）。
///
/// 覆盖：14 工具全集完整性、milestone 过滤（A1 六 / A2 全 14）、find 命中 /
/// 目录外 / A1 期 A2 工具不可寻址、llmToolsFor 输出 OpenAI function schema
/// 结构断言（四键子集 + additionalProperties:false，D4/FC-3）、门档与类别
/// 对 design §4.1 表、错误码全集。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart';

/// design §4.1 表的 14 工具名全集。
const Set<String> _allNames = <String>{
  'execute_readonly_sql',
  'list_tables',
  'describe_table',
  'get_sample_data',
  'explain_plan',
  'get_current_context',
  'submit_action_plan',
  'open_result_grid',
  'show_table_structure',
  'open_sql_editor',
  'render_chart',
  'pin_artifact',
  'open_in_classic',
  'focus_sidebar',
};

/// A1 档六工具（数据 5 + 上下文 1，tasks §6 计划期发现 #2）。
const Set<String> _a1Names = <String>{
  'execute_readonly_sql',
  'list_tables',
  'describe_table',
  'get_sample_data',
  'explain_plan',
  'get_current_context',
};

/// A2 档八工具（计划 1 + 舞台 5 + 跨经典建议 2）。
const Set<String> _a2Names = <String>{
  'submit_action_plan',
  'open_result_grid',
  'show_table_structure',
  'open_sql_editor',
  'render_chart',
  'pin_artifact',
  'open_in_classic',
  'focus_sidebar',
};

/// 按 name 取全集内 spec（不受 activeMilestone 过滤影响，供 A2 工具断言）。
AgentToolSpec _specByName(String name) {
  for (final AgentToolSpec spec in AgentToolCatalog.specsFor(milestone: 3)) {
    if (spec.name == name) {
      return spec;
    }
  }
  fail('tool not found in catalog: $name');
}

Set<String> _llmNames(List<Map<String, dynamic>> tools) => tools
    .map((Map<String, dynamic> tool) =>
        (tool['function'] as Map<String, dynamic>)['name'] as String)
    .toSet();

void main() {
  group('14 工具全集完整性', () {
    test('specsFor(3) 返回 14 工具，name 集合与 design §4.1 表一致', () {
      final List<AgentToolSpec> specs =
          AgentToolCatalog.specsFor(milestone: 3);
      expect(specs, hasLength(14));
      expect(specs.map((AgentToolSpec s) => s.name).toSet(), _allNames);
    });

    test('每工具 name 为 snake_case、description 非空、milestone ∈ {1, 2}', () {
      for (final AgentToolSpec spec
          in AgentToolCatalog.specsFor(milestone: 3)) {
        expect(spec.name, matches(RegExp(r'^[a-z][a-z0-9_]*$')),
            reason: spec.name);
        expect(spec.description, isNotEmpty, reason: spec.name);
        expect(spec.milestone, anyOf(1, 2), reason: spec.name);
      }
    });

    test('无 milestone 3 工具（FC-6：不预实现 A3 死占位）', () {
      final Set<int> milestones = AgentToolCatalog.specsFor(milestone: 3)
          .map((AgentToolSpec s) => s.milestone)
          .toSet();
      expect(milestones.difference(<int>{1, 2}), isEmpty);
    });
  });

  group('milestone 过滤', () {
    test('specsFor(1) 恰含 A1 六工具（数据 5 + 上下文 1），无 A2 工具', () {
      final List<AgentToolSpec> specs =
          AgentToolCatalog.specsFor(milestone: 1);
      expect(specs.map((AgentToolSpec s) => s.name).toSet(), _a1Names);
      expect(specs.map((AgentToolSpec s) => s.name).toSet().length, 6);
    });

    test('specsFor(2) 恰含 14；specsFor(3) 与 specsFor(2) 一致（无 A3 工具）',
        () {
      final List<AgentToolSpec> m2 =
          AgentToolCatalog.specsFor(milestone: 2);
      expect(m2, hasLength(14));
      expect(m2.map((AgentToolSpec s) => s.name).toSet(), _allNames);
      final Set<String> m3Names = AgentToolCatalog.specsFor(milestone: 3)
          .map((AgentToolSpec s) => s.name)
          .toSet();
      expect(m3Names, m2.map((AgentToolSpec s) => s.name).toSet());
    });

    test('llmToolsFor(1) 恰含 6 且不含任何 A2 工具；llmToolsFor(2) 恰含 14', () {
      final List<Map<String, dynamic>> t1 =
          AgentToolCatalog.llmToolsFor(milestone: 1);
      expect(t1, hasLength(6));
      final Set<String> names1 = _llmNames(t1);
      expect(names1, _a1Names);
      expect(names1.intersection(_a2Names), isEmpty);

      final List<Map<String, dynamic>> t2 =
          AgentToolCatalog.llmToolsFor(milestone: 2);
      expect(t2, hasLength(14));
      expect(_llmNames(t2), _allNames);
    });

    test('activeMilestone == 2（T28 A2 合龙相位：14 工具全量可寻址）', () {
      // T28：A1 期 == 1 的相位断言随合龙翻转为 2（任务书预留的切换点）。
      expect(AgentToolCatalog.activeMilestone, 2);
      expect(
        AgentToolCatalog.specsFor(milestone: AgentToolCatalog.activeMilestone),
        hasLength(14),
      );
    });
  });

  group('find（目录寻址）', () {
    test('命中 A1 工具，返回同名 spec', () {
      final AgentToolSpec? spec = AgentToolCatalog.find('list_tables');
      expect(spec, isNotNull);
      expect(spec?.name, 'list_tables');
      expect(spec?.category, AgentToolCategory.data);
    });

    test('目录外 name 返回 null（AC1.6 / AC7.3 无切换类工具）', () {
      expect(AgentToolCatalog.find('drop_database'), isNull);
      expect(AgentToolCatalog.find('switch_connection'), isNull);
      expect(AgentToolCatalog.find(''), isNull);
    });

    test('A2 相位（T28）：A2 八工具经 find 可寻址，全集与过滤一致', () {
      // T28 后 A2 工具进入可寻址集（A1 期不可寻址断言随合龙翻转）。
      for (final String name in _a2Names) {
        expect(AgentToolCatalog.find(name), isNotNull, reason: name);
      }
      expect(AgentToolCatalog.find('drop_database'), isNull);
    });
  });

  group('llmToolsFor 输出结构（OpenAI function schema）', () {
    test('条目顶层为 type=function + function{name, description, parameters}',
        () {
      for (final Map<String, dynamic> tool
          in AgentToolCatalog.llmToolsFor(milestone: 2)) {
        final Map<String, dynamic> function =
            tool['function'] as Map<String, dynamic>;
        expect(tool.keys.toSet(), <String>{'type', 'function'},
            reason: function['name'] as String);
        expect(tool['type'], 'function');
        expect(function.keys.toSet(),
            <String>{'name', 'description', 'parameters'},
            reason: function['name'] as String);
        expect(function['name'], isA<String>());
        expect(function['description'], isA<String>());
        expect(function['parameters'], isA<Map<String, dynamic>>());
      }
    });

    test('parameters 恰为四键子集且 additionalProperties:false（D4 / FC-3）',
        () {
      for (final Map<String, dynamic> tool
          in AgentToolCatalog.llmToolsFor(milestone: 2)) {
        final Map<String, dynamic> function =
            tool['function'] as Map<String, dynamic>;
        final String name = function['name'] as String;
        final Map<String, dynamic> parameters =
            function['parameters'] as Map<String, dynamic>;
        expect(parameters.keys.toSet(),
            <String>{'type', 'properties', 'required', 'additionalProperties'},
            reason: name);
        expect(parameters['type'], 'object', reason: name);
        expect(parameters['additionalProperties'], false, reason: name);
        expect(parameters['properties'], isA<Map<dynamic, dynamic>>(),
            reason: name);
        expect(parameters['required'], isA<List<dynamic>>(), reason: name);
      }
    });

    test('required 的每个键都在 properties 中声明（无悬空 required）', () {
      for (final Map<String, dynamic> tool
          in AgentToolCatalog.llmToolsFor(milestone: 2)) {
        final Map<String, dynamic> function =
            tool['function'] as Map<String, dynamic>;
        final String name = function['name'] as String;
        final Map<String, dynamic> parameters =
            function['parameters'] as Map<String, dynamic>;
        final Map<dynamic, dynamic> properties =
            parameters['properties'] as Map<dynamic, dynamic>;
        for (final dynamic key in parameters['required'] as List<dynamic>) {
          expect(properties.containsKey(key), isTrue,
              reason: '$name required key "$key" missing in properties');
        }
      }
    });
  });

  group('schema 抽样断言（逐工具参数面）', () {
    test('execute_readonly_sql：sql 必填 string', () {
      final Map<String, dynamic> schema =
          _specByName('execute_readonly_sql').inputSchema;
      expect(schema['required'], <String>['sql']);
      final Map<dynamic, dynamic> sql =
          (schema['properties'] as Map<dynamic, dynamic>)['sql']
              as Map<dynamic, dynamic>;
      expect(sql['type'], 'string');
    });

    test('get_sample_data：table 必填、limit 可选 integer（不在 required）', () {
      final Map<String, dynamic> schema =
          _specByName('get_sample_data').inputSchema;
      expect(schema['required'], <String>['table']);
      final Map<dynamic, dynamic> properties =
          schema['properties'] as Map<dynamic, dynamic>;
      expect(properties.keys.toSet(), <String>{'table', 'limit'});
      final Map<dynamic, dynamic> limit =
          properties['limit'] as Map<dynamic, dynamic>;
      expect(limit['type'], 'integer');
      expect((schema['required'] as List<dynamic>).contains('limit'), isFalse);
    });

    test('get_current_context：空参数（properties 与 required 皆空）', () {
      final Map<String, dynamic> schema =
          _specByName('get_current_context').inputSchema;
      expect(
          (schema['properties'] as Map<dynamic, dynamic>), isEmpty);
      expect(schema['required'], <String>[]);
    });

    test('submit_action_plan：steps 必填数组，嵌套 item 锁 sql/rollback_sql/'
        'irreversible/note 且 additionalProperties:false', () {
      final Map<String, dynamic> schema =
          _specByName('submit_action_plan').inputSchema;
      expect(schema['required'], <String>['steps']);
      final Map<dynamic, dynamic> steps =
          (schema['properties'] as Map<dynamic, dynamic>)['steps']
              as Map<dynamic, dynamic>;
      expect(steps['type'], 'array');
      final Map<dynamic, dynamic> item = steps['items'] as Map<dynamic, dynamic>;
      expect(item['additionalProperties'], false);
      expect(
        (item['properties'] as Map<dynamic, dynamic>).keys.toSet(),
        <String>{'sql', 'rollback_sql', 'irreversible', 'note'},
      );
      expect(item['required'], <String>['sql']);
    });
  });

  group('门档与类别（design §4.1 表列对齐）', () {
    test('A1 五数据工具：data / l0 / 依赖连接与库', () {
      const List<String> dataTools = <String>[
        'execute_readonly_sql',
        'list_tables',
        'describe_table',
        'get_sample_data',
        'explain_plan',
      ];
      for (final String name in dataTools) {
        final AgentToolSpec spec = _specByName(name);
        expect(spec.category, AgentToolCategory.data, reason: name);
        expect(spec.gateLevel, AgentGateLevel.l0, reason: name);
        expect(spec.requiresConnection, isTrue, reason: name);
        expect(spec.requiresDatabase, isTrue, reason: name);
        expect(spec.milestone, 1, reason: name);
      }
    });

    test('get_current_context：context 类、l0、无需连接（无上下文也报告空态）', () {
      final AgentToolSpec spec = _specByName('get_current_context');
      expect(spec.category, AgentToolCategory.context);
      expect(spec.gateLevel, AgentGateLevel.l0);
      expect(spec.requiresConnection, isFalse);
      expect(spec.requiresDatabase, isFalse);
    });

    test('submit_action_plan：plan / l1 / A2，写形态依赖连接与库', () {
      final AgentToolSpec spec = _specByName('submit_action_plan');
      expect(spec.category, AgentToolCategory.plan);
      expect(spec.gateLevel, AgentGateLevel.l1);
      expect(spec.milestone, 2);
      expect(spec.requiresConnection, isTrue);
      expect(spec.requiresDatabase, isTrue);
    });

    test('A2 舞台 5 工具：uiStage / l0；result_ref 类不要求连接，'
        'show_table_structure 要求连接与库', () {
      const List<String> stageTools = <String>[
        'open_result_grid',
        'show_table_structure',
        'open_sql_editor',
        'render_chart',
        'pin_artifact',
      ];
      for (final String name in stageTools) {
        final AgentToolSpec spec = _specByName(name);
        expect(spec.category, AgentToolCategory.uiStage, reason: name);
        expect(spec.gateLevel, AgentGateLevel.l0, reason: name);
        expect(spec.milestone, 2, reason: name);
      }
      expect(_specByName('open_result_grid').requiresConnection, isFalse);
      expect(_specByName('render_chart').requiresConnection, isFalse);
      expect(_specByName('pin_artifact').requiresConnection, isFalse);
      expect(_specByName('open_sql_editor').requiresConnection, isFalse);
      expect(_specByName('show_table_structure').requiresConnection, isTrue);
      expect(_specByName('show_table_structure').requiresDatabase, isTrue);
    });

    test('跨经典 2 工具：uiClassicSuggest / suggest 档 / 零自动副作用形态', () {
      for (final String name in const <String>['open_in_classic', 'focus_sidebar']) {
        final AgentToolSpec spec = _specByName(name);
        expect(spec.category, AgentToolCategory.uiClassicSuggest, reason: name);
        expect(spec.gateLevel, AgentGateLevel.suggest, reason: name);
        expect(spec.milestone, 2, reason: name);
        expect(spec.requiresConnection, isFalse, reason: name);
        expect(spec.requiresDatabase, isFalse, reason: name);
      }
    });
  });

  group('错误码全集（design §4.1）', () {
    test('11 个常量值与全集逐一对应', () {
      const List<String> codes = <String>[
        AgentToolErrorCodes.unknownTool,
        AgentToolErrorCodes.invalidArguments,
        AgentToolErrorCodes.contextRequired,
        AgentToolErrorCodes.readonlyConnection,
        AgentToolErrorCodes.writeRejectedReadonlyChannel,
        AgentToolErrorCodes.unsupportedDialect,
        AgentToolErrorCodes.gateRejected,
        AgentToolErrorCodes.planRejected,
        AgentToolErrorCodes.planAlreadyExecuted,
        AgentToolErrorCodes.stepLimitReached,
        AgentToolErrorCodes.executionFailed,
      ];
      expect(codes.toSet(), <String>{
        'UNKNOWN_TOOL',
        'INVALID_ARGUMENTS',
        'CONTEXT_REQUIRED',
        'READONLY_CONNECTION',
        'WRITE_REJECTED_READONLY_CHANNEL',
        'UNSUPPORTED_DIALECT',
        'GATE_REJECTED',
        'PLAN_REJECTED',
        'PLAN_ALREADY_EXECUTED',
        'STEP_LIMIT_REACHED',
        'EXECUTION_FAILED',
      });
    });

    test('错误码互不重复且为 UPPER_SNAKE 形态', () {
      const List<String> codes = <String>[
        AgentToolErrorCodes.unknownTool,
        AgentToolErrorCodes.invalidArguments,
        AgentToolErrorCodes.contextRequired,
        AgentToolErrorCodes.readonlyConnection,
        AgentToolErrorCodes.writeRejectedReadonlyChannel,
        AgentToolErrorCodes.unsupportedDialect,
        AgentToolErrorCodes.gateRejected,
        AgentToolErrorCodes.planRejected,
        AgentToolErrorCodes.planAlreadyExecuted,
        AgentToolErrorCodes.stepLimitReached,
        AgentToolErrorCodes.executionFailed,
      ];
      expect(codes.toSet().length, codes.length);
      for (final String code in codes) {
        expect(code, matches(RegExp(r'^[A-Z][A-Z0-9_]*$')), reason: code);
      }
    });
  });
}
