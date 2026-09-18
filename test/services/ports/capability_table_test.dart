// =============================================================================
// 能力真值表守卫测试（c01_port_contract.md §3.5.1 —— port 落地随附）。
// =============================================================================
// 断言 CapabilityTable ≡ DatabaseType 能力 getter 逐格等价（c04 §12.2 为
// 事实源）：两侧任何一方的改动都必须先过本测试，防三源漂移（表 / getter /
// c04 矩阵）。另覆盖 §3.3/§3.4 收编位取值、键空间 lint 与未知位语义。
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/ports/capability_table.dart';

/// §3.5.1 主守卫：17 个被收编的 getter ↔ 能力位逐格等价。
void main() {
  final getterBits = <(String, bool Function(DatabaseType))>[
    ('sql.query', (t) => t.isSQL),
    ('table.editColumns', (t) => t.supportsColumnEdit),
    ('table.editIndexes', (t) => t.supportsIndexEdit),
    ('view.list', (t) => t.supportsViews),
    ('view.materialized', (t) => t.supportsMaterializedViews),
    ('table.foreignKeys', (t) => t.supportsForeignKeys),
    ('proc.list', (t) => t.supportsProcedures),
    ('func.list', (t) => t.supportsFunctions),
    ('trigger.list', (t) => t.supportsTriggers),
    ('event.list', (t) => t.supportsEvents),
    ('table.analyze', (t) => t.supportsAnalyzeTable),
    ('table.optimize', (t) => t.supportsOptimizeTable),
    ('table.check', (t) => t.supportsCheckTable),
    ('schema.namespace', (t) => t.supportsSchemas),
    ('sequence.list', (t) => t.supportsSequences),
    ('table.rename', (t) => t.supportsRenameTable),
    ('table.stats', (t) => t.supportsTableStats),
  ];

  test('§3.5.1 能力位 ≡ getter 逐格等价（c04 §12.2）', () {
    for (final (bit, getter) in getterBits) {
      for (final type in DatabaseType.values) {
        expect(
          CapabilityTable.has(type, bit),
          getter(type),
          reason: '$bit ≠ getter on ${type.name}',
        );
      }
    }
  });

  test('派生 getter 语义：isSqlLike ≡ sql.query，isNoSQL/isSchemaLess ≡ 补集', () {
    for (final type in DatabaseType.values) {
      final isSql = CapabilityTable.has(type, 'sql.query');
      expect(type.isSqlLike, isSql, reason: 'isSqlLike on ${type.name}');
      expect(type.isNoSQL, !isSql, reason: 'isNoSQL on ${type.name}');
      expect(type.isSchemaLess, !isSql, reason: 'isSchemaLess on ${type.name}');
    }
  });

  test('派生 getter：supportsProgrammableObjects = 五个对象位之或', () {
    const bits = [
      'view.list',
      'proc.list',
      'func.list',
      'trigger.list',
      'event.list',
    ];
    for (final type in DatabaseType.values) {
      final any = bits.any((b) => CapabilityTable.has(type, b));
      expect(
        type.supportsProgrammableObjects,
        any,
        reason: 'programmableObjects on ${type.name}',
      );
    }
  });

  group('§3.2 marker 位（adapter 声明实测 2026-08-19）', () {
    test('tx.manual / ddl.execute / script.export / script.execute 同集', () {
      const bits = [
        'tx.manual',
        'ddl.execute',
        'script.export',
        'script.execute',
      ];
      const expected = {
        DatabaseType.mysql,
        DatabaseType.doris,
        DatabaseType.postgresql,
        DatabaseType.sqlite,
        DatabaseType.tdengine,
        DatabaseType.sqlserver,
        DatabaseType.oceanbase,
        DatabaseType.tidb,
        DatabaseType.starrocks,
        DatabaseType.mariadb,
      };
      for (final bit in bits) {
        expect(CapabilityTable.bits[bit], expected, reason: bit);
      }
    });

    test('process.list 含 pg（builder 直查）、process.kill 排除 ss（只读）', () {
      expect(CapabilityTable.bits['process.list'], {
        DatabaseType.mysql,
        DatabaseType.doris,
        DatabaseType.postgresql,
        DatabaseType.sqlserver,
        DatabaseType.oceanbase,
        DatabaseType.tidb,
        DatabaseType.starrocks,
        DatabaseType.mariadb,
      });
      expect(CapabilityTable.bits['process.kill'], {
        DatabaseType.mysql,
        DatabaseType.doris,
        DatabaseType.postgresql,
        DatabaseType.oceanbase,
        DatabaseType.tidb,
        DatabaseType.starrocks,
        DatabaseType.mariadb,
      });
    });

    test(
      'charset.list / replication.status / json.columns / sqlite.* / pg.*',
      () {
        expect(CapabilityTable.bits['charset.list'], {
          DatabaseType.mysql,
          DatabaseType.doris,
          DatabaseType.sqlserver,
          DatabaseType.oceanbase,
          DatabaseType.tidb,
          DatabaseType.starrocks,
          DatabaseType.mariadb,
        });
        expect(CapabilityTable.bits['replication.status'], {
          DatabaseType.mysql,
          DatabaseType.doris,
          DatabaseType.sqlserver,
          DatabaseType.oceanbase,
          DatabaseType.tidb,
          DatabaseType.starrocks,
          DatabaseType.mariadb,
        });
        expect(CapabilityTable.bits['json.columns'], {
          DatabaseType.mysql,
          DatabaseType.doris,
          DatabaseType.postgresql,
          DatabaseType.sqlite,
          DatabaseType.sqlserver,
          DatabaseType.oceanbase,
          DatabaseType.tidb,
          DatabaseType.starrocks,
          DatabaseType.mariadb,
        });
        expect(CapabilityTable.bits['sqlite.pragma'], {DatabaseType.sqlite});
        expect(CapabilityTable.bits['sqlite.attach'], {DatabaseType.sqlite});
        expect(CapabilityTable.bits['pg.extension'], {DatabaseType.postgresql});
      },
    );
  });

  group('§3.3 DS 分支位', () {
    test(
      'server.users / engine.status 仅 mysql；dataSync/aiAnalyze 为 {my,do}',
      () {
        expect(CapabilityTable.bits['server.users'], {DatabaseType.mysql});
        expect(CapabilityTable.bits['engine.status'], {DatabaseType.mysql});
        expect(CapabilityTable.bits['io.dataSync'], {
          DatabaseType.mysql,
          DatabaseType.doris,
        });
        expect(CapabilityTable.bits['ai.analyze'], {
          DatabaseType.mysql,
          DatabaseType.doris,
        });
      },
    );

    test('通用位 io.import/io.export/schema.diff/ai.assistant 全类型恒真', () {
      for (final bit in const [
        'io.import',
        'io.export',
        'schema.diff',
        'ai.assistant',
      ]) {
        expect(
          CapabilityTable.bits[bit],
          DatabaseType.values.toSet(),
          reason: bit,
        );
      }
    });

    test('query.explain = SQL 七类型', () {
      expect(
        CapabilityTable.bits['query.explain'],
        DatabaseType.values.where((t) => t.isSQL).toSet(),
      );
    });

    // C19 增补位（sidebar 清零收编：连接菜单门控 + PG 服务端搜索门控）；
    // T22-T25 四成员（ob/ti/sr/md）并入建库门控（复用 MySQL 形态）。
    test(
      'ddl.createDatabase = {my,pg,do,td,ss,ob,ti,sr,md}；pg.serverSearch 仅 pg',
      () {
        expect(CapabilityTable.bits['ddl.createDatabase'], {
          DatabaseType.mysql,
          DatabaseType.postgresql,
          DatabaseType.doris,
          DatabaseType.tdengine,
          DatabaseType.sqlserver,
          DatabaseType.oceanbase,
          DatabaseType.tidb,
          DatabaseType.starrocks,
          DatabaseType.mariadb,
        });
        expect(CapabilityTable.bits['pg.serverSearch'], {
          DatabaseType.postgresql,
        });
      },
    );

    test(
      'createTableMenuAction 门控集 = {my,do,lt,ss,pg,td,ob,ti,sr,md}（单一真相等价守卫）',
      () {
        // enum getter 是「新建表」菜单门控与动作路由的单一真相——断言其
        // 非 null 集与预期类型集逐格等价（防门控/路由漂移）。
        final supported = DatabaseType.values
            .where((t) => t.createTableMenuAction != null)
            .toSet();
        expect(supported, {
          DatabaseType.mysql,
          DatabaseType.doris,
          DatabaseType.sqlite,
          DatabaseType.sqlserver,
          DatabaseType.postgresql,
          DatabaseType.tdengine,
          DatabaseType.oceanbase,
          DatabaseType.tidb,
          DatabaseType.starrocks,
          DatabaseType.mariadb,
        });
        // 专属对话框路由
        expect(
          DatabaseType.postgresql.createTableMenuAction,
          'create_table_pg',
        );
        expect(
          DatabaseType.tdengine.createTableMenuAction,
          'create_supertable',
        );
        expect(DatabaseType.mysql.createTableMenuAction, 'create_table');
      },
    );

    test(
      'C19 树形态 getter：isConnectionLevelTree/isFlatFileTree/hasDatabaseObjectLayer',
      () {
        expect(
          DatabaseType.values.where((t) => t.isConnectionLevelTree).toSet(),
          {DatabaseType.redis, DatabaseType.sqlite},
        );
        expect(DatabaseType.values.where((t) => t.isFlatFileTree).toSet(), {
          DatabaseType.sqlite,
        });
        expect(
          DatabaseType.values.where((t) => t.hasDatabaseObjectLayer).toSet(),
          DatabaseType.values.where((t) => t.isSQL).toSet()
            ..add(DatabaseType.mongodb),
        );
        // procedureCallVerb：T-SQL EXEC，其余 CALL
        expect(DatabaseType.sqlserver.procedureCallVerb, 'EXEC');
        for (final t in DatabaseType.values.where(
          (t) => t != DatabaseType.sqlserver,
        )) {
          expect(t.procedureCallVerb, 'CALL', reason: t.name);
        }
      },
    );
  });

  group('§3.4 非 SQL 专有位', () {
    test('redis.* 位全部且仅 redis', () {
      final redisBits = CapabilityTable.knownCapabilityIds
          .where((id) => id.startsWith('redis.'))
          .toList();
      expect(redisBits.length, greaterThanOrEqualTo(15));
      for (final bit in redisBits) {
        expect(CapabilityTable.bits[bit], {DatabaseType.redis}, reason: bit);
      }
    });

    test('mongo.* / td.* 位', () {
      for (final bit in const [
        'mongo.aggregate',
        'mongo.validation',
        'mongo.gridfs',
        'mongo.insertDocument',
      ]) {
        expect(CapabilityTable.bits[bit], {DatabaseType.mongodb}, reason: bit);
      }
      for (final bit in const ['td.supertable', 'td.subtable', 'td.tag']) {
        expect(CapabilityTable.bits[bit], {DatabaseType.tdengine}, reason: bit);
      }
    });

    test('ch.dictionary backlog 预留位恒 false', () {
      for (final type in DatabaseType.values) {
        expect(CapabilityTable.has(type, 'ch.dictionary'), isFalse);
      }
    });
  });

  group('键空间与查询语义', () {
    test('未知位 id 恒 false', () {
      expect(
        CapabilityTable.has(DatabaseType.mysql, 'not.a.real.bit'),
        isFalse,
      );
      expect(CapabilityTable.has(DatabaseType.mysql, ''), isFalse);
    });

    test('键空间 lint：每个位 id 形如 <域>.<名> 且域在注册表内', () {
      const domains = {
        'sql',
        'tx',
        'ddl',
        'table',
        'view',
        'proc',
        'func',
        'trigger',
        'event',
        'sequence',
        'schema',
        'process',
        'server',
        'query',
        'engine',
        'io',
        'ai',
        'charset',
        'script',
        'json',
        'replication',
        'pg',
        'sqlite',
        'mongo',
        'redis',
        'td',
        'ch',
        'meta',
      };
      // 形如 <域>.<名>，名可多段（redis.keyspace.list / redis.structure.string）。
      final bitRe = RegExp(r'^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)+$');
      for (final id in CapabilityTable.knownCapabilityIds) {
        expect(bitRe.hasMatch(id), isTrue, reason: '格式: $id');
        expect(domains.contains(id.split('.').first), isTrue, reason: '域: $id');
      }
    });

    test('capabilitiesOf 与 has 自洽且 ⊆ 键空间', () {
      for (final type in DatabaseType.values) {
        final caps = CapabilityTable.of(type);
        for (final id in CapabilityTable.knownCapabilityIds) {
          expect(
            caps.contains(id),
            CapabilityTable.has(type, id),
            reason: '$id on ${type.name}',
          );
        }
        expect(caps.every(CapabilityTable.knownCapabilityIds.contains), isTrue);
      }
    });
  });
}
