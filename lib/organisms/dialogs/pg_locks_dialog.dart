// DBT-T8 · PostgreSQL 锁/等待分析面板（W-10）——只读聚合视图。
//
// - 查询：[locksQuery]（pg_locks × pg_stat_activity 聚合，只读 SELECT，
//   公开常量供 e2e 数据面断言与面板同源）；
// - 行结构：locktype / pid / mode / granted / waitingQuery / duration
//   （任务书草案列集）；
// - 手动刷新（ProcessManagerDialog 同款状态机：loading/error/empty/data，
//   零 Timer/零轮询）；
// - **只读**：无 terminate/kill 任何形态——进程终止走既有 process.kill
//   链路（任务书约束）；取数 loader 由插件注入（测试缝先例），本文件
//   不触碰 adapter、不读 provider。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// pg_locks × pg_stat_activity 聚合查询（只读；granted=false 的行 =
/// 正在等待的锁请求）。等待行排前，limit 500 防超宽面板。
const String pgLocksQuery = '''
SELECT l.locktype AS locktype,
       l.pid AS pid,
       l.mode AS mode,
       l.granted AS granted,
       COALESCE(left(a.query, 200), '') AS waiting_query,
       CASE WHEN a.query_start IS NOT NULL
            THEN extract(epoch FROM (now() - a.query_start))::int
            ELSE NULL END AS duration_seconds
FROM pg_locks l
LEFT JOIN pg_stat_activity a ON a.pid = l.pid
ORDER BY l.granted ASC, l.pid NULLS LAST, l.locktype
LIMIT 500
''';

/// 一行锁信息（聚合查询行的规范化形态；granted 经 bool/'t' 归一）。
class PgLockEntry {
  const PgLockEntry({
    required this.locktype,
    required this.pid,
    required this.mode,
    required this.granted,
    required this.waitingQuery,
    this.durationSeconds,
  });

  final String locktype;
  final int? pid;
  final String mode;
  final bool granted;
  final String waitingQuery;
  final int? durationSeconds;

  /// 聚合查询行 → 规范化条目（网关对 PG boolean/epoch 的解码形态兼容：
  /// bool 或 't'/'true' 字符串；数值或数字字符串）。
  static PgLockEntry fromRow(Map<String, dynamic> row) {
    final grantedRaw = row['granted'];
    final durationRaw = row['duration_seconds'];
    return PgLockEntry(
      locktype: row['locktype']?.toString() ?? '',
      pid: int.tryParse(row['pid']?.toString() ?? ''),
      mode: row['mode']?.toString() ?? '',
      granted:
          grantedRaw == true ||
          grantedRaw.toString() == 't' ||
          grantedRaw.toString() == 'true',
      waitingQuery: row['waiting_query']?.toString() ?? '',
      durationSeconds: durationRaw == null
          ? null
          : int.tryParse(durationRaw.toString()),
    );
  }
}

/// PG 锁/等待分析对话框（只读）。
///
/// [loader] 由插件注入（provider.executeQuery 既有只读执行路径）；
/// [PgLockEntry.fromRow] 归一化在 [loader] 侧完成与否均可——dialog 只消费
/// 已归一化的 [PgLockEntry] 列表。
class PgLocksDialog extends StatefulWidget {
  final String connectionId;

  /// 锁聚合加载器（插件注入的只读查询；测试注入 mock）。
  final Future<List<PgLockEntry>> Function(String connectionId) loader;

  const PgLocksDialog({
    super.key,
    required this.connectionId,
    required this.loader,
  });

  /// 便捷打开（生产入口由插件调用——loader 绑定 provider 既有只读面）。
  static Future<void> show(
    BuildContext context, {
    required String connectionId,
    required Future<List<PgLockEntry>> Function(String connectionId) loader,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PgLocksDialog(
        connectionId: connectionId,
        loader: loader,
      ),
    );
  }

  @override
  State<PgLocksDialog> createState() => _PgLocksDialogState();
}

class _PgLocksDialogState extends State<PgLocksDialog> {
  List<PgLockEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.loader(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('PgLocksDialog', 'load locks failed', e);
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.lock, size: 20, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.pgLocksTitle),
          const Spacer(),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildError(colors)
            : (_entries?.isEmpty ?? true)
            ? _buildEmpty(l10n, colors)
            : _buildTable(l10n, colors),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildError(ThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        child: Text(
          _error!,
          style: TextStyle(color: colors.error, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n, ThemeColors colors) {
    return Center(
      child: Text(
        l10n.pgLocksEmpty,
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
    );
  }

  Widget _buildTable(AppLocalizations l10n, ThemeColors colors) {
    final entries = _entries ?? const <PgLockEntry>[];
    final rows = [
      for (final e in entries)
        DataRow(
          cells: [
            DataCell(
              Text(
                e.locktype,
                style: _cellStyle(colors, mono: true),
              ),
            ),
            DataCell(
              Text(e.pid?.toString() ?? '-', style: _cellStyle(colors)),
            ),
            DataCell(Text(e.mode, style: _cellStyle(colors))),
            DataCell(
              Text(
                e.granted ? 'true' : 'false',
                // 等待行（granted=false）以警示色突出——诊断面板的核心关注点。
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: e.granted ? colors.textPrimary : colors.warning,
                ),
              ),
            ),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  e.waitingQuery.isEmpty ? '-' : e.waitingQuery,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cellStyle(colors, mono: true),
                ),
              ),
            ),
            DataCell(
              Text(
                _formatDuration(e.durationSeconds),
                style: _cellStyle(colors),
              ),
            ),
          ],
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = DataTable(
          headingTextStyle: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
          ),
          dataRowMinHeight: 30,
          dataRowMaxHeight: 30,
          columnSpacing: 20,
          columns: [
            DataColumn(label: Text(l10n.pgLocksColLocktype)),
            DataColumn(label: Text(l10n.pgLocksColPid), numeric: true),
            DataColumn(label: Text(l10n.pgLocksColMode)),
            DataColumn(label: Text(l10n.pgLocksColGranted)),
            DataColumn(label: Text(l10n.pgLocksColWaitingQuery)),
            DataColumn(label: Text(l10n.pgLocksColDuration), numeric: true),
          ],
          rows: rows,
        );
        // 表宽超出 dialog 内容区时横向滚动（waitingQuery 列较宽）。
        if (tableMinWidth > constraints.maxWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(child: table),
          );
        }
        return SingleChildScrollView(child: table);
      },
    );
  }

  /// DataTable 无固有宽度测量，用列数 × 经验列宽估计（只决定是否需要
  /// 横向滚动，不影响行渲染）。
  static const double tableMinWidth = 640;

  TextStyle _cellStyle(ThemeColors colors, {bool mono = false}) => TextStyle(
    fontSize: 12,
    color: colors.textPrimary,
    fontFamily: mono ? AppDesignSystem.monoFontFamily : null,
    fontFamilyFallback: mono
        ? AppDesignSystem.monoFontFamilyFallback
        : null,
  );

  /// 秒数 → '12s' / '2m 05s'（锁面板等待时长可读化；null = '-'）。
  static String _formatDuration(int? seconds) {
    if (seconds == null) return '-';
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
