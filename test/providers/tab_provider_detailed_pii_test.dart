// TabProvider.executeQueryDetailed SELECT PII 脱敏回归测试（裁决选项 A ②）。
//
// 工作台执行改走 detailed 通道后，SELECT 脱敏口径必须与 executeQuery
// 完全一致（:599-605 同源）——本测试锁定 TabProvider 层行为：严禁工作台
// 下绕此层直绑 dbService（否则 SELECT 脱敏回归）。
//
// 断言面：
// - SELECT + 非空行集 → rows 敏感列过 PIIMasker（email/ip 确定性脱敏形态），
//   非敏感列原样；元数据（affectedRows/executionTimeMs）原样保留；
// - 非 SELECT（写语句）→ 不脱敏（原样透传）；
// - SELECT + 空行集 → 不调用脱敏（maskRows 空集短路，原样返回）。
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/providers/tab_provider.dart';
import 'package:dbmaster/services/database_service.dart';

/// 只覆写 [executeQueryDetailed] 的 DatabaseService 桩（真实
/// transactionEvents/events 流不受影响——TabProvider 构造零副作用）。
class _DetailedStubDatabaseService extends DatabaseService {
  _DetailedStubDatabaseService({this.affectedRows, this.executionTimeMs});

  final int? affectedRows;
  final int? executionTimeMs;

  @override
  Future<QueryExecutionResult> executeQueryDetailed(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    return QueryExecutionResult(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'email': 'alice@example.com',
          'ip': '192.168.3.128',
          'label': 'plain-value',
        },
      ],
      affectedRows: affectedRows,
      executionTimeMs: executionTimeMs,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabProvider.executeQueryDetailed（detailed 孪生，SELECT PII 脱敏同口径）', () {
    test('SELECT → 敏感列脱敏、非敏感列原样、元数据保留', () async {
      final provider = TabProvider(
        _DetailedStubDatabaseService(affectedRows: 7, executionTimeMs: 42),
      );

      final result = await provider.executeQueryDetailed('SELECT 1');

      expect(result.affectedRows, 7, reason: '元数据 affectedRows 原样保留');
      expect(result.executionTimeMs, 42, reason: '元数据 executionTimeMs 原样保留');
      final row = result.rows.single;
      expect(
        row['email'],
        'al***@example.com',
        reason: 'email 列值脱敏（PIIMasker email 形态）',
      );
      expect(
        row['ip'],
        '**********128',
        reason: 'ip 列值脱敏（PIIMasker partial 形态：前 10 位掩蔽 + 后 3 位保留）',
      );
      expect(row['id'], 1, reason: '非敏感列原样透传');
      expect(row['label'], 'plain-value', reason: '非敏感列原样透传');
    });

    test('非 SELECT（写语句）→ 不脱敏，引擎值原样透传', () async {
      final provider = TabProvider(
        _DetailedStubDatabaseService(affectedRows: 5),
      );

      final result = await provider.executeQueryDetailed(
        'INSERT INTO t VALUES (1)',
      );

      expect(result.affectedRows, 5, reason: '写语句 affectedRows 透传');
      expect(
        result.rows.single['email'],
        'alice@example.com',
        reason: '写语句不走 SELECT 脱敏（口径与 executeQuery 一致）',
      );
    });

    test('SELECT 空行集 → 不脱敏（空集短路，与 executeQuery 同）', () async {
      final provider = TabProvider(_EmptyDetailedStubDatabaseService());

      final result = await provider.executeQueryDetailed('SELECT 1');

      expect(result.rows, isEmpty);
      expect(result.executionTimeMs, 10, reason: '空行集元数据照常返回');
    });
  });
}

/// 空行集桩（脱敏空集短路路径）。
class _EmptyDetailedStubDatabaseService extends DatabaseService {
  @override
  Future<QueryExecutionResult> executeQueryDetailed(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    return QueryExecutionResult(
      <Map<String, dynamic>>[],
      executionTimeMs: 10,
    );
  }
}
