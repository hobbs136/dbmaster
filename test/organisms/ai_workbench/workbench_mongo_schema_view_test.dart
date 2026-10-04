//! WorkbenchMongoSchemaView 组件测试（2b.2a 任务卡 §6.2 条款 2）。
//!
//! headless `_LightApp` 模式（widget_test.dart:154 同款最小树：仅
//! ChangeNotifierProvider<AppProvider>.value + MaterialApp + l10n delegates，
//! 无 main.dart 导入、无平台通道）。覆盖五要点：
//! ① 三态节点断言（加载/失败+重试/空集合，en locale 文案 = 2b.0 预登记
//! key 值）；② 失败态重试调用计数（重试 = 再调 loadMongoDBSchema，且失败
//! 后不自动重拉）；③ schema 字段渲染 byType(SchemaNestedExpander) + 头行
//! 集合名/字段数徽标；④ 首帧 post-frame 触发 load（参数正确：connectionId/
//! databaseName/collectionName 三参逐一到 facade）；⑤ loading 守卫去重
//! （provider 已加载中时首帧零排程 + 加载中 rebuild 零重复调用 + 多次
//! notify 后调用数恒 1）。
//!
//! 断言纪律（AGENTS.md §5 约定 3）：只断言结构/存在性/文本/行为调用，
//! 不断言颜色、间距、字体。真库维度不在此件——并入 2b.2b e2e 草稿口径。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_mongo_schema_view.dart';
import 'package:dbmaster/organisms/mongodb/schema_view/schema_nested_expander.dart';
import 'package:dbmaster/providers/app_provider.dart';

/// 2b.2a 测试桩：覆盖 AppProvider 的 Mongo schema facade 三方法，镜像真实
/// facade 的 loading 守卫语义（app_provider.dart:2898：已在加载中 → 直接
/// 返回、不重复拉取、不计数）。
class _FakeMongoAppProvider extends AppProvider {
  Map<String, dynamic>? schema;
  bool loading = false;

  /// 通过守卫的调用次数（= 真实发起拉取）。
  int loadCalls = 0;

  /// 命中守卫（loading 已 true 仍被调）次数。
  int guardHits = 0;

  /// 每次 load 收到的三参（首帧触发参数正确性断言用）。
  final List<String> calledConnectionIds = [];
  final List<String> calledDatabases = [];
  final List<String> calledCollections = [];

  /// true = load 只翻 loading、等待测试手动调 [completeLoad] 完成
  /// （加载态断言 / 失败态时序用）。
  bool manualComplete = false;

  /// true = 下次完成时 schema 保持 null（模拟 facade 加载失败）。
  bool failNext = false;

  String? _lastCollection;

  @override
  Map<String, dynamic>? getMongoDBSchema(
    String connectionId,
    String collectionName,
  ) => schema;

  @override
  bool isLoadingMongoDBSchema(String connectionId, String collectionName) =>
      loading;

  @override
  Future<void> loadMongoDBSchema(
    String connectionId,
    String databaseName,
    String collectionName, {
    int sampleSize = 100,
  }) async {
    calledConnectionIds.add(connectionId);
    calledDatabases.add(databaseName);
    calledCollections.add(collectionName);
    _lastCollection = collectionName;
    if (loading) {
      guardHits++;
      return;
    }
    loadCalls++;
    loading = true;
    notifyListeners();
    if (manualComplete) return;
    await Future<void>.microtask(() {});
    completeLoad();
  }

  /// 手动完成当前挂起的加载（loading → false + 按 failNext 决定 schema）。
  void completeLoad() {
    final collection = _lastCollection;
    if (!failNext && collection != null) {
      schema = _seedSchema(collection);
    }
    loading = false;
    notifyListeners();
  }
}

/// 3 顶层字段（含 1 嵌套 document）种子 schema——与真实 adapter 输出同形
/// （mongodb_gateway_adapter.dart:2138-2142：collectionName/totalSampled/fields）。
Map<String, dynamic> _seedSchema(String collectionName) => {
  'collectionName': collectionName,
  'totalSampled': 10,
  'fields': <String, dynamic>{
    'age': <String, dynamic>{'type': 'int', 'occurrence': 9},
    'name': <String, dynamic>{'type': 'String', 'occurrence': 10},
    'address': <String, dynamic>{
      'type': 'Document',
      'occurrence': 6,
      'subFields': <String, dynamic>{
        'city': <String, dynamic>{'type': 'String', 'occurrence': 6},
      },
    },
  },
};

/// 空集合 adapter 输出（totalSampled 0 + 空 fields）。
Map<String, dynamic> _emptySchema(String collectionName) => {
  'collectionName': collectionName,
  'totalSampled': 0,
  'fields': <String, dynamic>{},
};

