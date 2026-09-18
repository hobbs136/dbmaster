import 'dart:async';
import 'dart:convert';
import '../utils/app_logger.dart';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/backup_models.dart';
import 'database_service.dart';
import 'schema_diff/table_dependency_sorter.dart';
import 'sql_parser_service.dart';

class BackupService {
  final DatabaseService _dbService;
  final List<BackupFile> _backups = [];
  final _progressController = StreamController<BackupProgress>.broadcast();

  Stream<BackupProgress> get progressStream => _progressController.stream;

  BackupService(this._dbService);

  // 获取备份存储目录
  Future<Directory> _getBackupDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(
      '${appDir.path}${Platform.pathSeparator}backups',
    );
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  // 生成备份ID
  String _generateBackupId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        16,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  // 创建备份
  Future<BackupFile> createBackup(BackupOptions options) async {
    if (!_dbService.isConnected) {
      throw Exception('未连接到数据库');
    }

    final server = _dbService.currentServer;
    if (server == null) {
      throw Exception('未找到当前服务器信息');
    }

    final database = server.database ?? 'unknown';
    final backupId = _generateBackupId();
    final timestamp = DateTime.now();
    final fileName =
        '${database}_${timestamp.millisecondsSinceEpoch}.${options.format}';

    _progressController.add(
      BackupProgress(status: 'running', progress: 0.0, currentTable: '准备中...'),
    );

    try {
      final backupDir = await _getBackupDirectory();
      final filePath = '${backupDir.path}${Platform.pathSeparator}$fileName';

      // 获取要备份的表列表
      List<String> tablesToBackup;
      if (options.tables.isEmpty) {
        tablesToBackup = await _dbService.getTables();
      } else {
        tablesToBackup = options.tables;
      }

      if (tablesToBackup.isEmpty) {
        throw Exception('没有要备份的表');
      }

      String content;
      int processedTables = 0;

      switch (options.format.toLowerCase()) {
        case 'sql':
          content = await _createSqlBackup(tablesToBackup, options, (
            table,
            progress,
          ) {
            _progressController.add(
              BackupProgress(
                status: 'running',
                progress: (processedTables + progress) / tablesToBackup.length,
                currentTable: table,
              ),
            );
          });
          break;
        case 'json':
          content = await _createJsonBackup(tablesToBackup, options, (
            table,
            progress,
          ) {
            _progressController.add(
              BackupProgress(
                status: 'running',
                progress: (processedTables + progress) / tablesToBackup.length,
                currentTable: table,
              ),
            );
          });
          break;
        case 'csv':
          content = await _createCsvBackup(tablesToBackup, options, (
            table,
            progress,
          ) {
            _progressController.add(
              BackupProgress(
                status: 'running',
                progress: (processedTables + progress) / tablesToBackup.length,
                currentTable: table,
              ),
            );
          });
          break;
        default:
          throw Exception('不支持的备份格式: ${options.format}');
      }

      // 写入文件
      final file = File(filePath);
      await file.writeAsString(content);

      final backupFile = BackupFile(
        id: backupId,
        name: fileName,
        type: options.format,
        size: await file.length(),
        createdAt: timestamp,
        database: database,
        tables: tablesToBackup,
        description: options.description,
        connectionId: _dbService.activeConnectionId,
      );

      _backups.add(backupFile);

      _progressController.add(
        BackupProgress(status: 'completed', progress: 1.0, currentTable: '完成'),
      );

      // 保存备份元数据
      await _saveBackupMetadata();

      return backupFile;
    } catch (e) {
      _progressController.add(
        BackupProgress(
          status: 'error',
          progress: 0.0,
          currentTable: '',
          error: e.toString(),
        ),
      );
      rethrow;
    }
  }

