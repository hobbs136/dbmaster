import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/schema_diff_models.dart';
import '../../utils/app_logger.dart';
import 'schema_diff_service.dart';

/// Schema 快照持久化服务
/// 负责保存/加载/导出/导入 Schema 快照为本地 JSON 文件
class SchemaSnapshotService {
  static const String _snapshotDirName = 'schema_snapshots';
  static const String _fileExtension = '.dbsnap';

  final SchemaDiffService _diffService;

  SchemaSnapshotService(this._diffService);

  /// 获取快照存储目录
  Future<Directory> get _storageDir async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}$_snapshotDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 保存快照到本地 JSON 文件
  Future<PersistedSnapshot> saveSnapshot({
    required SchemaSnapshot snapshot,
    required String name,
    String? dbType,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = '${_sanitizeFileName(name)}_$id$_fileExtension';
    final dir = await _storageDir;
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final persisted = PersistedSnapshot.fromSchemaSnapshot(
      id: id,
      name: name,
      filePath: filePath,
      snapshot: snapshot,
      dbType: dbType,
    );

    final json = jsonEncode(persisted.toJson());
    final file = File(filePath);
    await file.writeAsString(json);

    final fileSize = await file.length();

    AppLogger.d(
      'SchemaSnapshotService',
      'Saved snapshot "$name" ($id) to $filePath ($fileSize bytes)',
    );

    return persisted.copyWithFileSize(fileSize);
  }

  /// 列出所有已保存的快照（仅元数据，不含完整 snapshot）
  Future<List<PersistedSnapshot>> listSnapshots() async {
    final dir = await _storageDir;
    final snapshots = <PersistedSnapshot>[];

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith(_fileExtension)) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          snapshots.add(PersistedSnapshot.fromJson(json));
        } catch (e) {
          AppLogger.d(
            'SchemaSnapshotService',
            'Failed to parse snapshot file ${entity.path}: $e',
          );
        }
      }
    }

    // 按捕获时间降序排列
    snapshots.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return snapshots;
  }

  /// 加载一个快照的完整数据
  Future<PersistedSnapshot> loadSnapshot(String id) async {
    final dir = await _storageDir;
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.contains(id))
        .toList();

    if (files.isEmpty) {
      throw Exception('Snapshot $id not found');
    }

    final file = files.first as File;
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return PersistedSnapshot.fromJson(json);
  }

  /// 删除一个快照文件
  Future<void> deleteSnapshot(String id) async {
    final dir = await _storageDir;
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.contains(id))
        .toList();

    for (final entity in files) {
      if (entity is File) {
        await entity.delete();
        AppLogger.d('SchemaSnapshotService', 'Deleted snapshot $id');
      }
    }
  }

  /// 导出快照到用户指定路径
  Future<void> exportSnapshot(String id, String targetPath) async {
    final persisted = await loadSnapshot(id);
    final json = jsonEncode(persisted.toJson());
    final file = File(targetPath);
    await file.writeAsString(json);
    AppLogger.d(
      'SchemaSnapshotService',
      'Exported snapshot "$id" to $targetPath',
    );
  }

  /// 从文件路径导入快照
  Future<PersistedSnapshot> importSnapshot(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw Exception('Snapshot file not found: $sourcePath');
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final incoming = PersistedSnapshot.fromJson(json);

    // 保存到本地存储目录
    final saved = await saveSnapshot(
      snapshot: incoming.snapshot,
      name: '${incoming.name} (imported)',
      dbType: incoming.dbType,
    );

    AppLogger.d(
      'SchemaSnapshotService',
      'Imported snapshot from $sourcePath as ${saved.id}',
    );

    return saved;
  }

  /// 比较两个已持久化的快照
  SchemaDiffReport compareSnapshots({
    required PersistedSnapshot source,
    required PersistedSnapshot target,
  }) {
    return _diffService.compareSnapshots(
      source: source.snapshot,
      target: target.snapshot,
    );
  }

  /// 比较快照与当前数据库
  Future<SchemaDiffReport> compareSnapshotWithLive({
    required PersistedSnapshot snapshot,
    required String connectionId,
    required String connectionName,
    required String databaseName,
  }) async {
    final liveSnapshot = await _diffService.captureSnapshot(
      connectionId: connectionId,
      connectionName: connectionName,
      databaseName: databaseName,
    );

    return _diffService.compareSnapshots(
      source: snapshot.snapshot,
      target: liveSnapshot,
    );
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(' ', '_');
  }
}
