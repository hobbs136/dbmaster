// DBT-T3 · MySQL 变量浏览器（W-03）—— SHOW VARIABLES 只读两列浏览。
//
// 只读：不做 SET GLOBAL（plan §5-10 裁定）。执行经 AppProvider.dbService
// 既有只读执行路径（MUST NOT 直接实例化 adapter）；[loader] 为 widget
// 测试注入缝（ProcessManagerDialog.loader 先例），null = 走 provider 默认
// 路径。命名避开既有 AI 参数 VariableDialog。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// MySQL 变量浏览器对话框（只读）。
///
/// 行数据 = `{'name': ..., 'value': ...}`（列序已由 loader 解出）。
class MysqlVariablesBrowserDialog extends StatefulWidget {
  final String connectionId;

  /// 取数注入缝（测试用）；null = 经 AppProvider.dbService 执行
  /// `SHOW VARIABLES`（既有只读执行路径）。
  final Future<List<Map<String, String>>> Function(String connectionId)?
  loader;

  const MysqlVariablesBrowserDialog({
    super.key,
    required this.connectionId,
    this.loader,
  });

  @override
  State<MysqlVariablesBrowserDialog> createState() =>
      _MysqlVariablesBrowserDialogState();
}

class _MysqlVariablesBrowserDialogState
    extends State<MysqlVariablesBrowserDialog> {
  static const Duration _debounceDuration = Duration(milliseconds: 250);

  bool _loading = true;
  Object? _error;
  List<Map<String, String>> _variables = const [];
  String _query = '';
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// 默认取数：SHOW VARIABLES 经 dbService 既有只读执行路径（编辑器同面，
  /// 不写查询历史——历史由编辑器层 TabProvider 记账）。
  Future<List<Map<String, String>>> _defaultLoad(String connectionId) async {
    final provider = context.read<AppProvider>();
    final rows = await provider.dbService.executeQuery(
      'SHOW VARIABLES',
      connectionId: connectionId,
    );
    return [for (final row in rows) _entryFromRow(row)];
  }

  /// 行按列序位置取值（先例 DatabaseService.getGlobalVariables——
  /// SHOW VARIABLES 列名为 Variable_name/Value，网关行序保持列序）。
  static Map<String, String> _entryFromRow(Map<String, dynamic> row) {
    final values = row.values.toList();
    return {
      'name': values.isNotEmpty ? values[0]?.toString() ?? '' : '',
      'value': values.length > 1 ? values[1]?.toString() ?? '' : '',
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = widget.loader ?? _defaultLoad;
      final result = await load(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _variables = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('MysqlVariablesBrowserDialog', 'SHOW VARIABLES failed', e);
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  /// 防抖后的过滤视图：name / value 大小写不敏感包含命中。
  List<Map<String, String>> get _filtered {
    if (_query.isEmpty) return _variables;
    return _variables
        .where(
          (v) =>
              (v['name'] ?? '').toLowerCase().contains(_query) ||
              (v['value'] ?? '').toLowerCase().contains(_query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.slidersHorizontal, size: 20, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.mysqlVariablesTitle),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.mysqlVariablesSearchHint,
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 16,
                  color: colors.textMuted,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(child: _buildError(colors))
            else if (_filtered.isEmpty)
              Expanded(child: _buildEmpty(colors))
            else
              Expanded(child: _buildList(colors)),
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

  Widget _buildError(ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 28,
            color: colors.error,
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.mysqlVariablesLoadFailed,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: Text(l10n.commonRefresh),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Text(
        l10n.mysqlVariablesEmpty,
        style: TextStyle(color: colors.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _buildList(ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    final rows = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  l10n.mysqlVariablesColName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  l10n.mysqlVariablesColValue,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 30,
            itemBuilder: (context, index) {
              final name = rows[index]['name'] ?? '';
              final value = rows[index]['value'] ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppDesignSystem.monoFontFamily,
                          fontFamilyFallback:
                              AppDesignSystem.monoFontFamilyFallback,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppDesignSystem.monoFontFamily,
                          fontFamilyFallback:
                              AppDesignSystem.monoFontFamilyFallback,
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