  // 创建 SQL 备份
  Future<String> _createSqlBackup(
    List<String> tables,
    BackupOptions options,
    Function(String table, double progress) onProgress,
  ) async {
    final buffer = StringBuffer();
    final server = _dbService.currentServer!;

    // 文件头
    buffer.writeln('-- DBMaster Database Backup');
    buffer.writeln('-- Database: ${server.database}');
    buffer.writeln('-- Server: ${server.host}:${server.port}');
    buffer.writeln('-- Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('-- Version: 1.0');
    buffer.writeln('');
    buffer.writeln('SET FOREIGN_KEY_CHECKS=0;');
    buffer.writeln('SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";');
    buffer.writeln('SET AUTOCOMMIT=0;');
    buffer.writeln('START TRANSACTION;');
    buffer.writeln('');

    // Collect CREATE TABLE SQLs for topological sorting
    final createSqlMap = <String, String>{};
    if (options.includeStructure) {
      for (final table in tables) {
        try {
          final createSql = await _dbService.getCreateTableSql(table);
          if (createSql.isNotEmpty) {
            createSqlMap[table] = createSql;
          }
        } catch (e) {
          AppLogger.d('BackupService', '获取表结构失败 $table: $e');
        }
      }
    }

    // Sort tables by FK dependency order if we have CREATE TABLE SQLs
    final sortedTables = createSqlMap.isNotEmpty
        ? TableDependencySorter.sortByCreateOrder(createSqlMap)
        : tables;

    for (var i = 0; i < sortedTables.length; i++) {
      final table = sortedTables[i];
      onProgress(table, 0.0);

      if (options.includeStructure) {
        // 添加 DROP TABLE
        if (options.addDropTable) {
          buffer.writeln('DROP TABLE IF EXISTS `$table`;');
          buffer.writeln('');
        }

        // 获取 CREATE TABLE
        final createSql = createSqlMap[table];
        if (createSql != null && createSql.isNotEmpty) {
          buffer.writeln(createSql);
          buffer.writeln(';');
          buffer.writeln('');
        }
      }

      if (options.includeData) {
        // 导出数据
        await _exportTableDataSql(buffer, table, options);
      }

      onProgress(table, 1.0);
    }

    buffer.writeln('');
    buffer.writeln('COMMIT;');
    buffer.writeln('SET FOREIGN_KEY_CHECKS=1;');

    return buffer.toString();
  }

  // 导出表数据为 SQL
  Future<void> _exportTableDataSql(
    StringBuffer buffer,
    String table,
    BackupOptions options,
  ) async {
    try {
      String whereClause = '';
      if (options.whereClause != null && options.whereClause!.isNotEmpty) {
        whereClause = ' WHERE ${options.whereClause}';
      }

      String limitClause = '';
      if (options.limit != null) {
        limitClause = ' LIMIT ${options.limit}';
      }

      final results = await _dbService.executeQuery(
        'SELECT * FROM `$table`$whereClause$limitClause',
      );

      if (results.isEmpty) return;

      final columns = results.first.keys.toList();
      final columnNames = columns.map((c) => '`$c`').join(', ');

      if (options.extendedInsert) {
        // 使用扩展插入（多行值）
        buffer.writeln('INSERT INTO `$table` ($columnNames) VALUES');

        for (var i = 0; i < results.length; i++) {
          final row = results[i];
          final values = columns
              .map((col) => _escapeSqlValue(row[col]))
              .join(', ');

          if (i < results.length - 1) {
            buffer.writeln('($values),');
          } else {
            buffer.writeln('($values);');
          }
        }
      } else {
        // 单行插入
        for (final row in results) {
          final values = columns
              .map((col) => _escapeSqlValue(row[col]))
              .join(', ');
          buffer.writeln(
            'INSERT INTO `$table` ($columnNames) VALUES ($values);',
          );
        }
      }

      buffer.writeln('');
    } catch (e) {
      AppLogger.d('BackupService', '导出表数据失败 $table: $e');
    }
  }

  // SQL 值转义
  String _escapeSqlValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is bool) return value ? '1' : '0';
    if (value is num) return value.toString();
    if (value is DateTime) return "'${value.toIso8601String()}'";

    // 字符串转义
    String str = value.toString();
    str = str.replaceAll(r'\', r'\\');
    str = str.replaceAll("'", r"\'");
    str = str.replaceAll('\n', r'\n');
    str = str.replaceAll('\r', r'\r');
    str = str.replaceAll('\t', r'\t');
    return "'$str'";
  }

