// T20（W-17）· Redis 备份与持久化 —— RDB 状态只读区 + BGSAVE 触发。
//
// Redis 运维小闭环（「还原」半项不做，plan §5-13）：
// - 状态区只读（零 Timer/零轮询，沿 2b.1 observe 先例）：INFO persistence
//   五字段 + LASTSAVE unix 时间格式化 + 手动刷新 + 「最后更新于」时间戳
//   （复用既有 workbenchObserveLastUpdated key——ARB 由 T22 冻结，本批不碰）；
// - CONFIG GET `save`/`dir`/`dbfilename` 子区（可选增强）：CONFIG 为
//   dangerous 级 → readonly 连接被 adapter 守卫拦截/取数失败 → 子区隐藏
//   降级 + AppLogger，主状态区不受影响；
// - BGSAVE 触发（服务器写操作 ◆）：DestructiveConfirmDialog（warning
//   tone；影响说明 = fork 内存翻倍 + 生产低峰建议 + 当前变更数；明示目标
//   实例）→ dbService.triggerRedisBgsave（readonly 由 adapter runCommand
//   首行 guardReadOnlyQuery fail-closed 拦截，服务层零新增拦截面）→ 成功
//   snackbar + 状态区刷新 + recordQuery 审计（isWriteQuery:true，SQL 过
//   AuditSqlSanitizer 既有口径）；
// - 只读连接 → BGSAVE 入口禁用（连接事实 from provider.savedConnections）；
// - BGSAVE 进行中（rdb_bgsave_in_progress=1）→ 触发按钮禁用 + 状态提示；
// - **SAVE（同步阻塞）任何入口不出现**；不做 CONFIG SET。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../molecules/destructive_confirm_dialog.dart';
import '../../providers/app_provider.dart';
import '../../services/audit_log_service.dart';
import '../../services/readonly_guard.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../connection/error_boundary.dart';

/// 状态载荷加载接缝：默认 dbService.getRedisPersistenceInfo（生产路径），
/// 测试注入计数。
typedef RedisPersistenceLoader =
    Future<Map<String, String>> Function(String connectionId);

/// CONFIG 读取接缝：默认 dbService.getRedisConfig（dangerous 级，readonly
/// 连接被 adapter 守卫拦截 → 子区隐藏降级）。测试注入。
typedef RedisConfigLoader =
    Future<Map<String, String>> Function(String connectionId);

/// BGSAVE 触发接缝：默认 dbService.triggerRedisBgsave。测试注入计数。
typedef RedisBgsaveTrigger = Future<String> Function(String connectionId);

/// BGSAVE 审计载荷（recordQuery 口径子集；测试断言面）。
typedef RedisBackupAuditRecord =
    ({
      String connectionId,
      String sql,
      Duration executionTime,
      bool success,
      String? errorMessage,
    });

/// 审计器接缝：默认落 AuditLogService，测试注入 mock。
typedef RedisBackupAuditor = Future<void> Function(RedisBackupAuditRecord record);

/// 默认审计器：BGSAVE 事件落 AuditLogService（先 initialize；SQL 脱敏与
/// 截断由 recordQuery 内部既有口径处理；isWriteQuery:true）。
Future<void> _auditBgsave(RedisBackupAuditRecord record) async {
  final audit = AuditLogService();
  await audit.initialize();
  audit.recordQuery(
    connectionId: record.connectionId,
    sql: record.sql,
    executionTime: record.executionTime,
    success: record.success,
    errorMessage: record.errorMessage,
    isWriteQuery: true,
  );
}

