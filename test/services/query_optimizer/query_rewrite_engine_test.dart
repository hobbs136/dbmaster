import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_optimizer/query_rewrite_engine.dart';
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';

void main() {
  group('QueryRewriteEngine', () {
    test('suggests rewriting SELECT *', () {
      final query = 'SELECT * FROM users WHERE id = 1';
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: query,
        steps: [],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final rewrites = QueryRewriteEngine.suggestRewrites(
        originalQuery: query,
        plan: plan,
      );

      expect(
        rewrites.any((r) => r.type == RewriteType.selectStarToColumns),
        isTrue,
      );
    });

    test('suggests keyset pagination for OFFSET', () {
      final query =
          'SELECT id, name FROM users ORDER BY id LIMIT 10 OFFSET 1000';
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: query,
        steps: [],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final rewrites = QueryRewriteEngine.suggestRewrites(
        originalQuery: query,
        plan: plan,
      );

      expect(rewrites.any((r) => r.type == RewriteType.offsetToKeyset), isTrue);
    });

    test('suggests NOT EXISTS for NOT IN', () {
      final query =
          'SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM orders)';
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: query,
        steps: [],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final rewrites = QueryRewriteEngine.suggestRewrites(
        originalQuery: query,
        plan: plan,
      );

      expect(
        rewrites.any((r) => r.type == RewriteType.notInToNotExists),
        isTrue,
      );
    });

    test('returns empty list for already optimized query', () {
      final query = 'SELECT id, name FROM users WHERE id = 1';
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: query,
        steps: [
          PlanStep(table: 'users', scanType: ScanType.const_, key: 'PRIMARY'),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final rewrites = QueryRewriteEngine.suggestRewrites(
        originalQuery: query,
        plan: plan,
      );

      expect(rewrites, isEmpty);
    });

    test('preserves original query logic', () {
      final query = 'SELECT * FROM users';
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: query,
        steps: [],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final rewrites = QueryRewriteEngine.suggestRewrites(
        originalQuery: query,
        plan: plan,
      );

      final selectStarRewrite = rewrites.firstWhere(
        (r) => r.type == RewriteType.selectStarToColumns,
      );

      expect(selectStarRewrite.originalQuery, equals(query));
      expect(selectStarRewrite.rewrittenQuery, isNot(equals(query)));
      expect(selectStarRewrite.reason, isNotEmpty);
    });

    test('handles complex queries with multiple issues', () {
      final query =
          'SELECT * FROM users WHERE status = "active" ORDER BY created_at LIMIT 10 OFFSET 500';
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: query,
        steps: [
          PlanStep(
            table: 'users',
            scanType: ScanType.fullTable,
            extra: 'Using filesort',
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final rewrites = QueryRewriteEngine.suggestRewrites(
        originalQuery: query,
        plan: plan,
      );

      // Should detect both SELECT * and OFFSET
      expect(rewrites.length, greaterThanOrEqualTo(2));
    });

    group('SELECT * rewrite with schema', () {
      ExecutionPlan planFor(String q) => ExecutionPlan(
            databaseType: 'mysql',
            originalQuery: q,
            steps: [],
            rawData: {},
            analyzedAt: DateTime.now(),
          );

      test('uses real columns when tableColumns provides the FROM table', () {
        const query = 'SELECT * FROM users WHERE id = 1';
        final rewrites = QueryRewriteEngine.suggestRewrites(
          originalQuery: query,
          plan: planFor(query),
          tableColumns: {
            'users': ['id', 'name', 'email', 'created_at'],
          },
        );
        final rw = rewrites.firstWhere(
          (r) => r.type == RewriteType.selectStarToColumns,
        );
        // 真列名替换 *，无裸 TODO
        expect(rw.rewrittenQuery, contains('id, name, email, created_at'));
        expect(rw.rewrittenQuery, isNot(contains('TODO')));
        expect(rw.reason, contains('users'));
      });

      test('table-name placeholder when schema unavailable but FROM parseable',
          () {
        const query = 'SELECT * FROM users WHERE id = 1';
        final rewrites = QueryRewriteEngine.suggestRewrites(
          originalQuery: query,
          plan: planFor(query),
          // 不传 tableColumns
        );
        final rw = rewrites.firstWhere(
          (r) => r.type == RewriteType.selectStarToColumns,
        );
        // 占位含表名（可操作），不是裸 TODO
        expect(rw.rewrittenQuery, contains('users'));
        expect(rw.reason, contains('users'));
      });

      test('schema-qualified FROM (schema.table) resolves via table segment', () {
        const query = 'SELECT * FROM public.users';
        final rewrites = QueryRewriteEngine.suggestRewrites(
          originalQuery: query,
          plan: planFor(query),
          tableColumns: {
            'users': ['id', 'name'],
          },
        );
        final rw = rewrites.firstWhere(
          (r) => r.type == RewriteType.selectStarToColumns,
        );
        expect(rw.rewrittenQuery, contains('id, name'));
      });

      test('JOIN query falls back to bare TODO (cannot pick one table)', () {
        const query = 'SELECT * FROM users u JOIN orders o ON u.id = o.user_id';
        final rewrites = QueryRewriteEngine.suggestRewrites(
          originalQuery: query,
          plan: planFor(query),
          tableColumns: {
            'users': ['id', 'name'],
          },
        );
        final rw = rewrites.firstWhere(
          (r) => r.type == RewriteType.selectStarToColumns,
        );
        // JOIN 不猜表 → 走裸 TODO 分支（占位是 "Specify required columns"，
        // 不是 "replace with needed columns of <table>"）
        expect(
          rw.rewrittenQuery,
          contains('TODO: Specify required columns'),
        );
        expect(rw.reason, isNot(contains('`users`')));
      });

      test('schema provided but FROM table absent → table-name placeholder', () {
        const query = 'SELECT * FROM users WHERE id = 1';
        final rewrites = QueryRewriteEngine.suggestRewrites(
          originalQuery: query,
          plan: planFor(query),
          tableColumns: {
            'orders': ['id', 'total'],
          },
        );
        final rw = rewrites.firstWhere(
          (r) => r.type == RewriteType.selectStarToColumns,
        );
        // 表名抽得到但 schema 没该表 → 走「表名占位」分支
        expect(rw.rewrittenQuery, contains('users'));
        expect(rw.rewrittenQuery, contains('TODO'));
      });
    });
  });
}
