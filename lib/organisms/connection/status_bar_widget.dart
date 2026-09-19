import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../providers/task_provider.dart';
import '../../models/database_models.dart';
import '../../models/connection_failure.dart';
import '../../services/database_abstract.dart'
    show SchemaAwareAdapter, PragmaAdapter;
import '../../l10n/app_localizations.dart';
import '../../utils/app_logger.dart';
import 'replication_panel.dart';
import '../server/server_status_bar.dart';
import '../../services/safety/safety_review_indicator.dart';

/// 底部状态栏组件
///
/// 设计规范：
/// - 高度 26px，背景 bgSecondary
/// - 无顶部分隔线，融入整体背景
/// - 状态指示器 6px，带动画脉冲效果
/// - 文字全部 11px
class StatusBarWidget extends StatelessWidget {
  const StatusBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        // TC-046: Use active tab's connection context
        final activeTab = provider.activeTab;
        final activeConnectionId = activeTab?.connectionId;
        final activeDbName = activeTab?.databaseName;

        // Find the server for the active tab
        final activeServer = provider.connection.getServerById(
          activeConnectionId,
        );

        final currentServer = activeServer ?? provider.connection.currentServer;
        final currentDatabase = provider.connection.currentDatabase;
        final isConnected = activeConnectionId != null
            ? provider.isConnectionConnected(activeConnectionId)
            : (currentServer != null && currentServer.connected);
        final isConnecting = provider.connection.isConnecting;
        final isReadOnly = currentServer?.readOnly ?? false;

        final serverName = currentServer?.name;
        final dbType = currentServer?.type.name ?? 'mysql';

        // 优先显示当前标签页的数据库（Session-per-Tab 隔离）
        final dbName = isConnected
            ? (activeDbName ??
                  currentDatabase?.name ??
                  AppLocalizations.of(context)!.statusNotConnected)
            : AppLocalizations.of(context)!.statusNotConnected;

        // 构建 Tooltip 内容（隐藏的服务器详情）
        final tooltipParts = <String>[];
        if (isConnected) {
          if (currentServer?.charset != null &&
              currentServer!.charset!.isNotEmpty) {
            tooltipParts.add('Charset: ${currentServer.charset}');
          }
          if (currentServer?.timezone != null &&
              currentServer!.timezone!.isNotEmpty) {
            tooltipParts.add('Timezone: ${currentServer.timezone}');
          }
          tooltipParts.add('DbMaster v0.0.1');
        }

