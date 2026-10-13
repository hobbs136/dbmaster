// DBT-T11 · MongoDB GridFS 只读查看器（W-12）+ DBT-T21 · 上传补齐。
//
// bucket 文件列表 + 元数据查看 + 下载（T11；下载写本地文件非库写路径——无
// 确认门需求，任务书 T11 口径）+ 上传（T21 写路径：FilePicker 选文件 →
// 50MB 护栏 → 预览确认（DestructiveConfirmDialog）→ 注入 uploader →
// 成功刷新/失败回滚提示 + recordQuery 审计）。**删除/重命名入口零出现**
// （T21 验收⑤；§9.6-5 后置）。
//
// - 取数五面经构造注入接缝（ProcessManagerDialog loader 形态）：库清单 /
//   bucket 探测（与树内 GridFS Buckets 节点同一配对识别规则）/ 文件列表 /
//   单文件元数据 / 内容字节——插件闭包绑定 adapter 薄包装
//   （listGridFsFiles/getGridFsFileMetadata/readGridFsFileBytes，全只读）；
// - 上传（T21）同注入模式加 uploadFile/uploadFilePicker/uploadAuditLogger
//   三接缝；**生产默认在 dialog 内解析 AppProvider → adapter
//   uploadGridFsFile**（任务书「插件零改」约束——T17 并行持有插件文件；
//   同 T11 savePathPicker 默认 FilePicker 的接缝形态）；
// - bucket 选择 = **自动选首个**（多数库仅默认 fs bucket）：免提示文案
//   也少一步操作；多 bucket 经下拉切换（下拉恒有值，无需 hint 文案——
//   T11 预登记 key 集无 bucket 提示键，ARB 冻结不自加，缺 key 登记见
//   任务回报）；
// - 下载沿 AI-SEX 导出交互（workbench_session_export.dart 先例）：
//   FilePicker saveFile → 取字节 → 写盘 → 成功/失败 snackbar +
//   `AuditLogService().logExportEvent(format: 'gridfs_file')` 审计。任一
//   取消点（文件选择器取消）= 零副作用零反馈；无进度框架（任务书边界节
//   「沿用既有导出交互，不新造」）——下载期间行内 spinner + 全表下载禁用
//   （一次一个，防重入）；文件名沿用 GridFS 原名（byte-faithful 下载不做
//   扩展名补全）；
// - 上传（T21）同「不新造进度框架」口径：执行中工具栏行内 spinner +
//   全面板动作禁用（一次一个）；审计沿 T11 导出之外的单独立审计口径 =
//   `AuditLogService().recordQuery(isWriteQuery: true)`，SQL 位记摘要式
//   描述（`gridfs upload <bucket>/<filename> <n> chunks`——不落二进制）；
//   失败路径审计 success:false 同落（写路径留痕）；
// - 状态机沿 MongoProcessDialog / PgLocksDialog 同款：loading / error /
//   empty / data，手动刷新，零 Timer；
// - [savePathPicker]/[exportAuditLogger]/[uploadFilePicker]/[uploadFile]/
//   [uploadAuditLogger] 为 @visibleForTesting 注入接缝
//   （AI-SEX-104/105 先例），生产走默认 FilePicker / AuditLogService /
//   AppProvider→adapter。
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../services/adapters/mongodb_adapter.dart';
import '../../services/audit_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../connection/error_boundary.dart';
import '../../molecules/destructive_confirm_dialog.dart';

/// 审计格式常量（与既有 export_service 的 'csv'/'json'、AI-SEX 的
/// 'ai_session_json' 同层取值空间；任务书草案口径 `format: 'gridfs_file'`）。
const String kMongoGridFsAuditFormat = 'gridfs_file';

/// GridFS 文件条目（fs.files wire 文档 → 规范化；`_id`/`uploadDate` 为
/// 扩展 JSON 子文档形态，构造期一次性解包，build 零解析）。
@immutable
class MongoGridFsFileEntry {
  const MongoGridFsFileEntry({
    required this.objectIdHex,
    required this.filename,
    required this.length,
    required this.chunkSize,
    this.uploadDate,
    this.md5,
    this.contentType,
  });

  /// `_id.$oid` 的 24 位 hex（下载/元数据的寻址键）。
  final String objectIdHex;
  final String filename;

  /// 文件字节数（length，wire 可能为 int/double——JSON 数值容错归整）。
  final int length;

  /// chunk 大小（字节；多 chunk 文件的分片粒度）。
  final int chunkSize;

  /// 上传时间（`uploadDate.$date` RFC3339；解析失败容错归 null）。
  final DateTime? uploadDate;

