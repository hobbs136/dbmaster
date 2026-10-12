// ============================================================================
// DBT-T11 · MongoDB GridFS 只读查看器 E2E（W-12 真库验证）
//
// 覆盖（任务书 T11 真库验证节，引擎 = WSL MongoDB 8.0.32（admin 认证），
// 连接信息唯一来源 test_db_local_wsl.txt，口令经 DBMASTER_MONGO_PASSWORD
// dart-define 注入；fixture = 自建自删测试库 + mongosh 预置 GridFS 文件——
// 夹具非产品功能，真 BSON Binary 只能经 mongosh BinData 写入（网关入向
// 无 $binary 反解，产品通道写不出真二进制 chunk；mongo_dart 亦非依赖））：
//   ① 面板项打开（生产 onActivate 链）→ 选库 → bucket 自动选中 → 文件列表
//      真数据（objectId/filename/size/uploadDate/chunkSize）+ 行元数据详情
//      （含用户 metadata JSON）；
//   ② 下载全链路：**内容与预置逐字节一致**（多 chunk 文件 chunkSize=8 →
//      3 chunk 乱序插入 → 证 n 升序拼接）→ 临时文件比对 → 下载审计落账
//      （AuditLogService export 条目 format='gridfs_file'）。
//      下载驱动 = 直构 dialog 注入 savePathPicker 接缝（FilePicker 8.x
//      Windows = Isolate.spawn + comdlg32 FFI 原生对话框，测试不可 mock、
//      不可直开——AI-SEX「FilePicker 平台插件测试不 mock，接缝注入」同裁
//      定；loader/写盘/审计全走生产默认链）。
//
// 前置：Mongo 网关壳（ADR-0006）硬依赖 dbmaster server 会话——
// DBMASTER_SERVER_BIN 指向 dbmaster-server.exe；WSL mongosh 可用；无前置
// 或未注入凭据时以可 grep 的 MONGO_E2E_SKIP 整组跳过（FR-011 无假绿纪律）。
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
import 'package:dbmaster/organisms/dialogs/mongo_gridfs_dialog.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mongodb_sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mongodb_gateway_adapter.dart';
import 'package:dbmaster/services/audit_log_service.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

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

/// 能力面板驱动壳（与 T7/T10 e2e 同款）：装配后把可见项渲染为 ListTile，
/// onTap = item.onActivate（与真实菜单同一激活闭包）。
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

/// mongosh 夹具产物（预置内容与寻址键）。
class _GridFsFixture {
  _GridFsFixture({
    required this.database,
    required this.bucket,
    required this.oidMulti,
    required this.oidSingle,
    required this.contentMulti,
    required this.contentSingle,
    required this.nameMulti,
    required this.nameSingle,
  });

  final String database;
  final String bucket;
  final String oidMulti;
  final String oidSingle;
  final List<int> contentMulti;
  final List<int> contentSingle;
  final String nameMulti;
  final String nameSingle;
}

/// 24 位 hex ObjectId（时间戳 8 + 序号 4 + 常量尾 12；夹具寻址键，仅本
/// 测试内使用——长度必须恰为 24，短一位 mongosh ObjectId 即抛 BSONError）。
String _oidHex(int seq) {
  final ts = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;
  final tsHex = ts.toRadixString(16).padLeft(8, '0');
  return '$tsHex${seq.toRadixString(16).padLeft(4, '0')}e2ea0db1f00d';
}

