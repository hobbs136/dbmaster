// ============================================================================
// DBT-T19（W-16）· PG 分区建表 DDL 生成单测
//
// 断言面（任务书 T19 验收①「adapter SQL 生成逐字断言」）：
//   - RANGE：父表 PK 提升为表级约束（复合 PK 内联会形成多个主键约束）+
//     PARTITION BY 子句 + 分区链式 FROM/TO（首分区 MINVALUE，后续下界 =
//     前一分区上界；MAXVALUE 透传）；
//   - LIST：FOR VALUES IN 值列表；
//   - 空 partition 行跳过（与 Doris 先例一致）；
//   - 无 PK 分区表合法（不强制 PK）；
//   - 标识符双引号转义 + schema 限定名逐段转义。
// 方言说明：PG 不支持 MySQL/Doris 式内联分区定义，生成多语句序列
//（父表 + 逐分区 CREATE TABLE … PARTITION OF …），见 adapter 头注。
//
// R2 security 修复批追加 · 失败回收语义（executeQuery 注入接缝）：
//   - 父表 CREATE（stmts[0]）失败 → 零 DROP 语句 + 异常重抛（表非本操作
//     创建——同名既有业务表绝不能被回收 DROP 误删）；
//   - 子语句失败（父表属本操作）→ 回收 DROP 发出 + 异常重抛。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/postgresql_gateway_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/organisms/connection/table_dialog/create_table_dialog.dart';

/// 执行注入接缝：记录 executeQuery 语句 + 按子串命中抛引擎错误（42P07
/// 同名冲突模拟）；isConnected / currentConnection 抬为已连非只读态
/// （guardReadOnly 对 null 连接 fail-closed，见 ai_adapter_mixin）。
class _SeamPgAdapter extends PostgreSQLAdapter {
  final List<String> executed = <String>[];
  final List<String> failOnContaining = <String>[];

  @override
  bool get isConnected => true;

  @override
  DatabaseConnection? get currentConnection => DatabaseConnection(
    id: 'seam_conn',
    name: 'seam',
    type: DatabaseType.postgresql,
    host: '127.0.0.1',
    port: 5432,
    database: 'seam_db',
  );

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    if (failOnContaining.any(sql.contains)) {
      throw const PostgreSqlGatewayException(
        'DB_ERROR',
        'relation "public.legacy" already exists',
        engineCode: '42P07',
      );
    }
    executed.add(sql);
    return QueryResult(columns: const ['ok'], rows: const []);
  }
}