Future<void> _pumpView(WidgetTester tester, _FakeMongoAppProvider provider) {
  return tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(
          body: WorkbenchMongoSchemaView(
            connectionId: 'conn-1',
            databaseName: 'mydb',
            collectionName: 'users',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('首帧触发 load：三参正确且调用数恒 1（守卫去重）', (tester) async {
    final fake = _FakeMongoAppProvider();
    await _pumpView(tester, fake);
    await tester.pump();

    expect(fake.loadCalls, 1);
    expect(fake.calledConnectionIds, ['conn-1']);
    expect(fake.calledDatabases, ['mydb']);
    expect(fake.calledCollections, ['users']);

    // 多次无关 notify + 重建：不再重复拉取（首帧已排程 + 缓存已就位）。
    fake.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(fake.loadCalls, 1);

    // 内容已渲染（schema 字段树 + 头行集合名 + 字段数徽标）。
    expect(find.byType(SchemaNestedExpander), findsNWidgets(3));
    expect(find.text('users'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('加载态：加载文案可见 + 加载中零重复调用', (tester) async {
    final fake = _FakeMongoAppProvider()..manualComplete = true;
    await _pumpView(tester, fake);
    await tester.pump();

    expect(find.text('Loading schema…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 加载中 rebuild：守卫去重，调用数仍 1。
    fake.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(fake.loadCalls, 1);

    // 完成 → 加载态退出、内容就位。
    fake.completeLoad();
    await tester.pump();
    expect(find.text('Loading schema…'), findsNothing);
    expect(find.byType(SchemaNestedExpander), findsNWidgets(3));
  });

  testWidgets('失败态：失败文案 + Retry + 失败后不自动重拉', (tester) async {
    final fake = _FakeMongoAppProvider()
      ..manualComplete = true
      ..failNext = true;
    await _pumpView(tester, fake);
    await tester.pump();
    fake.completeLoad();
    await tester.pump();

    expect(find.text('Schema load failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // 失败态不自动重拉（防每帧重拉循环）。
    await tester.pump();
    expect(fake.loadCalls, 1);

    // 重试 = 再调 loadMongoDBSchema：先回加载态，完成后进内容。
    fake.failNext = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(fake.loadCalls, 2);
    expect(find.text('Loading schema…'), findsOneWidget);
    fake.completeLoad();
    await tester.pump();
    expect(find.byType(SchemaNestedExpander), findsNWidgets(3));
  });

  testWidgets('空集合态：空态标题 + hint，零字段树', (tester) async {
    final fake = _FakeMongoAppProvider()..schema = _emptySchema('users');
    await _pumpView(tester, fake);
    await tester.pump();

    expect(find.text('No schema data'), findsOneWidget);
    expect(
      find.text('This collection is empty or has no documents to analyze'),
      findsOneWidget,
    );
    expect(find.byType(SchemaNestedExpander), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('schema 字段渲染：头行摘要 + byType(SchemaNestedExpander)', (
    tester,
  ) async {
    final fake = _FakeMongoAppProvider()..schema = _seedSchema('users');
    await _pumpView(tester, fake);
    await tester.pump();

    // 头行：集合名（构造函数值，数据非文案）+ 字段数徽标。
    expect(find.text('users'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // 字段树：3 顶层 SchemaNestedExpander，字段名逐一渲染。
    expect(find.byType(SchemaNestedExpander), findsNWidgets(3));
    expect(find.text('age'), findsOneWidget);
    expect(find.text('name'), findsOneWidget);
    expect(find.text('address'), findsOneWidget);
    // 嵌套子字段未展开不渲染（SchemaNestedExpander 折叠语义零改动复用）。
    expect(find.text('city'), findsNothing);
  });

  testWidgets('loading 守卫：provider 已加载中时首帧零排程', (tester) async {
    final fake = _FakeMongoAppProvider()..loading = true;
    await _pumpView(tester, fake);
    await tester.pump();
    await tester.pump();

    // 首帧即加载中 → 不再排程拉取（schema_view_widget.dart:21-26 同款判断：
    // 「未在加载」才拉取）。
    expect(fake.loadCalls, 0);
    expect(fake.guardHits, 0);
    expect(find.text('Loading schema…'), findsOneWidget);

    // 完成后正常进内容（本用例从未走 load 路径，直接模拟加载结束落地数据）。
    fake.schema = _seedSchema('users');
    fake.loading = false;
    fake.notifyListeners();
    await tester.pump();
    expect(find.byType(SchemaNestedExpander), findsNWidgets(3));
  });
}
