// ============================================================================
// DBT-T17 · MongoDB Schema 类型分布 E2E（W-14 真库验证）
//
// 覆盖（任务书 T17 真库验证节，引擎 = WSL MongoDB 8.0（admin 认证），连接
// 信息唯一来源 test_db_local_wsl.txt，凭据经 DBMASTER_MONGO_* dart-define
// 注入）：
//   ① dbmaster_test 真集合：分布非空渲染；集合级分组计数总和 = 字段数
//      （期望值从同一真数据的 facade 结果经 InferredDocumentSchema 推导，
//      UI 逐组对账）；presence 值域 [0,1]（UI 百分比 ∈ [0,100]）；混合
//      类型集合 Mixed 标注出现（真集合无混合类型字段则跳过并登记）；
//   ② 自建自删库零文档集合（createCollection）→ 空态；
//   ③ 自建自删库混合类型集合（同字段跨文档多型）→ Mixed 组标签 + 字段级
//      Mixed 特标 chip（自建控数，Mixed 断言的确定性落点）。
//
// 自建夹具经 WSL mongosh（gridfs e2e 先例：夹具非产品功能；MongoDB 删空
// 集合即删集合，零文档集合须显式 createCollection）；tearDownAll
// dropDatabase 回收。前置：Mongo 网关壳（ADR-0006）硬依赖 dbmaster server
// 会话——DBMASTER_SERVER_BIN 指向 dbmaster-server.exe；无二进制/未注入凭据
// /mongosh 不可用时以可 grep 的 MONGO_E2E_SKIP 整组跳过（FR-011 无假绿）。
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mongodb_sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

/// dbmaster_test fixture 库（任务书 T7 真库验证节：11 集合 100,160 docs）。
const String _fixtureDb = 'dbmaster_test';

/// 自建夹具库（唯一名，setUpAll 种入 / tearDownAll dropDatabase 回收）。
final String _selfDb =
    'dbmaster_t17_${DateTime.now().millisecondsSinceEpoch}';

/// 自建夹具集合：users = 混合类型（v 字段跨文档三型）；empty_coll =
/// createCollection 零文档（空态用）。
const String _mixedCollection = 'users';
const String _emptyCollection = 'empty_coll';

/// 真值表 fake：委托 CapabilityTable（与装配生产语义同面）。
class _E2ECapabilityPort implements DbCapabilityPort {
  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      CapabilityTable.has(type, capabilityId);

  @override
  Set<String> capabilitiesOf(DatabaseType type) => CapabilityTable.of(type);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('E2E fake 仅实现能力位查询');
}

/// 能力面板驱动壳：装配（core + mongo 插件 × CapabilityTable 门控）后把
/// 每个可见项渲染为 ListTile，onTap = item.onActivate（与真实菜单同一
/// 激活闭包；菜单本体渲染属 T2 框架，非本 E2E 断言面）。
class _CapabilityPanelHarness extends StatelessWidget {
  const _CapabilityPanelHarness();

  @override
  Widget build(BuildContext context) {
    final groups = assembleCapabilityMenu(
      context: context,
      type: DatabaseType.mongodb,
      port: _E2ECapabilityPort(),
      plugins: const [CoreSidebarPlugin(), MongodbSidebarPlugin()],
      l10n: AppLocalizations.of(context)!,
    );
    return Scaffold(
      body: ListView(
        children: [
          for (final group in groups)
            for (final item in group.items)
              ListTile(
                key: Key('${group.id}/${item.item.id}'),
                title: Text('${group.id}/${item.item.id}'),
                onTap: item.item.onActivate,
              ),
        ],
      ),
    );
  }
}

/// mongosh 经 WSL 执行脚本（ASCII-only——Dart Process.stdin 走系统码页，
/// CJK 注释字节会以非 UTF-8 到达 mongosh 使其静默停演，gridfs e2e 实测）。
Future<bool> _runMongoshScript(String script) async {
  final uri =
      'mongodb://${MongoDBTestConfig.host}:${MongoDBTestConfig.port}'
      '/${MongoDBTestConfig.authDatabase}?authSource=${MongoDBTestConfig.authDatabase}';
  final proc = await Process.start(
    'wsl',
    ['-d', 'Ubuntu-24.04', '--', 'mongosh', uri, '--quiet'],
  );
  proc.stdin.add(utf8.encode(script));
  await proc.stdin.flush();
  await proc.stdin.close();
  const decoder = Utf8Decoder(allowMalformed: true);
  final out = await proc.stdout.transform(decoder).join();
  final err = await proc.stderr.transform(decoder).join();
  final code = await proc.exitCode;
  final failedMarker = RegExp('MongoServerError|BSONError|Uncaught');
  final ok = code == 0 &&
      !failedMarker.hasMatch(out) &&
      !failedMarker.hasMatch(err);
  if (!ok) {
    // ignore: avoid_print
    print('MONGO_E2E_FIXTURE: exit=$code out=$out err=$err');
  }
  return ok;
}

