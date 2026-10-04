// T20 SqlStatementGateRunner 单测（design-ai-agent §2.3 / §6 计划期发现 #9）。
//
// 骨架以注入回调桩断言（无 UI、无真实库——服务层纯逻辑面）：
// - 拆分：多语句按序 / 纯注释回退整块 / 畸形 SQL fail-closed（F1）/ 空输入；
// - 写确认两模式：perStatement（逐写语句回调、cancel 整批零执行、
//   allowSession/allowOnce 放行、abort 静默）/ none（A2 计划语义零回调）；
// - 双门路由：DDL/DML 异常接住 → 确认后 bypass 第二道执行；取消/缺位
//   fail-closed；bypass 失败按普通失败继续；
// - 失败边界：M1 部分失败继续（AC9.5）/ haltOnStatementFailure 即停
//   （k+1..n skipped，A2 计划语义）；
// - 逐语句交错回调（done/failed 回调、skipped 不回调）与 shouldContinue
//   探针中止。
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/sql_parser_service.dart' show ParseException;
import 'package:dbmaster/services/sql_statement_gate_runner.dart';

ImpactReport _impact(String sql) => ImpactReport(
  ddlStatement: sql,
  targetTable: 't1',
  ddlType: 'DROP',
  riskLevel: RiskLevel.high,
  affectedObjects: const [],
  dependencies: const [],
  warnings: const [],
  recommendations: const [],
  requiresConfirmation: true,
  analyzedAt: DateTime(2026, 1, 1),
);

const List<Map<String, dynamic>> _kRows = <Map<String, dynamic>>[
  <String, dynamic>{'id': 1},
];

