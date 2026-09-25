/// T09 AgentUiPort / AgentResultRef 单测（tasks-ai-agent.md §3 T09）。
///
/// 接口无逻辑，测试从简：值对象构造与字段、rows 内存引用不复制、
/// AgentUiOutcome 形态（ok/failure 构造 + 值相等语义）、fake 实现编译性
/// 用例（七方法签名绑定 + 参数与 outcome 透传）。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';

void main() {
  group('AgentResultRef', () {
    test('构造与字段', () {
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'name': 'a'},
        <String, dynamic>{'id': 2, 'name': 'b'},
      ];
      final AgentResultRef ref = AgentResultRef(
        refId: 'res_3',
        sql: 'SELECT id, name FROM t',
        rowCount: 42,
        columns: <String>['id', 'name'],
        rows: rows,
      );

      expect(ref.refId, 'res_3');
      expect(ref.sql, 'SELECT id, name FROM t');
      expect(ref.rowCount, 42);
      expect(ref.columns, <String>['id', 'name']);
      expect(ref.rows, hasLength(2));
      expect(ref.rows.first, <String, dynamic>{'id': 1, 'name': 'a'});
    });

    test('rows 为内存引用不复制（同一 List 实例）', () {
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        <String, dynamic>{'id': 1},
      ];
      final AgentResultRef ref = AgentResultRef(
        refId: 'res_1',
        sql: 'SELECT 1',
        rowCount: 1,
        columns: <String>['id'],
        rows: rows,
      );

      expect(identical(ref.rows, rows), isTrue);
    });
  });

  group('AgentUiOutcome', () {
    test('ok：默认无 message', () {
      const AgentUiOutcome o = AgentUiOutcome.ok();

      expect(o.ok, isTrue);
      expect(o.message, isNull);
    });

    test('ok：可携带附加 message', () {
      const AgentUiOutcome o = AgentUiOutcome.ok(message: 'grid opened');

      expect(o.ok, isTrue);
      expect(o.message, 'grid opened');
    });

    test('failure：ok=false 且 message 必填（自纠通路，AC15.1）', () {
      const AgentUiOutcome o = AgentUiOutcome.failure(
        'chart kind "pie" unsupported',
      );

      expect(o.ok, isFalse);
      expect(o.message, 'chart kind "pie" unsupported');
    });

    test('值相等语义（==/hashCode 按 ok+message）', () {
      const AgentUiOutcome failA = AgentUiOutcome.failure('x');
      const AgentUiOutcome failB = AgentUiOutcome.failure('x');
      const AgentUiOutcome okA = AgentUiOutcome.ok();
      const AgentUiOutcome okB = AgentUiOutcome.ok();

      expect(failA, equals(failB));
      expect(failA.hashCode, failB.hashCode);
      expect(okA, equals(okB));
      expect(okA.hashCode, okB.hashCode);
      expect(failA, isNot(equals(okA)));
      expect(
        AgentUiOutcome.failure('x'),
        isNot(equals(const AgentUiOutcome.failure('y'))),
      );
    });
  });

  group('AgentUiPort fake 实现（编译性用例）', () {
    test('七方法签名绑定 + 参数与 outcome 透传', () async {
      final _FakeAgentUiPort port = _FakeAgentUiPort();
      final AgentResultRef ref = AgentResultRef(
        refId: 'res_2',
        sql: 'SELECT * FROM t',
        rowCount: 10,
        columns: <String>['a'],
        rows: const <Map<String, dynamic>>[],
      );

      expect(
        await port.openResultGrid(ref, 'title'),
        const AgentUiOutcome.ok(message: 'grid:res_2'),
      );
      expect(
        await port.showTableStructure('users'),
        const AgentUiOutcome.ok(message: 'structure:users'),
      );
      expect(
        await port.openSqlEditor('SELECT 1'),
        const AgentUiOutcome.ok(message: 'editor'),
      );
      expect(
        await port.renderChart(ref, 'bar'),
        const AgentUiOutcome.ok(message: 'chart:res_2'),
      );
      expect(
        await port.pinArtifact(ref, 'label'),
        const AgentUiOutcome.ok(message: 'pin:res_2'),
      );
      expect(
        await port.suggestOpenInClassic('SELECT 2'),
        const AgentUiOutcome.ok(message: 'suggest:classic'),
      );
      expect(
        await port.suggestFocusSidebar(database: 'db1', table: 't1'),
        const AgentUiOutcome.ok(message: 'suggest:sidebar:db1/t1'),
      );

      expect(port.calls, <String>[
        'openResultGrid:res_2:title',
        'showTableStructure:users',
        'openSqlEditor:SELECT 1',
        'renderChart:res_2:bar',
        'pinArtifact:res_2:label',
        'suggestOpenInClassic:SELECT 2',
        'suggestFocusSidebar:db1/t1',
      ]);
    });

    test('失败 outcome 可自实现回喂（AC15.1 形态）', () async {
      final _FailingAgentUiPort port = _FailingAgentUiPort();

      final AgentUiOutcome outcome = await port.renderChart(
        AgentResultRef(
          refId: 'res_1',
          sql: 'SELECT 1',
          rowCount: 1,
          columns: <String>['a'],
          rows: const <Map<String, dynamic>>[],
        ),
        'pie',
      );

      expect(outcome.ok, isFalse);
      expect(outcome.message, contains('unsupported'));
    });
  });
}

