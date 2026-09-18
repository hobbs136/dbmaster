//! 能力位唯一真相（c01_port_contract.md §2.3/§3 的编译期表）。
//!
//! 三源收编（c04_capability_matrix.md §12 双源实锤的治理）：
//! - §3.1 通用 SQL 位 ← `DatabaseType` 21 getter 中的 17 个（其余 4 个为派生：
//!   isSqlLike ≡ isSQL、isNoSQL/isSchemaLess ≡ !sql.query、
//!   supportsProgrammableObjects 为若干位之或）；
//! - §3.2 marker 位 ← database_abstract.dart 12 个 marker 接口的 adapter 实现
//!   （2026-08-19 逐文件 grep 实测；PG 的 ProcessList 为 builder 直查而非
//!   marker 实现，但 c01 §3.1 明确 PG Terminate 与 MySQL/Doris 同键，故
//!   process.list 含 pg、process.kill 为 {my,do,pg}——SS 进程只读无 kill）；
//! - §3.3 DS 分支位 + §3.4 非 SQL 专有位 ← c01 §3 定义的类型集。
//!
//! 防漂移（§3.5.1）：`test/services/ports/capability_table_test.dart` 断言
//! 17 个 getter 取值与本表逐格等价——两侧任何一方改动先过该测试。enum getter
//! 保持现状实现（供存量 207 处 `DatabaseType.` 引用消费，按区块重建清零），
//! 新代码能力判定一律经 `DbCapabilityPort.hasCapability`。
//!
//! 键空间：`<域>.<动词或对象>` 小驼峰；域 ∈ {sql, tx, ddl, table, view, proc,
//! func, trigger, event, sequence, schema, process, server, query, engine,
//! io, ai, charset, script, json, replication, pg, sqlite, mongo, redis,
//! td, ch, meta}。`ch.dictionary` 为 backlog 位，恒 false（预留不设真值）。

import '../../models/database_models.dart';

// 缩写：my=mysql pg=postgresql lt=sqlite do=doris rd=redis mg=mongodb
//      td=tdengine ss=sqlserver ch=clickhouse
//      ob/ti/sr/md = T22-T25 MySQL 协议族薄适配四成员（OceanBase/TiDB/
//      StarRocks/MariaDB）——通用 SQL 位与 marker 位与 MySQL 同面（客户端
//      复用 MySQLGatewayBaseAdapter，T29 起）；专有位（engine.status 等）不随入。
const Set<DatabaseType> _sqlFamily = {
  DatabaseType.mysql,
  DatabaseType.postgresql,
  DatabaseType.sqlite,
  DatabaseType.doris,
  DatabaseType.tdengine,
  DatabaseType.sqlserver,
  DatabaseType.clickhouse,
  DatabaseType.oceanbase,
  DatabaseType.tidb,
  DatabaseType.starrocks,
  DatabaseType.mariadb,
};
const Set<DatabaseType> _all = {
  DatabaseType.mysql,
  DatabaseType.postgresql,
  DatabaseType.sqlite,
  DatabaseType.doris,
  DatabaseType.redis,
  DatabaseType.mongodb,
  DatabaseType.tdengine,
  DatabaseType.sqlserver,
  DatabaseType.clickhouse,
  DatabaseType.oceanbase,
  DatabaseType.tidb,
  DatabaseType.starrocks,
  DatabaseType.mariadb,
};