/// Redis 备份与持久化对话框（W-17：RDB 状态只读区 + BGSAVE 确认门 + 审计）。
///
/// [loadInfo]/[loadConfig]/[trigger]/[audit] 为 `@visibleForTesting` 注入
/// 接缝（sqlite_maintenance_dialog 先例），生产经 [show] 走默认
/// （dbService 既有通道，零新执行通道）。
class RedisBackupDialog extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;

  @visibleForTesting
  final RedisPersistenceLoader? loadInfo;

  @visibleForTesting
  final RedisConfigLoader? loadConfig;

  @visibleForTesting
  final RedisBgsaveTrigger? trigger;

  @visibleForTesting
  final RedisBackupAuditor? audit;

  const RedisBackupDialog({
    super.key,
    required this.provider,
    required this.connectionId,
    this.loadInfo,
    this.loadConfig,
    this.trigger,
    this.audit,
  });

  static Future<void> show(BuildContext context, {required String connectionId}) {
    return showDialog<void>(
      context: context,
      builder: (_) => RedisBackupDialog(
        provider: context.read<AppProvider>(),
        connectionId: connectionId,
      ),
    );
  }

  @override
  State<RedisBackupDialog> createState() => _RedisBackupDialogState();
}

class _RedisBackupDialogState extends State<RedisBackupDialog> {
  Map<String, String>? _info;
  Map<String, String>? _config;
  DateTime? _lastUpdated;
  bool _loading = false;
  String? _error;
  bool _triggering = false;

  /// 只读连接事实（BGSAVE 入口禁用 + CONFIG 子区隐藏的依据）。
  bool get _isReadOnly {
    for (final candidate in widget.provider.savedConnections) {
      if (candidate.id == widget.connectionId) return candidate.readOnly;
    }
    // 连接事实不可确认 → fail-closed（触发入口按禁用处理；状态区不受影响）。
    return true;
  }

  /// 目标实例展示名（确认门明示目标实例；只含名称与地址，不含凭据）。
  String get _serverDisplayName {
    for (final candidate in widget.provider.savedConnections) {
      if (candidate.id == widget.connectionId) {
        return '${candidate.name} (${candidate.host}:${candidate.port})';
      }
    }
    return widget.connectionId;
  }

