// C12 · NoSQL 文档 / Redis 键值渲染器单测 + 形态判定接线。
//
// 覆盖：三新渲染器 viewModeId/形态/descriptor、注册序（形态默认视图）、
// BSON 类型推断与展示文本、ExecutionResult.dataShape 序列化往返与历史
// 兼容、shapeForDatabaseType 九类型映射、三渲染器 widget 渲染与交互。
// 宿主级（ResultsWidget 按形态默认选文档视图）在 results_view_mode_test。
//
// 用例登记：「C12 附录」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/result_data_shape.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/plugins/bson_type.dart';
import 'package:dbmaster/organisms/results/plugins/document_result_renderer.dart';
import 'package:dbmaster/organisms/results/plugins/json_tree_result_renderer.dart';
import 'package:dbmaster/organisms/results/plugins/key_value_result_renderer.dart';
import 'package:dbmaster/organisms/results/plugins/table_result_renderer.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/plugin_registry.dart';
import 'package:dbmaster/plugins/result_renderer_plugin.dart';

void main() {
  ExecutionResult resultWith(
    List<Map<String, dynamic>> data, {
    String sql = 'db.users.find({})',
    ResultDataShape? shape,
  }) =>
      ExecutionResult(
        statement: SQLStatement(
          index: 0,
          sql: sql,
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
        success: true,
        data: data,
        executionTime: const Duration(milliseconds: 5),
        dataShape: shape,
      );

  ResultRenderContext contextFor(
    ExecutionResult result,
    List<Map<String, dynamic>> rows,
  ) =>
      ResultRenderContext(
        result: result,
        rows: rows,
        columns: rows.isNotEmpty ? rows.first.keys.toList() : const [],
        columnTypes: const {},
      );

  group('C12 · 三新渲染器声明', () {
    test('viewModeId 对齐 c03 §4 命名表（document/jsonTree/keyValue）', () {
      expect(const DocumentResultRenderer().viewModeId, 'document');
      expect(const JsonTreeResultRenderer().viewModeId, 'jsonTree');
      expect(const KeyValueResultRenderer().viewModeId, 'keyValue');
    });

    test('形态声明：document→nosqlDocument；jsonTree→双形态；keyValue→redisKeyValue', () {
      expect(
        const DocumentResultRenderer().supportedShapes,
        const {ResultDataShape.nosqlDocument},
      );
      expect(
        const JsonTreeResultRenderer().supportedShapes,
        const {ResultDataShape.nosqlDocument, ResultDataShape.redisKeyValue},
      );
      expect(
        const KeyValueResultRenderer().supportedShapes,
        const {ResultDataShape.redisKeyValue},
      );
    });

    test('descriptor：core 来源 + 空类型集 + id 全局唯一', () {
      final renderers = <dynamic>[
        const DocumentResultRenderer(),
        const JsonTreeResultRenderer(),
        const KeyValueResultRenderer(),
        const TableResultRenderer(),
      ];
      final ids = renderers.map((r) => (r as ResultRendererPlugin).descriptor.id).toSet();
      expect(ids.length, 4);
      for (final r in renderers.cast<ResultRendererPlugin>()) {
        expect(r.descriptor.source, PluginSource.core);
        expect(r.descriptor.supportedTypes, isEmpty);
      }
    });

    test('displayName 消费新 viewMode* l10n 键（en 值锁定）', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        const DocumentResultRenderer().descriptor.displayName!(l10n),
        'Documents',
      );
      expect(
        const JsonTreeResultRenderer().descriptor.displayName!(l10n),
        'JSON Tree',
      );
      expect(
        const KeyValueResultRenderer().descriptor.displayName!(l10n),
        'Key-Value',
      );
    });
  });

  group('C12 · 注册序（形态默认视图）', () {
    test('nosqlDocument → document 默认，jsonTree/table 可切换', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);
      expect(
        registry
            .resultRenderersFor(shape: ResultDataShape.nosqlDocument)
            .map((r) => r.viewModeId)
            .toList(),
        ['document', 'jsonTree', 'table'],
      );
    });

    test('redisKeyValue → keyValue 默认，jsonTree/table 可切换', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);
      expect(
        registry
            .resultRenderersFor(shape: ResultDataShape.redisKeyValue)
            .map((r) => r.viewModeId)
            .toList(),
        ['keyValue', 'jsonTree', 'table'],
      );
    });

    test('sqlRows 序不变（table/chart/card，C11 行为保持）', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);
      expect(
        registry
            .resultRenderersFor(shape: ResultDataShape.sqlRows)
            .map((r) => r.viewModeId)
            .toList(),
        ['table', 'chart', 'card'],
      );
    });
  });

  group('C12 · 形态判定（shapeForDatabaseType + ExecutionResult 序列化）', () {
    test('九类型映射：mongo→nosqlDocument、redis→redisKeyValue、SQL 家族→sqlRows', () {
      expect(
        ResultDataShape.shapeForDatabaseType(DatabaseType.mongodb),
        ResultDataShape.nosqlDocument,
      );
      expect(
        ResultDataShape.shapeForDatabaseType(DatabaseType.redis),
        ResultDataShape.redisKeyValue,
      );
      const sqlTypes = [
        DatabaseType.mysql,
        DatabaseType.postgresql,
        DatabaseType.sqlite,
        DatabaseType.sqlserver,
        DatabaseType.doris,
        DatabaseType.clickhouse,
        DatabaseType.tdengine,
      ];
      for (final t in sqlTypes) {
        expect(
          ResultDataShape.shapeForDatabaseType(t),
          ResultDataShape.sqlRows,
          reason: '${t.name} 应为 sqlRows',
        );
      }
    });

    test('ExecutionResult.dataShape toJson/fromJson 往返', () {
      final result = resultWith(
        const [
          {'_id': '507f1f77bcf86cd799439011', 'name': 'Alice'},
        ],
        shape: ResultDataShape.nosqlDocument,
      );
      final restored = ExecutionResult.fromJson(result.toJson());
      expect(restored.dataShape, ResultDataShape.nosqlDocument);
    });

    test('历史记录无 dataShape → null（宿主回退 sqlRows）', () {
      final legacy = ExecutionResult.fromJson({
        'statement': {
          'index': 0,
          'sql': 'SELECT 1',
          'type': 'select',
          'lineStart': 1,
          'lineEnd': 1,
        },
        'success': true,
        'data': [
          {'a': 1},
        ],
        'executionTimeMs': 3,
      });
      expect(legacy.dataShape, isNull);
      // copyWith 可补标形态
      expect(
        legacy.copyWith(dataShape: ResultDataShape.redisKeyValue).dataShape,
        ResultDataShape.redisKeyValue,
      );
    });
  });

  group('C12 · BSON 类型推断（bson_type）', () {
    test('六徽章类型 + Object/null', () {
      expect(bsonFieldTypeOf('507f1f77bcf86cd799439011'), BsonFieldType.objectId);
      expect(bsonFieldTypeOf('hello'), BsonFieldType.string);
      expect(bsonFieldTypeOf(42), BsonFieldType.number);
      expect(bsonFieldTypeOf(1.5), BsonFieldType.number);
      expect(bsonFieldTypeOf(true), BsonFieldType.boolean);
      expect(bsonFieldTypeOf('2024-05-18T08:32:11.000Z'), BsonFieldType.isoDate);
      expect(bsonFieldTypeOf('2024-05-18 08:32:11'), BsonFieldType.isoDate);
      expect(bsonFieldTypeOf(['a', 'b']), BsonFieldType.array);
      expect(bsonFieldTypeOf({'k': 'v'}), BsonFieldType.object);
      expect(bsonFieldTypeOf(null), BsonFieldType.nullValue);
    });

    test('边界：纯日期不带时间是 String；23 位 hex 不是 ObjectId；UUID 是 String', () {
      expect(bsonFieldTypeOf('2024-05-18'), BsonFieldType.string);
      expect(bsonFieldTypeOf('507f1f77bcf86cd79943901'), BsonFieldType.string);
      expect(
        bsonFieldTypeOf('550e8400-e29b-41d4-a716-446655440000'),
        BsonFieldType.string,
      );
    });

    test('值展示：字符串带引号 / ISODate 包裹 / 超长截断', () {
      expect(bsonValueDisplay('Alice'), '"Alice"');
      expect(
        bsonValueDisplay('2024-05-18T08:32:11.000Z'),
        'ISODate("2024-05-18T08:32:11.000Z")',
      );
      expect(bsonValueDisplay(null), 'null');
      expect(
        bsonValueDisplay('a' * 100, maxLen: 10).length,
        11, // 10 字符 + 省略号
      );
    });
  });

  /// Builder 包装把 context 交给渲染器 build（渲染器接口要求 BuildContext）。
  Future<void> pumpRenderer(
    WidgetTester tester,
    ResultRendererPlugin renderer,
    ResultRenderContext renderContext,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(builder: (context) => renderer.build(context, renderContext)),
        ),
      ),
    );
  }

  group('C12 · 文档卡片渲染器（widget）', () {
    final docs = <Map<String, dynamic>>[
      {
        '_id': '507f1f77bcf86cd799439011',
        'name': 'Alice Chen',
        'age': 29,
        'isActive': true,
        'createdAt': '2024-05-18T08:32:11.000Z',
        'tags': ['admin', 'beta'],
        'profile': {'email': 'alice@example.com'},
      },
    ];

    testWidgets('卡片结构：_id 头 + 六类徽章 + 嵌套对象框默认折叠', (tester) async {
      await pumpRenderer(
        tester,
        const DocumentResultRenderer(),
        contextFor(
          resultWith(docs, shape: ResultDataShape.nosqlDocument),
          docs,
        ),
      );
      // 头部 _id 值 + 六徽章标签（ObjectId/String/Number/Boolean/ISODate/Array）
      expect(find.text('507f1f77bcf86cd799439011'), findsOneWidget);
      expect(find.text('ObjectId'), findsOneWidget);
      expect(find.text('String'), findsOneWidget);
      expect(find.text('Number'), findsOneWidget);
      expect(find.text('Boolean'), findsOneWidget);
      expect(find.text('ISODate'), findsOneWidget);
      expect(find.text('Array'), findsOneWidget);
      // 字段值按原型格式展示
      expect(find.textContaining('"Alice Chen"'), findsOneWidget);
      expect(find.textContaining('ISODate("2024-05-18'), findsOneWidget);
      // 嵌套对象默认折叠：字段名可见、内部值不可见
      expect(find.text('profile'), findsOneWidget);
      expect(find.textContaining('alice@example.com'), findsNothing);
    });

    testWidgets('嵌套对象点击展开后内部字段可见', (tester) async {
      await pumpRenderer(
        tester,
        const DocumentResultRenderer(),
        contextFor(
          resultWith(docs, shape: ResultDataShape.nosqlDocument),
          docs,
        ),
      );
      // 折叠框的展开开关在「Expand」标签上（字段名本身不可点）
      await tester.tap(find.text('Expand'));
      await tester.pumpAndSettle();
      expect(find.textContaining('alice@example.com'), findsOneWidget);
    });

    testWidgets('超阈值文档默认折叠：展示前 N 字段 + 展开按钮', (tester) async {
      final bigDoc = <String, dynamic>{
        for (var i = 0; i < 12; i++) 'field$i': i,
      };
      await pumpRenderer(
        tester,
        const DocumentResultRenderer(),
        contextFor(
          resultWith([bigDoc], shape: ResultDataShape.nosqlDocument),
          [bigDoc],
        ),
      );
      // 无 _id → 首字段 field0 为头部；正文 field1..field11（11 个 > 8 阈值）
      // 折叠为前 4 个（field1..field4）+ 展开按钮（en: Expand 7 more fields）
      expect(find.text('field0'), findsOneWidget);
      expect(find.text('field4'), findsOneWidget);
      expect(find.text('field5'), findsNothing);
      expect(find.text('Expand 7 more fields'), findsOneWidget);
      await tester.tap(find.text('Expand 7 more fields'));
      await tester.pumpAndSettle();
      expect(find.text('field5'), findsOneWidget);
      expect(find.text('field11'), findsOneWidget);
      expect(find.text('Collapse'), findsOneWidget);
    });
  });

  group('C12 · JSON 树渲染器（widget）', () {
    final docs = <Map<String, dynamic>>[
      {
        '_id': '507f1f77bcf86cd799439011',
        'name': 'Alice',
        'profile': {'email': 'alice@example.com'},
      },
    ];

    testWidgets('根/文档层默认展开，深层容器默认折叠', (tester) async {
      await pumpRenderer(
        tester,
        const JsonTreeResultRenderer(),
        contextFor(
          resultWith(docs, shape: ResultDataShape.nosqlDocument),
          docs,
        ),
      );
      // 文档层字段可见
      expect(find.text('name'), findsOneWidget);
      expect(find.textContaining('"Alice"'), findsOneWidget);
      // 深层容器（depth 2 的 profile）折叠：仅节点行 + 项数摘要
      expect(find.text('profile'), findsOneWidget);
      expect(find.textContaining('alice@example.com'), findsNothing);
      expect(find.text('1 items'), findsOneWidget);
    });

    testWidgets('点击折叠节点强制展开（覆盖默认折叠层）', (tester) async {
      await pumpRenderer(
        tester,
        const JsonTreeResultRenderer(),
        contextFor(
          resultWith(docs, shape: ResultDataShape.nosqlDocument),
          docs,
        ),
      );
      await tester.tap(find.text('profile'));
      await tester.pumpAndSettle();
      expect(find.textContaining('alice@example.com'), findsOneWidget);
      expect(find.text('email'), findsOneWidget);
    });
  });

  group('C12b · Redis 键值渲染器（widget）', () {
    testWidgets('GET 单行单字段 → String 卡，标题取命令键名 + 长度脚注', (tester) async {
      const rows = <Map<String, dynamic>>[
        {'result': '{"id":1001,"name":"Alice"}'},
      ];
      await pumpRenderer(
        tester,
        const KeyValueResultRenderer(),
        contextFor(
          resultWith(rows, sql: 'GET user:1001', shape: ResultDataShape.redisKeyValue),
          rows,
        ),
      );
      expect(find.text('user:1001'), findsOneWidget);
      expect(find.text('String'), findsOneWidget);
      expect(find.text('Field: result'), findsOneWidget);
      expect(find.text('Length: 26 chars'), findsOneWidget);
    });

    testWidgets('HGETALL 单行多字段 → Hash 卡（Field/Value 表头 + 行）', (tester) async {
      const rows = <Map<String, dynamic>>[
        {'email': 'alice@example.com', 'level': 'P7'},
      ];
      await pumpRenderer(
        tester,
        const KeyValueResultRenderer(),
        contextFor(
          resultWith(
            rows,
            sql: 'HGETALL user:1001:profile',
            shape: ResultDataShape.redisKeyValue,
          ),
          rows,
        ),
      );
      expect(find.text('Hash'), findsOneWidget);
      expect(find.text('Field'), findsOneWidget);
      expect(find.text('Value'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('P7'), findsOneWidget);
    });

    testWidgets('多行结果 → 每行一卡，标题退序号', (tester) async {
      const rows = <Map<String, dynamic>>[
        {'index': 0, 'value': 'a'},
        {'index': 1, 'value': 'b'},
      ];
      await pumpRenderer(
        tester,
        const KeyValueResultRenderer(),
        contextFor(
          resultWith(rows, sql: 'LRANGE mylist 0 -1', shape: ResultDataShape.redisKeyValue),
          rows,
        ),
      );
      expect(find.text('#0'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('mylist'), findsNothing);
    });
  });
}