/// 记录调用并回固定成功 outcome 的 fake（证明接口可被 UI 无关实现绑定）。
class _FakeAgentUiPort implements AgentUiPort {
  final List<String> calls = <String>[];

  @override
  Future<AgentUiOutcome> openResultGrid(
    AgentResultRef ref,
    String? title,
  ) async {
    calls.add('openResultGrid:${ref.refId}:$title');
    return AgentUiOutcome.ok(message: 'grid:${ref.refId}');
  }

  @override
  Future<AgentUiOutcome> showTableStructure(String table) async {
    calls.add('showTableStructure:$table');
    return AgentUiOutcome.ok(message: 'structure:$table');
  }

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) async {
    calls.add('openSqlEditor:$sql');
    return AgentUiOutcome.ok(message: 'editor');
  }

  @override
  Future<AgentUiOutcome> renderChart(
    AgentResultRef ref,
    String? chartKind,
  ) async {
    calls.add('renderChart:${ref.refId}:$chartKind');
    return AgentUiOutcome.ok(message: 'chart:${ref.refId}');
  }

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) async {
    calls.add('pinArtifact:${ref.refId}:$label');
    return AgentUiOutcome.ok(message: 'pin:${ref.refId}');
  }

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) async {
    calls.add('suggestOpenInClassic:$sql');
    return AgentUiOutcome.ok(message: 'suggest:classic');
  }

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) async {
    calls.add('suggestFocusSidebar:${database ?? ''}/${table ?? ''}');
    return AgentUiOutcome.ok(
      message: 'suggest:sidebar:${database ?? ''}/${table ?? ''}',
    );
  }
}

/// 恒定失败 outcome 的 fake（失败回喂形态用例）。
class _FailingAgentUiPort implements AgentUiPort {
  @override
  Future<AgentUiOutcome> renderChart(
    AgentResultRef ref,
    String? chartKind,
  ) async {
    return AgentUiOutcome.failure('chart kind "$chartKind" unsupported');
  }

  @override
  Future<AgentUiOutcome> openResultGrid(
    AgentResultRef ref,
    String? title,
  ) async => AgentUiOutcome.failure('unsupported');

  @override
  Future<AgentUiOutcome> showTableStructure(String table) async =>
      AgentUiOutcome.failure('unsupported');

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) async =>
      AgentUiOutcome.failure('unsupported');

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) async =>
      AgentUiOutcome.failure('unsupported');

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) async =>
      AgentUiOutcome.failure('unsupported');

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) async => AgentUiOutcome.failure('unsupported');
}
