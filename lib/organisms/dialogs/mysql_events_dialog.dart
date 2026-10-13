// DBT-T18 · MySQL 事件设计器（W-15）—— 浏览 / 查看 DDL / 新建 / 编辑 / 删除。
//
// DDL 写路径（CREATE/ALTER/DROP EVENT = 高风险面）：
// - 每动作独立确认门：新建/编辑 = DDL 预览门（[DestructiveConfirmDialog]
//   extraContent = mono DDL 预览，预览与执行同一 [MysqlEventDdl] 生成函数
//   ——逐字一致，无两处拼装）；删除 = typed confirmation（输入事件名解禁）。
// - 执行经 provider 既有执行面 `dbService.executeQueryBypassDdlDetailed`
//   （工作台双门后 bypass 先例：本预览门即该路径唯一确认门；只读闸门与
//   DML 检查在 detailed 通道内仍生效——CREATE/ALTER/DROP 均在
//   `_isWriteQuery` 关键字面，readonly 连接服务层 fail-closed）。
// - 审计：`AuditLogService.recordQuery`（isWriteQuery: true，成功/失败均落；
//   SQL 脱敏与截断由 recordQuery 内部既有口径处理）；审计写失败不阻塞 UI。
// - `@@event_scheduler` 只读展示（OFF 提示事件不会执行，不做 SET GLOBAL
//   开关——plan §9.6-3 裁定）。
// - DO body 为任意 SQL 文本（不解析不校验语法——引擎自校验，错误原文展示）；
//   标识符/字符串转义沿 [SqlEscapeUtils]（MySQL 反引号方言）；字符串字面量
//   一律 [SqlEscapeUtils.escapeMySqlString]（R1-P1：MySQL 串内反斜杠是转义
//   字符，先 `\`→`\\` 再 `'`→`''`——本 dialog 仅 MySQL 连接可达，无需按方言
//   dispatch）。
// [loader]/[ddlFetcher]/[executor]/[auditor] 为 @visibleForTesting 注入缝
// （SqliteMaintenanceDialog 先例），生产经 [show] 走默认实现。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../molecules/destructive_confirm_dialog.dart';
import '../../providers/app_provider.dart';
import '../../services/audit_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/sql_escape_utils.dart';
import '../connection/error_boundary.dart';

/// 事件调度状态 token（MySQL 语法原样，技术字符串不入 l10n）。
const List<String> kMysqlEventStatusTokens = [
  'ENABLE',
  'DISABLE',
  'DISABLE ON SLAVE',
];

/// EVERY 间隔单位（MySQL INTERVAL_FIELD 关键字）。
const List<String> kMysqlEventIntervalUnits = [
  'SECOND',
  'MINUTE',
  'HOUR',
  'DAY',
  'WEEK',
  'MONTH',
  'QUARTER',
  'YEAR',
];

/// 事件列表行（information_schema.EVENTS 只读投影）。
class MysqlEventEntry {
  final String name;
  final String status;
  final String eventType; // RECURRING / ONE TIME
  final String? intervalValue;
  final String? intervalField;
  final String? executeAt;
  final String? lastExecuted;
  final String? definer;

  const MysqlEventEntry({
    required this.name,
    required this.status,
    required this.eventType,
    this.intervalValue,
    this.intervalField,
    this.executeAt,
    this.lastExecuted,
    this.definer,
  });

  /// 调度列展示串：RECURRING → EVERY n unit；ONE TIME → AT ts。
  String get scheduleDisplay {
    if (eventType.toUpperCase() == 'ONE TIME') {
      return 'AT ${executeAt ?? ''}'.trim();
    }
    final v = (intervalValue ?? '').isEmpty ? '' : ' $intervalValue';
    return 'EVERY$v ${intervalField ?? ''}'.trim();
  }
}

/// 列表快照：事件行 + `@@event_scheduler` 只读状态（ON / OFF）。
class MysqlEventsSnapshot {
  final List<MysqlEventEntry> events;
  final String schedulerState;

  const MysqlEventsSnapshot({required this.events, required this.schedulerState});
}

/// 表单输入（提交时由控制器快照；ALTER 回填由 SHOW CREATE EVENT 反解析）。
class MysqlEventFormInput {
  final String name;
  final String definer; // 空 = 不写 DEFINER 子句（当前用户）；否则 'user@host'
  final String status; // kMysqlEventStatusTokens 之一
  final bool recurring; // true = EVERY，false = AT
  final String everyValue; // EVERY 数值（正整数字符串）
  final String everyUnit; // kMysqlEventIntervalUnits 之一
  final String starts; // 可选 'YYYY-MM-DD HH:MM:SS'
  final String ends; // 可选
  final String atTime; // AT 一次性时间戳（recurring=false 时必填）
  final bool preserve; // ON COMPLETION PRESERVE / NOT PRESERVE
  final String comment; // 可选
  final String doBody; // DO 语句体（原样）

  const MysqlEventFormInput({
    this.name = '',
    this.definer = '',
    this.status = 'ENABLE',
    this.recurring = true,
    this.everyValue = '',
    this.everyUnit = 'MINUTE',
    this.starts = '',
    this.ends = '',
    this.atTime = '',
    this.preserve = false,
    this.comment = '',
    this.doBody = '',
  });

  /// 解析 'user@host' → (user, host)；格式不合法返回 null。
  (String, String)? get definerParts {
    final trimmed = definer.trim();
    if (trimmed.isEmpty) return null;
    final at = trimmed.indexOf('@');
    if (at <= 0 || at != trimmed.lastIndexOf('@')) return null;
    final user = trimmed.substring(0, at);
    final host = trimmed.substring(at + 1);
    if (user.isEmpty || host.isEmpty) return null;
    return (user, host);
  }

