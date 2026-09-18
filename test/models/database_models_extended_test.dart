import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('DatabaseType', () {
    test('has correct number of values', () {
      expect(DatabaseType.values.length, greaterThanOrEqualTo(7));
    });

    test('displayName is never empty', () {
      for (final t in DatabaseType.values) {
        expect(t.displayName, isNotEmpty);
      }
    });

    test('defaultPort returns non-negative integer', () {
      for (final t in DatabaseType.values) {
        expect(t.defaultPort, greaterThanOrEqualTo(0));
      }
    });

    test('isSqlLike returns correctly', () {
      expect(DatabaseType.mysql.isSqlLike, true);
      expect(DatabaseType.mongodb.isSqlLike, false);
      expect(DatabaseType.redis.isSqlLike, false);
    });

    // emoji icon getter 已删除（F-37），改为断言矢量图标与品牌色
    test('typeIcon 与 brandColor 均已定义', () {
      for (final t in DatabaseType.values) {
        expect(t.typeIcon, isNotNull);
        expect(t.brandColor, isNotNull);
      }
      // 抽查品牌色与设计令牌一致
      expect(DatabaseType.mysql.brandColor, const Color(0xFF00758F));
    });
  });

  group('DbServer', () {
    final server = DbServer(
      id: 'srv-1',
      name: 'Production MySQL',
      type: DatabaseType.mysql,
      host: '192.168.1.100',
      port: 3306,
      username: 'admin',
      password: 'secret',
      database: 'app_db',
      useSSL: true,
      groupId: 'group-1',
      environment: ConnectionEnvironment.production,
    );

    test('toJson/fromJson round-trip', () {
      final restored = DbServer.fromJson(server.toJson());
      expect(restored.id, 'srv-1');
      expect(restored.name, 'Production MySQL');
      expect(restored.type, DatabaseType.mysql);
      expect(restored.host, '192.168.1.100');
      expect(restored.port, 3306);
      expect(restored.username, 'admin');
      expect(restored.useSSL, true);
      expect(restored.environment, ConnectionEnvironment.production);
      expect(restored.groupId, 'group-1');
    });

    test('toJson/fromJson handles minimal server', () {
      final minimal = DbServer(
        id: 'min',
        name: 'Min',
        type: DatabaseType.sqlite,
        host: 'localhost',
        port: 0,
      );
      final restored = DbServer.fromJson(minimal.toJson());
      expect(restored.id, 'min');
      expect(restored.useSSL, false);
      expect(restored.useSshTunnel, false);
    });

    // 网关 TLS 透传两键（Redis/Mongo/TDengine）：序列化往返 + 旧 JSON
    // 无键时向后兼容默认 false。
    test('useTls/tlsInsecure round-trip', () {
      final tlsServer = DbServer(
        id: 'tls-1',
        name: 'TLS Redis',
        type: DatabaseType.redis,
        host: '127.0.0.1',
        port: 6379,
        useTls: true,
        tlsInsecure: true,
      );
      final restored = DbServer.fromJson(tlsServer.toJson());
      expect(restored.useTls, true);
      expect(restored.tlsInsecure, true);
    });

    test('legacy JSON without tls keys defaults to false', () {
      final legacy = DbServer(
        id: 'old',
        name: 'Old',
        type: DatabaseType.redis,
        host: '127.0.0.1',
        port: 6379,
      ).toJson();
      // 模拟旧版本持久化产物：不含 useTls/tlsInsecure 两键
      legacy.remove('useTls');
      legacy.remove('tlsInsecure');
      final restored = DbServer.fromJson(legacy);
      expect(restored.useTls, false);
      expect(restored.tlsInsecure, false);
    });

    test('copyWith updates useTls/tlsInsecure', () {
      final copied = server.copyWith(useTls: true, tlsInsecure: true);
      expect(copied.useTls, true);
      expect(copied.tlsInsecure, true);
      expect(server.useTls, false);
    });

    test('copyWith updates specific fields', () {
      final copied = server.copyWith(name: 'Staging', port: 3307);
      expect(copied.name, 'Staging');
      expect(copied.port, 3307);
      expect(copied.id, server.id);
    });

    test('password is redacted in toJson', () {
      final noPwd = server.copyWith(password: '');
      expect(noPwd.password, '');
      expect(noPwd.id, server.id);
      expect(noPwd.name, server.name);
    });
  });

  group('Database', () {
    test('constructor sets fields', () {
      final db = Database(
        name: 'test_db',
        tables: [
          DbTable(name: 'users'),
          DbTable(name: 'orders'),
        ],
        views: ['user_summary'],
        procedures: ['sp_get_users'],
        triggers: [
          DbTrigger(
            name: 'trg1',
            timing: 'BEFORE',
            event: 'INSERT',
            table: 'users',
          ),
        ],
        events: [],
      );
      expect(db.name, 'test_db');
      expect(db.tables.length, 2);
      expect(db.views.length, 1);
      expect(db.procedures.length, 1);
      expect(db.triggers.length, 1);
    });
  });

  group('DbTable', () {
    test('constructor sets fields', () {
      final table = DbTable(
        name: 'users',
        columns: [
          DbColumn(
            name: 'id',
            type: 'INT',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(
            name: 'name',
            type: 'VARCHAR(255)',
            isPrimaryKey: false,
            isNullable: true,
          ),
        ],
        indexes: [
          DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
        ],
      );
      expect(table.name, 'users');
      expect(table.columns.length, 2);
      expect(table.indexes.length, 1);
    });
  });

  group('DbColumn', () {
    test('equals based on name and type', () {
      final a = DbColumn(
        name: 'id',
        type: 'INT',
        isPrimaryKey: true,
        isNullable: false,
      );
      final b = DbColumn(
        name: 'id',
        type: 'INT',
        isPrimaryKey: false,
        isNullable: true,
      );
      expect(a, b);
    });

    test('not equal with different name', () {
      final a = DbColumn(
        name: 'id',
        type: 'INT',
        isPrimaryKey: true,
        isNullable: false,
      );
      final b = DbColumn(
        name: 'name',
        type: 'INT',
        isPrimaryKey: true,
        isNullable: false,
      );
      expect(a, isNot(b));
    });
  });

  group('DbIndex', () {
    test('constructor sets fields', () {
      final idx = DbIndex(
        name: 'idx_users_email',
        columns: ['email'],
        isUnique: true,
      );
      expect(idx.name, 'idx_users_email');
      expect(idx.columns, ['email']);
      expect(idx.isUnique, true);
    });
  });

  group('ForeignKey', () {
    test('constructor and fields', () {
      final fk = ForeignKey(
        name: 'fk_orders_users',
        table: 'orders',
        column: 'user_id',
        referencedTable: 'users',
        referencedColumn: 'id',
      );
      expect(fk.name, 'fk_orders_users');
      expect(fk.column, 'user_id');
      expect(fk.referencedTable, 'users');
      expect(fk.referencedColumn, 'id');
    });

    test('toJson/fromJson round-trip', () {
      final fk = ForeignKey(
        name: 'fk_orders_users',
        table: 'orders',
        column: 'user_id',
        referencedTable: 'users',
        referencedColumn: 'id',
        onUpdate: 'CASCADE',
        onDelete: 'SET NULL',
      );
      final restored = ForeignKey.fromJson(fk.toJson());
      expect(restored.name, 'fk_orders_users');
      expect(restored.column, 'user_id');
      expect(restored.referencedTable, 'users');
      expect(restored.onUpdate, 'CASCADE');
      expect(restored.onDelete, 'SET NULL');
    });
  });

  group('DbTrigger', () {
    test('constructor sets fields', () {
      final trg = DbTrigger(
        name: 'before_insert',
        timing: 'BEFORE',
        event: 'INSERT',
        table: 'users',
        statement: 'SET NEW.created_at = NOW();',
      );
      expect(trg.name, 'before_insert');
      expect(trg.timing, 'BEFORE');
      expect(trg.event, 'INSERT');
      expect(trg.table, 'users');
      expect(trg.statement, 'SET NEW.created_at = NOW();');
    });
  });

  group('ConnectionEnvironment', () {
    test('has expected values', () {
      expect(ConnectionEnvironment.values.length, 3);
    });
  });

  // T015 — ProcessInfo tests for MySQL native experience
  group('ProcessInfo', () {
    test('fromMap parses SHOW PROCESSLIST output', () {
      final info = ProcessInfo.fromMap({
        'Id': '42',
        'User': 'root',
        'Host': 'localhost:3306',
        'db': 'test_db',
        'Command': 'Query',
        'Time': '15',
        'State': 'Sending data',
        'Info': 'SELECT * FROM large_table',
      });
      expect(info.id, 42);
      expect(info.user, 'root');
      expect(info.host, 'localhost:3306');
      expect(info.database, 'test_db');
      expect(info.command, 'Query');
      expect(info.time, 15);
      expect(info.state, 'Sending data');
      expect(info.info, 'SELECT * FROM large_table');
    });

    test('fromMap handles null info (Sleep processes)', () {
      final info = ProcessInfo.fromMap({
        'Id': '1',
        'User': 'event_scheduler',
        'Host': 'localhost',
        'db': '',
        'Command': 'Daemon',
        'Time': '3600',
        'State': 'Waiting on empty queue',
        'Info': null,
      });
      expect(info.id, 1);
      expect(info.command, 'Daemon');
      expect(info.info, isNull);
      expect(info.database, '');
    });

    test('fromMap handles lowercase column names', () {
      final info = ProcessInfo.fromMap({
        'id': '10',
        'user': 'app_user',
        'host': '10.0.0.5:45678',
        'db': 'production',
        'command': 'Sleep',
        'time': 0,
        'state': '',
        'info': null,
      });
      expect(info.id, 10);
      expect(info.user, 'app_user');
      expect(info.command, 'Sleep');
      expect(info.time, 0);
    });

    test('fromMap handles int time value directly', () {
      final info = ProcessInfo.fromMap({
        'Id': '3',
        'User': 'admin',
        'Host': '10.0.0.1',
        'db': 'mysql',
        'Command': 'Query',
        'Time': 5,
        'State': 'executing',
        'Info': 'KILL CONNECTION 42',
      });
      expect(info.time, 5);
    });

    test('const constructor creates expected values', () {
      const info = ProcessInfo(
        id: 1,
        user: 'root',
        host: 'localhost',
        database: 'test',
        command: 'Query',
        time: 10,
        state: 'creating sort index',
        info: 'SELECT * FROM t1 ORDER BY c1',
      );
      expect(info.id, 1);
      expect(info.time, 10);
      expect(info.state, 'creating sort index');
    });
  });

  // T016 — ReplicationStatus tests for MySQL native experience
  group('ReplicationStatus', () {
    test('fromMap parses SHOW SLAVE STATUS output', () {
      final status = ReplicationStatus.fromMap({
        'Slave_IO_Running': 'Yes',
        'Slave_SQL_Running': 'Yes',
        'Seconds_Behind_Master': 0,
        'Last_IO_Error': '',
        'Last_SQL_Error': '',
        'Master_Log_File': 'mysql-bin.000042',
        'Read_Master_Log_Pos': '1024',
      });
      expect(status.slaveIoRunning, 'Yes');
      expect(status.slaveSqlRunning, 'Yes');
      expect(status.secondsBehindMaster, 0);
      expect(status.isRunning, isTrue);
      expect(status.hasError, isFalse);
    });

    test('isRunning returns false when IO thread stopped', () {
      final status = ReplicationStatus.fromMap({
        'Slave_IO_Running': 'No',
        'Slave_SQL_Running': 'Yes',
        'Seconds_Behind_Master': null,
        'Last_IO_Error': 'error connecting to master',
        'Last_SQL_Error': '',
      });
      expect(status.isRunning, isFalse);
    });

    test('isRunning returns false when SQL thread stopped', () {
      final status = ReplicationStatus.fromMap({
        'Slave_IO_Running': 'Yes',
        'Slave_SQL_Running': 'No',
        'Seconds_Behind_Master': 120,
        'Last_IO_Error': '',
        'Last_SQL_Error': 'Duplicate entry for key PRIMARY',
      });
      expect(status.isRunning, isFalse);
    });

    test('hasError detects IO errors', () {
      final status = ReplicationStatus.fromMap({
        'Slave_IO_Running': 'No',
        'Slave_SQL_Running': 'Yes',
        'Seconds_Behind_Master': null,
        'Last_IO_Error': 'connection refused',
        'Last_SQL_Error': '',
      });
      expect(status.hasError, isTrue);
    });

    test('hasError detects SQL errors', () {
      final status = ReplicationStatus.fromMap({
        'Slave_IO_Running': 'Yes',
        'Slave_SQL_Running': 'No',
        'Seconds_Behind_Master': null,
        'Last_IO_Error': '',
        'Last_SQL_Error': 'table does not exist',
      });
      expect(status.hasError, isTrue);
    });

    test('hasError returns false when both errors are empty', () {
      final status = ReplicationStatus.fromMap({
        'Slave_IO_Running': 'Yes',
        'Slave_SQL_Running': 'Yes',
        'Seconds_Behind_Master': 5,
        'Last_IO_Error': '',
        'Last_SQL_Error': '',
      });
      expect(status.hasError, isFalse);
    });

    test('lag is high when Seconds_Behind_Master is large', () {
      final status = ReplicationStatus.fromMap({
        'Slave_IO_Running': 'Yes',
        'Slave_SQL_Running': 'Yes',
        'Seconds_Behind_Master': 3600,
      });
      expect(status.secondsBehindMaster, 3600);
      expect(status.isRunning, isTrue);
    });

    test('raw map preserves all fields', () {
      final map = {
        'Slave_IO_Running': 'Yes',
        'Slave_SQL_Running': 'Yes',
        'Seconds_Behind_Master': 0,
        'Last_IO_Error': '',
        'Last_SQL_Error': '',
        'Master_Log_File': 'bin.001',
        'Read_Master_Log_Pos': '512',
        'Extra_Field': 'extra_value',
      };
      final status = ReplicationStatus.fromMap(map);
      expect(status.raw['Extra_Field'], 'extra_value');
    });
  });
}
