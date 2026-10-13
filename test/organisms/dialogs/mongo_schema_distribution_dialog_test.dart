// DBT-T17（第二程序 R2）· MongoDB Schema 类型分布 dialog widget 测试：
// mock schema 渲染（集合级类型分组计数 / presence 条 / Mixed 标注 / 嵌套
// 标注 + 展开/收起）/ 空态 / 加载态 / 失败态 / 库切换重载（facade 缓存
// key 不含库名的既有边界——dialog 侧按「库+集合」维度管理加载调用的
// 行为锚定，见 dialog 文件头注）。
//
// 数据注入接缝驱动（MongoGridFsDialog 测试同模式）：dialog 三取数面全部
// 构造注入，测试零 AppProvider、零平台通道。真库全链路在
// integration_test/mongodb_schema_distribution_e2e_test.dart（连 WSL）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/dialogs/mongo_schema_distribution_dialog.dart';

// ── fixture（adapter inferDocumentSchema 原始输出 wire 形态）──────────

Map<String, dynamic> _rawSchema({
  String collectionName = 'users',
  int totalSampled = 100,
  Map<String, dynamic> fields = const {},
}) =>
    {
      'collectionName': collectionName,
      'totalSampled': totalSampled,
      'fields': fields,
    };

/// 五字段混合 fixture：String×2 / int×1 / Mixed×1 / Document×1（含一层
/// subFields）——分组计数（2/1/1/1）、Mixed 特标、嵌套展开全覆盖。
Map<String, dynamic> get _mixedFields => {
      'name': {'type': 'String', 'occurrence': 100},
      'email': {'type': 'String', 'occurrence': 90},
      'age': {'type': 'int', 'occurrence': 80},
      'score': {'type': 'Mixed', 'occurrence': 50},
      'meta': {
        'type': 'Document',
        'occurrence': 40,
        'subFields': {
          'created': {'type': 'date', 'occurrence': 40},
        },
      },
    };

