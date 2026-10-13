// ============================================================================
// DBT-T21 · MongoDB GridFS 上传 E2E（真库验证，WSL MongoDB 8.0.32）
//
// 覆盖（任务书 T21 真库验证节；引擎 = WSL MongoDB 8.0.32（admin 认证），
// 连接信息唯一来源 test_db_local_wsl.txt，口令经 DBMASTER_MONGO_PASSWORD
// dart-define 注入；实验库/bucket 自建自删）：
//   ① 基础上传（adapter 写面直驱）：文本 + 二进制各一 → T11 只读面读回
//      **逐字节一致** + fs.files 元数据（length/chunkSize/filename）+
//      fs.files 行数对账；
//   ② 多 chunk 分批（>100 chunks，~26 MB 真文件路径）：字节预算分批
//      （axum 2MB body 上限约束，批 ≈5 满 chunk——单请求 34MB 必 413，
//      本用例即分批正确性的实证）→ chunks 计数 == 101 + 全量读回逐字节
//      一致；
//   ③ dialog 全链路（生产默认 uploader = AppProvider → adapter）：面板
//      预览确认 → 上传 → 成功反馈 + 列表刷新见新行 + recordQuery 审计
//      （isWriteQuery:true，SQL 位摘要式描述，不含二进制）；
//   ④ 失败路径（mongosh 预置冲突 files_id chunk + (files_id,n) 唯一索引）
//      → E11000 → 回滚（本 files_id chunks 清零）+ fs.files 零行 + 错误
//      反馈含回滚注记；
//   ⑤ readonly 连接：adapter guardReadOnly 抛 + dialog 上传入口禁用；
//      取消路径（选择器/确认门）= 零 chunks 零审计零反馈。
//
// 前置：同 T11 viewer e2e——embedded dbmaster server（DBMASTER_SERVER_BIN
// 或 exe 同目录）+ WSL mongosh + DBMASTER_MONGO_PASSWORD；缺前置以可 grep
// 的 MONGO_E2E_SKIP 整组跳过（无假绿纪律）。
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/dialogs/mongo_gridfs_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/services/audit_log_service.dart';
import 'package:dbmaster/services/readonly_guard.dart';

import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

/// 冲突路径固定 files_id（24-hex；e2e 经 gridFsFilesIdFactory 接缝注入）。
const String _kConflictOid = '65f1a2b3c4d5e6f7081921bb';

/// mongosh 预置实验 bucket（自建自删）：.files/.chunks 空集合对（dialog
/// bucket 探测可见）+ GridFS 规范 (files_id,n) 唯一索引；可选预置冲突
/// chunk（[conflictOid] 非空时）——上传批 1 的 n=0 即与其撞 E11000。
/// 口令经 stdin 传入（不进 argv/代码/日志）；脚本 ASCII-only（T11 夹具
/// 同款平台约束注记）。
Future<bool> _seedBucket(String database, {String? conflictOid}) async {
  final script =
      """
db.auth('admin', '${MongoDBTestConfig.password}');
db = db.getSiblingDB('$database');
db.createCollection('media.files');
db.createCollection('media.chunks');
db.getCollection('media.chunks').createIndex({files_id: 1, n: 1}, {unique: true});
${conflictOid == null ? '' : "db.getCollection('media.chunks').insertOne({files_id: ObjectId('$conflictOid'), n: 0, data: BinData(0, 'AA==')});"}
""";
  final uri =
      'mongodb://${MongoDBTestConfig.host}:${MongoDBTestConfig.port}'
      '/${MongoDBTestConfig.authDatabase}?authSource=${MongoDBTestConfig.authDatabase}';
  final proc = await Process.start('wsl', [
    '-d',
    'Ubuntu-24.04',
    '--',
    'mongosh',
    uri,
    '--quiet',
  ]);
  proc.stdin.add(utf8.encode(script));
  await proc.stdin.flush();
  await proc.stdin.close();
  const decoder = Utf8Decoder(allowMalformed: true);
  final out = await proc.stdout.transform(decoder).join();
  final err = await proc.stderr.transform(decoder).join();
  final code = await proc.exitCode;
  final failedMarker = RegExp('MongoServerError|BSONError|Uncaught');
  final ok =
      code == 0 && !failedMarker.hasMatch(out) && !failedMarker.hasMatch(err);
  if (!ok) {
    // ignore: avoid_print
    print('MONGO_E2E_FIXTURE: exit=$code out=$out err=$err');
  }
  return ok;
}

