import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ai_memory_item.dart';
import '../../utils/app_logger.dart';

/// AI 记忆服务（跨会话可复用的短事实存储，T3）。
///
/// 存储介质为 SharedPreferences 分键 JSON 数组（裸键先例
/// `query_settings_service.dart`）：
/// - 全局作用域键 `ai_memory_global`；
/// - 连接作用域键 `ai_memory_conn_<connectionId>`。
///
/// 容量纪律照 `audit_log_service.dart` 教训（prefs 整文件全量重写，条数×
/// 单条体积直接决定所有 prefs 写入成本）：
/// - 每作用域上限 [_maxEntriesPerScope] 条，超出按
///   [AiMemoryItem.updatedAt] 淘汰最旧；
/// - 单条 content 截断到 [_maxContentChars] 字符；
/// - 写入防抖 [_persistDebounce]（批量编辑合并为一次全量落盘）；
/// - [initialize] 幂等，读写方法内部自带初始化，调用方无需先显式调用。
///
/// 持久化失败只记日志、不抛出（记忆写失败不应阻断调用方路径，与审计
/// 同策略）；单例全局共享（ConnectionProvider 清理钩子与管理对话框共用
/// 同一份内存态）。
class AiMemoryService {
  static const String _globalKey = 'ai_memory_global';
  static const String _connectionKeyPrefix = 'ai_memory_conn_';

  /// 每作用域条数上限，超出按 updatedAt 淘汰最旧。
  static const int _maxEntriesPerScope = 200;

  /// 单条 content 截断上限（字符数）。
  static const int _maxContentChars = 500;

  /// 写入防抖窗口。
  static const Duration _persistDebounce = Duration(milliseconds: 300);

  // 全局作用域内存态（按 updatedAt 升序维护，队首最旧）。
  final List<AiMemoryItem> _global = <AiMemoryItem>[];

  // 连接作用域内存态（同排序约定），key = connectionId。
  final Map<String, List<AiMemoryItem>> _byConnection =
      <String, List<AiMemoryItem>>{};

  bool _initialized = false;
  Timer? _persistTimer;
  final Set<String> _dirtyKeys = <String>{};
  int _idCounter = 0;

  static final AiMemoryService _instance = AiMemoryService._internal();
  factory AiMemoryService() => _instance;
  AiMemoryService._internal();

  // ==================== 生命周期 ====================