void main() {
  const runner = SqlStatementGateRunner();

  group('多语句拆分', () {
    test('多语句按序拆分逐条执行；语句已 trim；haltIndex = -1', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: 'SELECT 1;   SELECT 2 ;  SELECT 3',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(executed, ['SELECT 1', 'SELECT 2', 'SELECT 3']);
      expect(
        result.results.map((r) => r.status),
        everyElement(SqlStatementStatus.done),
      );
      expect(result.haltIndex, -1);
    });

    test('畸形 SQL（未闭合注释）→ splitFailed 零执行 + splitError 透出（F1）', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: 'SELECT 1; DROP TABLE x; /*',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.splitFailed);
      expect(executed, isEmpty, reason: '拆分失败不整块回退执行（fail-open 防护）');
      expect(result.splitError, isA<ParseException>());
      expect(result.results, isEmpty);
    });

    test('拆分结果为空（纯注释）→ 回退整块原文单语句执行（M1 既有语义）', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: '/* only comment */',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(executed, ['/* only comment */']);
    });

    test('空白输入 → emptyInput 零执行（M1 空白守卫后的防御边界）', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: '   ',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.emptyInput);
      expect(executed, isEmpty);
    });
  });

  group('写确认策略 perStatement（M1 模式）', () {
    test('批量含写语句 cancel → 整批零执行（两遍法第一遍拦截，AC6.1）', () async {
      final executed = <String>[];
      final confirmedWrites = <String>[];
      final result = await runner.run(
        sql: 'SELECT 1; UPDATE t SET a = 1; SELECT 2',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          writeConfirm: SqlWriteConfirmStrategy.perStatement((statement) async {
            confirmedWrites.add(statement);
            return SqlWriteConfirmDecision.cancel;
          }),
        ),
      );

      expect(result.status, SqlBatchStatus.writeCancelled);
      expect(executed, isEmpty, reason: '确认前不执行任何语句（含只读语句）');
      expect(
        confirmedWrites,
        ['UPDATE t SET a = 1'],
        reason: '只对写语句回调确认，只读语句不弹',
      );
      expect(
        result.results.map((r) => r.status),
        everyElement(SqlStatementStatus.skipped),
      );
      expect(result.haltIndex, 1, reason: '中止边界 = 被取消的写语句序号');
    });

    test('allowSession → allowOnce 连续放行：全部写语句执行', () async {
      final executed = <String>[];
      final confirmedWrites = <String>[];
      final decisions = <SqlWriteConfirmDecision>[
        SqlWriteConfirmDecision.allowSession,
        SqlWriteConfirmDecision.allowOnce,
      ];
      final result = await runner.run(
        sql: 'UPDATE a SET x = 1; UPDATE b SET x = 2',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          writeConfirm: SqlWriteConfirmStrategy.perStatement((statement) async {
            confirmedWrites.add(statement);
            return decisions.removeAt(0);
          }),
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(executed, hasLength(2), reason: '两种放行决策都执行');
      expect(confirmedWrites, hasLength(2), reason: '逐写语句回调（放行集由调用方自持）');
    });

    test('aborted → 静默中止零执行', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: 'UPDATE t SET a = 1',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          writeConfirm: SqlWriteConfirmStrategy.perStatement(
            (statement) async => SqlWriteConfirmDecision.aborted,
          ),
        ),
      );

      expect(result.status, SqlBatchStatus.aborted);
      expect(executed, isEmpty);
    });
  });

  group('写确认策略 none（A2 计划模式）', () {
    test('写语句直接执行，确认回调零调用（计划批准即写授权）', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: 'UPDATE t SET a = 1; DELETE FROM u',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          writeConfirm: const SqlWriteConfirmStrategy.none(),
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(executed, hasLength(2), reason: 'none 模式写语句不拦');
    });

    test('writeConfirm 缺省即 none 形态（A2 执行器最小依赖面）', () async {
      final result = await runner.run(
        sql: 'DROP TABLE legacy',
        deps: SqlGateRunDeps(
          execute: (statement) async => const SqlStatementOutcome(rows: <Map<String, dynamic>>[]),
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
    });
  });

  group('双异常路由 gate #2（DDL）', () {
    test('DDL 异常 → ddlConfirm 接住；confirmed → executeBypassDdl 第二道执行', () async {
      final ddlException = DdlConfirmationRequiredException(
        sql: 'DROP TABLE t1',
        impactReport: _impact('DROP TABLE t1'),
      );
      final executed = <String>[];
      final bypassed = <String>[];
      final confirmed = <DdlConfirmationRequiredException>[];
      final result = await runner.run(
        sql: 'DROP TABLE t1',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            throw ddlException;
          },
          ddlConfirm: (e) async {
            confirmed.add(e);
            return SqlGateConfirmDecision.confirmed;
          },
          executeBypassDdl: (statement) async {
            bypassed.add(statement);
            return SqlStatementOutcome(rows: _kRows);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(confirmed.single, same(ddlException), reason: '异常负载原样透传给回调');
      expect(bypassed, ['DROP TABLE t1'], reason: '确认后走 bypass 双门第二道');
      expect(result.results.single.status, SqlStatementStatus.done);
      expect(result.results.single.rows, _kRows);
    });

    test('DDL cancel → ddlCancelled：零 bypass、余下 skipped、异常负载透出', () async {
      final ddlException = DdlConfirmationRequiredException(
        sql: 'DROP TABLE t1',
        impactReport: _impact('DROP TABLE t1'),
      );
      final executed = <String>[];
      final bypassed = <String>[];
      final result = await runner.run(
        sql: 'DROP TABLE t1; SELECT 9',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            throw ddlException;
          },
          ddlConfirm: (e) async => SqlGateConfirmDecision.cancelled,
          executeBypassDdl: (statement) async {
            bypassed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.ddlCancelled);
      expect(executed, ['DROP TABLE t1'], reason: '首次尝试执行（被管线拦截）');
      expect(bypassed, isEmpty, reason: '取消 → 不执行 bypass');
      expect(result.ddlException, same(ddlException));
      expect(
        result.results.map((r) => r.status),
        everyElement(SqlStatementStatus.skipped),
        reason: '中止语句与余下语句均 skipped（余下不再执行）',
      );
      expect(result.haltIndex, 0);
    });

    test('ddlConfirm 缺位 → fail-closed 视同取消（零 bypass）', () async {
      final ddlException = DdlConfirmationRequiredException(
        sql: 'DROP TABLE t1',
        impactReport: _impact('DROP TABLE t1'),
      );
      final bypassed = <String>[];
      final result = await runner.run(
        sql: 'DROP TABLE t1',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw ddlException,
          executeBypassDdl: (statement) async {
            bypassed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.ddlCancelled, reason: '缺位回调按取消处理');
      expect(bypassed, isEmpty);
    });

    test('DDL abort（context 失效映射）→ 静默中止', () async {
      final ddlException = DdlConfirmationRequiredException(
        sql: 'DROP TABLE t1',
        impactReport: _impact('DROP TABLE t1'),
      );
      final result = await runner.run(
        sql: 'DROP TABLE t1',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw ddlException,
          ddlConfirm: (e) async => SqlGateConfirmDecision.aborted,
          executeBypassDdl: (statement) async => const SqlStatementOutcome(rows: <Map<String, dynamic>>[]),
        ),
      );

      expect(result.status, SqlBatchStatus.aborted);
    });

    test('bypass 执行失败 → 按普通失败处理，余下语句继续（M1 语义）', () async {
      final ddlException = DdlConfirmationRequiredException(
        sql: 'DROP TABLE t1',
        impactReport: _impact('DROP TABLE t1'),
      );
      final executed = <String>[];
      final result = await runner.run(
        sql: 'DROP TABLE t1; SELECT 2',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            if (statement.startsWith('DROP')) throw ddlException;
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          ddlConfirm: (e) async => SqlGateConfirmDecision.confirmed,
          executeBypassDdl: (statement) async => throw Exception('bypass boom'),
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(executed, hasLength(2), reason: 'bypass 失败不中断余下语句');
      expect(result.results.first.status, SqlStatementStatus.failed);
      expect(result.results.first.error.toString(), contains('bypass boom'));
      expect(result.results.last.status, SqlStatementStatus.done);
    });
  });

  group('双异常路由 gate #2（DML）', () {
    const dmlException = DmlConfirmationRequiredException(
      sql: 'UPDATE orders SET status = 1',
      analysis: RiskAnalysisResult(
        riskLevel: DmlRiskLevel.high,
        affectedObjects: [],
      ),
      statements: [],
    );

    test('DML 异常 → dmlConfirm；confirmed → executeBypassDml', () async {
      final bypassed = <String>[];
      final confirmed = <DmlConfirmationRequiredException>[];
      final result = await runner.run(
        sql: 'UPDATE orders SET status = 1',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw dmlException,
          dmlConfirm: (e) async {
            confirmed.add(e);
            return SqlGateConfirmDecision.confirmed;
          },
          executeBypassDml: (statement) async {
            bypassed.add(statement);
            return SqlStatementOutcome(rows: _kRows);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(confirmed.single, same(dmlException));
      expect(bypassed, ['UPDATE orders SET status = 1']);
      expect(result.results.single.rows, _kRows);
    });

    test('DML cancel → dmlCancelled + 异常负载透出（审计字段承载）', () async {
      final bypassed = <String>[];
      final result = await runner.run(
        sql: 'UPDATE orders SET status = 1',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw dmlException,
          dmlConfirm: (e) async => SqlGateConfirmDecision.cancelled,
          executeBypassDml: (statement) async {
            bypassed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.dmlCancelled);
      expect(bypassed, isEmpty);
      expect(result.dmlException, same(dmlException));
      expect(result.results.single.status, SqlStatementStatus.skipped);
    });
  });

  group('失败边界（两停策略）', () {
    test('默认（M1）：第 k 句失败继续余下，逐句落结局（AC9.5）', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: 'SELECT 1; UPDATE t SET a = 1; SELECT 3',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            if (statement.startsWith('UPDATE')) throw Exception('boom');
            return SqlStatementOutcome(rows: _kRows);
          },
        ),
      );

      expect(result.status, SqlBatchStatus.completed, reason: '部分失败不改变批终局');
      expect(executed, hasLength(3));
      expect(
        result.results.map((r) => r.status).toList(),
        [
          SqlStatementStatus.done,
          SqlStatementStatus.failed,
          SqlStatementStatus.done,
        ],
      );
      expect(result.results[1].error.toString(), contains('boom'));
      expect(result.results.first.rows, _kRows);
      expect(result.haltIndex, -1);
    });

    test('haltOnStatementFailure=true（A2 计划）：第 k 句失败即停，k+1..n skipped', () async {
      final executed = <String>[];
      final result = await runner.run(
        sql: 'SELECT 1; UPDATE t SET a = 1; SELECT 3',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            if (statement.startsWith('UPDATE')) throw Exception('boom');
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          haltOnStatementFailure: true,
        ),
      );

      expect(result.status, SqlBatchStatus.failureHalt);
      expect(executed, hasLength(2), reason: '失败后不再执行 k+1..n');
      expect(
        result.results.map((r) => r.status).toList(),
        [
          SqlStatementStatus.done,
          SqlStatementStatus.failed,
          SqlStatementStatus.skipped,
        ],
      );
      expect(result.haltIndex, 2, reason: '边界索引 = 首个 skipped 语句序号');
    });
  });

  group('逐语句回调与探针', () {
    test('onStatementResult：done/failed 交错回调承载 rows/durationMs/error；skipped 不回调', () async {
      final emitted = <SqlStatementResult>[];
      final result = await runner.run(
        sql: 'SELECT 1; UPDATE t SET a = 1',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            if (statement.startsWith('UPDATE')) throw Exception('boom');
            return SqlStatementOutcome(rows: _kRows);
          },
          onStatementResult: emitted.add,
        ),
      );

      expect(emitted, hasLength(2));
      expect(emitted[0].status, SqlStatementStatus.done);
      expect(emitted[0].rows, _kRows);
      expect(emitted[0].durationMs, greaterThanOrEqualTo(0));
      expect(emitted[1].status, SqlStatementStatus.failed);
      expect(emitted[1].error.toString(), contains('boom'));
      expect(result.results, hasLength(2), reason: '终局与回调双通道一致');
    });

    test('shouldContinue=false → aborted，后续语句零执行', () async {
      final executed = <String>[];
      var probeCalls = 0;
      final result = await runner.run(
        sql: 'SELECT 1; SELECT 2',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            executed.add(statement);
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          shouldContinue: () {
            probeCalls++;
            return probeCalls == 1;
          },
        ),
      );

      expect(result.status, SqlBatchStatus.aborted);
      expect(executed, ['SELECT 1'], reason: '探针拒绝后不再执行第 2 句');
      expect(
        result.results.map((r) => r.status).toList(),
        [SqlStatementStatus.done, SqlStatementStatus.skipped],
      );
      expect(result.haltIndex, 1);
    });
  });

  group('affectedRows 贯通（裁决选项 A：SqlExecuteCallback 回调型扩宽）', () {
    test('写语句引擎 affectedRows 透传到 SqlStatementResult（逐语句回调 + 终局双通道）', () async {
      final emitted = <SqlStatementResult>[];
      final result = await runner.run(
        sql: 'INSERT INTO t VALUES (1); SELECT 2',
        deps: SqlGateRunDeps(
          execute: (statement) async {
            if (statement.startsWith('INSERT')) {
              return const SqlStatementOutcome(
                rows: <Map<String, dynamic>>[],
                affectedRows: 3,
              );
            }
            return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
          },
          onStatementResult: emitted.add,
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(result.results, hasLength(2));
      expect(
        result.results.first.affectedRows,
        3,
        reason: '写语句引擎值 3 贯通（detailed 通道不再解包丢失）',
      );
      expect(result.results.first.rows, isEmpty, reason: '写语句空行集不影响 affectedRows');
      expect(
        result.results.last.affectedRows,
        isNull,
        reason: '读语句引擎无影响行概念 → null',
      );
      expect(emitted.first.affectedRows, 3, reason: '回调通道与终局通道一致');
    });

    test('DDL bypass 第二道执行的 affectedRows 透传（多门路径最终成功执行段）', () async {
      final ddlException = DdlConfirmationRequiredException(
        sql: 'DROP TABLE t1',
        impactReport: _impact('DROP TABLE t1'),
      );
      final result = await runner.run(
        sql: 'DROP TABLE t1',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw ddlException,
          ddlConfirm: (e) async => SqlGateConfirmDecision.confirmed,
          executeBypassDdl: (statement) async => const SqlStatementOutcome(
            rows: <Map<String, dynamic>>[],
            affectedRows: 0,
          ),
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(
        result.results.single.affectedRows,
        0,
        reason: 'bypass 通道引擎值原样透传（DDL 成功常报 0，展示层抑制）',
      );
    });

    test('DML bypass 第二道执行的 affectedRows 透传', () async {
      const dmlException = DmlConfirmationRequiredException(
        sql: 'UPDATE orders SET status = 1',
        analysis: RiskAnalysisResult(
          riskLevel: DmlRiskLevel.high,
          affectedObjects: [],
        ),
        statements: [],
      );
      final result = await runner.run(
        sql: 'UPDATE orders SET status = 1',
        deps: SqlGateRunDeps(
          execute: (statement) async => throw dmlException,
          dmlConfirm: (e) async => SqlGateConfirmDecision.confirmed,
          executeBypassDml: (statement) async => const SqlStatementOutcome(
            rows: <Map<String, dynamic>>[],
            affectedRows: 7,
          ),
        ),
      );

      expect(result.status, SqlBatchStatus.completed);
      expect(result.results.single.affectedRows, 7, reason: 'DML bypass 引擎值 7 贯通');
    });
  });
}
