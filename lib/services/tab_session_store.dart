import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/database_models.dart' show DatabaseType;
import '../providers/tab_provider.dart' show QueryTab;
import '../utils/app_logger.dart';

/// 崩溃恢复快照：还原的标签页列表 + 崩溃时的活跃索引。
class TabSessionSnapshot {
  final List<QueryTab> tabs;
  final int activeTabIndex;

  const TabSessionSnapshot({required this.tabs, required this.activeTabIndex});
}

/// 标签页会话持久化（U16）——崩溃安全网，不是「每次启动恢复工作区」。
///
/// 策略：
/// - **自动落盘**：AppProvider 监听 TabProvider 变更防抖 800ms 写入
///   `<appSupport>/tab_session.json`（**瘦序列化**：SQL 文本 + 连接引用 +
///   保存态；不含 executionResults——结果集可达 MB 级，也不含 sessionId——
///   MySQL/Doris 运行态会话重启即失效，恢复时置 null）。
/// - **仅异常退出后恢复**：正常关窗走 _WindowCloseGuard 的批量保存确认，
///   用户「丢弃」的决定必须被尊重——所以 clean exit 时
///   [markCleanExit] 清空会话；崩溃/掉电/kill 留存文件，下次启动由
///   AppProvider 检测 [wasUncleanExit] 后恢复并提示。
/// - 退出标记 `<appSupport>/app_exit_state.json`：启动写 `running=true`，
///   clean exit 写 `running=false`；下次启动读到 running=true 即上次未走
///   完正常退出。文件缺失（首跑/旧版本）视为 clean，不误报。
///
/// 所有操作 best-effort：失败只记日志不抛——持久化本身不能成为新的错误源。
class TabSessionStore {
  TabSessionStore(this.baseDir);

  /// 会话与退出标记所在目录（应用支持目录）。
  final Directory baseDir;

  /// 测试 / 注入用工厂。
  static Future<TabSessionStore> createDefault() async {
    final support = await getApplicationSupportDirectory();
    return TabSessionStore(Directory(support.path));
  }

  File get _sessionFile =>
      File('${baseDir.path}${Platform.pathSeparator}tab_session.json');
  File get _exitStateFile =>
      File('${baseDir.path}${Platform.pathSeparator}app_exit_state.json');

  static const int _schema = 1;
  static const Duration _writeTimeout = Duration(seconds: 3);

  // ── 退出标记 ──

  /// 上次运行是否异常退出（未走完 clean 路径）。文件缺失 = 首次/旧版本 → false。
  Future<bool> wasUncleanExit() async {
    try {
      final f = _exitStateFile;
      if (!await f.exists()) return false;
      final body = jsonDecode(await f.readAsString());
      return body is Map<String, dynamic> && body['running'] == true;
    } catch (e) {
      AppLogger.w('TabSessionStore', 'read exit state failed: $e');
      return false;
    }
  }

  /// 启动（恢复判断之后）调用：此刻起进程消失即视为异常退出。
  Future<void> markRunning() async {
    try {
      await _atomicWrite(_exitStateFile, jsonEncode({'running': true}));
    } catch (e) {
      AppLogger.w('TabSessionStore', 'markRunning failed: $e');
    }
  }

  /// 正常退出路径调用：标记已 clean + 清空会话文件（丢弃决定被尊重）。
  Future<void> markCleanExit() async {
    try {
      await _atomicWrite(_exitStateFile, jsonEncode({'running': false}));
      final f = _sessionFile;
      if (await f.exists()) await f.delete();
    } catch (e) {
      AppLogger.w('TabSessionStore', 'markCleanExit failed: $e');
    }
  }

  // ── 会话文件 ──

  Future<void> save(List<QueryTab> tabs, int activeTabIndex) async {
    try {
      final payload = jsonEncode({
        'schema': _schema,
        'savedAt': DateTime.now().toIso8601String(),
        'activeTabIndex': activeTabIndex,
        'tabs': tabs.map(_tabToJson).toList(),
      });
      await _atomicWrite(_sessionFile, payload)
          .timeout(_writeTimeout);
    } catch (e) {
      // 超时（文件被占用等）也只记日志——下次变更会再试。
      AppLogger.w('TabSessionStore', 'save failed: $e');
    }
  }

  /// 读取会话；无文件 / 损坏 / schema 不识别 → null。
  Future<TabSessionSnapshot?> load() async {
    try {
      final f = _sessionFile;
      if (!await f.exists()) return null;
      final body = jsonDecode(await f.readAsString());
      if (body is! Map<String, dynamic>) return null;
      if (body['schema'] is! int || body['schema'] as int > _schema) {
        AppLogger.w('TabSessionStore',
            'unknown session schema ${body['schema']}; ignoring');
        return null;
      }
      final rawTabs = body['tabs'];
      if (rawTabs is! List) return null;
      final tabs = <QueryTab>[];
      for (final item in rawTabs) {
        if (item is! Map<String, dynamic>) continue;
        final tab = _tabFromJson(item);
        if (tab != null) tabs.add(tab);
      }
      final active = body['activeTabIndex'];
      return TabSessionSnapshot(
        tabs: tabs,
        activeTabIndex: active is int ? active : 0,
      );
    } catch (e) {
      AppLogger.w('TabSessionStore', 'load failed (corrupt?): $e');
      return null;
    }
  }

  // ── 瘦序列化 ──

  /// 与 QueryTab.toJson 的差异：**不含** executionResults（结果集太大）与
  /// sessionId（运行态，重启即失效）；恢复时 sessionId 恒为 null。
  static Map<String, dynamic> _tabToJson(QueryTab tab) => {
        'id': tab.id,
        if (tab.savedQueryId != null) 'savedQueryId': tab.savedQueryId,
        'title': tab.title,
        'sql': tab.sql,
        'connectionId': tab.connectionId,
        'databaseName': tab.databaseName,
        'databaseType': tab.databaseType?.name,
        'isSaved': tab.isSaved,
        'isModified': tab.isModified,
        if (tab.originalSql != null) 'originalSql': tab.originalSql,
        'isAutoTitle': tab.isAutoTitle,
      };

  static QueryTab? _tabFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    DatabaseType? dbType;
    final typeName = json['databaseType'] as String?;
    if (typeName != null) {
      try {
        dbType = DatabaseType.values
            .firstWhere((e) => e.name == typeName);
      } catch (_) {
        dbType = null; // 未知类型（跨版本枚举变更）退化为无类型快照
      }
    }
    return QueryTab(
      id: id,
      savedQueryId: json['savedQueryId'] as String?,
      title: title,
      sql: json['sql'] as String? ?? '',
      connectionId: json['connectionId'] as String?,
      databaseName: json['databaseName'] as String?,
      databaseType: dbType,
      isSaved: json['isSaved'] as bool? ?? false,
      isModified: json['isModified'] as bool? ?? false,
      originalSql: json['originalSql'] as String?,
      isAutoTitle: json['isAutoTitle'] as bool? ?? false,
    );
  }

  // ── 原子写（tmp + 替换）──

  Future<void> _atomicWrite(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }
}