void main() {
  group('PostgreSQLAdapter.buildPgPartitionDdl（DBT-T19）', () {
    test('RANGE：PK 提升表级 + 链式 FROM/TO + MAXVALUE 透传', () {
      final columns = <DbColumn>[
        DbColumn(
          name: 'id',
          type: 'BIGINT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(
          name: 'amt',
          type: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'note', type: 'TEXT'),
      ];
      final ddl = PostgreSQLAdapter.buildPgPartitionDdl(
        'public.sales_range',
        columns,
        strategy: 'RANGE',
        column: 'amt',
        partitions: const [
          (name: 'p0', values: '100'),
          (name: 'p1', values: '200'),
          (name: 'p2', values: 'MAXVALUE'),
        ],
      );
      expect(ddl, [
        'CREATE TABLE "public"."sales_range" ('
            '"id" BIGINT NOT NULL, '
            '"amt" INTEGER NOT NULL, '
            '"note" TEXT, '
            'PRIMARY KEY ("id", "amt")) '
            'PARTITION BY RANGE ("amt")',
        'CREATE TABLE "public"."p0" PARTITION OF "public"."sales_range" '
            'FOR VALUES FROM (MINVALUE) TO (100)',
        'CREATE TABLE "public"."p1" PARTITION OF "public"."sales_range" '
            'FOR VALUES FROM (100) TO (200)',
        'CREATE TABLE "public"."p2" PARTITION OF "public"."sales_range" '
            'FOR VALUES FROM (200) TO (MAXVALUE)',
      ]);
    });

    test('LIST：FOR VALUES IN 值列表 + 无 schema 前缀表名', () {
      final columns = <DbColumn>[
        DbColumn(
          name: 'code',
          type: 'TEXT',
          isPrimaryKey: true,
          isNullable: false,
        ),
      ];
      final ddl = PostgreSQLAdapter.buildPgPartitionDdl(
        'cities',
        columns,
        strategy: 'LIST',
        column: 'code',
        partitions: const [
          (name: 'p_east', values: "'NY', 'Boston'"),
          (name: 'p_west', values: "'LA'"),
        ],
      );
      expect(ddl, [
        'CREATE TABLE "cities" ("code" TEXT NOT NULL, PRIMARY KEY ("code")) '
            'PARTITION BY LIST ("code")',
        'CREATE TABLE "p_east" PARTITION OF "cities" '
            "FOR VALUES IN ('NY', 'Boston')",
        "CREATE TABLE \"p_west\" PARTITION OF \"cities\" FOR VALUES IN ('LA')",
      ]);
    });

    test('无 PK 分区表合法（不强制 PRIMARY KEY 子句）', () {
      final ddl = PostgreSQLAdapter.buildPgPartitionDdl(
        'public.events',
        [DbColumn(name: 'ts', type: 'TIMESTAMP', isNullable: false)],
        strategy: 'RANGE',
        column: 'ts',
        partitions: const [(name: 'y2026', values: "'2027-01-01'")],
      );
      expect(
        ddl.first,
        'CREATE TABLE "public"."events" ("ts" TIMESTAMP NOT NULL) '
            "PARTITION BY RANGE (\"ts\")",
      );
      expect(
        ddl.last,
        'CREATE TABLE "public"."y2026" PARTITION OF "public"."events" '
            "FOR VALUES FROM (MINVALUE) TO ('2027-01-01')",
      );
    });

    test('空名/空界分区行跳过；零分区 = 仅父表语句（合法 DDL）', () {
      final ddl = PostgreSQLAdapter.buildPgPartitionDdl(
        'public.t',
        [DbColumn(name: 'c', type: 'INTEGER')],
        strategy: 'RANGE',
        column: 'c',
        partitions: const [
          (name: '', values: '10'),
          (name: 'p0', values: ''),
          (name: '', values: ''),
          (name: 'p_ok', values: '10'),
        ],
      );
      expect(ddl, hasLength(2));
      expect(ddl.last, contains('PARTITION OF'));
      expect(ddl.last, contains('"p_ok"'));
    });

    test('标识符含双引号 = 转义双写（注入面防御）', () {
      final ddl = PostgreSQLAdapter.buildPgPartitionDdl(
        'public.t"x',
        [DbColumn(name: 'c', type: 'INTEGER')],
        strategy: 'LIST',
        column: 'c',
        partitions: const [(name: 'p"q', values: '1')],
      );
      expect(ddl.first, startsWith('CREATE TABLE "public"."t""x"'));
      expect(ddl.last, startsWith('CREATE TABLE "public"."p""q"'));
    });

    test('options 序列化协议锁定（CreatePostgresTableDialog.pgPartitionOptions）',
        () {
      // 协议形状与任务书草案逐字一致（strategy/column/partitions[].name|values）。
      final options = CreatePostgresTableDialog.pgPartitionOptions(
        'RANGE',
        'amt',
        const [('p0', '100'), ('p1', '200'), ('', '')],
      );
      expect(options, {
        'pgPartition': {
          'strategy': 'RANGE',
          'column': 'amt',
          'partitions': [
            {'name': 'p0', 'values': '100'},
            {'name': 'p1', 'values': '200'},
          ],
        },
      });
      // 未选分区键 → null（不分区，走既有裸建表路径零变化）。
      expect(
        CreatePostgresTableDialog.pgPartitionOptions('RANGE', null, const [
          ('p0', '10'),
        ]),
        isNull,
      );
      // 键在而零有效分区行 → 仍产出（PG 允许零分区父表，分区后补 ATTACH）。
      expect(
        CreatePostgresTableDialog.pgPartitionOptions('LIST', 'c', const []),
        {
          'pgPartition': {'strategy': 'LIST', 'column': 'c'},
        },
      );
    });
  });

  group('PostgreSQLAdapter 分区建表失败回收语义（R2 security 修复）', () {
    setUp(() {
      // 回收路径补审计（AuditLogService 首次 initialize 读 prefs）——
      // mock 空值保证单测环境确定性；审计失败不阻塞，断言面只看语句序列。
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Future<Object?> createPartitioned(_SeamPgAdapter adapter) {
      return adapter.createTable(
        'public.legacy',
        [
          DbColumn(name: 'id', type: 'BIGINT', isPrimaryKey: true),
        ],
        options: const {
          'pgPartition': {
            'strategy': 'RANGE',
            'column': 'id',
            'partitions': [
              {'name': 'p0', 'values': '100'},
            ],
          },
        },
      );
    }

    test('a) 父表 CREATE 失败：零 DROP 语句 + 异常重抛（同名既有表不被删）',
        () async {
      final adapter = _SeamPgAdapter()
        ..failOnContaining.add('PARTITION BY'); // 命中 stmts[0]（父表语句）

      await expectLater(
        createPartitioned(adapter),
        throwsA(
          isA<PostgreSqlGatewayException>()
              .having((e) => e.engineCode, 'engineCode', '42P07'),
        ),
        reason: '引擎错误原文应重抛（dialog 引擎错误兜底展示）',
      );
      // 核心断言：零 DROP——首语句失败 = 表非本操作创建，绝不可回收。
      expect(
        adapter.executed.where((s) => s.startsWith('DROP')),
        isEmpty,
        reason: '父表 CREATE 失败不得发出任何回收 DROP（防误删同名既有表）',
      );
      expect(adapter.executed, isEmpty, reason: '失败后不应再执行任何语句');
    });

    test('b) 子语句失败（父表属本操作）：回收 DROP 发出 + 异常重抛', () async {
      final adapter = _SeamPgAdapter()
        ..failOnContaining.add('PARTITION OF'); // 命中子语句，父表已建成

      await expectLater(
        createPartitioned(adapter),
        throwsA(isA<PostgreSqlGatewayException>()),
      );
      expect(adapter.executed, hasLength(2));
      expect(adapter.executed[0], contains('PARTITION BY'),
          reason: '父表 CREATE 已成功执行');
      expect(
        adapter.executed[1],
        'DROP TABLE IF EXISTS "public"."legacy"',
        reason: '仅子语句失败才回收本操作创建的父表',
      );
    });
  });
}
