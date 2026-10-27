// UI35-441 红测（编译红申报）：production 环境高危 DML 分流。
//
// 契约来源：B-07 冻结件——三挂接点分流条件 = 连接
// environment == ConnectionEnvironment.production；非 production 走既有确认门
// 逐字节不变（绿护栏见 query_execution_interceptor_test.dart 的
// 「checkDmlSafety 既有门绿护栏（UI35-442）」组）。
//
// ⚠️ seam 尚不存在：本测试以既有类型表达期望终态——checkDmlSafety 增加
// 可选 environment 入参（类型 ConnectionEnvironment? 为既有模型字段，
// 非发明新类型）。分流行为断言：
//   production + isBlocking SQL（无 WHERE DELETE / DROP / TRUNCATE）
//   → 不得再抛 DmlConfirmationRequiredException（改走 production guard 咨询），
//   且不得静默放行（仍须有拦截信号）。
// 编译错误原文 = 红态证据；实现批补 seam 后按实际形态转绿（允许适配 seam
// 形态，行为断言语义不变）。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/services/query_execution_interceptor.dart';

void main() {
  group('production 高危 DML 分流（UI35-441）', () {
    late QueryExecutionInterceptor interceptor;

    setUp(() {
      interceptor = QueryExecutionInterceptor();
    });

    Object? routingSignalOf(String sql) {
      try {
        interceptor.checkDmlSafety(
          sql: sql,
          dbType: DatabaseType.mysql,
          connectionId: 'conn-ui35-prod',
          environment: ConnectionEnvironment.production,
        );
      } catch (e) {
        return e;
      }
      return null;
    }

    test(
      'production + 无 WHERE DELETE → 不抛 DmlConfirmationRequiredException（production guard 分流，仍须拦截）',
      () {
        final signal = routingSignalOf('DELETE FROM orders');
        expect(
          signal,
          isNot(isA<DmlConfirmationRequiredException>()),
          reason: 'production 环境高危 DML 走 production guard 分流，'
              '不得再抛既有 DmlConfirmationRequiredException',
        );
        expect(
          signal,
          isNotNull,
          reason: 'production 分流不得静默放行（guard 咨询仍须阻断）',
        );
      },
    );

    test(
      'production + DROP TABLE → 不抛 DmlConfirmationRequiredException（production guard 分流，仍须拦截）',
      () {
        final signal = routingSignalOf('DROP TABLE orders');
        expect(
          signal,
          isNot(isA<DmlConfirmationRequiredException>()),
          reason: 'production 环境高危 DML 走 production guard 分流，'
              '不得再抛既有 DmlConfirmationRequiredException',
        );
        expect(
          signal,
          isNotNull,
          reason: 'production 分流不得静默放行（guard 咨询仍须阻断）',
        );
      },
    );

    test(
      'production + TRUNCATE TABLE → 不抛 DmlConfirmationRequiredException（production guard 分流，仍须拦截）',
      () {
        final signal = routingSignalOf('TRUNCATE TABLE orders');
        expect(
          signal,
          isNot(isA<DmlConfirmationRequiredException>()),
          reason: 'production 环境高危 DML 走 production guard 分流，'
              '不得再抛既有 DmlConfirmationRequiredException',
        );
        expect(
          signal,
          isNotNull,
          reason: 'production 分流不得静默放行（guard 咨询仍须阻断）',
        );
      },
    );
  });
}
