// T11（DBT）· MongoDB GridFS 查看器 dialog widget 测试：
// 列表渲染（自动选首个 bucket + 五列头）/ bucket 切换 / 空态（无 bucket 与
// 空 bucket 两形态）/ 失败态 / 元数据详情（字段 + metadata JSON）/ 元数据
// 加载失败 / **下载取消点零副作用**（AI-SEX-105 先例）/ 下载成功（逐字节
// 落盘 + 成功 snackbar + gridfs_file 审计）/ 下载失败（失败 snackbar、
// 零写盘零审计）/ 删除/重命名入口零出现（T21 验收⑤ reviewer 核查项）。
//
// T21（DBT）追加 · 上传写路径：调用参断言（bucket/filename/bytes 经注入
// uploader）/ 预览确认五要素 + 同名新版本注记 / 确认门与选择器两取消点
// 零副作用 / 50MB 护栏 / 失败回滚注记 + 失败审计 / readonly（含 provider
// 缺席 fail-closed）入口禁用 / 默认审计器先 initialize 再 recordQuery
//（R2 修复 2：上传为首审计动作不覆写既有审计历史）。
//
// 写盘断言机制（AI-SEX-104 先例）：dart:io IOOverrides.createFile 接缝把
// File.writeAsBytes 截获进进程内捕获（Windows flutter_tester fake async 内
// 真实文件 IO future 永不完成——平台事实见 workbench_session_export_test
// 文件头注）；zone 语义：async 函数整链留在启动它的 zone，tap 在 runZoned
// 内派发即整链捕获。
//
// 真库全链路（mongosh 夹具预置 GridFS 文件 → 面板列真数据 → 元数据详情 →
// 下载逐字节一致 + 审计）在 integration_test/mongodb_gridfs_viewer_e2e_test
// .dart；上传真库链路（多类型上传 + 读回逐字节比对 + >100 chunks 分批 +
// 冲突回滚）在 integration_test/mongodb_gridfs_upload_e2e_test.dart（均连
// WSL）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/dialogs/mongo_gridfs_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';

// ── fixture（wire 形态：$oid/$date 扩展 JSON 子文档，与网关出向一致）──

Map<String, dynamic> _filesDoc({
  required String oid,
  required String filename,
  required int length,
  int chunkSize = 261120,
  String? md5,
  String? contentType,
  Map<String, dynamic>? metadata,
}) => {
  '_id': {'\$oid': oid},
  'filename': filename,
  'length': length,
  'chunkSize': chunkSize,
  'uploadDate': {'\$date': '2026-10-12T08:30:00.000Z'},
  'md5': ?md5,
  'contentType': ?contentType,
  'metadata': ?metadata,
};

const String _oidA = '65f1a2b3c4d5e6f708190001';
const String _oidB = '65f1a2b3c4d5e6f708190002';

/// 进程内文件写入捕获（AI-SEX-104 同机制，writeAsBytes 形态）。
class _MemoryFiles {
  static final Map<String, List<int>> written = <String, List<int>>{};

  static void reset() => written.clear();

  static List<int>? bytesOf(String path) => written[path];
}

/// 注入集合（测试断言面：各接缝的调用记录 + 可编程返回）。
class _Seams {
  final listCalls = <String>[]; // 'db/bucket'
  final metadataCalls = <String>[]; // 'db/bucket/oid'
  final fetchCalls = <String>[]; // 'db/bucket/oid'
  final pickerCalls = <String>[];
  final auditCalls = <String>[];
  final uploadCalls = <String>[]; // 'cid/db/bucket/filename'（bytes 另册）
  final uploadBytes = <List<int>>[];
  final uploadPickCalls = <int>[]; // 选择器调用计数
  final uploadAuditCalls = <Map<String, Object?>>[] = [];
  Map<String, List<int>> bytesByOid = {
    _oidA: [1, 2, 3, 4],
    _oidB: [9],
  };
  String? pickerResult;
  Object? fetchError;
  ({String filename, List<int> bytes})? uploadPickResult;
  Object? uploadError;
}

