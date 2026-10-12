// T11（DBT）· MongoDB GridFS 查看器 dialog widget 测试：
// 列表渲染（自动选首个 bucket + 五列头）/ bucket 切换 / 空态（无 bucket 与
// 空 bucket 两形态）/ 失败态 / 元数据详情（字段 + metadata JSON）/ 元数据
// 加载失败 / **下载取消点零副作用**（AI-SEX-105 先例）/ 下载成功（逐字节
// 落盘 + 成功 snackbar + gridfs_file 审计）/ 下载失败（失败 snackbar、
// 零写盘零审计）/ UI 无上传/删除入口（任务书验收④ reviewer 核查项）。
//
// 写盘断言机制（AI-SEX-104 先例）：dart:io IOOverrides.createFile 接缝把
// File.writeAsBytes 截获进进程内捕获（Windows flutter_tester fake async 内
// 真实文件 IO future 永不完成——平台事实见 workbench_session_export_test
// 文件头注）；zone 语义：async 函数整链留在启动它的 zone，tap 在 runZoned
// 内派发即整链捕获。
//
// 真库全链路（mongosh 夹具预置 GridFS 文件 → 面板列真数据 → 元数据详情 →
// 下载逐字节一致 + 审计）在 integration_test/mongodb_gridfs_viewer_e2e_test
// .dart（连 WSL）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/dialogs/mongo_gridfs_dialog.dart';

// ── fixture（wire 形态：$oid/$date 扩展 JSON 子文档，与网关出向一致）──

Map<String, dynamic> _filesDoc({
  required String oid,
  required String filename,
  required int length,
  int chunkSize = 261120,
  String? md5,
  String? contentType,
  Map<String, dynamic>? metadata,
}) =>
    {
      '_id': {'\$oid': oid},
      'filename': filename,
      'length': length,
      'chunkSize': chunkSize,
      'uploadDate': {
        '\$date': '2026-10-12T08:30:00.000Z',
      },
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
  Map<String, List<int>> bytesByOid = {_oidA: [1, 2, 3, 4], _oidB: [9]};
  String? pickerResult;
  Object? fetchError;
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
        'uploadDate': {
          '\$date': 'not-a-date',
        },
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

  group('MongoGridFsDialog', () {
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
                  loadBuckets: (_, db) async =>
                      bucketsOf?.call(db) ?? ['media'],
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
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: home,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    /// 选库（首个 DropdownButton → 菜单条目；hint 文本命中区不稳，点按钮
    /// 本体）。
    Future<void> selectDatabase(WidgetTester tester, String db) async {
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(db).last);
      await tester.pumpAndSettle();
    }


    testWidgets('列表渲染：自动选首个 bucket + 五列头 + 数据行 + 无上传/删除入口', (
      tester,
    ) async {
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
      expect(find.text('Download'), findsAtLeastNWidgets(3), reason: '列头 + 两行动作');
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
      // 验收④（reviewer 核查项）：UI 无任何上传/删除入口。
      expect(find.text('Upload'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.byType(IconButton), findsOneWidget, reason: '仅 Refresh 一个图标钮');
    });

    testWidgets('bucket 切换：下拉换 photos → 重新列文件', (tester) async {
      final seams = _Seams();
      await pumpDialog(
        tester,
        seams,
        bucketsOf: (_) => ['media', 'photos'],
        filesOf: (_, bucket) => [
          _filesDoc(
            oid: _oidA,
            filename: 'in-$bucket.bin',
            length: 10,
          ),
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
        filesOf: (_, _) => [_filesDoc(oid: _oidA, filename: 'a.bin', length: 1)],
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
      await IOOverrides.runZoned<Future<void>>(
        () async {
          await tester.tap(find.byKey(Key('gridfs_download_$_oidA')));
          await tester.pump();
        },
        createFile: (path) => _CapturedFile(path),
      );
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

      await IOOverrides.runZoned<Future<void>>(
        () async {
          await tester.tap(find.byKey(Key('gridfs_download_$_oidA')));
          await tester.pump();
        },
        createFile: (path) => _CapturedFile(path),
      );
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
}
