import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/insert_execution_service.dart';
import 'package:dbmaster/services/database_abstract.dart';

// ============================================================================
// InsertExecutionService Tests
// ============================================================================

/// Minimal mock of DatabaseAdapter for testing InsertExecutionService.
class _MockAdapter implements DatabaseAdapter {
  final Map<String, SecurityCheckResult> _validationResults;
  final Map<String, QueryResult> _queryResults;
  final bool _throwOnExecute;

  _MockAdapter({
    Map<String, SecurityCheckResult>? validationResults,
    Map<String, QueryResult>? queryResults,
    bool throwOnExecute = false,
  }) : _validationResults = validationResults ?? {},
       _queryResults = queryResults ?? {},
       _throwOnExecute = throwOnExecute;

  @override
  SecurityCheckResult validateCommand(String command) {
    return _validationResults[command] ?? SecurityCheckResult.ok;
  }

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    if (_throwOnExecute) {
      throw Exception('Mock execution error');
    }
    return _queryResults[sql] ??
        QueryResult(
          columns: const [],
          rows: const [],
          affectedRows: 1,
          message: 'OK',
        );
  }

  // Stubbed unused members
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('InsertExecutionService', () {
    group('executeBatch', () {
      test('应成功执行所有有效 INSERT 语句', () async {
        final adapter = _MockAdapter();
        final service = InsertExecutionService(adapter: adapter);

        final result = await service.executeBatch(
          statements: const [
            "INSERT INTO users (name) VALUES ('Alice')",
            "INSERT INTO users (name) VALUES ('Bob')",
          ],
        );

        expect(result.totalStatements, 2);
        expect(result.successCount, 2);
        expect(result.failureCount, 0);
        expect(result.allSuccess, isTrue);
        expect(result.hasErrors, isFalse);
        expect(result.executedSql.length, 2);
      });

      test('被拒绝的语句应记录错误且不执行', () async {
        final adapter = _MockAdapter(
          validationResults: {
            "INSERT INTO users (name) VALUES ('Alice')": SecurityCheckResult.ok,
            "INSERT INTO users (name) VALUES ('Bob')":
                const SecurityCheckResult(
                  false,
                  CommandRiskLevel.dangerous,
                  reason: 'DROP detected',
                ),
          },
        );
        final service = InsertExecutionService(adapter: adapter);

        final result = await service.executeBatch(
          statements: const [
            "INSERT INTO users (name) VALUES ('Alice')",
            "INSERT INTO users (name) VALUES ('Bob')",
          ],
        );

        expect(result.totalStatements, 2);
        expect(result.successCount, 1);
        expect(result.failureCount, 1);
        expect(result.allSuccess, isFalse);
        expect(result.hasErrors, isTrue);
        expect(result.errors.length, 1);
        expect(result.errors.first, contains('被拒绝'));
        expect(result.executedSql.length, 1);
      });

      test('执行异常应记录错误', () async {
        final adapter = _MockAdapter(throwOnExecute: true);
        final service = InsertExecutionService(adapter: adapter);

        final result = await service.executeBatch(
          statements: const ["INSERT INTO users (name) VALUES ('Alice')"],
        );

        expect(result.successCount, 0);
        expect(result.failureCount, 1);
        expect(result.hasErrors, isTrue);
        expect(result.errors.first, contains('执行失败'));
      });

      test('skipValidation=true 应跳过校验', () async {
        final adapter = _MockAdapter(
          validationResults: {
            "INSERT INTO users (name) VALUES ('Alice')":
                const SecurityCheckResult(
                  false,
                  CommandRiskLevel.dangerous,
                  reason: 'Blocked',
                ),
          },
        );
        final service = InsertExecutionService(adapter: adapter);

        final result = await service.executeBatch(
          statements: const ["INSERT INTO users (name) VALUES ('Alice')"],
          skipValidation: true,
        );

        expect(result.successCount, 1, reason: 'skipValidation=true 时不应被拒绝');
        expect(result.hasErrors, isFalse);
      });

      test('空语句列表应返回空结果', () async {
        final adapter = _MockAdapter();
        final service = InsertExecutionService(adapter: adapter);

        final result = await service.executeBatch(statements: const []);

        expect(result.totalStatements, 0);
        expect(result.successCount, 0);
        expect(result.allSuccess, isTrue);
      });
    });

    group('validateStatements', () {
      test('应返回每条语句的校验结果', () {
        final adapter = _MockAdapter(
          validationResults: {
            'SQL1': SecurityCheckResult.ok,
            'SQL2': const SecurityCheckResult(
              false,
              CommandRiskLevel.warning,
              reason: 'Risky',
            ),
          },
        );
        final service = InsertExecutionService(adapter: adapter);

        final results = service.validateStatements(const ['SQL1', 'SQL2']);

        expect(results.length, 2);
        expect(results[0].allowed, isTrue);
        expect(results[1].allowed, isFalse);
        expect(results[1].riskLevel, CommandRiskLevel.warning);
      });
    });

    group('needsConfirmation', () {
      test('safe 级别语句不需要确认', () {
        final adapter = _MockAdapter(
          validationResults: {'SQL1': SecurityCheckResult.ok},
        );
        final service = InsertExecutionService(adapter: adapter);

        expect(service.needsConfirmation(const ['SQL1']), isFalse);
      });

      test('warning 级别语句需要确认', () {
        final adapter = _MockAdapter(
          validationResults: {
            'SQL1': const SecurityCheckResult(true, CommandRiskLevel.warning),
          },
        );
        final service = InsertExecutionService(adapter: adapter);

        expect(service.needsConfirmation(const ['SQL1']), isTrue);
      });

      test('dangerous 级别语句需要确认', () {
        final adapter = _MockAdapter(
          validationResults: {
            'SQL1': const SecurityCheckResult(true, CommandRiskLevel.dangerous),
          },
        );
        final service = InsertExecutionService(adapter: adapter);

        expect(service.needsConfirmation(const ['SQL1']), isTrue);
      });

      test('混合语句中只要有一个 risky 就需要确认', () {
        final adapter = _MockAdapter(
          validationResults: {
            'SQL1': SecurityCheckResult.ok,
            'SQL2': const SecurityCheckResult(true, CommandRiskLevel.warning),
          },
        );
        final service = InsertExecutionService(adapter: adapter);

        expect(service.needsConfirmation(const ['SQL1', 'SQL2']), isTrue);
      });
    });
  });
}
