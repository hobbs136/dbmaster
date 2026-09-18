import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/services/dml_safety_service.dart';

void main() {
  group('DmlSafetyService stored-procedure calls', () {
    final service = DmlSafetyService();

    test('EXEC proc call (SQLType.call) 不被误判为注入/高风险', () {
      final result = service.analyze(
        [
          SQLStatement(
            index: 0,
            sql: 'EXEC [dbo].[sp_get_user_orders];',
            type: SQLType.call,
            lineStart: 1,
            lineEnd: 1,
          ),
        ],
        DatabaseType.sqlserver,
      );
      expect(result.riskLevel, DmlRiskLevel.normal);
      expect(result.hasInjectionPattern, isFalse);
    });

    test('CALL proc (SQLType.call) 为正常风险', () {
      final result = service.analyze(
        [
          SQLStatement(
            index: 0,
            sql: 'CALL public.get_user_orders();',
            type: SQLType.call,
            lineStart: 1,
            lineEnd: 1,
          ),
        ],
        DatabaseType.postgresql,
      );
      expect(result.riskLevel, DmlRiskLevel.normal);
    });

    test('存储过程调用中的真实注入仍被检测（堆叠查询）', () {
      // EXEC proc; DROP TABLE —— '堆叠查询' 模式仍应检测到高风险
      final result = service.analyze(
        [
          SQLStatement(
            index: 0,
            sql: 'EXEC dbo.do_stuff; DROP TABLE users',
            type: SQLType.call,
            lineStart: 1,
            lineEnd: 1,
          ),
        ],
        DatabaseType.sqlserver,
      );
      expect(result.riskLevel, DmlRiskLevel.high);
      expect(result.hasInjectionPattern, isTrue);
    });
  });
}
