// =============================================================================
// AdapterBacking 单元测试（C10 · port 化连接语义——本地直连现状行为）。
// =============================================================================
// 验证：testConnection 透传 DatabaseService 的 String? 语义（null=成功）、
// persistConnection 本地 no-op、removeConnection no-op、connectionState 为
// directAdapter + 本地连接表 readOnly 反查、能力位委托真值表、Tier 1/执行
// 的 C13/C14 占位语义。
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/ports/adapter_backing.dart';
import 'package:dbmaster/services/ports/port_types.dart';

/// 只覆写 testConnection 的 DatabaseService 假体（其余成员不经本测试路径）。
class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService();

  String? nextResult;

  @override
  Future<String?> testConnection(DbServer server) async => nextResult;
}

DbServer _server(DatabaseType type) => DbServer(
      id: 'conn_1',
      name: 'test',
      type: type,
      host: type == DatabaseType.sqlite ? '/tmp/a.db' : 'db.local',
      port: 3306,
    );

void main() {
  late _FakeDatabaseService dbService;

  setUp(() {
    dbService = _FakeDatabaseService();
  });

  test('testConnection：本地直连成功（null → ok）', () async {
    final backing = AdapterBacking(dbService: dbService);
    dbService.nextResult = null;
    final result = await backing.testConnection(_server(DatabaseType.mysql));
    expect(result.ok, isTrue);
    expect(result.error, isNull);
  });

  test('testConnection：错误字符串原样透传（现状 UI 语义）', () async {
    final backing = AdapterBacking(dbService: dbService);
    dbService.nextResult = 'Connection refused (10061)';
    final result = await backing.testConnection(_server(DatabaseType.mysql));
    expect(result.ok, isFalse);
    expect(result.error, 'Connection refused (10061)');
  });

  test('persistConnection：本地 no-op 返回原 id', () async {
    final backing = AdapterBacking(dbService: dbService);
    final server = _server(DatabaseType.postgresql);
    expect(await backing.persistConnection(server), server.id);
  });

  test('removeConnection：no-op 正常完成', () async {
    final backing = AdapterBacking(dbService: dbService);
    await expectLater(backing.removeConnection('conn_1'), completes);
  });

  group('connectionState', () {
    test('directAdapter 形态', () async {
      final backing = AdapterBacking(dbService: dbService);
      final state = await backing.connectionState('conn_1');
      expect(state.mode, ConnectionMode.directAdapter);
      expect(state.readOnly, isFalse);
    });

    test('readOnly 经本地连接表反查；查无此连接退化为 false', () async {
      final ro = _server(DatabaseType.mysql).copyWith(readOnly: true);
      final backing = AdapterBacking(
        dbService: dbService,
        connectionLookup: (id) => id == ro.id ? ro : null,
      );
      expect((await backing.connectionState(ro.id)).readOnly, isTrue);
      expect((await backing.connectionState('missing')).readOnly, isFalse);
    });
  });

  group('能力位委托真值表', () {
    test('hasCapability', () {
      final backing = AdapterBacking(dbService: dbService);
      expect(backing.hasCapability(DatabaseType.mysql, 'sql.query'), isTrue);
      expect(backing.hasCapability(DatabaseType.redis, 'sql.query'), isFalse);
      expect(
        backing.hasCapability(DatabaseType.sqlite, 'sqlite.attach'),
        isTrue,
      );
      expect(backing.hasCapability(DatabaseType.mysql, 'nope'), isFalse);
    });

    test('capabilitiesOf 与真值表一致', () {
      final backing = AdapterBacking(dbService: dbService);
      expect(
        backing.capabilitiesOf(DatabaseType.sqlserver),
        containsAll(['schema.namespace', 'proc.list', 'process.list']),
      );
      expect(backing.capabilitiesOf(DatabaseType.tdengine), contains('td.tag'));
      expect(backing.capabilitiesOf(DatabaseType.mysql), isNotEmpty);
    });
  });

  group('C14 占位（C13 执行通道已落地，行为见 port_execution_test）', () {
    test('Tier 1 元数据抛 UnimplementedError', () {
      final backing = AdapterBacking(dbService: dbService);
      expect(
        () => backing.listDatabases('conn_1'),
        throwsUnimplementedError,
      );
      expect(
        () => backing.listTables('conn_1'),
        throwsUnimplementedError,
      );
      expect(
        () => backing.describeTable('conn_1', 't'),
        throwsUnimplementedError,
      );
    });
  });
}