  /// 必填校验：名称 / 调度（EVERY 数值或 AT 时间）/ DO body / DEFINER 格式。
  /// 返回首个不合法字段 id（name/every/at/doBody/definer），全部合法为 null。
  String? firstInvalidField() {
    if (name.trim().isEmpty) return 'name';
    final parts = definerParts;
    if (definer.trim().isNotEmpty && parts == null) return 'definer';
    if (recurring) {
      final v = int.tryParse(everyValue.trim());
      if (v == null || v <= 0) return 'every';
    } else {
      if (atTime.trim().isEmpty) return 'at';
    }
    if (doBody.trim().isEmpty) return 'doBody';
    return null;
  }
}

/// DDL 生成与 SHOW CREATE EVENT 反解析（纯函数，预览与执行同源）。
class MysqlEventDdl {
  MysqlEventDdl._();

  /// CREATE EVENT 语句（MySQL 8 语法序：ON SCHEDULE → ON COMPLETION →
  /// ENABLE/DISABLE → COMMENT → DO）。
  static String buildCreate(MysqlEventFormInput input) {
    return [
      'CREATE ${_definerClause(input)}EVENT '
          '${SqlEscapeUtils.escapeMySqlIdentifier(input.name.trim())}',
      '  ON SCHEDULE ${_scheduleClause(input)}',
      '  ON COMPLETION ${input.preserve ? 'PRESERVE' : 'NOT PRESERVE'}',
      '  ${input.status}',
      if (input.comment.trim().isNotEmpty)
        "  COMMENT ${SqlEscapeUtils.escapeMySqlString(input.comment.trim())}",
      '  DO',
      input.doBody.trim(),
    ].join('\n');
  }

  /// ALTER EVENT 语句（[originalName] 为被编辑事件名；表单名变化 → RENAME TO）。
  /// COMMENT 子句恒输出（空串 = 清除注释，忠实反映表单态；CREATE 则省略空注释）。
  static String buildAlter(MysqlEventFormInput input, String originalName) {
    final renamed = input.name.trim() != originalName;
    return [
      'ALTER ${_definerClause(input)}EVENT '
          '${SqlEscapeUtils.escapeMySqlIdentifier(originalName)}',
      '  ON SCHEDULE ${_scheduleClause(input)}',
      '  ON COMPLETION ${input.preserve ? 'PRESERVE' : 'NOT PRESERVE'}',
      if (renamed)
        '  RENAME TO ${SqlEscapeUtils.escapeMySqlIdentifier(input.name.trim())}',
      '  ${input.status}',
      "  COMMENT ${SqlEscapeUtils.escapeMySqlString(input.comment.trim())}",
      '  DO',
      input.doBody.trim(),
    ].join('\n');
  }

  /// DROP EVENT 语句（typed confirmation 已保护，不用 IF EXISTS 掩盖竞态）。
  static String buildDrop(String eventName) =>
      'DROP EVENT ${SqlEscapeUtils.escapeMySqlIdentifier(eventName)}';

  static String _definerClause(MysqlEventFormInput input) {
    final parts = input.definerParts;
    if (parts == null) return '';
    final (user, host) = parts;
    return 'DEFINER=${SqlEscapeUtils.escapeMySqlIdentifier(user)}'
        '@${SqlEscapeUtils.escapeMySqlIdentifier(host)} ';
  }

  static String _scheduleClause(MysqlEventFormInput input) {
    if (!input.recurring) {
      return 'AT ${SqlEscapeUtils.escapeMySqlString(input.atTime.trim())}';
    }
    final buffer = StringBuffer(
      'EVERY ${int.parse(input.everyValue.trim())} ${input.everyUnit}',
    );
    if (input.starts.trim().isNotEmpty) {
      buffer.write(
        ' STARTS ${SqlEscapeUtils.escapeMySqlString(input.starts.trim())}',
      );
    }
    if (input.ends.trim().isNotEmpty) {
      buffer.write(
        ' ENDS ${SqlEscapeUtils.escapeMySqlString(input.ends.trim())}',
      );
    }
    return buffer.toString();
  }

