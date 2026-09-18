// spec 041 (US3 / T023) — buildFilteredSelect 纯函数表驱动单测。
// 覆盖：各方言标识符引号、SQLServer TOP vs LIMIT、AND/OR、isNull/isNotNull、
// 恶意值转义、标识符白名单跳过、空值/空条件边界。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/filter_condition.dart';
import 'package:dbmaster/utils/filter_query_builder.dart';

FilterCondition _cond(String field, FilterOperator op, [String value = '']) =>
    FilterCondition(field: field, op: op, value: value);

void main() {
  group('buildFilteredSelect — 方言 dispatch (LIMIT vs TOP)', () {
    test('MySQL: 反引号 + 尾部 LIMIT', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 'users',
        conditions: [_cond('status', FilterOperator.eq, 'active')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, "SELECT * FROM `users` WHERE `status` = 'active' LIMIT 3000;");
    });

    test('PostgreSQL: 双引号 + schema.table 拆段', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 'public.users',
        conditions: [_cond('status', FilterOperator.eq, 'active')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.postgresql,
      );
      expect(
        sql,
        'SELECT * FROM "public"."users" WHERE "status" = \'active\' LIMIT 3000;',
      );
    });

    test('SQLite: 双引号', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 'users',
        conditions: [_cond('name', FilterOperator.eq, 'Bob')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.sqlite,
      );
      expect(sql, 'SELECT * FROM "users" WHERE "name" = \'Bob\' LIMIT 3000;');
    });

    test('SQL Server: 方括号 + SELECT TOP N（无 LIMIT）', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 'users',
        conditions: [_cond('status', FilterOperator.eq, 'active')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.sqlserver,
      );
      expect(sql, 'SELECT TOP 3000 * FROM [users] WHERE [status] = \'active\';');
    });

    test('Doris / TDengine: 反引号 + 尾部 LIMIT', () {
      for (final t in [DatabaseType.doris, DatabaseType.tdengine]) {
        final sql = buildFilteredSelect(
          qualifiedTable: 'users',
          conditions: [_cond('status', FilterOperator.eq, 'active')],
          combinator: FilterCombinator.and,
          dbType: t,
        );
        expect(
          sql,
          "SELECT * FROM `users` WHERE `status` = 'active' LIMIT 3000;",
        );
      }
    });
  });

  group('buildFilteredSelect — 组合器与操作符', () {
    test('AND 两条件', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [
          _cond('a', FilterOperator.eq, '1'),
          _cond('b', FilterOperator.eq, '2'),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, "SELECT * FROM `t` WHERE `a` = '1' AND `b` = '2' LIMIT 3000;");
    });

    test('OR 两条件', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [
          _cond('a', FilterOperator.eq, '1'),
          _cond('b', FilterOperator.eq, '2'),
        ],
        combinator: FilterCombinator.or,
        dbType: DatabaseType.mysql,
      );
      expect(sql, "SELECT * FROM `t` WHERE `a` = '1' OR `b` = '2' LIMIT 3000;");
    });

    test('isNull / isNotNull 不取值', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [
          _cond('a', FilterOperator.isNull),
          _cond('b', FilterOperator.isNotNull),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, 'SELECT * FROM `t` WHERE `a` IS NULL AND `b` IS NOT NULL LIMIT 3000;');
    });

    test('like / notLike / 比较符', () {
      expect(
        buildFilteredSelect(
          qualifiedTable: 't',
          conditions: [_cond('name', FilterOperator.like, '%a%')],
          combinator: FilterCombinator.and,
          dbType: DatabaseType.mysql,
        ),
        "SELECT * FROM `t` WHERE `name` LIKE '%a%' LIMIT 3000;",
      );
      expect(
        buildFilteredSelect(
          qualifiedTable: 't',
          conditions: [_cond('n', FilterOperator.gte, '10')],
          combinator: FilterCombinator.and,
          dbType: DatabaseType.mysql,
        ),
        "SELECT * FROM `t` WHERE `n` >= '10' LIMIT 3000;",
      );
    });
  });

  group('buildFilteredSelect — 安全（转义 / 白名单）', () {
    test('恶意值 O\'Brien 被转义（\' → \'\'）', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 'users',
        conditions: [_cond('name', FilterOperator.eq, "O'Brien")],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, "SELECT * FROM `users` WHERE `name` = 'O''Brien' LIMIT 3000;");
    });

    test('含分号 / 注释符的值不破坏 SQL 结构（仅作字面值）', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 'users',
        conditions: [_cond('name', FilterOperator.eq, 'a; -- /*')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.postgresql,
      );
      // 整个值被当字面值（单引号包裹），不会断句或注入
      expect(
        sql,
        'SELECT * FROM "users" WHERE "name" = \'a; -- /*\' LIMIT 3000;',
      );
    });

    test('非法列名（空格 / 注入尝试）被白名单跳过', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [
          _cond('a', FilterOperator.eq, '1'), // 合法
          _cond('b; DROP TABLE t', FilterOperator.eq, 'x'), // 非法 → 跳过
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      // 只有合法条件 a 进 WHERE
      expect(sql, "SELECT * FROM `t` WHERE `a` = '1' LIMIT 3000;");
    });

    test('全部非法列名 → 无 WHERE', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [_cond('bad name', FilterOperator.eq, 'x')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, 'SELECT * FROM `t` LIMIT 3000;');
    });
  });

  group('buildFilteredSelect — 边界', () {
    test('空条件 → 无 WHERE 全表查询', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, 'SELECT * FROM `t` LIMIT 3000;');
    });

    test('需值操作符空值 → 该条件跳过', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [
          _cond('a', FilterOperator.eq, ''), // 空值 → 跳过
          _cond('b', FilterOperator.eq, '2'),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, "SELECT * FROM `t` WHERE `b` = '2' LIMIT 3000;");
    });

    test('自定义 limit 生效', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
        limit: 100,
      );
      expect(sql, 'SELECT * FROM `t` LIMIT 100;');
    });

    test('SQL Server 自定义 limit → TOP', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.sqlserver,
        limit: 50,
      );
      expect(sql, 'SELECT TOP 50 * FROM [t];');
    });
  });

  group('buildFilteredSelect — boolean 值（per-dbType 裸值，不加引号）', () {
    FilterCondition _bool(String field, String value) => FilterCondition(
      field: field,
      op: FilterOperator.eq,
      value: value,
      kind: FilterValueKind.boolean,
    );

    test('PostgreSQL boolean → TRUE/FALSE', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [_bool('active', 'true')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.postgresql,
      );
      expect(sql, 'SELECT * FROM "t" WHERE "active" = TRUE LIMIT 3000;');
    });

    test('MySQL boolean → 1/0', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [_bool('active', 'false')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, "SELECT * FROM `t` WHERE `active` = 0 LIMIT 3000;");
    });

    test('SQL Server boolean → 1/0', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [_bool('active', 'true')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.sqlserver,
      );
      expect(sql, 'SELECT TOP 3000 * FROM [t] WHERE [active] = 1;');
    });

    test('SQLite/Doris/TDengine boolean → 1/0', () {
      for (final t in [
        DatabaseType.sqlite,
        DatabaseType.doris,
        DatabaseType.tdengine,
      ]) {
        final sql = buildFilteredSelect(
          qualifiedTable: 't',
          conditions: [_bool('active', 'true')],
          combinator: FilterCombinator.and,
          dbType: t,
        );
        expect(sql.contains('= 1'), isTrue, reason: '$t boolean true → 1');
      }
    });

    test('boolean 输入 1/0 也归一化为裸值', () {
      final sql = buildFilteredSelect(
        qualifiedTable: 't',
        conditions: [_bool('active', '1')],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      expect(sql, "SELECT * FROM `t` WHERE `active` = 1 LIMIT 3000;");
    });
  });
}
