// PG serial/identity 列同步回归测试。
// 根因：PG serial 列的 column_default = nextval('tbl_col_seq'::regclass)，原样写进
// 目标库 CREATE TABLE 的 DEFAULT 会因序列不存在而失败 → PG 事务回滚 → 目标库无变化。
// 修复：resolvePgSerialColumn 把 integer/bigint/smallint + nextval 默认转为
// serial/bigserial/smallserial 并清空默认值（仅 PG）。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_service.dart';

void main() {
  group('resolvePgSerialColumn', () {
    test('PG integer + nextval 默认 → serial，清空默认值', () {
      final r = resolvePgSerialColumn(
        DatabaseType.postgresql,
        'integer',
        "nextval('users_id_seq'::regclass)",
      );
      expect(r.type, 'serial');
      expect(r.defaultValue, isNull);
    });

    test('PG bigint + nextval 默认 → bigserial', () {
      final r = resolvePgSerialColumn(
        DatabaseType.postgresql,
        'bigint',
        "nextval('events_id_seq'::regclass)",
      );
      expect(r.type, 'bigserial');
      expect(r.defaultValue, isNull);
    });

    test('PG smallint + nextval 默认 → smallserial', () {
      final r = resolvePgSerialColumn(
        DatabaseType.postgresql,
        'smallint',
        "nextval('codes_code_seq'::regclass)",
      );
      expect(r.type, 'smallserial');
      expect(r.defaultValue, isNull);
    });

    test('PG int4/int8/int2 别名也应识别', () {
      expect(
        resolvePgSerialColumn(
          DatabaseType.postgresql,
          'int4',
          "nextval('a_s'::regclass)",
        ).type,
        'serial',
      );
      expect(
        resolvePgSerialColumn(
          DatabaseType.postgresql,
          'int8',
          "nextval('a_s'::regclass)",
        ).type,
        'bigserial',
      );
    });

    test('PG 整型但默认不是 nextval（如 now()）→ 原样保留', () {
      final r = resolvePgSerialColumn(
        DatabaseType.postgresql,
        'integer',
        'now()',
      );
      expect(r.type, 'integer');
      expect(r.defaultValue, 'now()');
    });

    test('PG 整型无默认值 → 原样保留', () {
      final r = resolvePgSerialColumn(DatabaseType.postgresql, 'integer', null);
      expect(r.type, 'integer');
      expect(r.defaultValue, isNull);
    });

    test('PG 非整型（varchar）即使带 nextval → 不转、保留默认值', () {
      final r = resolvePgSerialColumn(
        DatabaseType.postgresql,
        'character varying(255)',
        "nextval('weird_seq'::regclass)",
      );
      expect(r.type, 'character varying(255)');
      expect(r.defaultValue, "nextval('weird_seq'::regclass)");
    });

    test('非 PG（MySQL/SQLite）即便整型 + nextval → 不转', () {
      final mysql = resolvePgSerialColumn(
        DatabaseType.mysql,
        'integer',
        "nextval('s'::regclass)",
      );
      expect(mysql.type, 'integer');
      expect(mysql.defaultValue, "nextval('s'::regclass)");

      final sqlite = resolvePgSerialColumn(
        DatabaseType.sqlite,
        'integer',
        "nextval('s'::regclass)",
      );
      expect(sqlite.type, 'integer');
    });

    test('nextval 前缀大小写不敏感（PG 返回的 column_default 恒小写，稳妥起见仍校验）', () {
      // PG information_schema 实际返回小写 nextval(...)；此处仅锁定小写契约。
      final r = resolvePgSerialColumn(
        DatabaseType.postgresql,
        'integer',
        "nextval('t_id_seq'::regclass)",
      );
      expect(r.type, 'serial');
    });
  });

  // FK 引用 schema 限定——裸名 REFERENCES 在目标库 search_path(public)
  // 下解析不到，补同 schema 前缀。
  group('resolvePgQualifiedFkReference', () {
    test('本表带 schema + 裸名引用 → 补同 schema 限定', () {
      expect(
        resolvePgQualifiedFkReference('ecommerce.products', 'brands'),
        'ecommerce.brands',
      );
    });

    test('引用已限定（含点）→ 原样返回，不重复限定', () {
      expect(
        resolvePgQualifiedFkReference('ecommerce.products', 'other.brands'),
        'other.brands',
      );
      expect(
        resolvePgQualifiedFkReference('ecommerce.products', 'public.users'),
        'public.users',
      );
    });

    test('本表无 schema（裸名）→ 原样返回', () {
      expect(resolvePgQualifiedFkReference('products', 'brands'), 'brands');
    });
  });
}
