import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audit_log_entry.dart';
import '../models/export_audit_entry.dart';
import '../utils/app_logger.dart';
import '../utils/audit_sql_sanitizer.dart';

/// Service for recording and querying query audit logs
/// Stores logs locally using SharedPreferences (JSON format)
/// Maximum 10,000 entries, older entries are removed automatically
class AuditLogService {
  static const String _storageKey = 'audit_logs';
  static const String _exportStorageKey = 'audit_export_logs';
  /// 审计日志在 SharedPreferences 只作近期活动轨迹（整文件每次全量重写，
  /// 条数×SQL 体积直接决定所有 prefs 写入成本）。旧值 10000 + 未截断 SQL
  /// 曾把 prefs 撑到 9.6MB——多语句执行每条一次全量 jsonEncode，UI 线程
  /// 实测阻塞 ~40s。合规级长期留存应走 SQLite。
  static const int _maxEntries = 500;

  /// 单条审计 SQL 截断上限（脱敏后再截断，避免 MB 级脚本整体入档）。
  static const int _maxSqlChars = 500;

  final List<AuditLogEntry> _entries = [];
  final List<ExportAuditEntry> _exportEntries = [];
  bool _initialized = false;

  static final AuditLogService _instance = AuditLogService._internal();
  factory AuditLogService() => _instance;
  AuditLogService._internal();

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadEntries();
    await _loadExportEntries();
    _initialized = true;
  }

  Future<void> _loadEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        _entries.clear();
        _entries.addAll(
          list.map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>)),
        );
        // 存量修复：旧版 10000 条 + 未截断 SQL 可达 ~10MB，加载即裁剪回写。
        var repaired = false;
        if (_entries.length > _maxEntries) {
          _entries.removeRange(0, _entries.length - _maxEntries);
          repaired = true;
        }
        for (var i = 0; i < _entries.length; i++) {
          final e = _entries[i];
          if (e.sql.length > _maxSqlChars) {
            _entries[i] = AuditLogEntry(
              id: e.id,
              timestamp: e.timestamp,
              connectionId: e.connectionId,
              connectionName: e.connectionName,
              databaseName: e.databaseName,
              sql: _truncateSql(e.sql),
              executionTime: e.executionTime,
              rowCount: e.rowCount,
              success: e.success,
              errorMessage: e.errorMessage,
              isWriteQuery: e.isWriteQuery,
            );
            repaired = true;
          }
        }
        if (repaired) {
          await _persistEntries();
        }
      }
    } catch (e) {
      AppLogger.e('AuditLogService', 'Failed to load audit logs', e);
    }
  }

  Future<void> _loadExportEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_exportStorageKey);
      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        _exportEntries.clear();
        _exportEntries.addAll(
          list.map((e) => ExportAuditEntry.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      AppLogger.e('AuditLogService', 'Failed to load export logs', e);
    }
  }

  Future<void> _persistExportEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr =
          jsonEncode(_exportEntries.map((e) => e.toJson()).toList());
      await prefs.setString(_exportStorageKey, jsonStr);
    } catch (e) {
      AppLogger.e('AuditLogService', 'Failed to persist export logs', e);
    }
  }

  Future<void> _persistEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      AppLogger.e('AuditLogService', 'Failed to persist audit logs', e);
    }
  }

  void recordQuery({
    required String connectionId,
    String? connectionName,
    String? databaseName,
    required String sql,
    required Duration executionTime,
    int? rowCount,
    required bool success,
    String? errorMessage,
    bool isWriteQuery = false,
  }) {
    final entry = AuditLogEntry(
      id: 'audit_${DateTime.now().millisecondsSinceEpoch}_${_entries.length}',
      timestamp: DateTime.now(),
      connectionId: connectionId,
      connectionName: connectionName,
      databaseName: databaseName,
      sql: _truncateSql(AuditSqlSanitizer.sanitize(sql)),
      executionTime: executionTime,
      rowCount: rowCount,
      success: success,
      errorMessage: errorMessage,
      isWriteQuery: isWriteQuery,
    );

    _entries.add(entry);

    // Remove old entries if exceeding max
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }

    _schedulePersist();
  }

  static String _truncateSql(String sql) {
    if (sql.length <= _maxSqlChars) return sql;
    return '${sql.substring(0, _maxSqlChars)}...';
  }

  /// 防抖持久化：批量写入合并到一次（jsonEncode 全量 + prefs 整文件
  /// 重写，逐条触发在 N 条脚本执行下是 N 次 MB 级编码）。
  Timer? _persistDebounce;

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 2), () {
      _persistEntries();
    });
  }

  List<AuditLogEntry> getRecentEntries({int limit = 100}) {
    final sorted = List<AuditLogEntry>.from(_entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  List<AuditLogEntry> searchEntries({
    String? connectionId,
    String? searchQuery,
    DateTime? startTime,
    DateTime? endTime,
    bool? success,
    bool? isWriteQuery,
  }) {
    return _entries.where((entry) {
      if (connectionId != null && entry.connectionId != connectionId) {
        return false;
      }
      if (searchQuery != null &&
          !entry.sql.toLowerCase().contains(searchQuery.toLowerCase()) &&
          !(entry.connectionName?.toLowerCase().contains(
                searchQuery.toLowerCase(),
              ) ??
              false)) {
        return false;
      }
      if (startTime != null && entry.timestamp.isBefore(startTime)) {
        return false;
      }
      if (endTime != null && entry.timestamp.isAfter(endTime)) {
        return false;
      }
      if (success != null && entry.success != success) {
        return false;
      }
      if (isWriteQuery != null && entry.isWriteQuery != isWriteQuery) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  int get entryCount => _entries.length;

  Future<void> clearLogs() async {
    _entries.clear();
    await _persistEntries();
  }

  Map<String, dynamic> getStatistics() {
    if (_entries.isEmpty) {
      return {
        'totalQueries': 0,
        'successfulQueries': 0,
        'failedQueries': 0,
        'avgExecutionTimeMs': 0,
        'writeQueries': 0,
      };
    }

    final totalExecutionTime = _entries.fold(
      Duration.zero,
      (sum, entry) => sum + entry.executionTime,
    );

    final successfulQueries = _entries.where((e) => e.success).length;
    final failedQueries = _entries.where((e) => !e.success).length;
    final writeQueries = _entries.where((e) => e.isWriteQuery).length;

    return {
      'totalQueries': _entries.length,
      'successfulQueries': successfulQueries,
      'failedQueries': failedQueries,
      'avgExecutionTimeMs': totalExecutionTime.inMilliseconds / _entries.length,
      'writeQueries': writeQueries,
    };
  }

  // ============ R4: 导出审计日志（独立存储，不混入查询审计）============

  /// 记录一次导出事件（NF5: 只记处理方式，不记 PII 明文）。
  Future<void> logExportEvent({
    String? sourceSql,
    required String format,
    required int rowCount,
    Map<String, String> columnActions = const {},
  }) async {
    await initialize();
    final entry = ExportAuditEntry(
      id: 'export_${DateTime.now().millisecondsSinceEpoch}_${_exportEntries.length}',
      timestamp: DateTime.now(),
      sourceSql: sourceSql != null ? AuditSqlSanitizer.sanitize(sourceSql) : null,
      format: format,
      rowCount: rowCount,
      columnActions: columnActions,
    );
    _exportEntries.add(entry);
    if (_exportEntries.length > _maxEntries) {
      _exportEntries.removeAt(0);
    }
    await _persistExportEntries();
  }

  /// 获取最近的导出审计条目。
  List<ExportAuditEntry> getRecentExportEntries({int limit = 100}) {
    final sorted = List<ExportAuditEntry>.from(_exportEntries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  int get exportEntryCount => _exportEntries.length;
}
