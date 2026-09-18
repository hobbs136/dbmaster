// Feature 039 — Redis 只读守卫真实库 e2e（T015 部分，证最高风险守卫真拦）。
// 连真实 Redis（参数经 DBMASTER_REDIS_* 提供，db15），建只读连接，断言写被拦 + 读放行。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/readonly_guard.dart';

import 'config/redis_test_config.dart';
import 'helpers/redis_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // T29 非 SQL 批次（B4）：Redis 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 REDIS_E2E_SKIP 跳过（无假绿）。
  var redisE2EGatewayReady = false;
  setUpAll(() async {
    redisE2EGatewayReady = await ensureEmbeddedServerForRedisE2E();
    if (redisE2EGatewayReady && !RedisTestConfig.available) {
      // ignore: avoid_print
      print('REDIS_E2E_SKIP: DBMASTER_REDIS_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      redisE2EGatewayReady = false;
    }
  });
  final prefix = RedisTestConfig.generateTestKeyPrefix();

  Future<RedisAdapter> connectReadOnly() async {
    final a = RedisAdapter();
    final ok = await a.connect(
      DatabaseConnection(
        id: 'ro-test',
        name: 'ro-test',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
        readOnly: true, // 关键：只读
      ),
    );
    expect(ok, true, reason: 'Redis 连接失败（检查 ${RedisTestConfig.host}:${RedisTestConfig.port} 可达）');
    return a;
  }

  // 安全网清理：若 guard 失效导致写漏放，清掉测试键前缀（用可写连接）。
  tearDown(() async {
    final w = RedisAdapter();
    if (!await w.connect(
      DatabaseConnection(
        id: 'cleanup',
        name: 'cleanup',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      ),
    )) {
      return;
    }
    try {
      final keys = await w.runCommand(['KEYS', '$prefix*']);
      if (keys is List) {
        for (final k in keys) {
          await w.runCommand(['DEL', k.toString()]);
        }
      }
    } catch (_) {
    } finally {
      await w.disconnect();
    }
  });

  test('只读 Redis: runCommand SET 被拦 (ReadOnlyBlockedException) + key 未创建', () async {
    if (!redisE2EGatewayReady) return;
    final a = await connectReadOnly();
    try {
      final key = '${prefix}_set';
      await expectLater(
        a.runCommand(['SET', key, 'v']),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      // 读操作放行：GET 确认 key 未被创建
      final v = await a.runCommand(['GET', key]);
      expect(v, isNull, reason: '只读连接的 SET 不应创建 key');
    } finally {
      await a.disconnect();
    }
  });

  test('只读 Redis: runCommand FLUSHDB 被拦', () async {
    if (!redisE2EGatewayReady) return;
    final a = await connectReadOnly();
    try {
      await expectLater(
        a.runCommand(['FLUSHDB']),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    } finally {
      await a.disconnect();
    }
  });

  test('只读 Redis: executeQuery "SET ..." 被拦', () async {
    if (!redisE2EGatewayReady) return;
    final a = await connectReadOnly();
    try {
      await expectLater(
        a.executeQuery('SET ${prefix}_q v'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    } finally {
      await a.disconnect();
    }
  });

  test('只读 Redis: 读操作 (GET) 放行，不抛 ReadOnlyBlockedException', () async {
    if (!redisE2EGatewayReady) return;
    final a = await connectReadOnly();
    try {
      final v = await a.runCommand(['GET', '${prefix}_nonexistent']);
      expect(v, isNull); // 读放行，无异常
    } finally {
      await a.disconnect();
    }
  });
}