  // 创建 JSON 备份
  Future<String> _createJsonBackup(
    List<String> tables,
    BackupOptions options,
    Function(String table, double progress) onProgress,
  ) async {
    final result = <String, dynamic>{};
    final server = _dbService.currentServer!;

    result['metadata'] = {
      'version': '1.0',
      'database': server.database,
      'server': '${server.host}:${server.port}',
      'generatedAt': DateTime.now().toIso8601String(),
      'includeStructure': options.includeStructure,
      'includeData': options.includeData,
    };

    final tablesData = <String, dynamic>{};

    for (var i = 0; i < tables.length; i++) {
      final table = tables[i];
      onProgress(table, 0.0);

      final tableData = <String, dynamic>{};

      if (options.includeStructure) {
        try {
          final columns = await _dbService.getTableColumns(table);
          final indexes = await _dbService.getTableIndexes(table);

          tableData['structure'] = {
            'columns': columns
                .map(
                  (c) => {
                    'name': c.name,
                    'type': c.type,
                    'isPrimaryKey': c.isPrimaryKey,
                    'isNullable': c.isNullable,
                    'defaultValue': c.defaultValue,
                  },
                )
                .toList(),
            'indexes': indexes
                .map(
                  (idx) => {
                    'name': idx.name,
                    'columns': idx.columns,
                    'isUnique': idx.isUnique,
                  },
                )
                .toList(),
          };
        } catch (e) {
          AppLogger.d('BackupService', '获取表结构失败 $table: $e');
        }
      }

      if (options.includeData) {
        try {
          String whereClause = '';
          if (options.whereClause != null && options.whereClause!.isNotEmpty) {
            whereClause = ' WHERE ${options.whereClause}';
          }

          String limitClause = '';
          if (options.limit != null) {
            limitClause = ' LIMIT ${options.limit}';
          }

          final data = await _dbService.executeQuery(
            'SELECT * FROM `$table`$whereClause$limitClause',
          );
          tableData['data'] = data;
        } catch (e) {
          AppLogger.d('BackupService', '获取表数据失败 $table: $e');
        }
      }

      tablesData[table] = tableData;
      onProgress(table, 1.0);
    }

    result['tables'] = tablesData;
    return const JsonEncoder.withIndent('  ').convert(result);
  }

  // 创建 CSV 备份
  Future<String> _createCsvBackup(
    List<String> tables,
    BackupOptions options,
    Function(String table, double progress) onProgress,
  ) async {
    final buffer = StringBuffer();
    final server = _dbService.currentServer!;

    // 元数据注释
    buffer.writeln('# DBMaster Database Backup');
    buffer.writeln('# Database: ${server.database}');
    buffer.writeln('# Server: ${server.host}:${server.port}');
    buffer.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('# Tables: ${tables.join(", ")}');
    buffer.writeln('');

    for (var i = 0; i < tables.length; i++) {
      final table = tables[i];
      onProgress(table, 0.0);

      buffer.writeln('## TABLE: $table');

      if (options.includeStructure) {
        try {
          final columns = await _dbService.getTableColumns(table);
          buffer.writeln('# COLUMNS: ${columns.map((c) => c.name).join(", ")}');
        } catch (e) {
          AppLogger.d('BackupService', '获取表结构失败 $table: $e');
        }
      }

      if (options.includeData) {
        try {
          String whereClause = '';
          if (options.whereClause != null && options.whereClause!.isNotEmpty) {
            whereClause = ' WHERE ${options.whereClause}';
          }

          String limitClause = '';
          if (options.limit != null) {
            limitClause = ' LIMIT ${options.limit}';
          }

          final data = await _dbService.executeQuery(
            'SELECT * FROM `$table`$whereClause$limitClause',
          );

          if (data.isNotEmpty) {
            // CSV 头部
            final columns = data.first.keys.toList();
            buffer.writeln(columns.map((c) => '"$c"').join(','));

            // CSV 数据
            for (final row in data) {
              final values = columns.map((col) {
                final value = row[col];
                if (value == null) return '';
                final str = value.toString().replaceAll('"', '""');
                return '"$str"';
              }).toList();
              buffer.writeln(values.join(','));
            }
          }
        } catch (e) {
          AppLogger.d('BackupService', '获取表数据失败 $table: $e');
        }
      }

      buffer.writeln('');
      buffer.writeln('## END TABLE: $table');
      buffer.writeln('');

      onProgress(table, 1.0);
    }

    return buffer.toString();
  }