  /// MD5（MongoDB 5.0 起 fs.files 不再自动生成——可缺省）。
  final String? md5;

  /// 用户/驱动存的内容类型（可缺省）。
  final String? contentType;

  /// wire 文档 → 条目（缺省容错：filename 空/length 非 num 归零）。
  static MongoGridFsFileEntry fromFilesDoc(Map<String, dynamic> doc) {
    final id = doc['_id'];
    final uploadDate = doc['uploadDate'];
    return MongoGridFsFileEntry(
      objectIdHex: id is Map ? id[r'$oid']?.toString() ?? '' : '',
      filename: doc['filename']?.toString() ?? '',
      length: doc['length'] is num ? (doc['length'] as num).toInt() : 0,
      chunkSize: doc['chunkSize'] is num
          ? (doc['chunkSize'] as num).toInt()
          : 0,
      uploadDate: uploadDate is Map && uploadDate[r'$date'] is String
          ? DateTime.tryParse(uploadDate[r'$date'] as String)
          : null,
      md5: doc['md5']?.toString(),
      contentType: doc['contentType']?.toString(),
    );
  }

  /// wire 文档列表 → 条目列表。
  static List<MongoGridFsFileEntry> listFromFilesDocs(
    List<Map<String, dynamic>> docs,
  ) => [for (final doc in docs) fromFilesDoc(doc)];

  /// 集合名清单 → GridFS bucket 名（`<bucket>.files` + `<bucket>.chunks`
  /// 成对才识别——与树内 GridFS Buckets 节点/adapter getGridFSBuckets 同一
  /// 规则；仅配对探测，无任何写）。
  static List<String> bucketNamesFrom(Iterable<String> collectionNames) {
    final names = collectionNames.toSet();
    final buckets = [
      for (final name in names)
        if (name.endsWith('.files') &&
            names.contains('${name.substring(0, name.length - 6)}.chunks'))
          name.substring(0, name.length - 6),
    ];
    buckets.sort();
    return buckets;
  }

  /// 字节数可读化（B/KB/MB/GB，两位小数）。
  static String formatBytes(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '$bytes B';
  }
}

// ── 注入接缝（插件闭包绑定 adapter 薄包装；测试注入 mock）──────────────

/// 库清单加载器。
typedef MongoGridFsDatabaseLoader =
    Future<List<String>> Function(String connectionId);

/// 指定库的 bucket 探测器（集合名配对识别，只读）。
typedef MongoGridFsBucketLoader =
    Future<List<String>> Function(String connectionId, String database);

/// bucket 文件列表加载器（wire 文档 → 条目映射归对话框）。
typedef MongoGridFsFileLister =
    Future<List<MongoGridFsFileEntry>> Function(
      String connectionId,
      String database,
      String bucket,
    );

/// 单文件完整元数据加载器（详情面板；文件不存在返回 null）。
typedef MongoGridFsMetadataLoader =
    Future<Map<String, dynamic>?> Function(
      String connectionId,
      String database,
      String bucket,
      String objectIdHex,
    );

/// 文件内容字节读取器（下载用）。
typedef MongoGridFsBytesReader =
    Future<List<int>> Function(
      String connectionId,
      String database,
      String bucket,
      String objectIdHex,
    );

/// 保存路径选择器接缝（默认 FilePicker saveFile）。
typedef MongoGridFsSavePathPicker =
    Future<String?> Function(String suggestedFileName);

/// 导出审计器接缝（默认 AuditLogService.logExportEvent）。
typedef MongoGridFsAuditLogger =
    Future<void> Function({required String sourceSql});

/// 上传执行器接缝（DBT-T21；返回 files_id 24-hex）。默认经
/// AppProvider → adapter `uploadGridFsFile`（分片/分批/回滚全在 adapter
/// 写面，dialog 不直拼命令——任务书「只经 adapter 新 writer 面」）。
typedef MongoGridFsUploader =
    Future<String> Function(
      String connectionId,
      String database,
      String bucket,
      String filename,
      List<int> bytes,
    );

/// 上传源文件选择器接缝（默认 FilePicker pickFiles withData；取消 = null
/// → 零副作用零反馈）。
typedef MongoGridFsUploadFilePicker =
    Future<({String filename, List<int> bytes})?> Function();

/// 上传审计器接缝（默认 AuditLogService.recordQuery isWriteQuery:true；
/// [summary] = 摘要式描述，不含二进制——任务书审计口径）。
typedef MongoGridFsUploadAuditLogger =
    Future<void> Function({
      required bool success,
      required int chunkCount,
      required String summary,
      required Duration elapsed,
      String? errorMessage,
    });