  /// SHOW CREATE EVENT 输出反解析（容错：逐子句游标扫描，解析不到的字段
  /// 留默认空值——调用方提示以原始 DDL 为准手改）。
  static MysqlEventFormInput parseShowCreate(String ddl) {
    final c = _DdlCursor(ddl);
    var definer = '';
    c.skipWs();
    // CREATE / ALTER 头（不匹配也继续，容错）。
    for (final head in const ['CREATE', 'ALTER']) {
      if (c.tryLiteral(head)) break;
    }
    c.skipWs();
    if (c.tryLiteral('DEFINER=')) {
      final user = c.tryIdentifier();
      if (user != null && c.tryLiteral('@')) {
        final host = c.tryIdentifier();
        if (host != null) definer = '$user@$host';
      }
    }
    c.skipWs();
    // 事件名仅在 EVENT 字面量成立时解析（SHOW CREATE EVENT 输出恒反引号；
    // 垃圾输入不吞裸词 → name 留空，字段以默认空值降级）。
    final eventMatched = c.tryLiteral('EVENT');
    c.skipWs();
    final qualified = eventMatched ? c.tryQualifiedIdentifier() : null;
    final name = qualified?.$2 ?? '';

    var recurring = true;
    var everyValue = '';
    var everyUnit = 'MINUTE';
    var starts = '';
    var ends = '';
    var atTime = '';
    c.skipWs();
    if (c.tryLiteral('ON')) {
      c.skipWs();
      c.tryLiteral('SCHEDULE');
      c.skipWs();
      if (c.tryLiteral('AT')) {
        c.skipWs();
        final ts = c.tryQuotedString();
        if (ts != null) {
          recurring = false;
          atTime = ts;
        }
        // `AT ts + INTERVAL …` 复合形态不支持反解析 → 调度字段留空手改。
      } else if (c.tryLiteral('EVERY')) {
        c.skipWs();
        final value = c.tryWord();
        if (value != null) everyValue = value;
        c.skipWs();
        final unit = c.tryWord();
        if (unit != null) everyUnit = unit.toUpperCase();
        c.skipWs();
        if (c.tryLiteral('STARTS')) {
          c.skipWs();
          starts = c.tryQuotedString() ?? '';
          c.skipWs();
        }
        if (c.tryLiteral('ENDS')) {
          c.skipWs();
          ends = c.tryQuotedString() ?? '';
          c.skipWs();
        }
      }
    }

    var preserve = false;
    c.skipWs();
    if (c.tryLiteral('ON')) {
      c.skipWs();
      c.tryLiteral('COMPLETION');
      c.skipWs();
      // NOT PRESERVE → preserve=false；PRESERVE → true（NOT 在前需取反）。
      final notSeen = c.tryLiteral('NOT');
      c.skipWs();
      preserve = c.tryLiteral('PRESERVE') && !notSeen;
      c.skipWs();
    }

    var status = 'ENABLE';
    if (c.tryLiteral('DISABLE ON SLAVE')) {
      status = 'DISABLE ON SLAVE';
    } else if (c.tryLiteral('DISABLE')) {
      status = 'DISABLE';
    } else {
      c.tryLiteral('ENABLE');
    }
    c.skipWs();

    var comment = '';
    if (c.tryLiteral('COMMENT')) {
      c.skipWs();
      comment = c.tryQuotedString() ?? '';
      c.skipWs();
    }

    var doBody = '';
    c.skipWs();
    if (c.tryLiteral('DO')) {
      doBody = c.rest().trim();
    }

    return MysqlEventFormInput(
      name: name,
      definer: definer,
      status: status,
      recurring: recurring,
      everyValue: everyValue,
      everyUnit: everyUnit,
      starts: starts,
      ends: ends,
      atTime: atTime,
      preserve: preserve,
      comment: comment,
      doBody: doBody,
    );
  }
}

/// SHOW CREATE EVENT 反解析游标（大小写不敏感字面量 + 引号串/标识符解析）。
class _DdlCursor {
  final String _src;
  int _pos = 0;

  _DdlCursor(this._src);

  void skipWs() {
    while (_pos < _src.length && (_src.codeUnitAt(_pos) == 0x20 ||
        _src.codeUnitAt(_pos) == 0x09 ||
        _src.codeUnitAt(_pos) == 0x0A ||
        _src.codeUnitAt(_pos) == 0x0D)) {
      _pos++;
    }
  }

  bool tryLiteral(String token) {
    skipWs();
    final lower = _src.substring(_pos).toLowerCase();
    final t = token.toLowerCase();
    if (!lower.startsWith(t)) return false;
    // 词边界：字面量后不得紧跟标识符字符（避免 EVERY 匹配 EVERYTHING）。
    final next = _pos + t.length;
    if (next < _src.length) {
      final ch = _src[next];
      final isWordChar = ch == '_' || ch == r'$' ||
          (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) ||
          ch.toLowerCase() != ch.toUpperCase();
      if (isWordChar) return false;
    }
    _pos = next;
    return true;
  }

  /// 反引号标识符或裸词；不匹配返回 null。
  String? tryIdentifier() {
    skipWs();
    if (_pos >= _src.length) return null;
    if (_src.codeUnitAt(_pos) == 0x60) {
      final end = _src.indexOf('`', _pos + 1);
      if (end < 0) return null;
      final name = _src.substring(_pos + 1, end);
      _pos = end + 1;
      return name;
    }
    return tryWord();
  }

  /// `db`.`name` 限定标识符 → (db, name)；单标识符 → (null, name)。
  (String?, String)? tryQualifiedIdentifier() {
    final first = tryIdentifier();
    if (first == null) return null;
    skipWs();
    final beforeDot = _pos;
    if (_pos < _src.length && _src.codeUnitAt(_pos) == 0x2E) {
      _pos++;
      final second = tryIdentifier();
      if (second != null) return (first, second);
      _pos = beforeDot;
    }
    return (null, first);
  }

  /// 裸词（[A-Za-z0-9_$]+）；立即返回（无需词边界判断）。
  String? tryWord() {
    skipWs();
    final start = _pos;
    while (_pos < _src.length) {
      final ch = _src[_pos];
      final ok = ch == '_' || ch == r'$' ||
          (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) ||
          (ch.toLowerCase() != ch.toUpperCase());
      if (!ok) break;
      _pos++;
    }
    if (_pos == start) return null;
    return _src.substring(start, _pos);
  }

