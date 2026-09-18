import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/schema_diff/schema_diff_service.dart';
import 'package:dbmaster/services/schema_diff/schema_snapshot_service.dart';

/// SchemaSnapshotService 单元测试。
///
/// 覆盖：保存/列表/加载/删除/导出/导入的文件 IO 往返，以及 compareSnapshots
/// 纯委托逻辑。文件 IO 通过 mock getApplicationSupportDirectory 重定向到临时目录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  //path_provider mock —— SchemaSnapshotService 通过
  // getApplicationSupportDirectory() 解析存储目录；不 mock 会挂起。
  // 沿用 backup_service_test 的四通道写法，但方法改为 Support 目录。
  void mockPathProvider() {
    const channels = [
      MethodChannel('plugins.flutter.io/path_provider'),
      MethodChannel('plugins.flutter.io/path_provider_foundation'),
      MethodChannel('plugins.flutter.io/path_provider_linux'),
      MethodChannel('plugins.flutter.io/path_provider_windows'),
    ];
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return tempDir.path;
        }
        return null;
      });
    }
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('snapshot_test_');
    mockPathProvider();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  SchemaSnapshotService newService() =>
      SchemaSnapshotService(SchemaDiffService(_StubDatabaseService()));

  test('saveSnapshot 写入文件并回填 fileSizeBytes', () async {
    final service = newService();
    final persisted = await service.saveSnapshot(
      snapshot: _sampleSnapshot('db1', tables: [_table('users')]),
      name: 'My Snapshot',
      dbType: 'mysql',
    );

    expect(persisted.id, isNotEmpty);
    expect(persisted.name, 'My Snapshot');
    expect(persisted.dbType, 'mysql');
    expect(persisted.tableCount, 1);
    expect(persisted.fileSizeBytes, greaterThan(0));
    expect(await File(persisted.filePath).exists(), isTrue);
  });

  test('listSnapshots 按捕获时间降序返回已保存快照', () async {
    final service = newService();
    final older = await service.saveSnapshot(
      snapshot: _sampleSnapshot('older', capturedAt: DateTime(2024, 1, 1)),
      name: 'older',
    );
    // 保证两次保存生成不同的毫秒 id（saveSnapshot 用 DateTime.now 作 id）。
    await Future<void>.delayed(const Duration(milliseconds: 3));
    final newer = await service.saveSnapshot(
      snapshot: _sampleSnapshot('newer', capturedAt: DateTime(2024, 6, 1)),
      name: 'newer',
    );

    final list = await service.listSnapshots();
    expect(list.length, 2);
    expect(list.first.id, newer.id);
    expect(list.last.id, older.id);
  });

  test('listSnapshots 忽略无法解析的损坏文件', () async {
    final service = newService();
    await service.saveSnapshot(snapshot: _sampleSnapshot('db1'), name: 'good');
    // 写入一个非 JSON 的 .dbsnap 文件模拟损坏。
    final dir = Directory(
      '${tempDir.path}${Platform.pathSeparator}schema_snapshots',
    );
    await File('${dir.path}${Platform.pathSeparator}broken.dbsnap')
        .writeAsString('not json');

    final list = await service.listSnapshots();
    expect(list.length, 1);
  });

  test('loadSnapshot 按 id 返回完整快照；缺失时抛异常', () async {
    final service = newService();
    final saved = await service.saveSnapshot(
      snapshot: _sampleSnapshot('db1'),
      name: 'snap',
    );

    final loaded = await service.loadSnapshot(saved.id);
    expect(loaded.id, saved.id);
    expect(loaded.snapshot.databaseName, 'db1');

    expect(
      () => service.loadSnapshot('does-not-exist'),
      throwsA(isA<Exception>()),
    );
  });

  test('deleteSnapshot 移除文件', () async {
    final service = newService();
    final saved = await service.saveSnapshot(
      snapshot: _sampleSnapshot('db1'),
      name: 'snap',
    );

    expect((await service.listSnapshots()).length, 1);
    await service.deleteSnapshot(saved.id);
    expect((await service.listSnapshots()).length, 0);
  });

  test('exportSnapshot → importSnapshot 往返一致', () async {
    final service = newService();
    final saved = await service.saveSnapshot(
      snapshot: _sampleSnapshot('db1'),
      name: 'snap',
      dbType: 'postgres',
    );

    final exportPath =
        '${tempDir.path}${Platform.pathSeparator}export.dbsnap';
    await service.exportSnapshot(saved.id, exportPath);
    expect(await File(exportPath).exists(), isTrue);

    final imported = await service.importSnapshot(exportPath);
    expect(imported.name, contains('imported'));
    expect(imported.snapshot.databaseName, 'db1');
    expect(imported.dbType, 'postgres');
  });

  test('importSnapshot 缺失文件时抛异常', () async {
    final service = newService();
    expect(
      () => service.importSnapshot(
        '${tempDir.path}${Platform.pathSeparator}nope.dbsnap',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('compareSnapshots 委托 diffService 生成报告', () {
    final service = newService();
    final source = PersistedSnapshot.fromSchemaSnapshot(
      id: 'a',
      name: 'a',
      filePath: 'a',
      snapshot: _sampleSnapshot('src', tables: [_table('users')]),
    );
    final target = PersistedSnapshot.fromSchemaSnapshot(
      id: 'b',
      name: 'b',
      filePath: 'b',
      snapshot: _sampleSnapshot('tgt'),
    );

    final report = service.compareSnapshots(source: source, target: target);
    expect(report.hasChanges, isTrue);
    expect(report.tableDiffs.any((t) => t.name == 'users'), isTrue);
  });
}

/// 占位 DatabaseService —— 快照持久化与 compareSnapshots 均不触碰真实适配器。
class _StubDatabaseService extends DatabaseService {}

SchemaSnapshot _sampleSnapshot(
  String databaseName, {
  DateTime? capturedAt,
  List<DbTable> tables = const [],
}) {
  return SchemaSnapshot(
    connectionId: 'conn1',
    connectionName: 'Local',
    databaseName: databaseName,
    capturedAt: capturedAt ?? DateTime(2024, 3, 1),
    tables: tables,
  );
}

DbTable _table(String name) => DbTable(
      name: name,
      columns: [DbColumn(name: 'id', type: 'INT', isPrimaryKey: true)],
    );