/// IOOverrides 注入的 File 替身：只具体实现生产链路触达的 writeAsBytes，
/// 其余成员 noSuchMethod fail-loud（防静默走错路径）。
class _CapturedFile implements File {
  _CapturedFile(this.path);

  @override
  final String path;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    _MemoryFiles.written[path] = bytes;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 选库（首个 DropdownButton → 菜单条目；hint 文本命中区不稳，点按钮
/// 本体）——两 group 共用（T11 列表 / T21 上传）。
Future<void> selectDatabase(WidgetTester tester, String db) async {
  await tester.tap(find.byType(DropdownButton<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(db).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _MemoryFiles.reset();
  });

  group('MongoGridFsFileEntry 模型（wire 映射 + bucket 配对识别）', () {
    test('fromFilesDoc：\$oid/\$date 解包 + 数值容错 + 缺省容错', () {
      final entry = MongoGridFsFileEntry.fromFilesDoc(
        _filesDoc(
          oid: _oidA,
          filename: 'report.bin',
          length: 2048,
          md5: 'd41d8cd98f00b204e9800998ecf8427e',
          contentType: 'application/octet-stream',
          metadata: {'source': 'dbt-t11'},
        ),
      );
      expect(entry.objectIdHex, _oidA);
      expect(entry.filename, 'report.bin');
      expect(entry.length, 2048);
      expect(entry.chunkSize, 261120);
      expect(entry.uploadDate, isNotNull);
      expect(entry.uploadDate!.toUtc().year, 2026);
      expect(entry.md5, 'd41d8cd98f00b204e9800998ecf8427e');
      expect(entry.contentType, 'application/octet-stream');

      // 缺省容错：无 _id/数值字段非 num 归零、日期坏值归 null。
      final bare = MongoGridFsFileEntry.fromFilesDoc({
        'filename': null,
        'length': 'huge',
        'uploadDate': {'\$date': 'not-a-date'},
      });
      expect(bare.objectIdHex, '');
      expect(bare.filename, '');
      expect(bare.length, 0);
      expect(bare.uploadDate, isNull);
    });

    test('bucketNamesFrom：.files+.chunks 成对识别、去重排序、孤儿排除', () {
      final buckets = MongoGridFsFileEntry.bucketNamesFrom([
        'users',
        'media.files',
        'media.chunks',
        'fs.files',
        'fs.chunks',
        'orphan.files', // 无配对 chunks → 不识别
      ]);
      expect(buckets, ['fs', 'media']);
      expect(MongoGridFsFileEntry.bucketNamesFrom(['users']), isEmpty);
    });

    test('formatBytes：B/KB/MB 可读化', () {
      expect(MongoGridFsFileEntry.formatBytes(512), '512 B');
      expect(MongoGridFsFileEntry.formatBytes(2048), '2.00 KB');
      expect(MongoGridFsFileEntry.formatBytes(5 * 1024 * 1024), '5.00 MB');
    });
  });

  Future<void> pumpDialog(
    WidgetTester tester,
    _Seams seams, {
    List<String> databases = const ['db1'],
    List<String> Function(String db)? bucketsOf,
    final List<Map<String, dynamic>> Function(String db, String bucket)?
    filesOf,
    Future<Map<String, dynamic>?> Function(
      String db,
      String bucket,
      String oid,
    )?
    metadataOf,
    AppProvider? provider,
    // true = 不注入审计器，走生产默认 _defaultUploadAudit（R2 修复 2 回归
    // 面：上传为首审计动作时先 initialize 再 recordQuery，不覆写历史）。
    bool useDefaultUploadAudit = false,
  }) async {
    final home = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => MongoGridFsDialog(
                connectionId: 'mg_conn',
                loadDatabases: (_) async => databases,
                loadBuckets: (_, db) async => bucketsOf?.call(db) ?? ['media'],
                listFiles: (_, db, bucket) async {
                  seams.listCalls.add('$db/$bucket');
                  if (filesOf == null) {
                    return const [];
                  }
                  return MongoGridFsFileEntry.listFromFilesDocs(
                    filesOf(db, bucket),
                  );
                },
                loadMetadata: (_, db, bucket, oid) async {
                  seams.metadataCalls.add('$db/$bucket/$oid');
                  return await metadataOf?.call(db, bucket, oid) ??
                      _filesDoc(oid: oid, filename: 'f-$oid', length: 10);
                },
                readFileBytes: (_, db, bucket, oid) async {
                  seams.fetchCalls.add('$db/$bucket/$oid');
                  if (seams.fetchError != null) throw seams.fetchError!;
                  return seams.bytesByOid[oid] ?? const <int>[];
                },
                savePathPicker: (suggested) async {
                  seams.pickerCalls.add(suggested);
                  return seams.pickerResult;
                },
                exportAuditLogger: ({required String sourceSql}) async {
                  seams.auditCalls.add(sourceSql);
                },
                uploadFile: (cid, db, bucket, filename, bytes) async {
                  seams.uploadCalls.add('$cid/$db/$bucket/$filename');
                  seams.uploadBytes.add(bytes);
                  if (seams.uploadError != null) throw seams.uploadError!;
                  return '65f1a2b3c4d5e6f7081900ff';
                },
                uploadFilePicker: () async {
                  seams.uploadPickCalls.add(1);
                  return seams.uploadPickResult;
                },
                uploadAuditLogger: useDefaultUploadAudit
                    ? null
                    : ({
                      required bool success,
                      required int chunkCount,
                      required String summary,
                      required Duration elapsed,
                      String? errorMessage,
                    }) async {
                      seams.uploadAuditCalls.add({
                        'success': success,
                        'chunkCount': chunkCount,
                        'summary': summary,
                        'elapsed': elapsed,
                        'errorMessage': errorMessage,
                      });
                    },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    final app = MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: home,
    );
    await tester.pumpWidget(
      provider == null
          ? app
          : ChangeNotifierProvider<AppProvider>.value(
              value: provider,
              child: app,
            ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// 带 provider 的种子（上传面需要：readonly 事实 + 默认 uploader 解析；
  /// T20 redis_backup_dialog_test 同款）。
  AppProvider seededProvider({bool readOnly = false}) {
    final provider = AppProvider();
    provider.connection.addSavedServerForTest(
      DbServer(
        id: 'mg_conn',
        name: 'MG-Local',
        type: DatabaseType.mongodb,
        host: '127.0.0.1',
        port: 27017,
        readOnly: readOnly,
      ),
    );
    return provider;
  }

  group('MongoGridFsDialog', () {
    testWidgets('列表渲染：自动选首个 bucket + 五列头 + 数据行 + 无上传/删除入口', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        bucketsOf: (_) => ['media', 'photos'],
        filesOf: (_, _) => [
          _filesDoc(oid: _oidA, filename: 'report.bin', length: 2048),
          _filesDoc(oid: _oidB, filename: 'photo.jpg', length: 512000),
        ],
      );
      await selectDatabase(tester, 'db1');

      // 标题 + 列头（含 Download 动作列）。
      expect(find.text('GridFS Files'), findsOneWidget);
      expect(
        find.text('Download'),
        findsAtLeastNWidgets(3),
        reason: '列头 + 两行动作',
      );
      expect(find.text('Object ID'), findsOneWidget);
      expect(find.text('File Name'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Upload Date'), findsOneWidget);
      expect(find.text('Chunk Size'), findsOneWidget);
      // 数据行（objectId/filename/size；日期本地时区渲染取日期前缀）。
      expect(find.text(_oidA), findsOneWidget);
      expect(find.text('report.bin'), findsOneWidget);
      expect(find.text('2.00 KB'), findsOneWidget);
      expect(find.text('500.00 KB'), findsOneWidget);
      // 日期本地时区渲染（跨时区 CI 稳健：UTC 日或 ±1 日均可命中）。
      expect(find.textContaining(RegExp('2026-10-1[12]')), findsNWidgets(2));
      // 自动选首个 bucket：'media'（列表已加载，非空态）。
      expect(seams.listCalls, ['db1/media']);
      expect(find.text('media'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      // 验收⑤（T21 后 reviewer 核查项）：删除/重命名入口零出现；上传入口
      // 为 T21 交付（provider 缺席直泵场景 = readonly fail-closed 禁用位）。
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Rename'), findsNothing);
      expect(find.byIcon(LucideIcons.trash2), findsNothing);
      final uploadBtn = tester.widget<IconButton>(
        find.byKey(const Key('gridfs_upload_btn')),
      );
      expect(
        uploadBtn.onPressed,
        isNull,
        reason: 'provider 缺席（直泵）→ readonly fail-closed 禁用',
      );
      expect(
        find.byType(IconButton),
        findsNWidgets(2),
        reason: 'Refresh + Upload 两个图标钮',
      );
    });

    testWidgets('bucket 切换：下拉换 photos → 重新列文件', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        bucketsOf: (_) => ['media', 'photos'],
        filesOf: (_, bucket) => [
          _filesDoc(oid: _oidA, filename: 'in-$bucket.bin', length: 10),
        ],
      );
      await selectDatabase(tester, 'db1');
      expect(seams.listCalls, ['db1/media']);

      await tester.tap(find.byType(DropdownButton<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('photos').last);
      await tester.pumpAndSettle();

      expect(seams.listCalls, ['db1/media', 'db1/photos']);
      expect(find.text('in-photos.bin'), findsOneWidget);
      expect(find.text('in-media.bin'), findsNothing);
    });

    testWidgets('空态：库无 GridFS bucket（无 .files/.chunks 配对）', (tester) async {
      final seams = _Seams();
      await pumpDialog(tester, seams, bucketsOf: (_) => []);
      await selectDatabase(tester, 'db1');

      expect(find.text('No files'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets('空态：bucket 存在但无文件', (tester) async {
      final seams = _Seams();
      await pumpDialog(tester, seams, filesOf: (_, _) => []);
      await selectDatabase(tester, 'db1');

      expect(find.text('No files'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets('失败态：listFiles 抛错 → 错误态展示不崩溃', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        filesOf: (_, _) => throw StateError('gateway unreachable'),
      );
      await selectDatabase(tester, 'db1');

      expect(find.text('GridFS Files'), findsOneWidget);
      expect(find.textContaining('gateway unreachable'), findsOneWidget);
      expect(find.text('No files'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('元数据详情：行点击 → 字段行 + 用户 metadata JSON', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        filesOf: (_, _) => [
          _filesDoc(oid: _oidA, filename: 'report.bin', length: 2048),
        ],
        metadataOf: (_, _, oid) async => _filesDoc(
          oid: oid,
          filename: 'report.bin',
          length: 2048,
          md5: 'd41d8cd98f00b204e9800998ecf8427e',
          contentType: 'application/octet-stream',
          metadata: {'source': 'dbt-t11-fixture'},
        ),
      );
      await selectDatabase(tester, 'db1');

      await tester.tap(find.text('report.bin'));
      await tester.pumpAndSettle();

      expect(seams.metadataCalls, ['db1/media/$_oidA']);
      expect(find.text('Metadata'), findsOneWidget);
      expect(find.textContaining(_oidA), findsWidgets);
      expect(find.text('MD5: '), findsOneWidget);
      expect(
        find.textContaining('d41d8cd98f00b204e9800998ecf8427e'),
        findsOneWidget,
      );
      expect(find.text('Content-Type: '), findsOneWidget);
      expect(find.textContaining('application/octet-stream'), findsOneWidget);
      // 用户 metadata 子文档 JSON。
      expect(find.textContaining('dbt-t11-fixture'), findsOneWidget);
    });

    testWidgets('元数据加载失败：loadFailed 错误态', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        filesOf: (_, _) => [
          _filesDoc(oid: _oidA, filename: 'a.bin', length: 1),
        ],
        // async 抛错（生产 adapter 面为 async 方法——同步 throw 不会发生）。
        metadataOf: (_, _, _) async => throw StateError('boom'),
      );
      await selectDatabase(tester, 'db1');
      await tester.tap(find.text('a.bin'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Load failed'), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
    });

    testWidgets('下载取消（选择器取消）= 零副作用：零取数/零写盘/零审计/零反馈', (tester) async {
      final seams = _Seams();
      seams.pickerResult = null;
      await pumpDialog(
        tester,
        seams,
        filesOf: (_, _) => [
          _filesDoc(oid: _oidA, filename: 'report.bin', length: 2048),
        ],
      );
      await selectDatabase(tester, 'db1');

      await tester.tap(find.byKey(Key('gridfs_download_$_oidA')));
      await tester.pumpAndSettle();

      expect(seams.pickerCalls, ['report.bin'], reason: '建议名 = GridFS 原名');
      expect(seams.fetchCalls, isEmpty, reason: '取消后不得取字节');
      expect(_MemoryFiles.written, isEmpty, reason: '零写盘');
      expect(seams.auditCalls, isEmpty, reason: '零审计');
      expect(find.byType(SnackBar), findsNothing, reason: '取消零反馈');
    });

    testWidgets('下载成功：逐字节落盘 + 成功 snackbar + gridfs_file 审计', (tester) async {
      final seams = _Seams();
      seams.pickerResult = '${Directory.systemTemp.path}/gridfs_out.bin';
      await pumpDialog(
        tester,
        seams,
        filesOf: (_, _) => [
          _filesDoc(oid: _oidA, filename: 'report.bin', length: 4),
        ],
      );
      await selectDatabase(tester, 'db1');

      // 写盘捕获（zone 语义：tap 在 runZoned 内派发 → _download 整链捕获）。
      await IOOverrides.runZoned<Future<void>>(() async {
        await tester.tap(find.byKey(Key('gridfs_download_$_oidA')));
        await tester.pump();
      }, createFile: (path) => _CapturedFile(path));
      await tester.pumpAndSettle();

      expect(seams.fetchCalls, ['db1/media/$_oidA']);
      // 逐字节一致（与预置 [1,2,3,4] 比对——e2e 再对真库内容复核）。
      expect(_MemoryFiles.bytesOf(seams.pickerResult!), [1, 2, 3, 4]);
      expect(find.text('Download complete'), findsOneWidget);
      // 审计：format=gridfs_file 口径（sourceSql 定位串含库/bucket/oid）。
      expect(seams.auditCalls, hasLength(1));
      expect(seams.auditCalls.single, contains('db1/media/$_oidA'));
    });

    testWidgets('下载失败：取字节抛错 → 失败 snackbar、零写盘零审计', (tester) async {
      final seams = _Seams();
      seams.pickerResult = '${Directory.systemTemp.path}/gridfs_out.bin';
      seams.fetchError = StateError('chunk corrupt');
      await pumpDialog(
        tester,
        seams,
        filesOf: (_, _) => [
          _filesDoc(oid: _oidA, filename: 'report.bin', length: 4),
        ],
      );
      await selectDatabase(tester, 'db1');

      await IOOverrides.runZoned<Future<void>>(() async {
        await tester.tap(find.byKey(Key('gridfs_download_$_oidA')));
        await tester.pump();
      }, createFile: (path) => _CapturedFile(path));
      await tester.pumpAndSettle();

      expect(seams.fetchCalls, ['db1/media/$_oidA']);
      expect(_MemoryFiles.written, isEmpty, reason: '失败不落半截文件');
      expect(seams.auditCalls, isEmpty, reason: '未发生导出不审计');
      expect(find.textContaining('Download failed'), findsOneWidget);
      expect(find.textContaining('chunk corrupt'), findsOneWidget);
      // 失败后可重试（下载锁已释放）。
      final button = tester.widget<TextButton>(
        find.byKey(Key('gridfs_download_$_oidA')),
      );
      expect(button.onPressed, isNotNull, reason: '失败后下载按钮复位');
    });
  });

  group('DBT-T21 · 上传（写路径）', () {
    /// 走到预览确认对话框（选库 → tap 上传钮 → picker 返回 → 预览弹出）。
    Future<void> pumpToPreview(
      WidgetTester tester,
      _Seams seams, {
      bool readOnly = false,
      String existingFilename = 'other.bin',
    }) async {
      await pumpDialog(
        tester,
        seams,
        provider: seededProvider(readOnly: readOnly),
        filesOf: (_, _) => [
          _filesDoc(oid: _oidA, filename: existingFilename, length: 10),
        ],
      );
      seams.uploadPickResult = (filename: 'hello.bin', bytes: [1, 2, 3, 4]);
      await selectDatabase(tester, 'db1');

      await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
      await tester.pumpAndSettle();

      // 预览确认（DestructiveConfirmDialog）弹出：标题 + 五要素。
      expect(find.text('Upload to GridFS'), findsOneWidget);
    }

    testWidgets(
      '成功全链路：调用参（cid/db/bucket/filename/bytes）+ 预览五要素 + 成功反馈 + 列表刷新 + 审计',
      (tester) async {
        final seams = _Seams();
        await pumpToPreview(tester, seams);

        // 影响说明五要素：文件名/大小/chunk 数/库/bucket（路径形态）。
        expect(find.textContaining('hello.bin'), findsOneWidget);
        expect(find.textContaining('Size: 4 B'), findsOneWidget);
        expect(find.textContaining('1 chunks'), findsOneWidget);
        expect(find.textContaining('db1/media'), findsOneWidget);
        // 不同名 → 无新版本注记。
        expect(find.textContaining('already exists'), findsNothing);

        await tester.tap(find.text('Upload').last); // LoadingButton 确认
        await tester.pumpAndSettle();

        // 调用参断言（验收①：bucket/filename/bytes——cid/db 全参）。
        expect(seams.uploadCalls, ['mg_conn/db1/media/hello.bin']);
        expect(seams.uploadBytes.single, [1, 2, 3, 4]);
        // 成功反馈 + 列表刷新（新文件行可见走 refresh 重列）。
        expect(find.text('Uploaded hello.bin'), findsOneWidget);
        expect(seams.listCalls, [
          'db1/media',
          'db1/media',
        ], reason: '成功后自动刷新一次');
        // 审计：success:true + 摘要式描述（bucket/filename/chunk 数，无二进制）。
        expect(seams.uploadAuditCalls, hasLength(1));
        final audit = seams.uploadAuditCalls.single;
        expect(audit['success'], isTrue);
        expect(audit['chunkCount'], 1);
        expect(audit['summary'], 'gridfs upload media/hello.bin 1 chunks');
      },
    );

    testWidgets('确认门取消 = 零调用零审计零反馈', (tester) async {
      final seams = _Seams();
      await pumpToPreview(tester, seams);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(seams.uploadCalls, isEmpty);
      expect(seams.uploadAuditCalls, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('GridFS Files'), findsOneWidget, reason: '回主面板');
    });

    testWidgets('选择器取消 = 零副作用（无预览零调用零反馈）', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        provider: seededProvider(),
        filesOf: (_, _) => [],
      );
      await selectDatabase(tester, 'db1');
      seams.uploadPickResult = null; // FilePicker 取消

      await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
      await tester.pumpAndSettle();

      expect(seams.uploadPickCalls, hasLength(1));
      expect(find.text('Upload to GridFS'), findsNothing, reason: '无预览');
      expect(seams.uploadCalls, isEmpty);
      expect(seams.uploadAuditCalls, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('50MB 护栏：超限拒绝（专键 + 大小值），零 uploader 零审计', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        provider: seededProvider(),
        filesOf: (_, _) => [],
      );
      await selectDatabase(tester, 'db1');
      seams.uploadPickResult = (
        filename: 'huge.bin',
        bytes: Uint8List(MongoDBAdapter.kGridFsUploadMaxBytes + 1),
      );

      await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
      await tester.pumpAndSettle();

      expect(find.textContaining('upload limit'), findsOneWidget);
      expect(find.textContaining('50.00 MB'), findsOneWidget);
      expect(find.text('Upload to GridFS'), findsNothing, reason: '不进预览');
      expect(seams.uploadCalls, isEmpty);
      expect(seams.uploadAuditCalls, isEmpty);
    });

    testWidgets('失败：回滚注记 + 失败审计 success:false', (tester) async {
      final seams = _Seams();
      seams.uploadError = MongoGridFsUploadException(
        cause: StateError('E11000 duplicate key'),
        rollbackComplete: false,
      );
      await pumpToPreview(tester, seams);

      await tester.tap(find.text('Upload').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to upload hello.bin'), findsOneWidget);
      expect(find.textContaining('E11000 duplicate key'), findsOneWidget);
      // 回滚注记（孤儿 chunks 风险登记边界的 UI 载体）。
      expect(find.textContaining('rolled back'), findsOneWidget);
      expect(seams.uploadAuditCalls, hasLength(1));
      final audit = seams.uploadAuditCalls.single;
      expect(audit['success'], isFalse);
      expect(audit['errorMessage'], contains('E11000'));
      expect(seams.listCalls, ['db1/media'], reason: '失败不刷新列表');
    });

    testWidgets('同名文件 → 预览注记「将新增一个版本」', (tester) async {
      final seams = _Seams();
      await pumpToPreview(tester, seams, existingFilename: 'hello.bin');

      expect(
        find.text(
          'A file with this name already exists; '
          'uploading adds a new version.',
        ),
        findsOneWidget,
      );
      // 取消收尾（零副作用）。
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(seams.uploadCalls, isEmpty);
    });

    testWidgets('readonly 连接 → 上传入口禁用（Refresh 不受影响）', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        provider: seededProvider(readOnly: true),
        filesOf: (_, _) => [],
      );
      await selectDatabase(tester, 'db1');

      final uploadBtn = tester.widget<IconButton>(
        find.byKey(const Key('gridfs_upload_btn')),
      );
      expect(uploadBtn.onPressed, isNull, reason: 'readonly → 上传禁用');
      final refreshBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, LucideIcons.refreshCw),
      );
      expect(refreshBtn.onPressed, isNotNull, reason: '只读面板可刷新');
      // 禁用态点按零副作用。
      await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
      await tester.pumpAndSettle();
      expect(seams.uploadPickCalls, isEmpty);
      expect(seams.uploadAuditCalls, isEmpty);
    });

    testWidgets(
      '默认审计器（R2 修复 2）：上传为首审计动作不丢既有历史（先 initialize 再 recordQuery）',
      (tester) async {
        // 预置既有审计历史 2 条（audit_logs key，AuditLogEntry.toJson 形）。
        // 缺陷形态：未 initialize 即 recordQuery → 内存仅新 1 条 → 防抖 2s
        // 持久化以单条覆写全部历史；修复后 = 既有 2 + 新 1 共 3 条。
        SharedPreferences.setMockInitialValues({
          'audit_logs': jsonEncode([
            {
              'id': 'audit_seed_1',
              'timestamp': '2026-10-12T08:00:00.000Z',
              'connectionId': 'conn_old',
              'sql': 'SELECT 1',
              'executionTimeMs': 5,
              'success': true,
              'isWriteQuery': false,
            },
            {
              'id': 'audit_seed_2',
              'timestamp': '2026-10-12T08:05:00.000Z',
              'connectionId': 'conn_old',
              'sql': 'UPDATE t SET x = 1',
              'executionTimeMs': 7,
              'success': true,
              'isWriteQuery': true,
            },
          ]),
        });

        final seams = _Seams();
        await pumpDialog(
          tester,
          seams,
          provider: seededProvider(),
          filesOf: (_, _) => [],
          useDefaultUploadAudit: true, // 走生产默认审计器（不注入）
        );
        await selectDatabase(tester, 'db1');
        seams.uploadPickResult = (filename: 'hello.bin', bytes: [1, 2, 3, 4]);
        await tester.tap(find.byKey(const Key('gridfs_upload_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upload').last);
        await tester.pumpAndSettle();
        expect(find.text('Uploaded hello.bin'), findsOneWidget,
            reason: '上传成功（审计走默认路径）');

        // 烧穿 2s 防抖持久化，读盘断言历史未丢。
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(); // 冲刷持久化 future 微任务
        final stored = jsonDecode(
          (await SharedPreferences.getInstance()).getString('audit_logs')!,
        ) as List<dynamic>;
        expect(
          stored,
          hasLength(3),
          reason: '既有 2 条历史必须保留（缺陷形态下只剩上传这 1 条）',
        );
        final ids = stored
            .map((e) => (e as Map<String, dynamic>)['id'])
            .toList();
        expect(ids, containsAll(['audit_seed_1', 'audit_seed_2']));
        expect(
          ids.last,
          startsWith('audit_'),
          reason: '新上传记录在案（gridfs 摘要式描述）',
        );
      },
    );
  });
}