  // 恢复备份
  Future<void> restoreBackup(String backupId, {ImportOptions? options}) async {
    final backup = _backups.firstWhere(
      (b) => b.id == backupId,
      orElse: () => throw Exception('备份文件不存在'),
    );

    if (!_dbService.isConnected) {
      throw Exception('未连接到数据库');
    }

    _progressController.add(
      BackupProgress(status: 'running', progress: 0.0, currentTable: '准备恢复...'),
    );

    try {
      final backupDir = await _getBackupDirectory();
      final filePath =
          '${backupDir.path}${Platform.pathSeparator}${backup.name}';
      final file = File(filePath);

      if (!await file.exists()) {
        throw Exception('备份文件不存在: $filePath');
      }

      final content = await file.readAsString();
      final importOptions = options ?? ImportOptions(format: backup.type);

      switch (backup.type.toLowerCase()) {
        case 'sql':
          await _restoreFromSql(content, importOptions);
          break;
        case 'json':
          await _restoreFromJson(content, importOptions);
          break;
        case 'csv':
          await _restoreFromCsv(content, importOptions);
          break;
        default:
          throw Exception('不支持的备份格式: ${backup.type}');
      }

      _progressController.add(
        BackupProgress(status: 'completed', progress: 1.0, currentTable: '完成'),
      );
    } catch (e) {
      _progressController.add(
        BackupProgress(status: 'error', progress: 0.0, error: e.toString()),
      );
      rethrow;
    }
  }

  // 从 SQL 恢复
  Future<void> _restoreFromSql(String content, ImportOptions options) async {
    // U08：SQL-aware 分割（字符串/注释里的分号不截断语句——dump 数据里
    // 值含分号很常见，旧朴素 split(';') 会把 INSERT 拦腰截断）。
    final statements = SQLParserService.split(content)
        .map((s) => s.sql)
        .toList();

    int processed = 0;
    for (final statement in statements) {
      try {
        await _dbService.executeQuery(statement);
        processed++;

        _progressController.add(
          BackupProgress(
            status: 'running',
            progress: processed / statements.length,
            currentTable: '执行 SQL 语句 $processed/${statements.length}',
          ),
        );
      } catch (e) {
        if (!options.skipErrors) {
          throw Exception('执行 SQL 失败: $e\n语句: $statement');
        }
        AppLogger.d('BackupService', '跳过错误: $e');
      }
    }
  }

  // 从 JSON 恢复
  Future<void> _restoreFromJson(String content, ImportOptions options) async {
    final data = jsonDecode(content) as Map<String, dynamic>;
    final tables = data['tables'] as Map<String, dynamic>? ?? {};

    int processedTables = 0;
    for (final entry in tables.entries) {
      final tableName = entry.key;
      final tableData = entry.value as Map<String, dynamic>;

      _progressController.add(
        BackupProgress(
          status: 'running',
          progress: processedTables / tables.length,
          currentTable: tableName,
        ),
      );

      // 如果需要，先清空表
      if (options.truncateBeforeImport) {
        try {
          await _dbService.executeQuery('TRUNCATE TABLE `$tableName`;');
        } catch (e) {
          if (!options.skipErrors) rethrow;
        }
      }

      // 插入数据
      final rows = tableData['data'] as List<dynamic>? ?? [];
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i] as Map<String, dynamic>;

        try {
          await _insertRow(tableName, row);
        } catch (e) {
          if (!options.skipErrors) {
            throw Exception('插入数据失败 $tableName: $e');
          }
        }
      }