        return Container(
          height: AppDesignSystem.statusHeight,
          // plan §3.5：底栏背景用 surfaceContainer（次级容器），与主面板拉开层级
          color: context.themeColors.bgTertiary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          child: Row(
            children: [
              // 左侧：连接状态（悬停 Tooltip 显示 charset/timezone/version）
              Builder(
                builder: (context) {
                  final statusWidget = _buildConnectionStatus(
                    context,
                    isConnected: isConnected,
                    isConnecting: isConnecting,
                    serverName: serverName,
                    dbType: dbType,
                    dbName: dbName,
                    isReadOnly: isReadOnly,
                    serverType: currentServer?.type,
                    connectionId: currentServer?.id,
                  );
                  if (tooltipParts.isEmpty) return statusWidget;
                  return Tooltip(
                    message: tooltipParts.join(' · '),
                    child: statusWidget,
                  );
                },
              ),

              const Spacer(),

              // D5: 安全审查指示器（🛡 已审查 · ✅）
              _buildSafetyIndicator(context),

              // Pro/Trial/Free 状态指示器
              _buildPlanStatus(context, provider),

              const SizedBox(width: AppDesignSystem.space3),

              // 任务指示器
              _buildTaskIndicator(context),

              const SizedBox(width: AppDesignSystem.space3),

              // C22-1：dbmaster Server 引擎连接状态（原 AppHeader 右端迁此）
              const ServerStatusBar(),
            ],
          ),
        );
      },
    );
  }

  /// 构建连接状态区域
  Widget _buildConnectionStatus(
    BuildContext context, {
    required bool isConnected,
    required bool isConnecting,
    String? serverName,
    required String dbType,
    required String dbName,
    required bool isReadOnly,
    DatabaseType? serverType,
    String? connectionId,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 状态指示器（带动画）
        _StatusIndicator(isActive: isConnected, isLoading: isConnecting),
        const SizedBox(width: AppDesignSystem.space1_5),

        // 连接状态文字
        Text(
          isConnecting
              ? AppLocalizations.of(context)!.statusConnecting
              : isConnected
              ? AppLocalizations.of(context)!.statusConnected
              : AppLocalizations.of(context)!.statusNotConnected,
          style: AppTextStyles.caption.copyWith(
            color: isConnected
                ? context.themeColors.textSecondary
                : context.themeColors.textMuted,
            fontWeight: AppDesignSystem.fontWeightMedium,
          ),
        ),

        // 服务器和数据库信息
        if (isConnected && serverName != null) ...[
          const SizedBox(width: AppDesignSystem.space3),
          _buildDivider(),
          const SizedBox(width: AppDesignSystem.space3),

          // 数据库类型图标
          _DbTypeIcon(type: dbType, size: 10),
          const SizedBox(width: AppDesignSystem.space1),

          // 服务器名称
          Text(
            serverName,
            style: AppTextStyles.caption.copyWith(
              color: context.themeColors.textMuted,
            ),
          ),

          const SizedBox(width: AppDesignSystem.space3),
          _buildDivider(),
          const SizedBox(width: AppDesignSystem.space3),

          // 数据库名称
          Icon(
            LucideIcons.database,
            size: 10,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            dbName,
            style: AppTextStyles.caption.copyWith(
              color: context.themeColors.textMuted,
            ),
          ),

          // Schema search_path indicator (PG / SQL Server)
          if (isConnected &&
              (serverType == DatabaseType.postgresql ||
                  serverType == DatabaseType.sqlserver) &&
              connectionId != null) ...[
            const SizedBox(width: AppDesignSystem.space3),
            _buildDivider(),
            const SizedBox(width: AppDesignSystem.space3),
            _SearchPathIndicator(connectionId: connectionId),
          ],

          // 只读模式指示器
          if (isConnected && isReadOnly) ...[
            const SizedBox(width: AppDesignSystem.space3),
            _buildDivider(),
            const SizedBox(width: AppDesignSystem.space3),
            _ReadOnlyIndicator(),
          ],

          // T020 — replication indicator (MySQL only)
          if (isConnected &&
              serverType == DatabaseType.mysql &&
              connectionId != null) ...[
            const SizedBox(width: AppDesignSystem.space3),
            _buildDivider(),
            const SizedBox(width: AppDesignSystem.space3),
            _ReplicationIndicator(connectionId: connectionId),
          ],

          // SQLite 文件信息指示器（文件大小 + WAL 模式 + 页大小）
          if (isConnected &&
              serverType == DatabaseType.sqlite &&
              connectionId != null) ...[
            const SizedBox(width: AppDesignSystem.space3),
            _buildDivider(),
            const SizedBox(width: AppDesignSystem.space3),
            _SqliteInfoIndicator(connectionId: connectionId),
          ],
        ],
      ],
    );
  }

  /// 构建分隔竖线
  Widget _buildDivider() {
    return Container(width: 1, height: 12, color: AppDesignSystem.divider);
  }

  /// 构建 Pro 状态指示器——全免费客户端，Pro 恒激活，无升级入口。
  /// D5: 安全审查指示器。审查通过显示 🛡，2s 后淡化。
  Widget _buildSafetyIndicator(BuildContext context) {
    final colors = context.themeColors;
    return AnimatedBuilder(
      animation: SafetyReviewIndicator.instance,
      builder: (context, _) {
        final result = SafetyReviewIndicator.instance.lastResult;
        if (result == null) return const SizedBox.shrink();

        final hasRisk = result.findingCount > 0;
        final color = result.hasHigh
            ? colors.error
            : result.hasMedium
            ? colors.warning
            : colors.success;

        return Padding(
          padding: const EdgeInsets.only(right: AppDesignSystem.space3),
          child: Tooltip(
            message:
                '${result.localizedLabel(AppLocalizations.of(context)!.safetyReviewedLabel)} · ${result.at.toLocal()}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.shield, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  result.localizedLabel(
                    AppLocalizations.of(context)!.safetyReviewedLabel,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: hasRisk ? color : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlanStatus(BuildContext context, AppProvider provider) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final color = colors.accentGreen;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.badgeCheck, size: 10, color: color),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            l10n.settingsProActivated,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: AppDesignSystem.fontWeightMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建任务指示器
  Widget _buildTaskIndicator(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, taskProvider, _) {
        final runningCount = taskProvider.runningTaskCount;
        final totalCount = taskProvider.tasks.length;

        return InkWell(
          onTap: () => context.read<AppProvider>().toggleExecutionCenter(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (runningCount > 0)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      context.themeColors.accentPurple,
                    ),
                  ),
                )
              else
                Icon(
                  LucideIcons.clipboardList,
                  size: 12,
                  color: totalCount > 0
                      ? context.themeColors.textMuted
                      : context.themeColors.textMuted.withValues(alpha: 0.5),
                ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                runningCount > 0 ? '$runningCount' : '$totalCount',
                style: AppTextStyles.caption.copyWith(
                  color: runningCount > 0
                      ? context.themeColors.accentPurple
                      : context.themeColors.textMuted,
                  fontWeight: AppDesignSystem.fontWeightMedium,
                ),
              ),
              const _ErrorBadge(),
              // T10 · 未处置连接失败指示点（与 _ErrorBadge 错误计数语义不同，不合并）。
              const _ConnectionFailureDot(),
            ],
          ),
        );
      },
    );
  }
}