  /// 单引号字符串（'' 转义还原）；不匹配返回 null。
  String? tryQuotedString() {
    skipWs();
    if (_pos >= _src.length || _src.codeUnitAt(_pos) != 0x27) return null;
    final buffer = StringBuffer();
    var i = _pos + 1;
    while (i < _src.length) {
      if (_src.codeUnitAt(i) == 0x27) {
        if (i + 1 < _src.length && _src.codeUnitAt(i + 1) == 0x27) {
          buffer.write("'");
          i += 2;
          continue;
        }
        _pos = i + 1;
        return buffer.toString();
      }
      buffer.write(_src[i]);
      i++;
    }
    return null;
  }

  String rest() => _src.substring(_pos < _src.length ? _pos : _src.length);
}

/// 列表取数注入缝（默认 = information_schema.EVENTS + @@event_scheduler，
/// 均经 dbService 只读执行面）。
typedef MysqlEventsLoader =
    Future<MysqlEventsSnapshot> Function(String connectionId, String databaseName);

/// SHOW CREATE EVENT 取 DDL 注入缝（默认 = dbService 只读执行面）。
typedef MysqlEventDdlFetcher =
    Future<String> Function(String connectionId, String databaseName, String eventName);

/// DDL 执行注入缝（默认 = dbService.executeQueryBypassDdlDetailed）。
typedef MysqlEventDdlExecutor =
    Future<void> Function(
      AppProvider provider,
      String connectionId,
      String databaseName,
      String sql,
    );

/// 事件 DDL 审计载荷（recordQuery 口径子集；测试断言面）。
typedef MysqlEventAuditRecord =
    ({
      String connectionId,
      String databaseName,
      String sql,
      Duration executionTime,
      bool success,
      String? errorMessage,
    });

/// 审计器注入缝：默认落 AuditLogService，测试注入 mock。
typedef MysqlEventAuditor = Future<void> Function(MysqlEventAuditRecord record);

/// 默认审计器：先 initialize；SQL 脱敏与截断由 recordQuery 内部处理。
Future<void> _auditEventDdl(MysqlEventAuditRecord record) async {
  final audit = AuditLogService();
  await audit.initialize();
  audit.recordQuery(
    connectionId: record.connectionId,
    databaseName: record.databaseName,
    sql: record.sql,
    executionTime: record.executionTime,
    success: record.success,
    errorMessage: record.errorMessage,
    isWriteQuery: true,
  );
}

/// MySQL 事件设计器对话框（浏览 + CREATE/ALTER/DROP EVENT，任务书 T18）。
class MysqlEventsDialog extends StatefulWidget {
  final String connectionId;
  final String databaseName;

  @visibleForTesting
  final MysqlEventsLoader? loader;

  @visibleForTesting
  final MysqlEventDdlFetcher? ddlFetcher;

  @visibleForTesting
  final MysqlEventDdlExecutor? executor;

  @visibleForTesting
  final MysqlEventAuditor? auditor;

  const MysqlEventsDialog({
    super.key,
    required this.connectionId,
    required this.databaseName,
    this.loader,
    this.ddlFetcher,
    this.executor,
    this.auditor,
  });

  static Future<void> show(
    BuildContext context, {
    required String connectionId,
    required String databaseName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MysqlEventsDialog(
        connectionId: connectionId,
        databaseName: databaseName,
      ),
    );
  }

  @override
  State<MysqlEventsDialog> createState() => _MysqlEventsDialogState();
}

class _MysqlEventsDialogState extends State<MysqlEventsDialog> {
  bool _loading = true;
  Object? _error;
  MysqlEventsSnapshot? _snapshot;
  bool _running = false;
  late final bool _readOnly;

  @override
  void initState() {
    super.initState();
    // 入口禁用面（UX 收口）：服务层 `_isWriteQuery` × `server.readOnly`
    // 闸门才是硬保证（CREATE/ALTER/DROP 关键字 fail-closed）。
    _readOnly = _resolveReadOnly(context.read<AppProvider>(), widget.connectionId);
    _load();
  }

  static bool _resolveReadOnly(AppProvider provider, String connectionId) {
    for (final server in provider.savedConnections) {
      if (server.id == connectionId) {
        return server.readOnly;
      }
    }
    return false;
  }

  /// 默认取数：information_schema.EVENTS 全列投影 + @@event_scheduler
  /// （两条只读 SELECT，均经 dbService 既有执行面）。
  Future<MysqlEventsSnapshot> _defaultLoad(
    AppProvider provider,
    String connectionId,
    String databaseName,
  ) async {
    final rows = await provider.dbService.executeQuery(
      'SELECT EVENT_NAME, STATUS, EVENT_TYPE, INTERVAL_VALUE, INTERVAL_FIELD, '
      'EXECUTE_AT, LAST_EXECUTED, DEFINER '
      'FROM information_schema.EVENTS '
      "WHERE EVENT_SCHEMA = ${SqlEscapeUtils.escapeMySqlString(databaseName)} "
      'ORDER BY EVENT_NAME',
      connectionId: connectionId,
    );
    var schedulerState = '';
    try {
      final sched = await provider.dbService.executeQuery(
        'SELECT @@event_scheduler',
        connectionId: connectionId,
      );
      if (sched.isNotEmpty && sched.first.values.isNotEmpty) {
        schedulerState = sched.first.values.first?.toString() ?? '';
      }
    } catch (e) {
      // 调度器探测失败不阻断列表（提示行仅在确知 OFF 时展示）。
      AppLogger.w('MysqlEventsDialog', 'read @@event_scheduler failed: $e');
    }
    return MysqlEventsSnapshot(
      schedulerState: schedulerState,
      events: [
        for (final row in rows)
          MysqlEventEntry(
            name: _rowStr(row, 'EVENT_NAME'),
            status: _rowStr(row, 'STATUS'),
            eventType: _rowStr(row, 'EVENT_TYPE'),
            intervalValue: _rowStr(row, 'INTERVAL_VALUE'),
            intervalField: _rowStr(row, 'INTERVAL_FIELD'),
            executeAt: _rowStr(row, 'EXECUTE_AT'),
            lastExecuted: _rowStr(row, 'LAST_EXECUTED'),
            definer: _rowStr(row, 'DEFINER'),
          ),
      ],
    );
  }