      processedTables++;
    }
  }

  // 从 CSV 恢复
  Future<void> _restoreFromCsv(String content, ImportOptions options) async {
    final lines = content.split('\n');
    String? currentTable;
    List<String>? headers;
    bool inTable = false;

    int processedLines = 0;
    int totalDataLines = lines
        .where(
          (l) =>
              !l.startsWith('#') && !l.startsWith('##') && l.trim().isNotEmpty,
        )
        .length;

    for (final line in lines) {
      final trimmed = line.trim();

      // 跳过注释行
      if (trimmed.startsWith('#')) continue;

      // 表开始标记
      if (trimmed.startsWith('## TABLE:')) {
        currentTable = trimmed.substring('## TABLE:'.length).trim();
        headers = null;
        inTable = true;

        // 如果需要，先清空表
        if (options.truncateBeforeImport) {
          try {
            await _dbService.executeQuery('TRUNCATE TABLE `$currentTable`;');
          } catch (e) {
            if (!options.skipErrors) rethrow;
          }
        }
        continue;
      }

      // 表结束标记
      if (trimmed.startsWith('## END TABLE:')) {
        currentTable = null;
        headers = null;
        inTable = false;
        continue;
      }

      if (!inTable || currentTable == null || trimmed.isEmpty) continue;

      // 解析 CSV 行
      final values = _parseCsvLine(trimmed);

      if (headers == null) {
        // 第一行是表头
        headers = values;
      } else {
        // 数据行
        final row = <String, dynamic>{};
        for (var i = 0; i < headers.length && i < values.length; i++) {
          row[headers[i]] = values[i];
        }

        try {
          await _insertRow(currentTable, row);
        } catch (e) {
          if (!options.skipErrors) {
            throw Exception('插入数据失败 $currentTable: $e');
          }
        }

        processedLines++;
        _progressController.add(
          BackupProgress(
            status: 'running',
            progress: processedLines / totalDataLines,
            currentTable: currentTable,
          ),
        );
      }
    }
  }

  // 简单的 CSV 行解析
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // 转义的引号
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    result.add(buffer.toString());
    return result;
  }

  // 插入单行数据
  Future<void> _insertRow(String tableName, Map<String, dynamic> row) async {
    if (row.isEmpty) return;

    final columns = row.keys.toList();
    final values = row.values.map((v) => _escapeSqlValue(v)).join(', ');
    final columnNames = columns.map((c) => '`$c`').join(', ');

    await _dbService.executeQuery(
      'INSERT INTO `$tableName` ($columnNames) VALUES ($values);',
    );
  }

  // 获取备份列表
  Future<List<BackupFile>> getBackupList() async {
    await _loadBackupMetadata();
    return List.unmodifiable(
      _backups..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  // 删除备份
  Future<void> deleteBackup(String backupId) async {
    final backup = _backups.firstWhere(
      (b) => b.id == backupId,
      orElse: () => throw Exception('备份文件不存在'),
    );

    final backupDir = await _getBackupDirectory();
    final filePath = '${backupDir.path}${Platform.pathSeparator}${backup.name}';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    _backups.removeWhere((b) => b.id == backupId);
    await _saveBackupMetadata();
  }

  // 导出备份文件到用户选择的位置
  Future<String> exportBackup(String backupId) async {
    final backup = _backups.firstWhere(
      (b) => b.id == backupId,
      orElse: () => throw Exception('备份文件不存在'),
    );

    final backupDir = await _getBackupDirectory();
    final sourcePath =
        '${backupDir.path}${Platform.pathSeparator}${backup.name}';
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw Exception('备份文件不存在');
    }

    // 选择保存位置
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出备份文件',
      fileName: backup.name,
      type: FileType.custom,
      allowedExtensions: [backup.type],
    );

    if (result == null) {
      throw Exception('用户取消');
    }

    await sourceFile.copy(result);
    return result;
  }

  // 导入备份文件
  Future<BackupFile> importBackup(String filePath) async {
    final sourceFile = File(filePath);

    if (!await sourceFile.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    // Windows 上路径可能混用 \ 和 /（如文件选择器/测试传入），
    // 只按 Platform.pathSeparator 切分会把整段带 / 的尾部当成文件名，
    // 拼出的 destPath 含不存在的子目录 → PathNotFoundException。统一按两种分隔符切。
    final fileName = sourceFile.path.split(RegExp(r'[\\/]')).last;
    final extension = fileName.split('.').last.toLowerCase();

    if (!['sql', 'json', 'csv'].contains(extension)) {
      throw Exception('不支持的文件格式: $extension');
    }

    final backupDir = await _getBackupDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newFileName = 'imported_${timestamp}_$fileName';
    final destPath = '${backupDir.path}${Platform.pathSeparator}$newFileName';

    await sourceFile.copy(destPath);

    // 尝试解析文件获取表信息
    List<String> tables = [];
    try {
      final content = await File(destPath).readAsString();
      tables = _extractTablesFromContent(content, extension);
    } catch (e) {
      AppLogger.d('BackupService', '解析备份文件失败: $e');
    }

    final backupFile = BackupFile(
      id: _generateBackupId(),
      name: newFileName,
      type: extension,
      size: await File(destPath).length(),
      createdAt: DateTime.now(),
      database: 'unknown',
      tables: tables,
      description: '从外部导入',
    );

    _backups.add(backupFile);
    await _saveBackupMetadata();

    return backupFile;
  }

  // 从内容中提取表名
  List<String> _extractTablesFromContent(String content, String format) {
    final tables = <String>[];

    switch (format) {
      case 'sql':
        // 从 SQL 中提取表名
        final createTableRegex = RegExp(
          r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"\x27]?(\w+)[`"\x27]?',
          caseSensitive: false,
        );
        final insertRegex = RegExp(
          r'INSERT\s+INTO\s+[`"\x27]?(\w+)[`"\x27]?',
          caseSensitive: false,
        );

        for (final match in createTableRegex.allMatches(content)) {
          final tableName = match.group(1);
          if (tableName != null && !tables.contains(tableName)) {
            tables.add(tableName);
          }
        }

        for (final match in insertRegex.allMatches(content)) {
          final tableName = match.group(1);
          if (tableName != null && !tables.contains(tableName)) {
            tables.add(tableName);
          }
        }
        break;

      case 'json':
        try {
          final data = jsonDecode(content) as Map<String, dynamic>;
          final tablesData = data['tables'] as Map<String, dynamic>? ?? {};
          tables.addAll(tablesData.keys);
        } catch (e) {
          AppLogger.d('BackupService', '解析 JSON 失败: $e');
        }
        break;

      case 'csv':
        // 从 CSV 注释中提取表名
        final tableRegex = RegExp(r'##\s*TABLE:\s*(\w+)');
        for (final match in tableRegex.allMatches(content)) {
          final tableName = match.group(1);
          if (tableName != null && !tables.contains(tableName)) {
            tables.add(tableName);
          }
        }
        break;
    }

    return tables;
  }

  // 获取备份文件路径
  Future<String?> getBackupFilePath(String backupId) async {
    final backup = _backups.firstWhere(
      (b) => b.id == backupId,
      orElse: () => throw Exception('备份文件不存在'),
    );

    final backupDir = await _getBackupDirectory();
    final filePath = '${backupDir.path}${Platform.pathSeparator}${backup.name}';
    final file = File(filePath);

    if (await file.exists()) {
      return filePath;
    }
    return null;
  }

  // 获取备份内容预览
  Future<String> getBackupPreview(
    String backupId, {
    int maxLength = 5000,
  }) async {
    final filePath = await getBackupFilePath(backupId);
    if (filePath == null) {
      throw Exception('备份文件不存在');
    }

    final file = File(filePath);
    final content = await file.readAsString();

    if (content.length <= maxLength) {
      return content;
    }
    return '${content.substring(0, maxLength)}\n\n... (${content.length - maxLength} 字符已省略)';
  }

  // 保存备份元数据
  Future<void> _saveBackupMetadata() async {
    try {
      final backupDir = await _getBackupDirectory();
      final metadataFile = File(
        '${backupDir.path}${Platform.pathSeparator}metadata.json',
      );

      final metadata = _backups.map((b) => b.toJson()).toList();
      await metadataFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      AppLogger.d('BackupService', '保存备份元数据失败: $e');
    }
  }

  // 加载备份元数据
  Future<void> _loadBackupMetadata() async {
    if (_backups.isNotEmpty) return; // 已经加载过

    try {
      final backupDir = await _getBackupDirectory();
      final metadataFile = File(
        '${backupDir.path}${Platform.pathSeparator}metadata.json',
      );

      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final List<dynamic> metadata = jsonDecode(content);

        _backups.clear();
        for (final item in metadata) {
          try {
            final backup = BackupFile.fromJson(item as Map<String, dynamic>);
            // 检查文件是否还存在
            final filePath =
                '${backupDir.path}${Platform.pathSeparator}${backup.name}';
            if (await File(filePath).exists()) {
              _backups.add(backup);
            }
          } catch (e) {
            AppLogger.d('BackupService', '加载备份元数据项失败: $e');
          }
        }
      }
    } catch (e) {
      AppLogger.d('BackupService', '加载备份元数据失败: $e');
    }
  }

  // 清理所有备份
  Future<void> clearAllBackups() async {
    final backupDir = await _getBackupDirectory();

    for (final backup in _backups) {
      final filePath =
          '${backupDir.path}${Platform.pathSeparator}${backup.name}';
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _backups.clear();
    await _saveBackupMetadata();
  }

  // 释放资源
  void dispose() {
    _progressController.close();
  }
}