/// mongosh 经 WSL 预置 GridFS bucket（自建测试库；口令经 stdin 传入——
/// 不进 argv/代码/日志）。
Future<bool> _seedGridFsFixture(_GridFsFixture f) async {
  final b64Single = base64Encode(f.contentSingle);
  String chunk(int n, List<int> bytes) =>
      "{files_id: ObjectId('${f.oidMulti}'), n: $n, "
      "data: BinData(0, '${base64Encode(bytes)}')}";
  final multi = f.contentMulti;
  // 注意：脚本须 ASCII-only（Dart Process.stdin 走系统码页，CJK 注释字节
  // 会以非 UTF-8 到达 mongosh 使其静默停演——实测 {ok:1} 后中断）。
  final script = """
db.auth('admin', '${MongoDBTestConfig.password}');
db = db.getSiblingDB('${f.database}');
db['${f.bucket}.files'].insertOne({
  _id: ObjectId('${f.oidSingle}'), length: ${f.contentSingle.length},
  chunkSize: 261120, uploadDate: new Date('2026-10-12T08:30:00.000Z'),
  filename: '${f.nameSingle}', contentType: 'application/octet-stream',
  metadata: {source: 'dbt-t11-e2e', kind: 'gridfs-single'}});
db['${f.bucket}.chunks'].insertOne({
  files_id: ObjectId('${f.oidSingle}'), n: 0, data: BinData(0, '$b64Single')});
db['${f.bucket}.files'].insertOne({
  _id: ObjectId('${f.oidMulti}'), length: ${multi.length},
  chunkSize: 8, uploadDate: new Date('2026-10-12T09:00:00.000Z'),
  filename: '${f.nameMulti}', metadata: {source: 'dbt-t11-e2e'}});
db['${f.bucket}.chunks'].insertMany([
  ${chunk(2, multi.sublist(16))},
  ${chunk(0, multi.sublist(0, 8))},
  ${chunk(1, multi.sublist(8, 16))},
]);
""";
  final uri =
      'mongodb://${MongoDBTestConfig.host}:${MongoDBTestConfig.port}'
      '/${MongoDBTestConfig.authDatabase}?authSource=${MongoDBTestConfig.authDatabase}';
  final proc = await Process.start(
    'wsl',
    ['-d', 'Ubuntu-24.04', '--', 'mongosh', uri, '--quiet'],
  );
  // 显式 UTF-8 字节写入（绕开 Process.stdin 的系统码页编码）。
  proc.stdin.add(utf8.encode(script));
  await proc.stdin.flush();
  await proc.stdin.close();
  // wsl.exe 偶发向输出掺 UTF-16 代理告警行——容错解码（成败判据走
  // exitCode + 错误标记缺席，不依赖输出全文可解码）。
  const decoder = Utf8Decoder(allowMalformed: true);
  final out = await proc.stdout.transform(decoder).join();
  final err = await proc.stderr.transform(decoder).join();
  final code = await proc.exitCode;
  // 成败判据：exit 0 且输出无任何未捕获错误（MongoServerError/BSONError/
  // Uncaught …——BSONError 实测会溜过仅查 MongoServerError 的判据）。
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

void main() {
  // Mongo 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  bool mongoE2EGatewayReady = false;
  setUpAll(() async {
    mongoE2EGatewayReady = await ensureEmbeddedServerForMongoE2E();
    if (mongoE2EGatewayReady && !MongoDBTestConfig.available) {
      // ignore: avoid_print
      print('MONGO_E2E_SKIP: DBMASTER_MONGO_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      mongoE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;
  late String testDb;
  late _GridFsFixture fixture;
  MongoDBAdapter? adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDb = MongoDBTestConfig.generateTestDatabaseName();
    fixture = _GridFsFixture(
      database: testDb,
      bucket: 'media',
      oidMulti: _oidHex(1),
      oidSingle: _oidHex(2),
      contentMulti: List<int>.generate(20, (i) => i),
      contentSingle: utf8.encode('DBT-T11 GridFS single chunk fixture'),
      nameMulti: 't11-multi.bin',
      nameSingle: 't11-report.bin',
    );
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t11-e2e-mongo',
      type: DatabaseType.mongodb,
      name: 'DBT T11 E2E MongoDB',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );
    // 面板闭包经 savedConnections 解析连接 → e2e server 先入 saved 表
    //（T7/T10 e2e 同款生产前置还原）。
    provider.connection.addSavedServerForTest(server);
  });

  tearDown(() async {
    try {
      if (adapter?.isConnected == true) {
        await adapter!.dropDatabase(testDb);
      }
    } catch (_) {}
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  Future<MongoDBAdapter> connectReal(WidgetTester tester) async {
    final connected = await tester.runAsync(
      () => provider.connection.connectToServer(server),
    );
    expect(connected, isTrue, reason: '真库连接失败（${MongoDBTestConfig.host}）');
    final raw = provider.dbService.getAdapter(server.id);
    expect(raw, isA<MongoDBAdapter>(), reason: '应取得 MongoDB 网关壳 adapter');
    return raw as MongoDBAdapter;
  }

  Future<bool> seed(WidgetTester tester) async =>
      await tester.runAsync(() => _seedGridFsFixture(fixture)) == true;

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const _CapabilityPanelHarness(),
        ),
      ),
    );
    await tester.pump();
  }

  /// 真实时钟轮询（[poll] 返回 true 停止；T10 e2e 同款）。
  Future<bool> pollReal(
    WidgetTester tester,
    Future<bool> Function() poll, {
    int timeoutMs = 20000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (await tester.runAsync(poll) == true) return true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }
    return false;
  }

  /// UI 条件轮询（真实时钟下完成加载，T10 e2e 同款）。
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

  /// 打开 GridFS 面板（面板项 → dialog）。
  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('advanced/mongo.gridfs')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 在已打开的 GridFS dialog 里选库。库清单经真实网关加载（秒级），
  /// 而 Dropdown 的 items 只在菜单展开时构建（展开时未加载则该次菜单为
  /// 空、不随后续数据更新）→ 展开后轮询目标条目，未出现收起重试。
  Future<void> selectTestDb(WidgetTester tester) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pump();
      final found = await waitUntil(
        tester,
        () => tester.any(find.text(testDb)),
        timeoutMs: 2000,
      );
      if (found) {
        await tester.tap(find.text(testDb).last);
        await tester.pump(const Duration(milliseconds: 300));
        return;
      }
      // 收起菜单（点遮罩）→ 真实时钟等下一轮。
      await tester.tapAt(const Offset(400, 20));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
    }
    fail('库下拉重试 10 次未出现 $testDb');
  }

  testWidgets('DBT-T11-PANEL：面板项 → bucket 自动选中 → 列表字段 + 元数据详情（真库）', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);
    expect(await seed(tester), isTrue, reason: 'mongosh 夹具预置失败');

    await pumpHarness(tester);
    await openPanel(tester);
    await selectTestDb(tester);

    // bucket 自动选中（media 唯一）→ 文件列表真数据（两文件，uploadDate
    // 降序 = multi 在前）。列表字段逐一断言（objectId/filename/size/
    // uploadDate/chunkSize）。
    final listed = await waitUntil(
      tester,
      () => tester.any(find.text(fixture.nameMulti)),
      timeoutMs: 30000,
    );
    expect(listed, isTrue, reason: '文件列表应渲染（${fixture.nameMulti}）');
    expect(find.text(fixture.oidMulti), findsOneWidget);
    expect(find.text(fixture.nameSingle), findsOneWidget);
    expect(find.text(fixture.oidSingle), findsOneWidget);
    expect(find.text('20 B'), findsOneWidget, reason: 'multi length=20');
    expect(find.text('8 B'), findsOneWidget, reason: 'multi chunkSize=8');
    expect(find.textContaining('2026-10-12'), findsNWidgets(2));
    expect(find.text('media'), findsOneWidget, reason: 'bucket 自动选中');

    // 行点击 → 元数据详情（字段 + 用户 metadata JSON + contentType）。
    await tester.tap(find.text(fixture.nameSingle));
    await tester.pump();
    final detailShown = await waitUntil(
      tester,
      () => tester.any(find.text('Metadata')),
      timeoutMs: 15000,
    );
    expect(detailShown, isTrue, reason: '元数据详情应渲染');
    expect(find.textContaining('application/octet-stream'), findsOneWidget);
    expect(find.textContaining('dbt-t11-e2e'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump();
  });

  testWidgets('DBT-T11-DOWNLOAD：多 chunk 下载逐字节一致 + 审计落账（真库）', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);
    expect(await seed(tester), isTrue, reason: 'mongosh 夹具预置失败');

    // 下载驱动 = 直构 dialog 注入 savePathPicker 接缝（FilePicker 8.x
    // Windows = comdlg32 原生对话框，测试不可 mock 不可直开——文件头注）；
    // loader/写盘/审计全走生产默认链（与插件闭包同一 adapter 面）。
    final tempPath =
        '${Directory.systemTemp.path}/dbmaster_t11_gridfs_${fixture.oidMulti}.bin';
    final home = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => MongoGridFsDialog(
                connectionId: server.id,
                loadDatabases: (cid) =>
                    provider.dbService.getDatabases(connectionId: cid),
                loadBuckets: (cid, db) async {
                  final info = await provider.loadDatabaseInfo(cid, db);
                  return MongoGridFsFileEntry.bucketNamesFrom(
                    info?.tables.map((t) => t.name) ?? const <String>[],
                  );
                },
                listFiles: (cid, db, bucket) async {
                  final a = provider.dbService.getAdapter(cid);
                  if (a is! MongoDBAdapter) {
                    throw StateError('MongoDB 连接不可用');
                  }
                  return MongoGridFsFileEntry.listFromFilesDocs(
                    await a.listGridFsFiles(bucket, database: db),
                  );
                },
                loadMetadata: (cid, db, bucket, oid) async {
                  final a = provider.dbService.getAdapter(cid);
                  if (a is! MongoDBAdapter) {
                    throw StateError('MongoDB 连接不可用');
                  }
                  return a.getGridFsFileMetadata(bucket, oid, database: db);
                },
                readFileBytes: (cid, db, bucket, oid) async {
                  final a = provider.dbService.getAdapter(cid);
                  if (a is! MongoDBAdapter) {
                    throw StateError('MongoDB 连接不可用');
                  }
                  return a.readGridFsFileBytes(bucket, oid, database: db);
                },
                savePathPicker: (_) async => tempPath,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 选库 → bucket 自动选中 → 列表渲染。
    await selectTestDb(tester);
    final listed = await waitUntil(
      tester,
      () => tester.any(find.text(fixture.nameMulti)),
      timeoutMs: 30000,
    );
    expect(listed, isTrue, reason: '文件列表应渲染');

    // 下载（多 chunk 乱序插入 → n 升序拼接）：tap 在 runAsync 真实异步
    // zone 内派发，HTTP 取数 + dart:io 写盘的 await 在真实事件环完成
    //（Windows flutter_tester fake async 内文件 IO future 不派发的平台
    // 事实，AI-SEX 头注；T10 e2e 真实 IO 同款 runAsync 通道）。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(Key('gridfs_download_${fixture.oidMulti}')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    // 等审计落账（下载链最后一环；写盘先行完成）。
    final audited = await pollReal(
      tester,
      () async =>
          AuditLogService()
              .getRecentExportEntries()
              .any((e) => e.format == 'gridfs_file'),
      timeoutMs: 30000,
    );
    expect(audited, isTrue, reason: '下载审计应落账（format=gridfs_file）');
    await tester.pump();
    expect(find.text('Download complete'), findsOneWidget);

    // 逐字节一致（temp 文件 vs 预置内容；sync 读 = AI-SEX-106 同款）。
    final file = File(tempPath);
    expect(file.existsSync(), isTrue, reason: '下载文件应落盘');
    final downloaded = file.readAsBytesSync();
    expect(downloaded, fixture.contentMulti,
        reason: '下载内容与预置逐字节一致（3 chunk n 升序拼接）');
    // 清理下载产物（自建自删）。
    try {
      file.deleteSync();
    } on FileSystemException {
      // 清理失败不阻塞（Windows 短时占用先例）。
    }

    await tester.tap(find.text('Close'));
    await tester.pump();
  });
}