  /// 网关/本地行键大小写归一取值（SHOW/IS 查询行键形态不一双保险）。
  static String? _rowStrOrNull(Map<String, dynamic> row, String key) {
    final direct = row[key];
    if (direct != null) return direct.toString();
    final lower = key.toLowerCase();
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value?.toString();
      }
    }
    return null;
  }

  static String _rowStr(Map<String, dynamic> row, String key) =>
      _rowStrOrNull(row, key) ?? '';

  /// 默认 SHOW CREATE EVENT 取 DDL（限定名避免依赖当前库上下文）。
  Future<String> _defaultFetchDdl(
    AppProvider provider,
    String connectionId,
    String databaseName,
    String eventName,
  ) async {
    final qualified =
        '${SqlEscapeUtils.escapeMySqlIdentifier(databaseName)}.'
        '${SqlEscapeUtils.escapeMySqlIdentifier(eventName)}';
    final rows = await provider.dbService.executeQuery(
      'SHOW CREATE EVENT $qualified',
      connectionId: connectionId,
    );
    if (rows.isEmpty) {
      throw Exception('Event not found: $eventName');
    }
    final row = rows.first;
    // 列名 'Create Event'（大小写归一匹配；取不到时回退最长字符串列）。
    for (final entry in row.entries) {
      if (entry.key.toLowerCase().replaceAll(' ', '') == 'createevent') {
        return entry.value?.toString() ?? '';
      }
    }
    String? longest;
    for (final value in row.values) {
      final s = value?.toString();
      if (s != null && (longest == null || s.length > longest.length)) {
        longest = s;
      }
    }
    return longest ?? '';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<AppProvider>();
      final load = widget.loader ??
          (cid, db) => _defaultLoad(provider, cid, db);
      final snapshot = await load(widget.connectionId, widget.databaseName);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('MysqlEventsDialog', 'load events failed', e);
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// 共享执行链：预览门已过 → bypass 执行 → 审计（成败均落）→ 刷新列表。
  Future<bool> _executeDdl(String sql, {required String actionLabel}) async {
    final provider = context.read<AppProvider>();
    final execute = widget.executor ??
        (prov, cid, db, ddl) => prov.dbService.executeQueryBypassDdlDetailed(
              ddl,
              connectionId: cid,
              database: db,
            );
    final audit = widget.auditor ?? _auditEventDdl;
    final stopwatch = Stopwatch()..start();
    try {
      await execute(provider, widget.connectionId, widget.databaseName, sql);
      stopwatch.stop();
      await _auditQuietly(
        audit,
        (
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          sql: sql,
          executionTime: stopwatch.elapsed,
          success: true,
          errorMessage: null,
        ),
      );
      return true;
    } catch (e) {
      stopwatch.stop();
      await _auditQuietly(
        audit,
        (
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          sql: sql,
          executionTime: stopwatch.elapsed,
          success: false,
          errorMessage: e.toString(),
        ),
      );
      if (!mounted) return false;
      final l10n = AppLocalizations.of(context)!;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.maintenanceFailed(actionLabel, e.toString()),
      );
      return false;
    }
  }

  /// 审计写失败不阻塞 UI（AppLogger 记录，任务书边界条款）。
  Future<void> _auditQuietly(
    MysqlEventAuditor audit,
    MysqlEventAuditRecord record,
  ) async {
    try {
      await audit(record);
    } catch (e) {
      AppLogger.e('MysqlEventsDialog', 'audit write failed', e);
    }
  }

  Future<void> _openCreateForm() async {
    final l10n = AppLocalizations.of(context)!;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MysqlEventFormDialog(
        title: l10n.mysqlEventsNew,
        originalName: null,
        input: const MysqlEventFormInput(),
        executeDdl: _executeDdl,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _openEditForm(MysqlEventEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    setState(() => _running = true);
    String? ddl;
    try {
      final fetch = widget.ddlFetcher ??
          (cid, db, name) => _defaultFetchDdl(provider, cid, db, name);
      ddl = await fetch(widget.connectionId, widget.databaseName, entry.name);
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.maintenanceFailed(l10n.mysqlEventsEdit(entry.name), e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
    if (ddl == null || !mounted) return;

    final edited = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MysqlEventFormDialog(
        title: l10n.mysqlEventsEdit(entry.name),
        originalName: entry.name,
        // ddl 已取到（上方非空判定），非空解包成立。
        input: MysqlEventDdl.parseShowCreate(ddl!),
        sourceDdl: ddl,
        executeDdl: _executeDdl,
      ),
    );
    if (edited == true) await _load();
  }

  Future<void> _dropEvent(MysqlEventEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final sql = MysqlEventDdl.buildDrop(entry.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DestructiveConfirmDialog(
        icon: LucideIcons.trash2,
        title: l10n.mysqlEventsDrop,
        impactDescription: l10n.mysqlEventsDropConfirm(entry.name),
        impactTone: DestructiveTone.error,
        confirmLabel: l10n.commonConfirm,
        requireTypedConfirmation: entry.name,
        contentWidth: 480,
        onConfirm: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _running = true);
    try {
      final ok = await _executeDdl(sql, actionLabel: l10n.mysqlEventsDrop);
      if (ok && mounted) await _load();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _viewDdl(MysqlEventEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    setState(() => _running = true);
    try {
      final fetch = widget.ddlFetcher ??
          (cid, db, name) => _defaultFetchDdl(provider, cid, db, name);
      final ddl =
          await fetch(widget.connectionId, widget.databaseName, entry.name);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _MysqlEventDdlViewDialog(eventName: entry.name, ddl: ddl),
      );
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('MysqlEventsDialog', 'SHOW CREATE EVENT failed', e);
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.maintenanceFailed(l10n.viewTableDdl, e.toString()),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return PopScope(
      // DDL 执行 / 取 DDL 在途禁止关闭（R4-d 先例：半途关窗留不可见在途命令）。
      canPop: !_running,
      child: AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.calendarClock, size: 20, color: colors.accentBlue),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text('${l10n.mysqlEventsTitle} · ${widget.databaseName}'),
            ),
          ],
        ),
        content: SizedBox(
          width: 760,
          height: 520,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError(l10n, colors)
                  : _buildBody(l10n, colors),
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppLocalizations l10n, ThemeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.triangleAlert, size: 28, color: colors.error),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.maintenanceFailed(l10n.mysqlEventsTitle, _error.toString()),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          TextButton.icon(
            onPressed: _running ? null : _load,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ThemeColors colors) {
    final snapshot = _snapshot;
    final events = snapshot?.events ?? const <MysqlEventEntry>[];
    // R1-P3-5：探测失败/空值（schedulerState 为空）不误报——仅确知非 ON
    // 才提示「调度器未开启」。
    final schedulerState = snapshot?.schedulerState.trim() ?? '';
    final schedulerOff =
        schedulerState.isNotEmpty && schedulerState.toUpperCase() != 'ON';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (schedulerOff)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
            child: Row(
              children: [
                Icon(LucideIcons.triangleAlert,
                    size: 14, color: colors.warning),
                const SizedBox(width: AppDesignSystem.space1),
                Expanded(
                  child: Text(
                    l10n.mysqlEventsSchedulerOff,
                    style: TextStyle(fontSize: 12, color: colors.warning),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: (_readOnly || _running) ? null : _openCreateForm,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(l10n.mysqlEventsNew),
            ),
            if (_readOnly)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppDesignSystem.space2),
                  child: Text(
                    l10n.readOnlyModeBlocked,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
              )
            else
              const Spacer(),
            IconButton(
              tooltip: l10n.commonRefresh,
              onPressed: _running ? null : _load,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space2),
        if (events.isEmpty)
          Expanded(child: _buildEmpty(l10n, colors))
        else
          Expanded(child: _buildList(l10n, colors, events)),
      ],
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, ThemeColors colors) {
    return Center(
      child: Text(
        l10n.mysqlEventsEmpty,
        style: TextStyle(color: colors.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _buildList(
    AppLocalizations l10n,
    ThemeColors colors,
    List<MysqlEventEntry> events,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _headerCell(l10n.mysqlEventsColName, colors),
              ),
              Expanded(
                flex: 1,
                child: _headerCell(l10n.mysqlEventsColStatus, colors),
              ),
              Expanded(
                flex: 1,
                child: _headerCell(l10n.mysqlEventsColType, colors),
              ),
              Expanded(
                flex: 2,
                child: _headerCell(l10n.mysqlEventsColSchedule, colors),
              ),
              Expanded(
                flex: 2,
                child: _headerCell(l10n.mysqlEventsColLastExecuted, colors),
              ),
              Expanded(
                flex: 2,
                child: _headerCell(l10n.mysqlEventsColDefiner, colors),
              ),
              SizedBox(
                width: 120,
                child: _headerCell(l10n.commonEdit, colors, visible: false),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: events.length,
            itemExtent: 32,
            itemBuilder: (context, index) => _buildRow(
              l10n,
              colors,
              events[index],
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text, ThemeColors colors, {bool visible = true}) {
    if (!visible) return const SizedBox.shrink();
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: colors.textMuted,
      ),
    );
  }

  Widget _buildRow(
    AppLocalizations l10n,
    ThemeColors colors,
    MysqlEventEntry entry,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _cell(entry.name, colors, mono: true, strong: true),
          ),
          Expanded(flex: 1, child: _cell(entry.status, colors)),
          Expanded(flex: 1, child: _cell(entry.eventType, colors)),
          Expanded(flex: 2, child: _cell(entry.scheduleDisplay, colors)),
          Expanded(
            flex: 2,
            child: _cell(
              entry.lastExecuted?.isNotEmpty == true
                  ? entry.lastExecuted!
                  : '—',
              colors,
            ),
          ),
          Expanded(flex: 2, child: _cell(entry.definer ?? '—', colors)),
          SizedBox(
            width: 120,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _rowAction(
                  l10n.viewTableDdl,
                  LucideIcons.eye,
                  _running ? null : () => _viewDdl(entry),
                ),
                _rowAction(
                  l10n.commonEdit,
                  LucideIcons.pencil,
                  (_readOnly || _running) ? null : () => _openEditForm(entry),
                ),
                _rowAction(
                  l10n.mysqlEventsDrop,
                  LucideIcons.trash2,
                  (_readOnly || _running) ? null : () => _dropEvent(entry),
                  destructive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowAction(
    String tooltip,
    IconData icon,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) {
    final colors = context.themeColors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 14,
        color: destructive ? colors.error : colors.textSecondary,
      ),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _cell(
    String text,
    ThemeColors colors, {
    bool mono = false,
    bool strong = false,
  }) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        fontFamily:
            mono ? AppDesignSystem.monoFontFamily : null,
        fontFamilyFallback:
            mono ? AppDesignSystem.monoFontFamilyFallback : null,
        color: strong ? colors.textPrimary : colors.textSecondary,
      ),
    );
  }
}

/// 事件 DDL 只读查看（mono SelectableText；选中即复制路径）。
class _MysqlEventDdlViewDialog extends StatelessWidget {
  final String eventName;
  final String ddl;

  const _MysqlEventDdlViewDialog({required this.eventName, required this.ddl});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.eye, size: 18, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(child: Text(l10n.viewTableDdl)),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eventName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            const Divider(height: 1),
            const SizedBox(height: AppDesignSystem.space2),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDesignSystem.space3),
                decoration: BoxDecoration(
                  color: colors.bgTertiary,
                  borderRadius:
                      BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    ddl,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      fontFamily: AppDesignSystem.monoFontFamily,
                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
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
}

/// 新建/编辑表单（提交 → DDL 预览门 → 执行 → 审计；返回 true = 已执行）。
class _MysqlEventFormDialog extends StatefulWidget {
  final String title;
  final String? originalName; // null = 新建；非空 = 编辑（RENAME 判据）
  final MysqlEventFormInput input;
  final String? sourceDdl; // 编辑模式原始 DDL 展示（以 DDL 为准手改提示）
  final Future<bool> Function(String sql, {required String actionLabel})
  executeDdl;

  const _MysqlEventFormDialog({
    required this.title,
    required this.originalName,
    required this.input,
    required this.executeDdl,
    this.sourceDdl,
  });

  @override
  State<_MysqlEventFormDialog> createState() => _MysqlEventFormDialogState();
}

class _MysqlEventFormDialogState extends State<_MysqlEventFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _definer;
  late final TextEditingController _everyValue;
  late final TextEditingController _starts;
  late final TextEditingController _ends;
  late final TextEditingController _atTime;
  late final TextEditingController _comment;
  late final TextEditingController _doBody;
  late String _status;
  late bool _recurring;
  late String _everyUnit;
  late bool _preserve;
  bool _submitted = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    final input = widget.input;
    _name = TextEditingController(text: input.name);
    // 编辑模式不回填 DEFINER：ALTER EVENT 省略 DEFINER 子句 = 保持原
    // definer 不变（重申子句需相应权限，非属主常见 1227/1449 失败面）；
    // 原 definer 经 sourceDdl 原文展示供参照。新建模式沿用输入值。
    _definer = TextEditingController(
      text: widget.originalName == null ? input.definer : '',
    );
    _everyValue = TextEditingController(text: input.everyValue);
    _starts = TextEditingController(text: input.starts);
    _ends = TextEditingController(text: input.ends);
    _atTime = TextEditingController(text: input.atTime);
    _comment = TextEditingController(text: input.comment);
    _doBody = TextEditingController(text: input.doBody);
    _status = kMysqlEventStatusTokens.contains(input.status)
        ? input.status
        : 'ENABLE';
    _recurring = input.recurring;
    _everyUnit = kMysqlEventIntervalUnits.contains(input.everyUnit)
        ? input.everyUnit
        : 'MINUTE';
    _preserve = input.preserve;
  }

  @override
  void dispose() {
    _name.dispose();
    _definer.dispose();
    _everyValue.dispose();
    _starts.dispose();
    _ends.dispose();
    _atTime.dispose();
    _comment.dispose();
    _doBody.dispose();
    super.dispose();
  }

  MysqlEventFormInput _snapshotInput() => MysqlEventFormInput(
        name: _name.text,
        definer: _definer.text,
        status: _status,
        recurring: _recurring,
        everyValue: _everyValue.text,
        everyUnit: _everyUnit,
        starts: _starts.text,
        ends: _ends.text,
        atTime: _atTime.text,
        preserve: _preserve,
        comment: _comment.text,
        doBody: _doBody.text,
      );

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final input = _snapshotInput();
    final l10n = AppLocalizations.of(context)!;
    if (input.firstInvalidField() != null) return;

    final originalName = widget.originalName;
    // 单一生成函数：预览与执行逐字一致（无假保存铁律①——预览即所执行）。
    final sql = originalName == null
        ? MysqlEventDdl.buildCreate(input)
        : MysqlEventDdl.buildAlter(input, originalName);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DestructiveConfirmDialog(
        icon: LucideIcons.calendarClock,
        title: widget.title,
        impactTone: DestructiveTone.warning,
        confirmLabel: l10n.commonConfirm,
        contentWidth: 620,
        extraContent: _ddlPreview(context, sql),
        onConfirm: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _running = true);
    try {
      final ok = await widget.executeDdl(sql, actionLabel: widget.title);
      if (!mounted) return;
      if (ok) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.calendarClock, size: 20, color: colors.accentBlue),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(child: Text(widget.title)),
          ],
        ),
        content: SizedBox(
          width: 620,
          height: 600,
          child: SingleChildScrollView(child: _buildForm(l10n, colors)),
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('mysql_event_form_save'),
            onPressed: _running ? null : _submit,
            child: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n, ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.sourceDdl != null) ...[
          _sourceDdlBox(l10n, colors),
          const SizedBox(height: AppDesignSystem.space3),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _textField(
                fieldKey: const Key('mysql_event_field_name'),
                controller: _name,
                label: l10n.mysqlEventsColName,
                errorText:
                    _submitted && _name.text.trim().isEmpty
                        ? l10n.commonRequired
                        : null,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: _textField(
                fieldKey: const Key('mysql_event_field_definer'),
                controller: _definer,
                label: l10n.mysqlEventsColDefiner,
                hintText: 'user@host',
                errorText: _definerError(l10n),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space3),
        Row(
          children: [
            Expanded(
              child: _dropdownField<String>(
                label: l10n.mysqlEventsStatus,
                value: _status,
                items: kMysqlEventStatusTokens,
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: _dropdownField<String>(
                label: l10n.mysqlEventsOnCompletion,
                value: _preserve ? 'PRESERVE' : 'NOT PRESERVE',
                items: const ['NOT PRESERVE', 'PRESERVE'],
                onChanged: (v) =>
                    setState(() => _preserve = v == 'PRESERVE'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space3),
        Text(
          l10n.mysqlEventsSchedule,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        _buildScheduleFields(l10n),
        const SizedBox(height: AppDesignSystem.space3),
        _textField(
          fieldKey: const Key('mysql_event_field_comment'),
          controller: _comment,
          label: l10n.mysqlEventsComment,
        ),
        const SizedBox(height: AppDesignSystem.space3),
        _textField(
          fieldKey: const Key('mysql_event_field_do_body'),
          controller: _doBody,
          label: l10n.mysqlEventsDoBody,
          minLines: 4,
          mono: true,
          errorText: _submitted && _doBody.text.trim().isEmpty
              ? l10n.commonRequired
              : null,
        ),
      ],
    );
  }

  String? _definerError(AppLocalizations l10n) {
    if (!_submitted) return null;
    if (_definer.text.trim().isEmpty) return null;
    return _snapshotInput().definerParts == null
        ? l10n.commonInvalidIdentifier
        : null;
  }

  Widget _buildScheduleFields(AppLocalizations l10n) {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: true,
              label: Text(l10n.mysqlEventsEvery),
            ),
            ButtonSegment(
              value: false,
              label: Text(l10n.mysqlEventsAt),
            ),
          ],
          selected: {_recurring},
          onSelectionChanged: (s) => setState(() => _recurring = s.first),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        if (_recurring) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _textField(
                  fieldKey: const Key('mysql_event_field_every_value'),
                  controller: _everyValue,
                  label: l10n.mysqlEventsEvery,
                  errorText: _everyError(l10n),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                flex: 3,
                child: _dropdownField<String>(
                  label: '',
                  value: _everyUnit,
                  items: kMysqlEventIntervalUnits,
                  onChanged: (v) =>
                      setState(() => _everyUnit = v ?? _everyUnit),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _textField(
                  fieldKey: const Key('mysql_event_field_starts'),
                  controller: _starts,
                  label: l10n.mysqlEventsStarts,
                  hintText: 'YYYY-MM-DD HH:MM:SS',
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: _textField(
                  fieldKey: const Key('mysql_event_field_ends'),
                  controller: _ends,
                  label: l10n.mysqlEventsEnds,
                  hintText: 'YYYY-MM-DD HH:MM:SS',
                ),
              ),
            ],
          ),
        ] else
          _textField(
            fieldKey: const Key('mysql_event_field_at'),
            controller: _atTime,
            label: l10n.mysqlEventsAt,
            hintText: 'YYYY-MM-DD HH:MM:SS',
            errorText: _submitted && _atTime.text.trim().isEmpty
                ? l10n.commonRequired
                : null,
          ),
        if (_recurring && _starts.text.trim().isNotEmpty &&
            _ends.text.trim().isNotEmpty &&
            _ends.text.trim().compareTo(_starts.text.trim()) < 0)
          Padding(
            padding: const EdgeInsets.only(top: AppDesignSystem.space1),
            child: Text(
              '${l10n.mysqlEventsEnds} < ${l10n.mysqlEventsStarts}',
              style: TextStyle(fontSize: 11, color: colors.warning),
            ),
          ),
      ],
    );
  }

  String? _everyError(AppLocalizations l10n) {
    if (!_submitted || !_recurring) return null;
    final v = int.tryParse(_everyValue.text.trim());
    if (v == null || v <= 0) return l10n.commonRequired;
    return null;
  }

  /// 编辑模式：SHOW CREATE EVENT 原文（mono 只读；反解析失败以它为准手改）。
  Widget _sourceDdlBox(AppLocalizations l10n, ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mysqlEventsDdlPreview,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 120),
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              widget.sourceDdl ?? '',
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 确认门内 DDL 预览块（mono SelectableText，与执行语句同一字符串）。
  Widget _ddlPreview(BuildContext context, String sql) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.mysqlEventsDdlPreview,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              sql,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    String? errorText,
    int minLines = 1,
    bool mono = false,
    Key? fieldKey,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      minLines: minLines,
      maxLines: minLines == 1 ? 1 : 10,
      style: TextStyle(
        fontSize: 12,
        fontFamily:
            mono ? AppDesignSystem.monoFontFamily : null,
        fontFamilyFallback:
            mono ? AppDesignSystem.monoFontFamilyFallback : null,
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: label.isEmpty ? null : label,
        hintText: hintText,
        errorText: errorText,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      isEmpty: false,
      decoration: InputDecoration(
        isDense: true,
        labelText: label.isEmpty ? null : label,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(value: item, child: Text(item.toString())),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
