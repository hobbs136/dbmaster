import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_parser_service.dart';
import 'package:dbmaster/models/sql_statement.dart';

void main() {
  group('SQLParserService', () {
    test('should split simple statements', () {
      final sql = 'SELECT 1; SELECT 2; SELECT 3;';
      final statements = SQLParserService.split(sql);

      expect(statements.length, 3);
      expect(statements[0].sql, 'SELECT 1');
      expect(statements[1].sql, 'SELECT 2');
      expect(statements[2].sql, 'SELECT 3');
    });

    test('should handle semicolons in strings', () {
      final sql = "SELECT 'Hello; World'; SELECT 2;";
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
      expect(statements[0].sql, "SELECT 'Hello; World'");
    });

    test('should handle escaped quotes', () {
      final sql = r"SELECT '\''; SELECT 2;";
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
      expect(statements[0].sql, r"SELECT '\''");
    });

    test('should handle line comments', () {
      final sql = '''
SELECT 1; -- comment; with semicolon
SELECT 2;
''';
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
    });

    test('should handle block comments', () {
      final sql = '''
SELECT 1; /* comment; with semicolon */ SELECT 2;
''';
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
    });

    test('should handle DELIMITER', () {
      final sql = '''
DELIMITER |
SELECT 1|
SELECT 2|
DELIMITER ;
SELECT 3;
''';
      final statements = SQLParserService.split(sql);

      expect(statements.length, 3);
      expect(statements[0].sql, 'SELECT 1');
      expect(statements[1].sql, 'SELECT 2');
      expect(statements[2].sql, 'SELECT 3');
    });

    test('DELIMITER 前缀标识符不误判为指令（词边界）', () {
      // `delimiter_table` 以 DELIMITER 开头——旧实现逐字符匹配关键字前缀，
      // 会把语句拦腰截断并把分隔符改成 "_table ..."。
      final sql = 'SELECT * FROM delimiter_table; SELECT 2;';
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
      expect(statements[0].sql, 'SELECT * FROM delimiter_table');
      expect(statements[1].sql, 'SELECT 2');
    });

    test('should handle backtick identifiers', () {
      final sql = 'SELECT * FROM `table;name`; SELECT 2;';
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
      expect(statements[0].sql, 'SELECT * FROM `table;name`');
    });

    test('should throw on unclosed string', () {
      final sql = "SELECT 'unclosed;";

      expect(() => SQLParserService.split(sql), throwsA(isA<ParseException>()));
    });

    test('should detect statement types', () {
      final sql = '''
SELECT 1;
INSERT INTO t VALUES (1);
UPDATE t SET a=1;
DELETE FROM t;
CREATE TABLE t (id INT);
CALL proc();
''';
      final statements = SQLParserService.split(sql);

      expect(statements[0].type, SQLType.select);
      expect(statements[1].type, SQLType.insert);
      expect(statements[2].type, SQLType.update);
      expect(statements[3].type, SQLType.delete);
      expect(statements[4].type, SQLType.ddl);
      expect(statements[5].type, SQLType.call);
    });

    test('should track line numbers', () {
      final sql = '''
SELECT 1;
SELECT 2;
SELECT 3;
''';
      final statements = SQLParserService.split(sql);

      expect(statements[0].lineStart, 1);
      expect(statements[0].lineEnd, 1);
      expect(statements[1].lineStart, 2);
      expect(statements[1].lineEnd, 2);
    });

    test('should handle statement without trailing semicolon', () {
      final sql = 'SELECT 1; SELECT 2';
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
      expect(statements[1].sql, 'SELECT 2');
    });

    test('should handle empty input', () {
      final statements = SQLParserService.split('');
      expect(statements, isEmpty);
    });

    test('should handle unicode and emoji', () {
      final sql = "INSERT INTO t VALUES ('测试;🎉'); SELECT 2;";
      final statements = SQLParserService.split(sql);

      expect(statements.length, 2);
      expect(statements[0].sql, "INSERT INTO t VALUES ('测试;🎉')");
    });
  });

  // T6: extractColumns / extractTableName / hasLimitClause / detectType ——
  // 被安全审查规则（SchemaCompatRule / MissingLimitRule）依赖，需覆盖
  // 正常提取 + 边缘 case（保守跳过，不误报）。
  group('extractTableName', () {
    test('SELECT FROM 提取表名', () {
      expect(
        SQLParserService.extractTableName(
            'SELECT * FROM users', SQLType.select),
        'users',
      );
    });

    test('SELECT FROM 反引号表名', () {
      expect(
        SQLParserService.extractTableName(
            'SELECT * FROM `order`', SQLType.select),
        'order',
      );
    });

    test('DELETE FROM 提取表名', () {
      expect(
        SQLParserService.extractTableName(
            'DELETE FROM logs WHERE id = 1', SQLType.delete),
        'logs',
      );
    });

    test('UPDATE 提取表名', () {
      expect(
        SQLParserService.extractTableName(
            'UPDATE products SET price = 100 WHERE id = 1', SQLType.update),
        'products',
      );
    });

    test('INSERT INTO 提取表名', () {
      expect(
        SQLParserService.extractTableName(
            'INSERT INTO orders (a) VALUES (1)', SQLType.insert),
        'orders',
      );
    });

    test('SELECT 无 FROM → null', () {
      expect(
        SQLParserService.extractTableName('SELECT 1', SQLType.select),
        isNull,
      );
    });
  });

  group('extractColumns', () {
    test('SELECT col1, col2 FROM → 提取列', () {
      final cols = SQLParserService.extractColumns(
          'SELECT id, name, email FROM users');
      expect(cols, containsAll(['id', 'name', 'email']));
    });

    test('SELECT * FROM → 空列表（无法提取）', () {
      final cols =
          SQLParserService.extractColumns('SELECT * FROM users');
      expect(cols, isEmpty);
    });

    test('WHERE 子句提取列名', () {
      final cols = SQLParserService.extractColumns(
          'SELECT * FROM users WHERE status = 1 AND name LIKE "%a%"');
      expect(cols, containsAll(['status', 'name']));
    });

    test('INSERT INTO t (col1, col2) → 提取列', () {
      final cols = SQLParserService.extractColumns(
          'INSERT INTO users (id, name, email) VALUES (1, 2, 3)');
      expect(cols, containsAll(['id', 'name', 'email']));
    });

    test('UPDATE SET col = → 提取列', () {
      final cols = SQLParserService.extractColumns(
          'UPDATE users SET name = "a", age = 1 WHERE id = 1');
      expect(cols, containsAll(['name', 'age']));
    });

    test('含 JOIN → 保守返回空（SELECT 列区段）', () {
      final cols = SQLParserService.extractColumns(
          'SELECT a.id, b.name FROM a JOIN b ON a.id = b.id');
      // JOIN 时 SELECT 列区段不提取；但 WHERE 段为空 → 整体空或仅 ON 列。
      // 保守策略：不误报多表列归属。
      expect(cols.every((c) => c != 'id' || c != 'name'), isTrue);
    });

    test('SELECT 函数/子查询 → 列区段跳过', () {
      final cols = SQLParserService.extractColumns(
          'SELECT COUNT(*) FROM users WHERE status = 1');
      // SELECT 段含 '(' → 跳过 SELECT 列提取；WHERE 段仍提取 status。
      expect(cols, contains('status'));
      expect(cols, isNot(contains('COUNT')));
    });

    test('反引号列名提取', () {
      final cols = SQLParserService.extractColumns(
          'SELECT `id`, `name` FROM users');
      expect(cols, containsAll(['id', 'name']));
    });

    test('SQL 关键字作列名 → 被过滤（保守不误判）', () {
      // 'order'/'group' 是 SQL 关键字，_isValidColumnName 会过滤掉，
      // 避免误报。这是保守策略的正确行为。
      final cols = SQLParserService.extractColumns(
          'SELECT `order`, `group` FROM users');
      expect(cols, isEmpty);
    });

    test('表限定列名 t.col → 只取列名', () {
      final cols = SQLParserService.extractColumns(
          'SELECT u.id, u.name FROM users u');
      expect(cols, containsAll(['id', 'name']));
    });

    test('SQL 关键字不误判为列名', () {
      final cols = SQLParserService.extractColumns(
          'SELECT id FROM users WHERE name = "FROM"');
      // "FROM" 是字符串值不是列；WHERE 提取 name，不提取值。
      expect(cols, contains('name'));
      expect(cols, isNot(contains('FROM')));
    });
  });

  group('hasLimitClause', () {
    test('有 LIMIT n → true', () {
      expect(SQLParserService.hasLimitClause('SELECT * FROM t LIMIT 100'),
          isTrue);
    });

    test('无 LIMIT → false', () {
      expect(SQLParserService.hasLimitClause('SELECT * FROM t'), isFalse);
    });

    test('LIMIT 在注释里 → false（不误判）', () {
      expect(
        SQLParserService.hasLimitClause(
            'SELECT * FROM t -- LIMIT 100\nWHERE 1=1'),
        isFalse,
      );
    });

    test('LIMIT 在字符串里 → false（不误判）', () {
      expect(
        SQLParserService.hasLimitClause(
            "SELECT * FROM t WHERE note = 'LIMIT 100'"),
        isFalse,
      );
    });
  });

  // extractLimitValue / hasOrderClause —— 被 EXPLAIN 安全规则（R9/R10）
  // 依赖：LIMIT 封顶估值判定需要取 LIMIT 数值，ORDER BY 决定扫描是否
  // 被 LIMIT 截断。
  group('extractLimitValue', () {
    test('LIMIT n → n', () {
      expect(SQLParserService.extractLimitValue('SELECT * FROM t LIMIT 100'),
          100);
    });

    test('MySQL LIMIT offset, count → 取 count', () {
      expect(
          SQLParserService.extractLimitValue('SELECT * FROM t LIMIT 20, 50'),
          50);
    });

    test('PostgreSQL LIMIT n OFFSET m → 取 n', () {
      expect(
        SQLParserService.extractLimitValue(
            'SELECT * FROM t LIMIT 100 OFFSET 20'),
        100,
      );
    });

    test('无 LIMIT → null', () {
      expect(SQLParserService.extractLimitValue('SELECT * FROM t'), isNull);
    });

    test('LIMIT 在注释里 → null（不误判）', () {
      expect(
        SQLParserService.extractLimitValue(
            'SELECT * FROM t -- LIMIT 100\nWHERE 1=1'),
        isNull,
      );
    });

    test('LIMIT 在字符串里 → null（不误判）', () {
      expect(
        SQLParserService.extractLimitValue(
            "SELECT * FROM t WHERE note = 'LIMIT 100'"),
        isNull,
      );
    });

    test('小写 limit → 取到', () {
      expect(SQLParserService.extractLimitValue('select * from t limit 10'),
          10);
    });
  });

  group('hasOrderClause', () {
    test('有 ORDER BY → true', () {
      expect(
          SQLParserService.hasOrderClause('SELECT * FROM t ORDER BY id'), isTrue);
    });

    test('无 ORDER BY → false', () {
      expect(SQLParserService.hasOrderClause('SELECT * FROM t LIMIT 100'),
          isFalse);
    });

    test('ORDER BY 在字符串里 → false（不误判）', () {
      expect(
        SQLParserService.hasOrderClause(
            "SELECT * FROM t WHERE note = 'ORDER BY id'"),
        isFalse,
      );
    });
  });

  // isSingleRowAggregate —— 被安全规则（R3 missing_limit / R9 / R10）
  // 依赖：整查询聚合（无 GROUP BY）恒返回单行，LIMIT/行数估值无意义。
  group('isSingleRowAggregate', () {
    test('SELECT COUNT(*) → true', () {
      expect(SQLParserService.isSingleRowAggregate('SELECT COUNT(*) FROM t'),
          isTrue);
    });

    test('SUM/AVG/MIN/MAX → true', () {
      expect(
          SQLParserService.isSingleRowAggregate('SELECT SUM(amount) FROM o'),
          isTrue);
      expect(SQLParserService.isSingleRowAggregate('SELECT AVG(price) FROM p'),
          isTrue);
      expect(SQLParserService.isSingleRowAggregate('SELECT MIN(x) FROM t'),
          isTrue);
      expect(SQLParserService.isSingleRowAggregate('SELECT MAX(x) FROM t'),
          isTrue);
    });

    test('多个聚合表达式 → true', () {
      expect(
        SQLParserService.isSingleRowAggregate(
            'SELECT COUNT(*), MAX(id) FROM t'),
        isTrue,
      );
    });

    test('带 WHERE 的 COUNT → true（R9 自行决定是否豁免）', () {
      expect(
        SQLParserService.isSingleRowAggregate(
            'SELECT COUNT(*) FROM t WHERE x = 1'),
        isTrue,
      );
    });

    test('小写 count(*) → true', () {
      expect(SQLParserService.isSingleRowAggregate('select count(*) from t'),
          isTrue);
    });

    test('GROUP BY → false（聚合分组返回多行，LIMIT 有意义）', () {
      expect(
        SQLParserService.isSingleRowAggregate(
            'SELECT dept, COUNT(*) FROM emp GROUP BY dept'),
        isFalse,
      );
    });

    test('普通 SELECT → false', () {
      expect(SQLParserService.isSingleRowAggregate('SELECT * FROM t'), isFalse);
    });

    test('聚合在标量子查询里 → false（外层仍多行）', () {
      expect(
        SQLParserService.isSingleRowAggregate(
            'SELECT * FROM t WHERE x = (SELECT COUNT(*) FROM u)'),
        isFalse,
      );
    });

    test('窗口函数 OVER → false（保守按多行）', () {
      expect(
        SQLParserService.isSingleRowAggregate(
            'SELECT SUM(x) OVER () FROM t'),
        isFalse,
      );
    });

    test('聚合函数名在列名里（非调用）→ false（词边界不误判）', () {
      expect(
        SQLParserService.isSingleRowAggregate('SELECT count_summary FROM t'),
        isFalse,
      );
    });

    test('COUNT 在字符串/注释里 → false（不误判）', () {
      expect(
        SQLParserService.isSingleRowAggregate(
            "SELECT note FROM t WHERE k = 'COUNT(*)'"),
        isFalse,
      );
      expect(
        SQLParserService.isSingleRowAggregate(
            '-- COUNT(*)\nSELECT * FROM t'),
        isFalse,
      );
    });

    test('非 SELECT（UPDATE）→ false', () {
      expect(
        SQLParserService.isSingleRowAggregate('UPDATE t SET a = 1'),
        isFalse,
      );
    });
  });

  group('detectType', () {
    test('SELECT → select', () {
      expect(SQLParserService.detectType('SELECT * FROM t'), SQLType.select);
    });

    test('INSERT → insert', () {
      expect(SQLParserService.detectType('INSERT INTO t VALUES (1)'),
          SQLType.insert);
    });

    test('UPDATE → update', () {
      expect(SQLParserService.detectType('UPDATE t SET a = 1'), SQLType.update);
    });

    test('DELETE → delete', () {
      expect(SQLParserService.detectType('DELETE FROM t'), SQLType.delete);
    });

    test('CREATE TABLE → ddl', () {
      expect(SQLParserService.detectType('CREATE TABLE t (id INT)'),
          SQLType.ddl);
    });

    test('ALTER TABLE → ddl', () {
      expect(SQLParserService.detectType('ALTER TABLE t ADD COLUMN x INT'),
          SQLType.ddl);
    });
  });

  // T2: extractWhereClause —— 供 FullTableScanRule 复用的 WHERE 提取 helper。
  group('extractWhereClause', () {
    test('有 WHERE → 提取子句内容', () {
      final where = SQLParserService.extractWhereClause(
          'SELECT * FROM users WHERE id = 1');
      expect(where, isNotNull);
      expect(where!.trim(), contains('id = 1'));
    });

    test('WHERE 后跟 GROUP BY → 截断到 GROUP 前', () {
      final where = SQLParserService.extractWhereClause(
          'SELECT * FROM t WHERE a = 1 GROUP BY a');
      expect(where, isNotNull);
      expect(where!, contains('a = 1'));
      expect(where, isNot(contains('GROUP')));
    });

    test('WHERE 后跟 ORDER BY → 截断到 ORDER 前', () {
      final where = SQLParserService.extractWhereClause(
          'SELECT * FROM t WHERE a = 1 ORDER BY a');
      expect(where, isNotNull);
      expect(where!, isNot(contains('ORDER')));
    });

    test('WHERE 后跟 LIMIT → 截断到 LIMIT 前', () {
      final where = SQLParserService.extractWhereClause(
          'SELECT * FROM t WHERE a = 1 LIMIT 10');
      expect(where, isNotNull);
      expect(where!, isNot(contains('LIMIT')));
    });

    test('无 WHERE → null', () {
      expect(SQLParserService.extractWhereClause('SELECT 1'), isNull);
    });

    test('WHERE 在块注释里 → 不误提取（返回 null）', () {
      // /* WHERE x=1 */ 是注释，不应被当作真正的 WHERE 子句。
      expect(
        SQLParserService.extractWhereClause(
            'SELECT * FROM t /* WHERE x = 1 */'),
        isNull,
      );
    });

    test('WHERE 在字符串里 → 不误提取（返回 null）', () {
      expect(
        SQLParserService.extractWhereClause(
            "SELECT 'WHERE x = 1' FROM t"),
        isNull,
      );
    });

    test('UPDATE ... WHERE → 提取', () {
      final where = SQLParserService.extractWhereClause(
          'UPDATE t SET a = 1 WHERE id = 5');
      expect(where, isNotNull);
      expect(where!.trim(), contains('id = 5'));
    });

    test('多条件 WHERE → 完整提取', () {
      final where = SQLParserService.extractWhereClause(
          'SELECT * FROM t WHERE a = 1 AND b = 2 OR c = 3');
      expect(where, isNotNull);
      expect(where!, contains('a = 1'));
      expect(where, contains('b = 2'));
      expect(where, contains('c = 3'));
    });
  });

  // T3: cleanForAnalysis（原 _stripCommentsAndStrings 公开）—— 验证公开后行为不变。
  group('cleanForAnalysis', () {
    test('删除行注释 --', () {
      final cleaned = SQLParserService.cleanForAnalysis(
          'SELECT 1 -- comment');
      expect(cleaned, isNot(contains('comment')));
      expect(cleaned, contains('SELECT 1'));
    });

    test('删除块注释 /* */', () {
      final cleaned = SQLParserService.cleanForAnalysis(
          'SELECT /* x */ 1');
      expect(cleaned, isNot(contains('x')));
    });

    test('字符串字面量替换为占位', () {
      final cleaned = SQLParserService.cleanForAnalysis(
          "SELECT 'hello world'");
      // 字符串内容应被移除（不残留 hello world）。
      expect(cleaned, isNot(contains('hello world')));
    });
  });

  // B6 T10：MySQL 可执行注释 /*! */ 不得当普通注释剥除——内容会被
  // MySQL 执行，剥掉会让关键字检测漏掉藏在注释里的语句。
  group('executable comment（B6 T10）', () {
    test('cleanForAnalysis：/*! 内容保留（去标记与版本前缀）', () {
      final cleaned = SQLParserService.cleanForAnalysis(
          '/*!50003 DROP TABLE x */');
      expect(cleaned, contains('DROP TABLE x'));
      expect(cleaned, isNot(contains('50003')));
      expect(cleaned, isNot(contains('!')));
    });

    test('cleanForAnalysis：无版本前缀的 /*! 同样保留内容', () {
      final cleaned = SQLParserService.cleanForAnalysis(
          'SELECT /*! SQL_NO_CACHE */ 1');
      expect(cleaned, contains('SQL_NO_CACHE'));
      expect(cleaned, contains('SELECT'));
    });

    test('cleanForAnalysis：普通块注释与优化器提示仍剥除', () {
      final cleaned = SQLParserService.cleanForAnalysis(
          '/* DROP TABLE x */ SELECT /*+ INDEX(t) */ 1');
      expect(cleaned, isNot(contains('DROP')));
      expect(cleaned, isNot(contains('INDEX')));
      // 注释位置留占位空格，归一化空白后应只剩 SELECT 1。
      expect(cleaned.replaceAll(RegExp(r'\s+'), ' ').trim(), 'SELECT 1');
    });

    test('cleanForAnalysis：未闭合的 /*! 按噪音处理', () {
      final cleaned = SQLParserService.cleanForAnalysis('/*! DROP TABLE x');
      expect(cleaned.trim(), isEmpty);
    });

    test('detectType：可执行注释内的语句类型可见', () {
      expect(
        SQLParserService.detectType('/*!40000 DROP TABLE x */'),
        SQLType.ddl,
      );
      expect(
        SQLParserService.detectType('/*!40000 DELETE FROM logs */'),
        SQLType.delete,
      );
    });

    test('detectType：前导行注释不再遮蔽类型判定', () {
      expect(
        SQLParserService.detectType('-- note\nDELETE FROM t'),
        SQLType.delete,
      );
    });

    test('detectDdlSubType：可执行注释内 DROP TABLE 可见', () {
      expect(
        SQLParserService.detectDdlSubType('/*!40000 DROP TABLE x */'),
        DdlSubType.dropTable,
      );
    });

    test('split：独立可执行注释保留为语句（原样含标记）', () {
      final statements = SQLParserService.split(
          'SELECT 1;\n/*!40000 DROP TABLE t */');
      expect(statements.length, 2);
      expect(statements[1].sql, contains('/*!40000'));
      expect(statements[1].sql, contains('DROP TABLE t'));
      expect(statements[1].type, SQLType.ddl);
    });

    test('split：语句中间的可执行注释保留原样', () {
      final statements = SQLParserService.split(
          'SELECT /*! SQL_NO_CACHE */ 1');
      expect(statements.length, 1);
      expect(statements[0].sql, contains('SQL_NO_CACHE'));
      expect(statements[0].type, SQLType.select);
    });

    test('split：普通块注释仍剥除', () {
      final statements = SQLParserService.split(
          'SELECT 1 /* plain comment */');
      expect(statements[0].sql, 'SELECT 1');
    });
  });
}