  /// 从 SharedPreferences 加载全部分键（幂等：已初始化时直接返回）。
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _global
        ..clear()
        ..addAll(_loadScope(prefs, _globalKey));
      _byConnection.clear();
      for (final key in prefs.getKeys()) {
        if (key.length <= _connectionKeyPrefix.length ||
            !key.startsWith(_connectionKeyPrefix)) {
          continue;
        }
        _byConnection[key.substring(_connectionKeyPrefix.length)] = _loadScope(
          prefs,
          key,
        );
      }
    } catch (e, st) {
      AppLogger.e('AiMemoryService', 'Failed to load AI memories', e, st);
    } finally {
      _initialized = true;
    }
  }

  // ==================== 读取 ====================

  /// 全局作用域记忆（按 updatedAt 新→旧）。
  List<AiMemoryItem> listGlobal() => _sortedDesc(_global);

  /// 指定连接作用域记忆（按 updatedAt 新→旧）；无记忆返回空列表。
  List<AiMemoryItem> listForConnection(String connectionId) =>
      _sortedDesc(_byConnection[connectionId] ?? const <AiMemoryItem>[]);

  /// 主题命中表名的记忆（供 describe_table 合并消费）。
  ///
  /// 匹配规则（简单匹配）：[AiMemoryItem.subject] 以 `<tableName>.` 开头
  /// 或包含表名，大小写不敏感；subject 为空的记忆不参与匹配。默认搜全局
  /// 作用域；传 [connectionId] 时合并该连接作用域（结果按 updatedAt 新→旧）。
  List<AiMemoryItem> forTable(String tableName, {String? connectionId}) {
    final name = tableName.trim().toLowerCase();
    if (name.isEmpty) return const <AiMemoryItem>[];
    bool matches(AiMemoryItem item) {
      final subject = item.subject?.trim().toLowerCase() ?? '';
      if (subject.isEmpty) return false;
      return subject.startsWith('$name.') || subject.contains(name);
    }

    final result = _global.where(matches).toList();
    if (connectionId != null) {
      result.addAll(
        (_byConnection[connectionId] ?? const <AiMemoryItem>[]).where(matches),
      );
    }
    return result..sort(_byUpdatedAtDesc);
  }

  // ==================== 写入 ====================

  /// 新增一条记忆，返回落库后的条目（id/时间戳由本方法生成）。
  ///
  /// - [scope] 为 [AiMemoryScope.connection] 时 [connectionId] 必填（空/缺
  ///   抛 ArgumentError）；为 global 时忽略传入的 [connectionId]；
  /// - [subject] 去首尾空白后为空视为无主题；
  /// - [content] 去首尾空白后必须非空（否则抛 ArgumentError），写入前
  ///   截断到 [_maxContentChars] 字符；
  /// - id 为时间戳 + 递增序号（`mem_<ms>_<n>`，仿 AuditLogService 防同
  ///   毫秒碰撞）。
  Future<AiMemoryItem> add({
    required AiMemoryScope scope,
    String? connectionId,
    String? subject,
    required String content,
    AiMemorySource source = AiMemorySource.manual,
  }) async {
    await initialize();
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }
    String? connId;
    if (scope == AiMemoryScope.connection) {
      final cid = connectionId?.trim() ?? '';
      if (cid.isEmpty) {
        throw ArgumentError.value(
          connectionId,
          'connectionId',
          'is required for connection-scoped memories',
        );
      }
      connId = cid;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = AiMemoryItem(
      id: 'mem_${now}_${_idCounter++}',
      scope: scope,
      connectionId: connId,
      subject: _normalizeSubject(subject),
      content: _truncateContent(trimmedContent),
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    final key = _keyFor(scope, connId);
    final list = _mutableList(scope, connId)
      ..add(item)
      ..sort(_byUpdatedAtAsc);
    _markDirty(key);
    _evictOldest(list, key);
    return item;
  }

  /// 更新一条记忆（按 [item.id] 在其作用域内寻址；未找到返回 false）。
  ///
  /// content 重新去空白（空内容抛 ArgumentError）并截断，subject 重新
  /// 规范化，updatedAt 刷新为当前时间。
  Future<bool> update(AiMemoryItem item) async {
    await initialize();
    final trimmedContent = item.content.trim();
    if (trimmedContent.isEmpty) {
      throw ArgumentError.value(item.content, 'content', 'must not be blank');
    }
    final list = _mutableList(item.scope, item.connectionId);
    final index = list.indexWhere((m) => m.id == item.id);
    if (index < 0) return false;
    list[index] = item.copyWith(
      subject: _normalizeSubject(item.subject),
      content: _truncateContent(trimmedContent),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    list.sort(_byUpdatedAtAsc);
    _markDirty(_keyFor(item.scope, item.connectionId));
    return true;
  }

  /// 删除一条记忆（按 [item.id] 在其作用域内寻址）；删除了返回 true。
  Future<bool> remove(AiMemoryItem item) async {
    await initialize();
    final list = _mutableList(item.scope, item.connectionId);
    final index = list.indexWhere((m) => m.id == item.id);
    if (index < 0) return false;
    list.removeAt(index);
    _markDirty(_keyFor(item.scope, item.connectionId));
    return true;
  }

  /// 清空某连接的全部连接作用域记忆（连接删除时的清理钩子）。
  ///
  /// 同时覆盖「防抖在途 + 立即删除」交错：内存态先移除、再把该键标记为
  /// 待写并统一落盘——[_itemsForKey] 对已移除的作用域返回 null，落盘为
  /// prefs.remove。失败只记日志、不抛出（不阻断连接删除）。
  Future<void> clearForConnection(String connectionId) async {
    await initialize();
    _byConnection.remove(connectionId);
    _dirtyKeys.add('$_connectionKeyPrefix$connectionId');
    await flush();
  }

  /// 立即落盘所有在途变更；无在途变更时为 no-op。供应用退出前与测试使用。
  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _flushPending();
  }

  // ==================== 内部 ====================

  List<AiMemoryItem> _loadScope(SharedPreferences prefs, String key) {
    final jsonStr = prefs.getString(key);
    if (jsonStr == null || jsonStr.isEmpty) return <AiMemoryItem>[];
    final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
    final items =
        list
            .whereType<Map<String, dynamic>>()
            .map(AiMemoryItem.fromJson)
            .toList()
          ..sort(_byUpdatedAtAsc);
    // 存量修复：加载时超限即按 updatedAt 裁剪回写（防 prefs 无限膨胀）。
    if (items.length > _maxEntriesPerScope) {
      items.removeRange(0, items.length - _maxEntriesPerScope);
      _dirtyKeys.add(key);
      _schedulePersist();
    }
    return items;
  }

  void _markDirty(String key) {
    _dirtyKeys.add(key);
    _schedulePersist();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _flushPending);
  }

  Future<void> _flushPending() async {
    _persistTimer = null;
    if (_dirtyKeys.isEmpty) return;
    final keys = _dirtyKeys.toList();
    _dirtyKeys.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in keys) {
        final items = _itemsForKey(key);
        if (items == null) {
          // 作用域已整体移除（clearForConnection）→ 落盘为删除该键。
          await prefs.remove(key);
        } else {
          await prefs.setString(
            key,
            jsonEncode(items.map((e) => e.toJson()).toList()),
          );
        }
      }
    } catch (e, st) {
      AppLogger.e('AiMemoryService', 'Failed to persist AI memories', e, st);
    }
  }

  void _evictOldest(List<AiMemoryItem> list, String key) {
    var evicted = false;
    while (list.length > _maxEntriesPerScope) {
      // 列表按 updatedAt 升序维护，队首即最旧。
      list.removeAt(0);
      evicted = true;
    }
    if (evicted) _markDirty(key);
  }

  /// 作用域对应的可变内存列表（连接作用域不存在时惰性创建）。
  List<AiMemoryItem> _mutableList(AiMemoryScope scope, String? connectionId) =>
      scope == AiMemoryScope.global
      ? _global
      : _byConnection.putIfAbsent(connectionId ?? '', () => <AiMemoryItem>[]);

  /// 作用域对应的持久化键；作用域已被清空时返回 null。
  List<AiMemoryItem>? _itemsForKey(String key) {
    if (key == _globalKey) return _global;
    if (key.startsWith(_connectionKeyPrefix) &&
        key.length > _connectionKeyPrefix.length) {
      return _byConnection[key.substring(_connectionKeyPrefix.length)];
    }
    return null;
  }

  String _keyFor(AiMemoryScope scope, String? connectionId) =>
      scope == AiMemoryScope.global
      ? _globalKey
      : '$_connectionKeyPrefix${connectionId ?? ''}';

  static String? _normalizeSubject(String? subject) {
    final trimmed = subject?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _truncateContent(String content) {
    if (content.length <= _maxContentChars) return content;
    return content.substring(0, _maxContentChars);
  }

  static int _byUpdatedAtAsc(AiMemoryItem a, AiMemoryItem b) =>
      a.updatedAt.compareTo(b.updatedAt);

  static int _byUpdatedAtDesc(AiMemoryItem a, AiMemoryItem b) =>
      b.updatedAt.compareTo(a.updatedAt);

  static List<AiMemoryItem> _sortedDesc(List<AiMemoryItem> items) =>
      List<AiMemoryItem>.from(items)..sort(_byUpdatedAtDesc);

  // ==================== 测试辅助 ====================

  /// 仅测试：取消在途防抖、清空内存态并复位初始化标记
  /// （下次 [initialize] 从 prefs 重读）。
  @visibleForTesting
  void resetForTesting() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _dirtyKeys.clear();
    _global.clear();
    _byConnection.clear();
    _initialized = false;
    _idCounter = 0;
  }
}