/// 错误数量徽标（执行中心有未处理错误时显示红点计数）。
class _ErrorBadge extends StatelessWidget {
  const _ErrorBadge();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final n = provider.executionCenter.errors.length;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: context.themeColors.error.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: Text(
            '$n',
            style: AppTextStyles.caption.copyWith(
              color: context.themeColors.error,
              fontSize: 11,
            ),
          ),
        );
      },
    );
  }
}

/// T10 · 未处置连接失败指示点：任一连接存在未处置失败时显示 error 色点
/// （14px 约束内，8px 视觉点 + 14px 命中区）。tooltip = 最新失败的人话
/// 原因；点击 = 打开执行中心 + 处置全部失败。与 [_ErrorBadge]（执行中心
/// 错误计数）并存、互不干扰。
class _ConnectionFailureDot extends StatelessWidget {
  const _ConnectionFailureDot();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final failure = provider.connection.latestUnacknowledgedFailure;
        if (failure == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context)!;
        return Tooltip(
          message: l10n.connectFailureLatestTooltip(
            _failurePlainMessage(l10n, failure.kind),
          ),
          child: InkWell(
            key: const ValueKey('status_bar_connection_failure_dot'),
            onTap: () {
              final appProvider = context.read<AppProvider>();
              appProvider.openExecutionCenter();
              appProvider.connection.acknowledgeAllFailures();
            },
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            child: SizedBox(
              width: 14,
              height: 14,
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.themeColors.error,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// T10 · 失败分型 → 人话消息（与 ConnectFailureDialog 同口径的展示边界
/// 映射；rawMessage 未脱敏不进 tooltip）。
String _failurePlainMessage(AppLocalizations l10n, ConnectionFailureKind kind) =>
    switch (kind) {
      ConnectionFailureKind.fileLocked => l10n.connectFailureFileLocked,
      ConnectionFailureKind.fileNotFound => l10n.connectFailureFileNotFound,
      ConnectionFailureKind.permissionDenied =>
        l10n.connectFailurePermissionDenied,
      ConnectionFailureKind.notADatabase => l10n.connectFailureNotADatabase,
      ConnectionFailureKind.corrupt => l10n.connectFailureCorrupt,
      ConnectionFailureKind.authFailed => l10n.connectFailureAuthFailed,
      ConnectionFailureKind.unreachable => l10n.connectFailureUnreachable,
      ConnectionFailureKind.unknown => l10n.connectFailureUnknown,
    };

/// 状态指示器（带动画脉冲效果）
class _StatusIndicator extends StatefulWidget {
  final bool isActive;
  final bool isLoading;

  const _StatusIndicator({required this.isActive, required this.isLoading});

  @override
  State<_StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<_StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 1.0,
      end: 2.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isLoading
        ? context.themeColors.warning
        : widget.isActive
        ? context.themeColors.success
        : context.themeColors.textMuted;

    return SizedBox(
      width: 10,
      height: 10,
      child: Center(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // 脉冲动画环
                if (widget.isActive)
                  Container(
                    width: 6 * _animation.value,
                    height: 6 * _animation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacityValue(
                        0.3 * (1 - (_animation.value - 1) / 1.5),
                      ),
                    ),
                  ),
                // 核心圆点
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 数据库类型图标
class _DbTypeIcon extends StatelessWidget {
  final String type;
  final double size;

  const _DbTypeIcon({required this.type, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = _getDbColor(context, type);

    return Container(
      width: size + 2,
      height: size + 2,
      decoration: BoxDecoration(
        color: color.withOpacityValue(0.15),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Center(
        child: Text(
          _getDbLabel(type),
          style: AppTextStyles.caption.copyWith(
            fontSize: size - 3,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  String _getDbLabel(String type) {
    switch (type.toLowerCase()) {
      case 'mysql':
        return 'M';
      case 'postgresql':
        return 'P';
      case 'mongodb':
        return 'Mg';
      case 'redis':
        return 'R';
      case 'doris':
        return 'D';
      default:
        return type.substring(0, 1).toUpperCase();
    }
  }

  Color _getDbColor(BuildContext context, String type) {
    // 品牌色统一走 ThemeColors 主题分发（c02 §3.2）；未知类型回退强调色
    final dbType = DatabaseType.tryFromName(type.toLowerCase());
    return dbType != null
        ? context.themeColors.brandColor(dbType)
        : context.themeColors.accentBlue;
  }
}

/// 只读模式指示器
class _ReadOnlyIndicator extends StatelessWidget {
  const _ReadOnlyIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.error.withOpacityValue(0.15),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.error.withOpacityValue(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.lock, size: 10, color: context.themeColors.error),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            'READ-ONLY',
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.themeColors.error,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// T019 — Replication indicator widget for MySQL status bar
class _ReplicationIndicator extends StatefulWidget {
  final String connectionId;

  const _ReplicationIndicator({required this.connectionId});

  @override
  State<_ReplicationIndicator> createState() => _ReplicationIndicatorState();
}

class _ReplicationIndicatorState extends State<_ReplicationIndicator> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadAndStartTimer();
  }

  void _loadAndStartTimer() {
    final provider = context.read<AppProvider>();
    provider.loadReplicationStatus(widget.connectionId);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        provider.loadReplicationStatus(widget.connectionId);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final provider = context.watch<AppProvider>();
    final status = provider.getReplicationStatus(widget.connectionId);

    if (status == null) return const SizedBox.shrink();

    final isRunning = status.isRunning;
    final lag = status.secondsBehindMaster;

    return InkWell(
      onTap: () => ReplicationDetailDialog.show(context, status),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space1_5,
          vertical: AppDesignSystem.space0_5,
        ),
        decoration: BoxDecoration(
          color: isRunning
              ? context.themeColors.success.withValues(alpha: 0.1)
              : context.themeColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(
            color: isRunning
                ? context.themeColors.success.withValues(alpha: 0.3)
                : context.themeColors.error.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRunning ? LucideIcons.refreshCw : LucideIcons.refreshCcw,
              size: 10,
              color: isRunning
                  ? context.themeColors.success
                  : context.themeColors.error,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              isRunning ? l10n.replicationRunning : l10n.replicationStopped,
              style: AppTextStyles.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isRunning
                    ? context.themeColors.success
                    : context.themeColors.error,
                height: 1.0,
              ),
            ),
            if (lag != null) ...[
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                '| ${l10n.replicationLag(lag)}',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11,
                  color: colors.textMuted,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// SQLite 文件信息指示器——紧凑显示 WAL 模式 + 页大小 + 文件大小，tooltip 含完整路径。
///
/// 设计：
/// - StatefulWidget + initState 一次性加载（不轮询）。切 tab/切连接时 widget 重建
///   （`Consumer<AppProvider>` 触发），自然重新加载。
/// - 不用 FutureBuilder（每次 rebuild 重复触发 Future）。
/// - 错误态静默返回 SizedBox.shrink()（避免空连接噪音）。
/// - 数据源：文件路径 = currentServer.host（SQLite 复用 host 字段）；
///   文件大小 = dart:io File.statSync；WAL/页大小 = adapter.getPragmas() 过滤两项。
class _SqliteInfoIndicator extends StatefulWidget {
  final String connectionId;

  const _SqliteInfoIndicator({required this.connectionId});

  @override
  State<_SqliteInfoIndicator> createState() => _SqliteInfoIndicatorState();
}

class _SqliteInfoIndicatorState extends State<_SqliteInfoIndicator> {
  /// null = 未加载/出错（静默隐藏）；非 null = 已加载。
  _SqliteInfo? _info;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final provider = context.read<AppProvider>();
      final server = provider.connection.getServerById(widget.connectionId);
      final path = server?.host ?? '';
      final adapter = provider.dbService.getAdapter(widget.connectionId);

      String? walMode;
      String? pageSize;
      String fileSize = '';

      // 文件大小（dart:io，仿 sqlite_tree_builder 既有模式）
      if (path.isNotEmpty) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            fileSize = _formatFileSize(file.lengthSync());
          }
        } catch (e) {
          AppLogger.w('SqliteInfoIndicator', 'Failed to get file size: $e');
        }
      }

      // WAL 模式 + 页大小（复用 adapter.getPragmas public API）
      if (adapter is PragmaAdapter) {
        final pragmaAdapter = adapter as PragmaAdapter;
        final pragmas = await pragmaAdapter.getPragmas();
        for (final p in pragmas) {
          if (p.name == 'journal_mode') walMode = p.currentValue;
          if (p.name == 'page_size') pageSize = p.currentValue;
        }
      }

      if (!mounted) return;
      setState(() {
        _info = _SqliteInfo(
          walMode: walMode,
          pageSize: pageSize,
          fileSize: fileSize,
          filePath: path,
        );
      });
    } catch (e) {
      AppLogger.w('SqliteInfoIndicator', 'Failed to load SQLite info: $e');
    }
  }

  /// 仿 sqlite_tree_builder._formatFileSize 的紧凑格式。
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    // 任何字段都没有 → 静默隐藏（避免空连接噪音）。
    if (info == null ||
        (info.walMode == null &&
            info.pageSize == null &&
            info.fileSize.isEmpty)) {
      return const SizedBox.shrink();
    }

    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    // tooltip：完整路径（+ 文件名前缀，避免长路径被截断时仍可识别）。
    final tooltipMsg = info.filePath.isNotEmpty
        ? '${l10n.sqliteStatusFileSize}: ${info.filePath}'
        : l10n.sqliteStatusFileSize;

    final chips = <Widget>[];
    if (info.walMode != null) {
      chips.add(_chip('${l10n.sqliteStatusWal}: ${info.walMode}', colors));
    }
    if (info.pageSize != null) {
      // page_size 是字节数，转 KB 更易读（1024 → 1 KB）。
      final psStr = _formatPageSize(info.pageSize!, l10n);
      chips.add(_chip('${l10n.sqliteStatusPageSize}: $psStr', colors));
    }
    if (info.fileSize.isNotEmpty) {
      chips.add(
        _chip('${l10n.sqliteStatusFileSize}: ${info.fileSize}', colors),
      );
    }

    return Tooltip(
      message: tooltipMsg,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: AppDesignSystem.space1_5),
            chips[i],
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: colors.accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.accentBlue.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.accentBlue,
          height: 1.0,
        ),
      ),
    );
  }

  static String _formatPageSize(String raw, AppLocalizations l10n) {
    final bytes = int.tryParse(raw);
    if (bytes == null) return raw;
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

/// SQLite 状态栏加载结果（内部传递用）。
class _SqliteInfo {
  final String? walMode;
  final String? pageSize;
  final String fileSize;
  final String filePath;
  _SqliteInfo({
    required this.walMode,
    required this.pageSize,
    required this.fileSize,
    required this.filePath,
  });
}

/// Displays the current search_path for schema-aware databases (PG, SQL Server).
/// Supports inline editing via a tappable popup.
class _SearchPathIndicator extends StatefulWidget {
  final String connectionId;

  const _SearchPathIndicator({required this.connectionId});

  @override
  State<_SearchPathIndicator> createState() => _SearchPathIndicatorState();
}

class _SearchPathIndicatorState extends State<_SearchPathIndicator> {
  String? _searchPath;

  @override
  void initState() {
    super.initState();
    _loadSearchPath();
  }

  Future<void> _loadSearchPath() async {
    final provider = context.read<AppProvider>();
    final rawAdapter = provider.dbService.getAdapter(widget.connectionId);
    if (rawAdapter case final SchemaAwareAdapter sa) {
      final current = sa.getCurrentSchema();
      if (mounted) {
        setState(() => _searchPath = current ?? 'public');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showEditDialog,
      child: Tooltip(
        message: 'Click to edit search_path',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.folder,
              size: 10,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              _searchPath ?? '...',
              style: AppTextStyles.caption.copyWith(
                fontSize: 11,
                color: context.themeColors.textMuted,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog() {
    final controller = TextEditingController(text: _searchPath ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit search_path'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'public, api, auth',
            helperText: 'Comma-separated schema names',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final input = controller.text;
              final schemas = input
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (schemas.isNotEmpty) {
                final provider = context.read<AppProvider>();
                final adapter = provider.dbService.getAdapter(
                  widget.connectionId,
                );
                if (adapter case final SchemaAwareAdapter sa) {
                  await sa.setSearchPath(schemas);
                }
              }
              if (mounted) {
                Navigator.of(ctx).pop();
                _loadSearchPath();
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