/// 注入接缝（调用记录 + 可编程返回）。
class _Seams {
  final loadCalls = <String>[]; // 'db/collection'
  List<String> databases = ['db1', 'db2'];
  Map<String, List<String>> collectionsByDb = {
    'db1': ['users'],
    'db2': ['users'],
  };
  final Map<String, Map<String, dynamic>> schemaByPair = {};
  Completer<Map<String, dynamic>>? gate;
  String? throwOnPair;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MongoSchemaDistributionDialog', () {
    Future<void> pumpDialog(WidgetTester tester, _Seams seams) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => MongoSchemaDistributionDialog.show(
                    context,
                    connectionId: 'mg_conn',
                    loadDatabases: (_) async => seams.databases,
                    loadCollections: (_, db) async =>
                        seams.collectionsByDb[db] ?? const <String>[],
                    loadSchema: (db, collection) async {
                      seams.loadCalls.add('$db/$collection');
                      final gate = seams.gate;
                      if (gate != null) return gate.future;
                      if (seams.throwOnPair == '$db/$collection') {
                        throw StateError('schema load boom');
                      }
                      return seams.schemaByPair['$db/$collection']!;
                    },
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    /// 打开下拉第 [index] 个并选中 [option]（菜单 overlay 项用 .last 命中；
    /// 菜单展开动画经 pumpAndSettle 渲染，随后单帧 pump 派发选中）。
    Future<void> selectOption(
      WidgetTester tester,
      String option, {
      int index = 0,
    }) async {
      await tester.tap(find.byType(DropdownButton<String>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pump();
    }

    Future<void> openOn(
      WidgetTester tester,
      _Seams seams,
      String db,
      String collection,
    ) async {
      await selectOption(tester, db);
      // 选库后集合清单异步加载 flush（微任务完成 + 重建）。
      await tester.pumpAndSettle();
      await selectOption(tester, collection, index: 1);
      await tester.pumpAndSettle();
    }

    testWidgets('渲染：选库选集合 → 头行抽样数 + 类型分组计数 + presence + Mixed 标注', (
      tester,
    ) async {
      final seams = _Seams()
        ..schemaByPair['db1/users'] =
            _rawSchema(fields: _mixedFields, totalSampled: 100);
      await pumpDialog(tester, seams);
      await openOn(tester, seams, 'db1', 'users');

      // 取数闭包按 库+集合 维度被调用。
      expect(seams.loadCalls, ['db1/users']);
      // 头行：抽样数（预登记 key en 文案）。
      expect(find.text('Sampled 100 documents'), findsOneWidget);
      // 集合级分组：String×2（计数降序首位）+ 其余三组各 1。
      expect(find.text('Type: String'), findsOneWidget);
      expect(find.text('2 fields'), findsOneWidget);
      expect(find.text('1 fields'), findsNWidgets(3));
      // 字段级：presence 条百分比（email = 90/100）。
      expect(find.text('Presence: 90%'), findsOneWidget);
      // Mixed：集合级组标签 + 字段级 chip 特标（l10n Mixed）双形态。
      expect(find.text('Type: Mixed'), findsOneWidget);
      expect(find.text('Mixed'), findsOneWidget);
      // ListView 懒构建：末位 meta 行在视口下缘外——滚动后断言嵌套标注。
      await tester.drag(
        find.byKey(const Key('mongo_schema_dist_list')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nested'), findsOneWidget);
      expect(find.text('created'), findsNothing);
      // 分布条列表容器在树（渲染主结构锚定）。
      expect(find.byKey(const Key('mongo_schema_dist_list')), findsOneWidget);
    });

    testWidgets('嵌套展开：toggle → subFields 渲染；再点收起', (tester) async {
      final seams = _Seams()
        ..schemaByPair['db1/users'] = _rawSchema(fields: _mixedFields);
      await pumpDialog(tester, seams);
      await openOn(tester, seams, 'db1', 'users');

      // meta 行位于列表末位（懒构建视口外）——先滚动入视口。
      await tester.drag(
        find.byKey(const Key('mongo_schema_dist_list')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mongo_schema_dist_toggle_meta')));
      await tester.pumpAndSettle();
      // 展开后子字段行更靠下——再滚动入视口。
      await tester.drag(
        find.byKey(const Key('mongo_schema_dist_list')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(find.text('created'), findsOneWidget);
      expect(
        find.byKey(const Key('mongo_schema_dist_sub_meta')),
        findsOneWidget,
      );
      // 子字段行 presence 条文本（meta 与 created 均为 40/100 → 两处 40%）。
      expect(find.text('Presence: 40%'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('mongo_schema_dist_toggle_meta')));
      await tester.pump();
      expect(find.text('created'), findsNothing);
      expect(
        find.byKey(const Key('mongo_schema_dist_sub_meta')),
        findsNothing,
      );
    });

    testWidgets('空态：totalSampled=0 → No fields', (tester) async {
      final seams = _Seams()
        ..schemaByPair['db1/users'] = _rawSchema(totalSampled: 0);
      await pumpDialog(tester, seams);
      await openOn(tester, seams, 'db1', 'users');

      expect(find.byKey(const Key('mongo_schema_dist_empty')), findsOneWidget);
      expect(find.text('No fields'), findsOneWidget);
    });

    testWidgets('加载态：loadSchema 未完成 → spinner；完成后数据态', (tester) async {
      final seams = _Seams()
        ..schemaByPair['db1/users'] = _rawSchema(fields: _mixedFields)
        ..gate = Completer<Map<String, dynamic>>();
      await pumpDialog(tester, seams);
      await selectOption(tester, 'db1');
      await tester.pumpAndSettle();
      await selectOption(tester, 'users', index: 1);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(seams.loadCalls, ['db1/users']);

      seams.gate!.complete(_rawSchema(fields: _mixedFields));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sampled 100 documents'), findsOneWidget);
    });

    testWidgets('失败态：loadSchema 抛 → Load failed 错误态（不崩溃）', (tester) async {
      final seams = _Seams()
        ..schemaByPair['db1/users'] = _rawSchema(fields: _mixedFields)
        ..throwOnPair = 'db1/users';
      await pumpDialog(tester, seams);
      await openOn(tester, seams, 'db1', 'users');

      expect(find.byKey(const Key('mongo_schema_dist_error')), findsOneWidget);
      expect(find.textContaining('Load failed'), findsOneWidget);
    });

    testWidgets('库切换重载：同名集合跨库各显式 load（缓存边界 dialog 侧管理）', (
      tester,
    ) async {
      final seams = _Seams()
        ..schemaByPair['db1/users'] = _rawSchema(
          fields: {
            'name': {'type': 'String', 'occurrence': 100},
          },
        )
        ..schemaByPair['db2/users'] = _rawSchema(
          collectionName: 'users',
          totalSampled: 10,
          fields: {
            'count': {'type': 'int', 'occurrence': 10},
          },
        );
      await pumpDialog(tester, seams);
      await openOn(tester, seams, 'db1', 'users');
      expect(seams.loadCalls, ['db1/users']);

      // 切库 → 集合下拉重置 → 重选同名集合 → 必须再次显式 load（不裸读
      // connectionId:collection 共享缓存——跨库同名串缓存边界的 dialog 侧
      // 处置，任务书 T17 边界节登记项）。
      await selectOption(tester, 'db2');
      await tester.pumpAndSettle();
      await selectOption(tester, 'users', index: 1);
      await tester.pumpAndSettle();

      expect(seams.loadCalls, ['db1/users', 'db2/users']);
      // db2 数据渲染（非 db1 残留）。
      expect(find.text('Sampled 10 documents'), findsOneWidget);
      expect(find.text('Type: int'), findsOneWidget);
    });
  });
}