/// MongoDB GridFS 管理对话框（选库 → bucket（自动选首个）→ 文件列表 →
/// 行元数据详情 + 下载 + 上传；删除/重命名零入口）。
class MongoGridFsDialog extends StatefulWidget {
  const MongoGridFsDialog({
    super.key,
    required this.connectionId,
    required this.loadDatabases,
    required this.loadBuckets,
    required this.listFiles,
    required this.loadMetadata,
    required this.readFileBytes,
    this.savePathPicker,
    this.exportAuditLogger,
    this.uploadFile,
    this.uploadFilePicker,
    this.uploadAuditLogger,
  });

  final String connectionId;
  final MongoGridFsDatabaseLoader loadDatabases;
  final MongoGridFsBucketLoader loadBuckets;
  final MongoGridFsFileLister listFiles;
  final MongoGridFsMetadataLoader loadMetadata;
  final MongoGridFsBytesReader readFileBytes;

  /// 保存路径选择器接缝（null = 默认 FilePicker）。
  @visibleForTesting
  final MongoGridFsSavePathPicker? savePathPicker;

  /// 导出审计接缝（null = 默认 AuditLogService 落账）。
  @visibleForTesting
  final MongoGridFsAuditLogger? exportAuditLogger;

  /// 上传执行器接缝（null = 默认 AppProvider → adapter；任务书「插件
  /// 零改」约束下生产默认在 dialog 内解析）。
  @visibleForTesting
  final MongoGridFsUploader? uploadFile;

  /// 上传源文件选择器接缝（null = 默认 FilePicker）。
  @visibleForTesting
  final MongoGridFsUploadFilePicker? uploadFilePicker;

  /// 上传审计接缝（null = 默认 AuditLogService.recordQuery 落账）。
  @visibleForTesting
  final MongoGridFsUploadAuditLogger? uploadAuditLogger;

  /// 便捷打开（生产入口由插件调用——闭包绑定 adapter 薄包装）。
  static Future<void> show(
    BuildContext context, {
    required String connectionId,
    required MongoGridFsDatabaseLoader loadDatabases,
    required MongoGridFsBucketLoader loadBuckets,
    required MongoGridFsFileLister listFiles,
    required MongoGridFsMetadataLoader loadMetadata,
    required MongoGridFsBytesReader readFileBytes,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MongoGridFsDialog(
        connectionId: connectionId,
        loadDatabases: loadDatabases,
        loadBuckets: loadBuckets,
        listFiles: listFiles,
        loadMetadata: loadMetadata,
        readFileBytes: readFileBytes,
      ),
    );
  }

  @override
  State<MongoGridFsDialog> createState() => _MongoGridFsDialogState();
}

class _MongoGridFsDialogState extends State<MongoGridFsDialog> {
  List<String> _databases = const [];
  List<String> _buckets = const [];
  String? _selectedDatabase;
  String? _selectedBucket;

  bool _loadingBuckets = false;
  bool _loadingFiles = false;
  String? _filesError;

  List<MongoGridFsFileEntry> _entries = const [];

  /// 选中行的元数据 future（行点击时置——FutureBuilder 不随 setState 重建
  /// 而重复取数）。
  Future<Map<String, dynamic>?>? _metadataFuture;

  /// 一次一个下载（防重入：执行中禁用全部行内下载与刷新/换库）。
  String? _downloadingObjectId;

  /// 上传执行中（防重入：禁用上传/刷新/换库/换 bucket/下载/行选择）。
  bool _uploading = false;

  /// 连接只读事实（上传入口禁用依据；T20 RedisBackupDialog 同款）。
  /// 连接事实不可确认（含 Provider 树缺席的直泵测试场景）→ fail-closed
  /// 按只读处理。
  bool get _connectionReadOnly {
    try {
      final provider = context.read<AppProvider>();
      for (final candidate in provider.savedConnections) {
        if (candidate.id == widget.connectionId) return candidate.readOnly;
      }
      return true;
    } on ProviderNotFoundException {
      return true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDatabases());
  }

  Future<void> _loadDatabases() async {
    try {
      final dbs = await widget.loadDatabases(widget.connectionId);
      if (!mounted) return;
      setState(() => _databases = dbs);
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('MongoGridFsDialog', 'load databases failed', e);
      setState(() => _filesError = e.toString());
    }
  }