void main() {
  bool mongoE2EGatewayReady = false;
  setUpAll(() async {
    mongoE2EGatewayReady = await ensureEmbeddedServerForMongoE2E();
    if (mongoE2EGatewayReady && !MongoDBTestConfig.available) {
      // ignore: avoid_print
      print(
        'MONGO_E2E_SKIP: DBMASTER_MONGO_* 未通过 --dart-define 提供'
        '（凭据不入库，缺参即跳过）',
      );
      mongoE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;
  late String testDb;
  MongoDBAdapter? adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDb = MongoDBTestConfig.generateTestDatabaseName();
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t21-e2e-mongo',
      type: DatabaseType.mongodb,
      name: 'DBT T21 E2E MongoDB',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );
    provider.connection.addSavedServerForTest(server);
    await AuditLogService().initialize();
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
    adapter?.gridFsFilesIdFactory = null;
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

  Future<bool> seed(
    WidgetTester tester,
    String db, {
    String? conflictOid,
  }) async =>
      await tester.runAsync(() => _seedBucket(db, conflictOid: conflictOid)) ==
      true;

  /// 真实时钟轮询（[poll] 返回 true 停止；T10/T11 e2e 同款）。
  Future<bool> pollReal(
    WidgetTester tester,
    Future<bool> Function() poll, {
    int timeoutMs = 30000,
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

  /// UI 条件轮询（真实时钟下完成加载，T11 e2e 同款）。
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

  /// 直构 dialog（T11 DOWNLOAD 同款：loader 全生产闭包，仅注入
  /// uploadFilePicker——FilePicker 8.x Windows 原生对话框测试不可 mock）。
  Widget dialogHome(
    AppProvider provider, {
    required String filename,
    required List<int> bytes,
  }) => Builder(
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
              uploadFilePicker: () async => (filename: filename, bytes: bytes),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );

  Future<void> pumpDialog(WidgetTester tester, Widget home) async {
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
  }

  /// 在已打开的 GridFS dialog 里选库（T11 e2e 同款重试轮询）。
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
      await tester.tapAt(const Offset(400, 20));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
    }
    fail('库下拉重试 10 次未出现 $testDb');
  }

  testWidgets('DBT-T21-UPLOAD-BASIC：文本+二进制上传 → 读回逐字节一致 + 元数据 + 行数对账', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);
    expect(await seed(tester, testDb), isTrue, reason: 'mongosh 预置 bucket 失败');

    final textBytes = utf8.encode('DBT-T21 GridFS upload e2e text fixture');
    final binBytes = Uint8List.fromList([
      for (var i = 0; i < 1024; i++) (i * 7 + 13) & 0xFF,
    ]);

    final results = (await tester.runAsync(() async {
      final oidText = await adapter!.uploadGridFsFile(
        'media',
        database: testDb,
        filename: 't21-text.txt',
        bytes: textBytes,
      );
      final oidBin = await adapter!.uploadGridFsFile(
        'media',
        database: testDb,
        filename: 't21-bin.bin',
        bytes: binBytes,
      );
      return (oidText: oidText, oidBin: oidBin);
    }))!;
    expect(results.oidText.length, 24);
    expect(results.oidBin.length, 24);

    final readback = (await tester.runAsync(() async {
      final text = await adapter!.readGridFsFileBytes(
        'media',
        results.oidText,
        database: testDb,
      );
      final bin = await adapter!.readGridFsFileBytes(
        'media',
        results.oidBin,
        database: testDb,
      );
      final meta = await adapter!.getGridFsFileMetadata(
        'media',
        results.oidText,
        database: testDb,
      );
      final files = await adapter!.listGridFsFiles('media', database: testDb);
      return (text: text, bin: bin, meta: meta, files: files);
    }))!;

    // 逐字节一致（T11 只读面读回 == 上传源）。
    expect(readback.text, textBytes, reason: '文本读回逐字节一致');
    expect(readback.bin, binBytes, reason: '二进制读回逐字节一致');
    // fs.files 元数据（length/chunkSize/filename）。
    final meta = readback.meta;
    expect(meta, isNotNull);
    expect(meta!['length'], textBytes.length);
    expect(meta['chunkSize'], MongoDBAdapter.kGridFsUploadChunkSize);
    expect(meta['filename'], 't21-text.txt');
    // fs.files 行数对账（本测试上传 2 个 → 恰 2 行；上传前 bucket 空集合）。
    expect(readback.files.length, 2);
  });

  testWidgets(
    'DBT-T21-UPLOAD-MULTICHUNK：>100 chunks（26 MB）分批断言 + 多 chunk（3 片）读回逐字节',
    (tester) async {
      if (!mongoE2EGatewayReady) return;
      adapter = await connectReal(tester);
      expect(
        await seed(tester, testDb),
        isTrue,
        reason: 'mongosh 预置 bucket 失败',
      );

      // ⚠ 26 MB 文件不做全量 readGridFsFileBytes 读回——**既有 server 缺陷**
      // （非本任务面，登记上报）：gateway 游标展平取 coll 用
      // `ns.rsplit('.').next()`（dbmaster-server crates/automation/src/
      // mongo.rs:429），对带点的 GridFS 集合名（`<db>.media.chunks`）误取
      // `chunks`——多批次结果（firstBatch 超 16MB 触发 getMore）报
      // Unauthorized namespace 不匹配。T11 e2e 夹具 ≤3 chunks（单批，
      // cursor id=0）从未触发。分批断言经 chunks 计数 + fs.files 元数据
      // length（小 find，零 getMore）覆盖；多 chunk n 序拼接读回用 3 片
      // （766 KB，单批内）文件逐字节覆盖。
      // 26,214,400 B（25 MiB ≈ 26.2 十进制 MB，「~26 MB 以内」）/ 261,120
      // = 100.39 → 恰 101 chunks（26 MiB 会得 105，超出行文口径）。
      const total = 26214400;
      final bigSource = Uint8List(total);
      for (var i = 0; i < total; i++) {
        bigSource[i] = (i * 31 + 7) & 0xFF;
      }
      // 3 chunks：2×255KiB + 1 尾片。
      final triSource = Uint8List(
        2 * MongoDBAdapter.kGridFsUploadChunkSize + 77,
      );
      for (var i = 0; i < triSource.length; i++) {
        triSource[i] = (i * 13 + 3) & 0xFF;
      }

      final outcome = (await tester.runAsync(() async {
        // countDocuments 无 database 参（默认路由 _currentDatabase=认证库）
        // ——先 useDatabase 对齐（record-only；显式 database 参调用不受影响）。
        await adapter!.useDatabase(testDb);
        // ① 26 MB（26,214,400 / 261,120 = 100.39 → 101 chunks；字节预算
        // ≈5 满 chunk/批 → 21 批——单请求 34MB 会被 axum 2MB 上限 413，
        // 本段成功即分批正确性实证）。
        final bigOid = await adapter!.uploadGridFsFile(
          'media',
          database: testDb,
          filename: 't21-big.bin',
          bytes: bigSource,
        );
        final bigChunks = await adapter!.countDocuments(
          'media.chunks',
          filter: {
            'files_id': {r'$oid': bigOid},
          },
        );
        final bigMeta = await adapter!.getGridFsFileMetadata(
          'media',
          bigOid,
          database: testDb,
        );
        // ② 3 chunks 读回（单批内，避开上记 server getMore 缺陷）。
        final triOid = await adapter!.uploadGridFsFile(
          'media',
          database: testDb,
          filename: 't21-tri.bin',
          bytes: triSource,
        );
        final triReadback = await adapter!.readGridFsFileBytes(
          'media',
          triOid,
          database: testDb,
        );
        final triChunks = await adapter!.countDocuments(
          'media.chunks',
          filter: {
            'files_id': {r'$oid': triOid},
          },
        );
        return (
          bigChunks: bigChunks,
          bigLength: bigMeta?['length'],
          triReadback: triReadback,
          triChunks: triChunks,
        );
      }))!;

      expect(outcome.bigChunks, 101, reason: '26MB 分片计数（>100 chunks）');
      expect(outcome.bigLength, total, reason: 'fs.files length == 源字节数');
      expect(outcome.triChunks, 3, reason: '3 片文件分片计数');
      expect(outcome.triReadback, triSource, reason: '多 chunk n 序拼接读回逐字节一致');
    },
  );

  testWidgets('DBT-T21-UPLOAD-DIALOG：面板预览确认 → 上传 → 成功反馈 + 列表刷新 + 审计', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);
    expect(await seed(tester, testDb), isTrue, reason: 'mongosh 预置 bucket 失败');

    final bytes = utf8.encode('DBT-T21 dialog-driven upload');
    await pumpDialog(
      tester,
      dialogHome(provider, filename: 't21-dialog.txt', bytes: bytes),
    );
    await selectTestDb(tester);

    // 上传入口可用（bucket 已随库自动选中）。
    final uploadBtn = tester.widget<IconButton>(
      find.byKey(const Key('gridfs_upload_btn')),
    );
    expect(uploadBtn.onPressed, isNotNull, reason: '可写连接 + bucket 选中 → 上传可用');

    await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
    await tester.pumpAndSettle();
    // 预览确认：标题 + 五要素。
    expect(find.text('Upload to GridFS'), findsOneWidget);
    expect(find.textContaining('t21-dialog.txt'), findsOneWidget);
    expect(find.textContaining('1 chunks'), findsOneWidget);
    expect(find.textContaining('$testDb/media'), findsOneWidget);

    // 确认 → 生产默认 uploader（AppProvider → adapter）真实上传。
    await tester.runAsync(() async {
      await tester.tap(find.text('Upload').last);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final uploaded = await waitUntil(
      tester,
      () => tester.any(find.text('Uploaded t21-dialog.txt')),
      timeoutMs: 30000,
    );
    expect(uploaded, isTrue, reason: '成功反馈应出现');

    // 列表刷新：新文件行可见（uploadDate 降序居首）。
    final listed = await waitUntil(
      tester,
      () => tester.any(find.text('t21-dialog.txt')),
      timeoutMs: 15000,
    );
    expect(listed, isTrue, reason: '刷新后新文件行可见');

    // 审计：recordQuery isWriteQuery:true + 摘要式 SQL（不含二进制）。
    final audited = await pollReal(
      tester,
      () async => AuditLogService().getRecentEntries().any(
        (e) =>
            e.databaseName == testDb &&
            e.isWriteQuery &&
            e.success &&
            e.sql.contains('gridfs upload media/t21-dialog.txt 1 chunks'),
      ),
    );
    expect(audited, isTrue, reason: '上传审计应落账（isWriteQuery:true）');

    await tester.tap(find.text('Close'));
    await tester.pump();
  });

  testWidgets(
    'DBT-T21-UPLOAD-CONFLICT：冲突 files_id → E11000 回滚 + files 零行 + 错误反馈',
    (tester) async {
      if (!mongoE2EGatewayReady) return;
      adapter = await connectReal(tester);
      expect(
        await seed(tester, testDb, conflictOid: _kConflictOid),
        isTrue,
        reason: 'mongosh 预置冲突 chunk 失败',
      );
      // files_id 固定为预置冲突值 → 批 1 的 n=0 撞 (files_id,n) 唯一索引。
      adapter!.gridFsFilesIdFactory = () => _kConflictOid;

      final bytes = utf8.encode('DBT-T21 conflict upload');
      await pumpDialog(
        tester,
        dialogHome(provider, filename: 't21-conflict.txt', bytes: bytes),
      );
      await selectTestDb(tester);

      await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Upload').last);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      final failed = await waitUntil(
        tester,
        () => tester.any(
          find.textContaining('Failed to upload t21-conflict.txt'),
        ),
        timeoutMs: 30000,
      );
      expect(failed, isTrue, reason: '失败反馈应出现');
      // 回滚注记（孤儿 chunks 风险登记边界的 UI 载体）。
      expect(find.textContaining('rolled back'), findsOneWidget);

      // 回滚事实：本 files_id 的 chunks 全部清零（含预置冲突 chunk——同
      // files_id 归属同一逻辑上传，删除为正确清理语义）。
      final outcome = (await tester.runAsync(() async {
        final chunkCount = await adapter!.countDocuments(
          'media.chunks',
          filter: {
            'files_id': {r'$oid': _kConflictOid},
          },
        );
        final files = await adapter!.listGridFsFiles('media', database: testDb);
        return (chunkCount: chunkCount, files: files);
      }))!;
      expect(outcome.chunkCount, 0, reason: '回滚后 chunks 清零');
      expect(outcome.files, isEmpty, reason: 'fs.files 零行（files 恒不写）');

      await tester.tap(find.text('Close'));
      await tester.pump();
    },
  );

  testWidgets('DBT-T21-UPLOAD-GUARD：readonly 拦截 + 入口禁用；取消路径零残留', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);
    expect(await seed(tester, testDb), isTrue, reason: 'mongosh 预置 bucket 失败');

    // ① readonly 连接：adapter guardReadOnly 抛（写面首行守卫）。
    final readOnlyServer = DbServer(
      id: 'dbt-t21-e2e-mongo-ro',
      type: DatabaseType.mongodb,
      name: 'DBT T21 E2E MongoDB RO',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
      readOnly: true,
    );
    provider.connection.addSavedServerForTest(readOnlyServer);
    final guardThrown = (await tester.runAsync(() async {
      final connected = await provider.connection.connectToServer(
        readOnlyServer,
      );
      if (!connected) return false;
      final roAdapter = provider.dbService.getAdapter(readOnlyServer.id);
      if (roAdapter is! MongoDBAdapter) return false;
      try {
        await roAdapter.uploadGridFsFile(
          'media',
          database: testDb,
          filename: 'ro.bin',
          bytes: [1],
        );
        return false; // 未拦截 = 失败
      } on ReadOnlyBlockedException {
        return true;
      }
    }))!;
    expect(guardThrown, isTrue, reason: 'readonly 连接应被 guardReadOnly 拦截');

    // ② dialog：readonly 连接（RO adapter 在连）入口禁用——bucket 经 stub
    // 恒可见，禁用唯一归因 = readonly（排除「无 bucket」歧义）。
    final roDialogHome = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => MongoGridFsDialog(
                connectionId: readOnlyServer.id,
                loadDatabases: (cid) =>
                    provider.dbService.getDatabases(connectionId: cid),
                loadBuckets: (cid, db) async => ['media'],
                listFiles: (cid, db, bucket) async => const [],
                loadMetadata: (cid, db, bucket, oid) async => null,
                readFileBytes: (cid, db, bucket, oid) async => const [],
                uploadFilePicker: () async =>
                    (filename: 'ro-dialog.bin', bytes: [1, 2, 3]),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await pumpDialog(tester, roDialogHome);
    await selectTestDb(tester);
    final roBtn = tester.widget<IconButton>(
      find.byKey(const Key('gridfs_upload_btn')),
    );
    expect(roBtn.onPressed, isNull, reason: 'readonly 连接 → 上传入口禁用');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // ③ 切回可写连接 → 取消路径（确认门取消）= 零 chunks 零审计零反馈。
    final reconnected = await tester.runAsync(
      () => provider.connection.connectToServer(server),
    );
    expect(reconnected, isTrue);
    await pumpDialog(
      tester,
      dialogHome(
        provider,
        filename: 't21-cancel.txt',
        bytes: utf8.encode('cancel me'),
      ),
    );
    await selectTestDb(tester);
    await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Upload to GridFS'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing, reason: '取消零反馈');
    final residue = (await tester.runAsync(() async {
      await adapter!.useDatabase(testDb);
      final chunks = await adapter!.countDocuments('media.chunks');
      final files = await adapter!.listGridFsFiles('media', database: testDb);
      final audited = AuditLogService().getRecentEntries().any(
        (e) => e.sql.contains('t21-cancel.txt'),
      );
      return (chunks: chunks, files: files, audited: audited);
    }))!;
    expect(residue.chunks, 0, reason: '取消零 chunks');
    expect(residue.files, isEmpty, reason: '取消零 files');
    expect(residue.audited, isFalse, reason: '取消零审计');
  });
}