Future<bool> _seedSelfDbFixture() {
  return _runMongoshScript("""
db.auth('${MongoDBTestConfig.username}', '${MongoDBTestConfig.password}');
db = db.getSiblingDB('$_selfDb');
db.$_mixedCollection.insertMany([
  {name: 'alice', age: 30, v: 'str-value', tags: ['x']},
  {name: 'bob', age: 41, v: 123, tags: ['y']},
  {name: 'carol', v: true}
]);
db.createCollection('$_emptyCollection');
""");
}

Future<bool> _dropSelfDbFixture() {
  return _runMongoshScript("""
db.auth('${MongoDBTestConfig.username}', '${MongoDBTestConfig.password}');
db.getSiblingDB('$_selfDb').dropDatabase();
""");
}

/// 期望分组（类型 → 字段数），按 dialog 同口径排序（计数降序 + 类型名升序
/// ——对账滚动单调向下）。
List<MapEntry<String, int>> orderedGroups(InferredDocumentSchema schema) {
  final counts = <String, int>{};
  for (final field in schema.fields) {
    counts[field.bsonType] = (counts[field.bsonType] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  return entries;
}

void main() {
  // Mongo 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  bool mongoE2EGatewayReady = false;
  bool selfDbReady = false;
  setUpAll(() async {
    mongoE2EGatewayReady = await ensureEmbeddedServerForMongoE2E();
    if (mongoE2EGatewayReady && !MongoDBTestConfig.available) {
      // ignore: avoid_print
      print('MONGO_E2E_SKIP: DBMASTER_MONGO_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      mongoE2EGatewayReady = false;
    }
    if (mongoE2EGatewayReady) {
      selfDbReady = await _seedSelfDbFixture();
      if (!selfDbReady) {
        // ignore: avoid_print
        print('MONGO_E2E_SKIP: T17 自建夹具种入失败（mongosh 不可用或脚本'
            '错误）——自建库两态跳过');
      }
    }
  });

  tearDownAll(() async {
    if (selfDbReady) {
      // 夹具回收失败仅打印（库唯一名不构成复用冲突，登记可手工清理）。
      final dropped = await _dropSelfDbFixture();
      if (!dropped) {
        // ignore: avoid_print
        print('MONGO_E2E_FIXTURE: dropDatabase 失败（$_selfDb 残留，需手工清理）');
      }
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t17-e2e-mongo',
      type: DatabaseType.mongodb,
      name: 'DBT T17 E2E MongoDB',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );
    // 面板闭包族（loadDatabaseInfo / loadMongoDBSchema）经 saved 连接解析
    // ——e2e server 必须先入 saved 表（T7/T12 同前置）。
    provider.connection.addSavedServerForTest(server);
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  Future<void> connectReal(WidgetTester tester) async {
    final connected = await tester
        .runAsync(() => provider.connection.connectToServer(server));
    expect(connected, isTrue, reason: '真库连接失败（${MongoDBTestConfig.host}）');
  }

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: _CapabilityPanelHarness()),
        ),
      ),
    );
    await tester.pump();
  }

  /// 轮询等待条件成立（runAsync 放行真实 I/O——真库往返在真实时钟下完成）。
  Future<bool> waitUntil(
    WidgetTester tester,
    bool Function() condition, {
    int timeoutMs = 30000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    return condition();
  }

  Future<void> activateItem(WidgetTester tester, String itemId) async {
    await tester.tap(find.byKey(Key('advanced/$itemId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 打开面板项对应 dialog 的下拉并选中 [option]（真库清单加载经 waitUntil
  /// 轮询；下拉展开态跨轮询帧保持）。
  Future<void> selectDropdownOption(
    WidgetTester tester,
    String option, {
    int dropdownIndex = 0,
  }) async {
    await tester.tap(find.byType(DropdownButton<String>).at(dropdownIndex));
    await tester.pump();
    final appeared = await waitUntil(
      tester,
      () => tester.any(find.text(option).last),
    );
    expect(appeared, isTrue, reason: '下拉选项未出现：$option');
    await tester.tap(find.text(option).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 打开分布面板并选齐 库 + 集合，等分布/空态渲染（真库 inferDocumentSchema
  /// 抽样往返）。
  Future<void> openDistributionOn(
    WidgetTester tester,
    String database,
    String collection,
  ) async {
    await pumpHarness(tester);
    await activateItem(tester, 'mongo.schemaAnalysis');
    expect(
      await waitUntil(
        tester,
        () => tester.any(find.text('Schema Type Distribution')),
      ),
      isTrue,
    );
    await selectDropdownOption(tester, database);
    await selectDropdownOption(tester, collection, dropdownIndex: 1);
    final rendered = await waitUntil(
      tester,
      () =>
          tester.any(find.byKey(const Key('mongo_schema_dist_list'))) ||
          tester.any(find.byKey(const Key('mongo_schema_dist_empty'))),
      timeoutMs: 60000,
    );
    expect(rendered, isTrue, reason: '分布/空态应渲染（真库往返）');
  }

  /// 读取 facade 缓存的真集合推断 schema（面板刚加载过，缓存必在）。
  InferredDocumentSchema readFacadeSchema(String collection) {
    final raw = provider.getMongoDBSchema(server.id, collection);
    if (raw == null) {
      fail('facade 应已缓存 $collection 的推断 schema（面板已加载）');
    }
    return InferredDocumentSchema.fromAdapterOutput(raw);
  }

  /// 滚动分布列表直到 [finder] 可见（ListView 懒构建——视口外行未 build；
  /// 沿 dialog 分组展示序单调向下滚。scrollable 参数须匹配 Scrollable 本体
  /// ——经 descendant 从 list key 定位）。
  Future<void> scrollUntilVisible(
    WidgetTester tester,
    Finder finder,
  ) async {
    await tester.scrollUntilVisible(
      finder,
      -120,
      scrollable: find.descendant(
        of: find.byKey(const Key('mongo_schema_dist_list')),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 40,
    );
    await tester.pumpAndSettle();
  }

  /// 采集当前视口内全部 presence 百分比（值域断言采样面）。
  Set<int> harvestPresencePercents(WidgetTester tester) {
    final percents = <int>{};
    for (final text in tester.widgetList<Text>(
      find.textContaining('Presence: '),
    )) {
      final match = RegExp(r'Presence: (\d+)%').firstMatch(text.data ?? '');
      if (match != null) percents.add(int.parse(match.group(1)!));
    }
    return percents;
  }

  testWidgets('DBT-T17-FIXTURE：dbmaster_test 真集合分布非空 + 分组计数对账 + presence 值域', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);

    // 定位首个「有字段」的真实集合（真实 listCollections + 推断抽样，幂等
    // 只读；与面板同源 loadDatabaseInfo / loadMongoDBSchema 路径）。
    final info = await provider.loadDatabaseInfo(server.id, _fixtureDb);
    final collections =
        info?.tables.map((t) => t.name).toList() ?? const <String>[];
    expect(collections, isNotEmpty, reason: '$_fixtureDb 库应含真实集合');
    String? pickedName;
    InferredDocumentSchema? pickedSchema;
    for (final name in collections.take(5)) {
      await tester.runAsync(
        () => provider.loadMongoDBSchema(server.id, _fixtureDb, name),
      );
      final raw = provider.getMongoDBSchema(server.id, name);
      if (raw == null) continue;
      final inferred = InferredDocumentSchema.fromAdapterOutput(raw);
      if (!inferred.isEmpty) {
        pickedName = name;
        pickedSchema = inferred;
        break;
      }
    }
    if (pickedName == null || pickedSchema == null) {
      fail('$_fixtureDb 前五个集合应至少一个有字段（fixture 100,160 docs）');
    }
    final groups = orderedGroups(pickedSchema);

    await openDistributionOn(tester, _fixtureDb, pickedName);

    // 头行：抽样数（INFERENCE 默认 100 上限，>0）。
    final sampledMatch = find.textContaining('Sampled ');
    expect(sampledMatch, findsOneWidget);
    final sampledText = tester.widget<Text>(sampledMatch.first).data ?? '';
    final sampled = RegExp(r'Sampled (\d+) documents').firstMatch(sampledText);
    expect(sampled, isNotNull, reason: '抽样头行文案异常：$sampledText');
    final sampledCount = int.parse(sampled!.group(1)!);
    expect(sampledCount, greaterThan(0), reason: '真集合抽样数应 > 0');
    expect(sampledCount, lessThanOrEqualTo(100),
        reason: 'INFERENCE 既有抽样口径 = 100（不放大）');

    // 集合级分组逐组对账（沿展示序滚动——懒构建视口外行未 build）：每组
    // 计数文案与期望一致；总和 = 字段数由 orderedGroups 构造保证（同一
    // fromAdapterOutput 数据面），累加复核任务书验收口径。
    var uiGroupFieldSum = 0;
    var presencePercents = <int>{};
    for (final entry in groups) {
      await scrollUntilVisible(tester, find.text('Type: ${entry.key}'));
      expect(find.text('${entry.value} fields'), findsWidgets,
          reason: '分组 ${entry.key} 计数 ${entry.value} 应渲染');
      presencePercents.addAll(harvestPresencePercents(tester));
      uiGroupFieldSum += entry.value;
    }
    expect(uiGroupFieldSum, pickedSchema.fields.length,
        reason: '类型计数总和 = 字段数（任务书验收口径）');

    // presence 值域：滚动全程采样 ∈ [0,100]（presenceRatio ∈ [0,1] 的 UI
    // 投影；模型侧同域由 SchemaField 构造断言保证）。
    expect(presencePercents, isNotEmpty, reason: '至少应渲染 presence 文案');
    for (final pct in presencePercents) {
      expect(pct, inInclusiveRange(0, 100), reason: 'presence 值域 [0,1]');
    }

    // 混合类型标注：真集合含 Mixed 字段则断言 chip（无则登记跳过——自建库
    // 用例为 Mixed 断言的确定性落点）。
    if (groups.any((g) => g.key == 'Mixed')) {
      await scrollUntilVisible(tester, find.text('Mixed'));
      expect(find.text('Mixed'), findsWidgets,
          reason: '混合类型字段应有 Mixed 特标 chip');
    } else {
      // ignore: avoid_print
      print('DBT-T17 登记: 真集合 $pickedName 无混合类型字段，Mixed 标注断言'
          '由自建库用例覆盖（任务书「无则跳过该断言并登记」）');
    }
  });

  testWidgets('DBT-T17-EMPTY：自建库零文档集合 → 空态', (tester) async {
    if (!mongoE2EGatewayReady || !selfDbReady) return;
    await connectReal(tester);
    await openDistributionOn(tester, _selfDb, _emptyCollection);

    expect(find.byKey(const Key('mongo_schema_dist_empty')), findsOneWidget);
    expect(find.text('No fields'), findsOneWidget);
  });

  testWidgets('DBT-T17-MIXED：自建库混合类型集合 → Mixed 组 + 字段级 Mixed chip', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady || !selfDbReady) return;
    await connectReal(tester);
    await openDistributionOn(tester, _selfDb, _mixedCollection);

    // v 字段跨文档多型 → dominant type = Mixed（分组期望从同一真数据推导，
    // 不硬编码 gateway 类型命名——_id 等字段的类型形态随网关出向而定）。
    final schema = readFacadeSchema(_mixedCollection);
    expect(schema.totalSampled, 3, reason: 'users 夹具 3 文档全采样');
    final groups = orderedGroups(schema);
    expect(
      groups.any((g) => g.key == 'Mixed'),
      isTrue,
      reason: 'v 字段跨文档三型 → Mixed 组必须在场',
    );

    // 集合级组标签 + 字段级 chip 特标双形态；逐组计数对账（同真数据推导）。
    for (final entry in groups) {
      await scrollUntilVisible(tester, find.text('Type: ${entry.key}'));
      expect(find.text('${entry.value} fields'), findsWidgets,
          reason: '分组 ${entry.key} 计数 ${entry.value} 应渲染');
    }
    await scrollUntilVisible(tester, find.text('Type: Mixed'));
    expect(find.text('Type: Mixed'), findsOneWidget);
    expect(find.text('Mixed'), findsOneWidget);
  });
}