  Future<void> _selectDatabase(String database) async {
    if (database == _selectedDatabase) return;
    setState(() {
      _selectedDatabase = database;
      _selectedBucket = null;
      _buckets = const [];
      _entries = const [];
      _filesError = null;
      _metadataFuture = null;
      _loadingBuckets = true;
    });
    List<String> buckets;
    try {
      buckets = await widget.loadBuckets(widget.connectionId, database);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _filesError = e.toString();
        _loadingBuckets = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _buckets = buckets);
    if (buckets.isNotEmpty) {
      // 自动选首个 bucket（见文件头注）：多数库仅默认 fs bucket，免一步
      // 手动选择；多 bucket 经下拉切换。
      await _selectBucket(buckets.first);
    } else {
      setState(() => _loadingBuckets = false);
    }
  }

  Future<void> _selectBucket(String bucket) async {
    if (bucket == _selectedBucket) return;
    setState(() {
      _selectedBucket = bucket;
      _metadataFuture = null;
      _filesError = null;
      _loadingBuckets = false;
    });
    await _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    final database = _selectedDatabase;
    final bucket = _selectedBucket;
    if (database == null ||
        bucket == null ||
        _downloadingObjectId != null ||
        _uploading) {
      return;
    }
    setState(() {
      _loadingFiles = true;
      _filesError = null;
    });
    try {
      final entries = await widget.listFiles(
        widget.connectionId,
        database,
        bucket,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loadingFiles = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('MongoGridFsDialog', 'list gridfs files failed', e);
      setState(() {
        _filesError = e.toString();
        _loadingFiles = false;
      });
    }
  }

  /// 下载全流程：FilePicker 选路径（取消 = 零副作用零反馈）→ 取字节 →
  /// 写盘 → 成功 snackbar + 审计；取字节/写盘失败 → 失败 snackbar，不落
  /// 审计（未发生导出；AI-SEX 同口径）。文件名沿用 GridFS 原名。
  Future<void> _download(MongoGridFsFileEntry entry) async {
    if (_downloadingObjectId != null) return;
    final database = _selectedDatabase;
    final bucket = _selectedBucket;
    if (database == null || bucket == null) return;
    final l10n = AppLocalizations.of(context)!;

    final picker = widget.savePathPicker ?? _defaultSavePathPicker(l10n);
    final String? pickedPath;
    try {
      pickedPath = await picker(
        entry.filename.isEmpty ? 'gridfs_file' : entry.filename,
      );
    } catch (e) {
      if (mounted) _showFailure(l10n, e);
      return;
    }
    if (pickedPath == null || pickedPath.isEmpty) return;
    if (!mounted) return;

    setState(() => _downloadingObjectId = entry.objectIdHex);
    try {
      final bytes = await widget.readFileBytes(
        widget.connectionId,
        database,
        bucket,
        entry.objectIdHex,
      );
      await File(pickedPath).writeAsBytes(bytes, flush: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadingObjectId = null);
      _showFailure(l10n, e);
      return;
    }
    if (!mounted) return;
    setState(() => _downloadingObjectId = null);
    AppErrorHandler.showSuccessSnackBar(
      context,
      l10n.mongoGridfsDownloadSuccess,
    );
    // 审计（失败不阻塞 UI——AI-SEX 同口径）。
    try {
      final logger = widget.exportAuditLogger ?? _defaultExportAuditLogger;
      await logger(
        sourceSql:
            'gridfs://$database/$bucket/${entry.objectIdHex}'
            ' (${entry.filename})',
      );
    } catch (e) {
      AppLogger.w('MongoGridFsDialog', 'audit log failed: $e');
    }
  }

  void _showFailure(AppLocalizations l10n, Object error) {
    if (!mounted) return;
    // 前缀 = 专键（无参形态，ARB 冻结）；错误详情为动态数据随文展示
    //（loadFailed {error} 先例是加载语义键，下载失败用专键前缀 + 原文）。
    AppErrorHandler.showErrorSnackBar(
      context,
      '${l10n.mongoGridfsDownloadFailed}: $error',
    );
  }

  /// 上传全流程（DBT-T21 写路径）：FilePicker 选文件（取消 = 零副作用
  /// 零反馈）→ 50MB 护栏（超出拒绝 + 提示，零库副作用）→ 预览确认
  /// （DestructiveConfirmDialog：文件名/大小/chunk 数/库/bucket；同名
  /// 文件注记「将新增一个版本」——GridFS 允许多版本不覆盖；取消 = 零
  /// 副作用）→ 注入 uploader 执行 → 成功 snackbar + 列表刷新 + 审计 /
  /// 失败 snackbar（含回滚注记）+ 审计（success:false 留痕）。
  Future<void> _pickAndUpload() async {
    if (_uploading || _downloadingObjectId != null) return;
    final database = _selectedDatabase;
    final bucket = _selectedBucket;
    if (database == null || bucket == null) return;
    final l10n = AppLocalizations.of(context)!;

    // ① 选择本地文件（用户主动；取消 = 零副作用零反馈）。
    final picker = widget.uploadFilePicker ?? _defaultUploadPicker;
    final picked = await picker();
    if (picked == null) return;
    if (!mounted) return;

    // ② 大小护栏（任务书④：≤50MB——客户端分片上传大文件非本批目标；
    //    超出走 mongorestore/驱动工具）。
    if (picked.bytes.length > MongoDBAdapter.kGridFsUploadMaxBytes) {
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.mongoGridfsUploadTooLarge(
          MongoGridFsFileEntry.formatBytes(
            MongoDBAdapter.kGridFsUploadMaxBytes,
          ),
        ),
      );
      return;
    }

    // ③ 预览确认（写路径确认门；影响五要素 = 文件名/大小/chunk 数/库/
    //    bucket；0 字节合法 = 0 chunks）。
    final chunkCount =
        (picked.bytes.length + MongoDBAdapter.kGridFsUploadChunkSize - 1) ~/
        MongoDBAdapter.kGridFsUploadChunkSize;
    final sameNameExists = _entries.any((e) => e.filename == picked.filename);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => DestructiveConfirmDialog(
            icon: LucideIcons.upload,
            title: l10n.mongoGridfsUploadPreviewTitle,
            impactTone: DestructiveTone.warning,
            confirmLabel: l10n.mongoGridfsUpload,
            onConfirm: () => Navigator.of(dialogContext).pop(true),
            impactDescription: [
              picked.filename,
              '${l10n.mongoGridfsColLength}: '
                  '${MongoGridFsFileEntry.formatBytes(picked.bytes.length)}',
              l10n.mongoGridfsUploadChunkCount('$chunkCount'),
              '$database/$bucket',
            ].join('\n'),
            extraContent: sameNameExists
                ? Text(l10n.mongoGridfsUploadNewVersionNote)
                : null,
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (!mounted) return;

    // ④ 执行（一次一个：上传中禁用刷新/换库/换 bucket/下载/行选择）。
    setState(() => _uploading = true);
    final stopwatch = Stopwatch()..start();
    final summary =
        'gridfs upload $bucket/${picked.filename} $chunkCount chunks';
    try {
      final uploader = widget.uploadFile ?? _defaultUpload;
      await uploader(
        widget.connectionId,
        database,
        bucket,
        picked.filename,
        picked.bytes,
      );
      stopwatch.stop();
      if (mounted) {
        setState(() => _uploading = false);
        AppErrorHandler.showSuccessSnackBar(
          context,
          l10n.mongoGridfsUploadSuccess(picked.filename),
        );
        // 完成后列表刷新（新文件行可见；uploadDate 降序居首）。
        await _refreshFiles();
      }
    } catch (e) {
      stopwatch.stop();
      AppLogger.e('MongoGridFsDialog', 'gridfs upload failed', e);
      var message = '${l10n.mongoGridfsUploadFailed(picked.filename)}: $e';
      if (e is MongoGridFsUploadException) {
        // 回滚注记（任务书「孤儿 chunks 风险登记边界」——adapter 尽力
        // 回滚后随异常上抛事实）。
        message += '\n${l10n.mongoGridfsUploadRollbackPartial}';
      }
      if (mounted) {
        setState(() => _uploading = false);
        AppErrorHandler.showErrorSnackBar(context, message);
      }
      // 失败审计（写路径留痕：success:false + 摘要错误；二进制不入审计）。
      try {
        await (widget.uploadAuditLogger ?? _defaultUploadAudit)(
          success: false,
          chunkCount: chunkCount,
          summary: summary,
          elapsed: stopwatch.elapsed,
          errorMessage: e.toString(),
        );
      } catch (auditError) {
        AppLogger.w('MongoGridFsDialog', 'upload audit failed: $auditError');
      }
      return;
    }
    // 成功审计（任务书口径：执行后落 recordQuery isWriteQuery:true，SQL
    // 位记摘要式描述；rowCount = chunks + files 行数）。
    try {
      await (widget.uploadAuditLogger ?? _defaultUploadAudit)(
        success: true,
        chunkCount: chunkCount,
        summary: summary,
        elapsed: stopwatch.elapsed,
      );
    } catch (auditError) {
      AppLogger.w('MongoGridFsDialog', 'upload audit failed: $auditError');
    }
  }

  /// 默认上传执行器：AppProvider → MongoDBAdapter `uploadGridFsFile`
  /// （分片/分批/失败回滚全在 adapter 写面；dialog 不直拼命令）。
  Future<String> _defaultUpload(
    String connectionId,
    String database,
    String bucket,
    String filename,
    List<int> bytes,
  ) {
    final provider = context.read<AppProvider>();
    final adapter = provider.dbService.getAdapter(connectionId);
    if (adapter is! MongoDBAdapter) {
      throw StateError('MongoDB 连接不可用（GridFS 需要 MongoDB 连接）');
    }
    return adapter.uploadGridFsFile(
      bucket,
      database: database,
      filename: filename,
      bytes: bytes,
    );
  }

  /// 默认上传源文件选择器（顶层实现的 l10n 标题闭包）。
  MongoGridFsUploadFilePicker get _defaultUploadPicker {
    final l10n = AppLocalizations.of(context)!;
    return () => _defaultUploadFilePicker(l10n);
  }

  /// 默认上传审计器（DBT-T21 单独立审计口径，与 T11 导出审计分账）：
  /// `recordQuery` isWriteQuery:true——SQL 位记摘要式描述（不落二进制），
  /// rowCount = chunks + files 行数；失败同落（success:false + 错误摘要）。
  /// 先 initialize（auditPgPartitionDdl 同款）：上传若是本会话首个审计
  /// 动作，未加载即持久化会以单条记录覆写既有审计历史。
  Future<void> _defaultUploadAudit({
    required bool success,
    required int chunkCount,
    required String summary,
    required Duration elapsed,
    String? errorMessage,
  }) async {
    final audit = AuditLogService();
    await audit.initialize();
    audit.recordQuery(
      connectionId: widget.connectionId,
      databaseName: _selectedDatabase,
      sql: summary,
      executionTime: elapsed,
      rowCount: success ? chunkCount + 1 : null,
      success: success,
      errorMessage: errorMessage,
      isWriteQuery: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.folderOpen, size: 20, color: colors.accentPurple),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.mongoGridfsTitle),
          const Spacer(),
          // 上传入口（DBT-T21；插件零改——入口在 dialog 工具栏）。禁用位：
          // 未选库/bucket、readonly 连接、下载/上传执行中。
          _uploading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  key: const Key('gridfs_upload_btn'),
                  tooltip: l10n.mongoGridfsUpload,
                  onPressed: _canUpload ? _pickAndUpload : null,
                  icon: const Icon(LucideIcons.upload, size: 16),
                ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed:
                (_loadingFiles ||
                    _downloadingObjectId != null ||
                    _uploading ||
                    _selectedBucket == null)
                ? null
                : _refreshFiles,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSelectors(l10n),
            if (_filesError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppDesignSystem.space2),
                child: Text(
                  _filesError!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppDesignSystem.space2),
            Expanded(flex: 5, child: _buildFileList(l10n, colors)),
            const Divider(height: 1),
            Expanded(flex: 4, child: _buildMetadataDetail(l10n, colors)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  /// 上传入口可用位（一次一个 + 未选库/bucket 禁用 + readonly 禁用——
  /// 任务书边界「非当前库 bucket 下拉为空 → 上传禁用」）。
  bool get _canUpload =>
      !_uploading &&
      _downloadingObjectId == null &&
      _selectedDatabase != null &&
      _selectedBucket != null &&
      !_connectionReadOnly;

  Widget _buildSelectors(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: DropdownButton<String>(
            value: _selectedDatabase,
            isExpanded: true,
            hint: Text(l10n.connectionDatabase),
            items: [
              for (final db in _databases)
                DropdownMenuItem<String>(value: db, child: Text(db)),
            ],
            onChanged: (_downloadingObjectId == null && !_uploading)
                ? (db) {
                    if (db != null) _selectDatabase(db);
                  }
                : null,
          ),
        ),
        const SizedBox(width: AppDesignSystem.space3),
        Expanded(
          // bucket 下拉恒有值（自动选首个，见文件头注）；无 bucket 的库不
          // 渲染该下拉（空态由列表区呈现）。
          child: _buckets.isEmpty
              ? const SizedBox.shrink()
              : DropdownButton<String>(
                  value: _selectedBucket,
                  isExpanded: true,
                  items: [
                    for (final bucket in _buckets)
                      DropdownMenuItem<String>(
                        value: bucket,
                        child: Text(bucket),
                      ),
                  ],
                  onChanged: (_downloadingObjectId == null && !_uploading)
                      ? (bucket) {
                          if (bucket != null) _selectBucket(bucket);
                        }
                      : null,
                ),
        ),
      ],
    );
  }

  Widget _buildFileList(AppLocalizations l10n, ThemeColors colors) {
    if (_selectedDatabase == null) {
      return const SizedBox.shrink();
    }
    if (_loadingBuckets) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    // 库无 GridFS bucket（无 .files/.chunks 配对）→ 空态（任务书边界节：
    // bucket 不存在/空 → 空态）。
    if (_selectedBucket == null) {
      return _buildEmpty(l10n, colors);
    }
    if (_loadingFiles) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    // 取数失败 → 列表区不渲染（错误文案已在上方错误行呈现，不叠空态
    // 误导「无文件」）。
    if (_filesError != null) {
      return const SizedBox.shrink();
    }
    if (_entries.isEmpty) {
      return _buildEmpty(l10n, colors);
    }
    final rows = [
      for (final e in _entries)
        DataRow(
          // 行点击 → 元数据详情（选中行高亮）；上传执行中禁用。
          onSelectChanged: (_downloadingObjectId == null && !_uploading)
              ? (_) => _selectEntry(e)
              : null,
          cells: [
            DataCell(_buildDownloadAction(l10n, colors, e)),
            DataCell(
              Text(e.objectIdHex, style: _cellStyle(colors, mono: true)),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  e.filename.isEmpty ? '-' : e.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cellStyle(colors),
                ),
              ),
            ),
            DataCell(
              Text(
                MongoGridFsFileEntry.formatBytes(e.length),
                style: _cellStyle(colors, mono: true),
              ),
            ),
            DataCell(
              Text(
                e.uploadDate == null ? '-' : _formatDate(e.uploadDate!),
                style: _cellStyle(colors),
              ),
            ),
            DataCell(
              Text(
                MongoGridFsFileEntry.formatBytes(e.chunkSize),
                style: _cellStyle(colors, mono: true),
              ),
            ),
          ],
        ),
    ];
    // 无条件横向滚动（MongoProcessDialog 同分支）：DataTable 在无界宽下取
    // 自然列宽，避免有界宽下的列挤压溢出。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingTextStyle: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
          ),
          dataRowMinHeight: 30,
          dataRowMaxHeight: 30,
          columnSpacing: 20,
          columns: [
            DataColumn(label: Text(l10n.mongoGridfsDownload)),
            DataColumn(label: Text(l10n.mongoGridfsColObjectId)),
            DataColumn(label: Text(l10n.mongoGridfsColFilename)),
            DataColumn(label: Text(l10n.mongoGridfsColLength), numeric: true),
            DataColumn(label: Text(l10n.mongoGridfsColUploadDate)),
            DataColumn(
              label: Text(l10n.mongoGridfsColChunkSize),
              numeric: true,
            ),
          ],
          rows: rows,
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, ThemeColors colors) {
    return Center(
      child: Text(
        l10n.mongoGridfsEmpty,
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
    );
  }

  /// 行内下载动作：一次一个（执行中全部行禁用 + 行内 spinner；上传执行中
  /// 同禁用——面板级一次一个写/读互斥）。
  Widget _buildDownloadAction(
    AppLocalizations l10n,
    ThemeColors colors,
    MongoGridFsFileEntry e,
  ) {
    final downloading = _downloadingObjectId == e.objectIdHex;
    final disabled =
        (_downloadingObjectId != null && !downloading) || _uploading;
    if (downloading) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return SizedBox(
      width: 88,
      child: TextButton(
        key: Key('gridfs_download_${e.objectIdHex}'),
        onPressed: disabled ? null : () => _download(e),
        style: TextButton.styleFrom(
          foregroundColor: colors.accentBlue,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(64, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          l10n.mongoGridfsDownload,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// 选中行 → 元数据详情（future 在此置——setState 块体同步赋值，异步
  /// 取数在 setState 外启动；FutureBuilder 不随 setState 重建而重复取数）。
  void _selectEntry(MongoGridFsFileEntry entry) {
    final future = widget.loadMetadata(
      widget.connectionId,
      _selectedDatabase!,
      _selectedBucket!,
      entry.objectIdHex,
    );
    // 拒绝可能发生在下一帧 FutureBuilder 挂接之前（microtask 先于 frame）：
    // 预挂吞错监听防 unhandled async error（FutureBuilder 自有监听仍按
    // 错误分支渲染）。
    future.ignore();
    // 箭头体会把 Future 作为返回值传给 setState（断言拦截）——必须块体。
    setState(() {
      _metadataFuture = future;
    });
  }

  Widget _buildMetadataDetail(AppLocalizations l10n, ThemeColors colors) {
    final future = _metadataFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          // 元数据取数失败 = 加载失败语义（loadFailed {error} 既有键）。
          return Text(
            l10n.loadFailed(snapshot.error.toString()),
            style: TextStyle(color: colors.error, fontSize: 12),
          );
        }
        final doc = snapshot.data;
        if (doc == null) {
          // 列取后文件被删等边缘 → 空态（只读视图，不报错）。
          return _buildEmpty(l10n, colors);
        }
        final entry = MongoGridFsFileEntry.fromFilesDoc(doc);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: AppDesignSystem.space2,
                  bottom: AppDesignSystem.space1,
                ),
                child: Text(
                  l10n.mongoGridfsMetadata,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              _buildInfoRow(
                l10n.mongoGridfsColObjectId,
                entry.objectIdHex,
                colors,
                mono: true,
              ),
              _buildInfoRow(
                l10n.mongoGridfsColFilename,
                entry.filename,
                colors,
              ),
              _buildInfoRow(
                l10n.mongoGridfsColLength,
                MongoGridFsFileEntry.formatBytes(entry.length),
                colors,
              ),
              _buildInfoRow(
                l10n.mongoGridfsColChunkSize,
                MongoGridFsFileEntry.formatBytes(entry.chunkSize),
                colors,
              ),
              _buildInfoRow(
                l10n.mongoGridfsColUploadDate,
                entry.uploadDate == null ? '-' : _formatDate(entry.uploadDate!),
                colors,
              ),
              if (entry.md5 != null && entry.md5!.isNotEmpty)
                _buildInfoRow('MD5', entry.md5!, colors, mono: true),
              if (entry.contentType != null && entry.contentType!.isNotEmpty)
                _buildInfoRow('Content-Type', entry.contentType!, colors),
              _buildMetadataJson(doc['metadata'], colors),
            ],
          ),
        );
      },
    );
  }

  /// 用户 metadata 子文档 JSON（可缺省；缺省不渲染 JSON 块）。
  Widget _buildMetadataJson(Object? metadata, ThemeColors colors) {
    if (metadata is! Map || metadata.isEmpty) return const SizedBox.shrink();
    final encoder = const JsonEncoder.withIndent('  ');
    final String json;
    try {
      json = encoder.convert(metadata);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppDesignSystem.space2),
      child: SelectableText(
        json,
        style: TextStyle(
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontSize: 12,
          color: colors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    ThemeColors colors, {
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
                fontFamily: mono ? AppDesignSystem.monoFontFamily : null,
                fontFamilyFallback: mono
                    ? AppDesignSystem.monoFontFamilyFallback
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _cellStyle(ThemeColors colors, {bool mono = false}) => TextStyle(
    fontSize: 12,
    color: colors.textPrimary,
    fontFamily: mono ? AppDesignSystem.monoFontFamily : null,
    fontFamilyFallback: mono ? AppDesignSystem.monoFontFamilyFallback : null,
  );

  /// uploadDate 展示（本地时区，分钟粒度——列宽友好）。
  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 默认保存路径选择器：FilePicker saveFile（byte-faithful 下载——不做
/// 扩展名限定，文件名沿用 GridFS 原名；标题复用面板标题 key）。
MongoGridFsSavePathPicker _defaultSavePathPicker(AppLocalizations l10n) {
  return (String suggestedFileName) => FilePicker.platform.saveFile(
    dialogTitle: l10n.mongoGridfsTitle,
    fileName: suggestedFileName,
  );
}

/// 默认导出审计器：导出事件落 AuditLogService（rowCount=1 单文件；sourceSql
/// 携带 gridfs:// 定位串便于审计回溯）。
Future<void> _defaultExportAuditLogger({required String sourceSql}) {
  return AuditLogService().logExportEvent(
    format: kMongoGridFsAuditFormat,
    rowCount: 1,
    sourceSql: sourceSql,
  );
}

/// 默认上传源文件选择器（DBT-T21）：FilePicker pickFiles withData（用户
/// 主动选文件；取消/无字节 = null → 零副作用零反馈）。
Future<({String filename, List<int> bytes})?> _defaultUploadFilePicker(
  AppLocalizations l10n,
) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: l10n.mongoGridfsUploadPreviewTitle,
    withData: true,
  );
  final files = result?.files ?? const <PlatformFile>[];
  if (files.isEmpty) return null;
  final file = files.first;
  final bytes = file.bytes;
  if (bytes == null) return null;
  return (filename: file.name, bytes: bytes);
}