/// 位 id → 取真类型集（声明面；只读常量）。
const Map<String, Set<DatabaseType>> _capabilityBits = {
  // ── §3.1 通用 SQL 位（getter 收编；取值 = c04 §12.2 逐格）──
  'sql.query': _sqlFamily,
  'table.editColumns': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.doris,
    DatabaseType.sqlserver,
    DatabaseType.clickhouse,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'table.editIndexes': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.doris,
    DatabaseType.sqlserver,
    DatabaseType.clickhouse,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'view.list': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.doris,
    DatabaseType.sqlserver,
    DatabaseType.clickhouse,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'table.foreignKeys': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.doris,
    DatabaseType.sqlserver,
    DatabaseType.clickhouse,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'proc.list': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlserver,
  },
  'func.list': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlserver,
  },
  'trigger.list': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlserver,
  },
  'event.list': {DatabaseType.mysql},
  'table.analyze': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.doris,
  },
  'table.optimize': {DatabaseType.mysql, DatabaseType.postgresql},
  'table.check': {DatabaseType.mysql, DatabaseType.postgresql},
  'schema.namespace': {DatabaseType.postgresql, DatabaseType.sqlserver},
  'view.materialized': {DatabaseType.postgresql, DatabaseType.doris},
  'sequence.list': {DatabaseType.postgresql},
  'table.rename': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.doris,
    DatabaseType.redis, // isSQL || redis（现状 getter 语义）
    DatabaseType.tdengine,
    DatabaseType.sqlserver,
    DatabaseType.clickhouse,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'table.stats': {
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },

  // ── §3.2 marker 接口位（adapter 声明实测，2026-08-19）──
  'tx.manual': {
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
  },
  'ddl.execute': {
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
  },
  'script.export': {
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
  },
  'script.execute': {
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
  },
  'charset.list': {
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.sqlserver,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'process.list': {
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.postgresql,
    DatabaseType.sqlserver,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  // 原 query.kill：MySQL KILL QUERY / PG Terminate / Doris Kill 同键；SS 只读无 kill。
  'process.kill': {
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.postgresql,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'replication.status': {
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.sqlserver,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'pg.extension': {DatabaseType.postgresql},
  'json.columns': {
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.sqlserver,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'sqlite.pragma': {DatabaseType.sqlite},
  'sqlite.attach': {DatabaseType.sqlite},

  // ── §3.3 DS 分支位（收编 87 处字面量的语义；引用随区块重建清零）──
  'server.users': {DatabaseType.mysql}, // getServerUsers 仅 MY
  'query.explain': _sqlFamily, // EXPLAIN 族，SQL 类
  'engine.status': {DatabaseType.mysql}, // MySQL 专有
  'io.dataSync': {DatabaseType.mysql, DatabaseType.doris},
  'ai.analyze': {DatabaseType.mysql, DatabaseType.doris},
  // C19 增补：sidebar 连接/搜索门控收编（原 UI 字面量 {my,pg,do,td,ss} / {pg}）。
  'ddl.createDatabase': {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.doris,
    DatabaseType.tdengine,
    DatabaseType.sqlserver,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  },
  'pg.serverSearch': {DatabaseType.postgresql}, // pg_catalog 直查搜索
  // 通用位：按现状全类型可达（c03 §3）。
  'io.import': _all,
  'io.export': _all,
  'schema.diff': _all,
  // AI 面板入口，通用位恒真（AI 配置与否属 UI 态非类型位）。
  'ai.assistant': _all,

  // ── §3.4 非 SQL 专有位 ──
  'redis.keyspace.list': {DatabaseType.redis},
  'redis.keyspace.search': {DatabaseType.redis},
  'redis.keyspace.expiring': {DatabaseType.redis},
  'redis.structure.string': {DatabaseType.redis},
  'redis.structure.hash': {DatabaseType.redis},
  'redis.structure.list': {DatabaseType.redis},
  'redis.structure.set': {DatabaseType.redis},
  'redis.structure.zset': {DatabaseType.redis},
  'redis.structure.stream': {DatabaseType.redis},
  'redis.pubsub': {DatabaseType.redis},
  'redis.lua': {DatabaseType.redis},
  'redis.slowlog': {DatabaseType.redis},
  'redis.functions': {DatabaseType.redis},
  'redis.config': {DatabaseType.redis},
  'redis.cli': {DatabaseType.redis},
  'mongo.aggregate': {DatabaseType.mongodb},
  'mongo.validation': {DatabaseType.mongodb},
  'mongo.gridfs': {DatabaseType.mongodb},
  'mongo.insertDocument': {DatabaseType.mongodb},
  'td.supertable': {DatabaseType.tdengine},
  'td.subtable': {DatabaseType.tdengine},
  'td.tag': {DatabaseType.tdengine},

  // ── backlog 预留位（恒 false，键空间占位防拼错）──
  'ch.dictionary': <DatabaseType>{},
};

/// 能力位静态查询（sync、编译期语义）。未知 id 返回 false。
class CapabilityTable {
  CapabilityTable._();

  /// 位 id → 取真类型集（声明面，只读）。
  static Map<String, Set<DatabaseType>> get bits => _capabilityBits;

  /// 注册键空间全集（§3.5.2 lint / 菜单装配防拼错用）。
  static Set<String> get knownCapabilityIds => _capabilityBits.keys.toSet();

  /// 类型 → 该类型全部取真能力位（快照，勿原地修改）。
  static Set<String> of(DatabaseType type) =>
      _perType[type] ?? const <String>{};

  static bool has(DatabaseType type, String capabilityId) =>
      _capabilityBits[capabilityId]?.contains(type) ?? false;

  static final Map<DatabaseType, Set<String>> _perType = () {
    final map = <DatabaseType, Set<String>>{};
    for (final type in DatabaseType.values) {
      map[type] = Set.unmodifiable(
        _capabilityBits.entries
            .where((e) => e.value.contains(type))
            .map((e) => e.key)
            .toSet(),
      );
    }
    return map;
  }();
}