  @override
  void initState() {
    super.initState();
    // 零 Timer/零轮询：仅首帧与手动刷新取数（2b.1 observe 先例）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await (widget.loadInfo ?? _defaultLoadInfo)(
        widget.connectionId,
      );
      Map<String, String>? config;
      // CONFIG 子区：readonly 连接直接跳过（入口禁用路径），不发起 dangerous
      // 级命令；可写连接取数失败 → 隐藏降级 + AppLogger，主状态区不受影响。
      if (!_isReadOnly) {
        try {
          final raw = await (widget.loadConfig ?? _defaultLoadConfig)(
            widget.connectionId,
          );
          config = raw.isEmpty
              ? null
              : {
                  for (final key in const ['save', 'dir', 'dbfilename'])
                    if (raw.containsKey(key)) key: raw[key]!,
                };
          if (config != null && config.isEmpty) config = null;
        } catch (e) {
          AppLogger.w(
            'RedisBackup',
            'CONFIG GET failed (readonly or denied), section hidden: $e',
          );
          config = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _info = info;
        _config = config;
        _lastUpdated = DateTime.now();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, String>> _defaultLoadInfo(String connectionId) =>
      widget.provider.connection.dbService.getRedisPersistenceInfo(
        connectionId: connectionId,
      );

  Future<Map<String, String>> _defaultLoadConfig(String connectionId) =>
      widget.provider.connection.dbService.getRedisConfig(
        connectionId: connectionId,
      );

  Future<String> _defaultTrigger(String connectionId) =>
      widget.provider.connection.dbService.triggerRedisBgsave(
        connectionId: connectionId,
      );

  bool get _bgsaveInProgress =>
      _info?['rdb_bgsave_in_progress'] == '1' ||
      _info?['rdb_bgsave_in_progress'] == 'true';

  int? get _changesSinceLastSave =>
      int.tryParse(_info?['rdb_changes_since_last_save'] ?? '');

  /// 触发入口禁用条件：只读（fail-closed）/ 执行中 / BGSAVE 进行中。
  bool get _triggerDisabled =>
      _isReadOnly || _triggering || _bgsaveInProgress;

  Future<void> _triggerBgsave() async {
    final l10n = AppLocalizations.of(context)!;
    final changes = _changesSinceLastSave;

    // 独立确认门（取消 = 零执行、零审计）：明示目标实例 + fork 影响说明
    // + 当前变更数提示。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DestructiveConfirmDialog(
        icon: LucideIcons.databaseBackup,
        title: l10n.redisBackupTrigger,
        impactTone: DestructiveTone.warning,
        body: l10n.redisBackupConfirmImpact,
        confirmLabel: l10n.redisBackupTrigger,
        extraContent: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${l10n.redisBackupTitle}: $_serverDisplayName',
              style: TextStyle(
                color: ctx.themeColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (changes != null) ...[
              const SizedBox(height: AppDesignSystem.space1),
              Text(
                l10n.redisBackupChangesSince('$changes'),
                style: TextStyle(color: ctx.themeColors.textMuted, fontSize: 12),
              ),
            ],
          ],
        ),
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _triggering = true);
    final stopwatch = Stopwatch()..start();
    var success = true;
    String? errorMessage;
    try {
      await (widget.trigger ?? _defaultTrigger)(widget.connectionId);
    } catch (e) {
      success = false;
      // 只读拦截映射本地化文案；其余展示引擎错误原文（fork 失败等，不吞错）。
      errorMessage = e is ReadOnlyBlockedException
          ? l10n.readOnlyModeBlocked
          : e.toString();
    }
    stopwatch.stop();

    // 审计落账（成败两态均落）——写失败不阻塞 UI（AppLogger 记录后继续）。
    try {
      await (widget.audit ?? _auditBgsave)(
        (
          connectionId: widget.connectionId,
          sql: 'BGSAVE',
          executionTime: stopwatch.elapsed,
          success: success,
          errorMessage: errorMessage,
        ),
      );
    } catch (e) {
      AppLogger.w('RedisBackup', 'audit log failed (non-blocking): $e');
    }

    if (!mounted) return;
    setState(() => _triggering = false);
    if (success) {
      AppErrorHandler.showSuccessSnackBar(context, l10n.redisBackupSuccess);
      // 成功后刷新状态区（LASTSAVE/rdb_changes_since_last_save 变化可见）。
      await _refresh();
    } else {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.redisBackupFailed,
        tag: 'RedisBackup',
        opContext: 'BGSAVE',
        connectionId: widget.connectionId,
      );
      setState(() => _error = errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(
            LucideIcons.databaseBackup,
            size: 20,
            color: context.themeColors.textPrimary,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.redisBackupTitle,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTargetRow(context, l10n),
              const SizedBox(height: AppDesignSystem.space3),
              _buildStatusSection(context, l10n),
              const SizedBox(height: AppDesignSystem.space3),
              _buildConfigSection(context, l10n),
              const SizedBox(height: AppDesignSystem.space3),
              _buildTriggerSection(context, l10n),
            ],
          ),
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

  Widget _buildTargetRow(BuildContext context, AppLocalizations l10n) {
    return Text(
      _serverDisplayName,
      style: TextStyle(
        color: context.themeColors.textMuted,
        fontSize: 11,
      ),
    );
  }

  /// 状态区（只读）：加载态 / 失败态 / 空态 / 数据行 + 刷新 + 最后更新于。
  Widget _buildStatusSection(BuildContext context, AppLocalizations l10n) {
    final children = <Widget>[];
    if (_loading && _info == null) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppDesignSystem.space3),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    } else if (_error != null && _info == null) {
      children.add(_buildErrorState(context));
    } else if (_info == null || _info!.isEmpty) {
      children.add(_buildEmptyState(context, l10n));
    } else {
      children.add(_buildStatusRows(context, l10n));
    }
    children.add(const SizedBox(height: AppDesignSystem.space2));
    children.add(_buildRefreshRow(context, l10n));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildStatusRows(BuildContext context, AppLocalizations l10n) {
    final info = _info ?? const {};
    final rows = <Widget>[
      _statusRow(context, l10n.redisBackupLastSave(_formatUnixSeconds(
        int.tryParse(info['lastsave'] ?? '') ??
            int.tryParse(info['rdb_last_save_time'] ?? ''),
      ))),
      _statusRow(
        context,
        l10n.redisBackupBgsaveStatus(_bgsaveStatusText(info)),
      ),
      _statusRow(
        context,
        l10n.redisBackupChangesSince(
          info['rdb_changes_since_last_save'] ?? '-',
        ),
      ),
    ];
    if (_bgsaveInProgress) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: AppDesignSystem.space1),
          child: Row(
            children: [
              Icon(
                // 静态图标（不转圈）：进行中是持续态，无限动画会卡死
                // pumpAndSettle 类自动化验证（widget 测试纪律）。
                LucideIcons.loader,
                size: 12,
                color: context.themeColors.warning,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                l10n.redisBackupInProgress,
                style: TextStyle(
                  color: context.themeColors.warning,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  /// 上次 BGSAVE 状态（rdb_last_bgsave_status）+ 耗时
  /// （rdb_last_bgsave_time_sec，缺失不计入——ARB 冻结不新增 key）。
  String _bgsaveStatusText(Map<String, String> info) {
    final status = info['rdb_last_bgsave_status'];
    if (status == null || status.isEmpty) return '-';
    final secs = int.tryParse(info['rdb_last_bgsave_time_sec'] ?? '');
    return secs == null ? status : '$status (${secs}s)';
  }

  /// unix 秒 → 'yyyy-MM-dd HH:mm:ss'；无效输入回显 '-'。
  String _formatUnixSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return '-';
    final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Widget _statusRow(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: Text(
        text,
        style: TextStyle(color: context.themeColors.textPrimary, fontSize: 13),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space3),
      child: Text(
        l10n.noData,
        style: TextStyle(color: context.themeColors.textMuted, fontSize: 12),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 14,
              color: context.themeColors.error,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Expanded(
              child: Text(
                // 加载失败展示错误原文（不吞错）；触发失败另有 snackbar
                // 文案（redisBackupFailed），此处不复用以免语义错位。
                _error ?? '',
                style: TextStyle(
                  color: context.themeColors.error,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRefreshRow(BuildContext context, AppLocalizations l10n) {
    final updated = _lastUpdated;
    return Row(
      children: [
        TextButton.icon(
          onPressed: _loading ? null : () => unawaited(_refresh()),
          icon: _loading
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.refreshCw, size: 14),
          label: Text(l10n.redisBackupRefresh),
        ),
        const Spacer(),
        if (updated != null)
          Text(
            l10n.workbenchObserveLastUpdated(_formatClock(updated)),
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  String _formatClock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// CONFIG 子区（可选增强）：save/dir/dbfilename 三键；readonly 或取数
  /// 失败 → 整区隐藏（[_config] == null）。
  Widget _buildConfigSection(BuildContext context, AppLocalizations l10n) {
    final config = _config;
    if (_isReadOnly || config == null || config.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.redisBackupConfigSection,
          style: TextStyle(
            color: context.themeColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        for (final entry in config.entries)
          _statusRow(context, '${entry.key} = ${entry.value}'),
      ],
    );
  }

  Widget _buildTriggerSection(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: context.themeColors.warning,
            foregroundColor: context.themeColors.bgPrimary,
          ),
          onPressed: _triggerDisabled
              ? null
              : () => unawaited(_triggerBgsave()),
          icon: _triggering
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.databaseBackup, size: 16),
          label: Text(l10n.redisBackupTrigger),
        ),
        if (_isReadOnly)
          Padding(
            padding: const EdgeInsets.only(top: AppDesignSystem.space1),
            child: Text(
              l10n.readOnlyModeBlocked,
              style: TextStyle(color: context.themeColors.textMuted, fontSize: 11),
            ),
          )
        else if (_bgsaveInProgress)
          Padding(
            padding: const EdgeInsets.only(top: AppDesignSystem.space1),
            child: Text(
              l10n.redisBackupInProgress,
              style: TextStyle(color: context.themeColors.textMuted, fontSize: 11),
            ),
          ),
      ],
    );
  }
}
