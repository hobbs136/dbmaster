//! SQLite PRAGMA Explorer — 查看和修改 SQLite PRAGMA 配置项。
//!
//! 入口：SQLite 侧边栏 Database Info 节点右键 → "PRAGMA Explorer"。
//! 数据：adapter.getPragmas()（遍历 _pragmaCatalog 查当前值）。
//! 可写项支持 inline 编辑（弹输入框 → setPragma → 刷新）。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../providers/app_provider.dart';
import '../../services/database_abstract.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// PRAGMA Explorer 对话框。展示分类 PRAGMA + 当前值 + 搜索 + 可写项编辑。
class PragmaExplorerDialog extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;

  const PragmaExplorerDialog({
    super.key,
    required this.provider,
    required this.connectionId,
  });

  /// Convenience method to show as a dialog.
  static Future<void> show(
    BuildContext context, {
    required AppProvider provider,
    required String connectionId,
  }) {
    return showDialog(
      context: context,
      builder: (_) =>
          PragmaExplorerDialog(provider: provider, connectionId: connectionId),
    );
  }

  @override
  State<PragmaExplorerDialog> createState() => _PragmaExplorerDialogState();
}

class _PragmaExplorerDialogState extends State<PragmaExplorerDialog> {
  List<PragmaInfo>? _pragmas;
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  bool _initialLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // initState 阶段 context 尚未就绪（AppLocalizations.of 在 initState 调会抛
    // dependOnInheritedWidgetOfExactType 断言）。改在 didChangeDependencies 首次触发。
    if (!_initialLoaded) {
      _initialLoaded = true;
      _loadPragmas();
    }
  }

  Future<void> _loadPragmas() async {
    final l10n = AppLocalizations.of(context);
    try {
      final adapter = widget.provider.dbService.getAdapter(widget.connectionId);
      if (adapter == null) {
        if (!mounted) return;
        setState(() {
          _error = l10n?.pragmaNoAdapter ?? 'No adapter';
          _loading = false;
        });
        return;
      }
      if (adapter is! PragmaAdapter) {
        if (!mounted) return;
        setState(() {
          _error =
              l10n?.pragmaNotSQLite ??
              'PRAGMA Explorer is only available for SQLite connections';
          _loading = false;
        });
        return;
      }
      final pragmaAdapter = adapter as PragmaAdapter;
      final pragmas = await pragmaAdapter.getPragmas();
      if (!mounted) return;
      setState(() {
        _pragmas = pragmas;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      AppLogger.e('PragmaExplorer', 'Failed to load PRAGMAs', e);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setPragma(PragmaInfo pragma, String newValue) async {
    final adapter = widget.provider.dbService.getAdapter(widget.connectionId);
    if (adapter is! PragmaAdapter) return;
    final pragmaAdapter = adapter as PragmaAdapter;
    try {
      final updated = await pragmaAdapter.setPragma(pragma.name, newValue);
      if (!mounted) return;
      setState(() {
        final idx = _pragmas?.indexWhere((p) => p.name == pragma.name);
        if (idx != null && idx >= 0 && _pragmas != null) {
          _pragmas![idx] = updated;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${pragma.name}: $e'),
          backgroundColor: context.themeColors.error,
        ),
      );
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
            LucideIcons.slidersHorizontal,
            size: 20,
            color: context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            l10n.pragmaExplorerTitle,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 520,
        child: _buildContent(context, l10n),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.commonClose,
            style: TextStyle(color: context.themeColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: context.themeColors.error,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              _error!,
              style: TextStyle(color: context.themeColors.textSecondary),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadPragmas();
              },
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    final pragmas = _pragmas ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        TextField(
          decoration: InputDecoration(
            hintText: l10n.pragmaSearchHint,
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
          ),
          onChanged: (value) =>
              setState(() => _searchQuery = value.toLowerCase()),
        ),
        const SizedBox(height: AppDesignSystem.space3),
        // PRAGMA list grouped by category
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: PragmaCategory.values.map((category) {
                final items = _filterPragmas(
                  pragmas.where((p) => p.category == category).toList(),
                );
                if (items.isEmpty) return const SizedBox.shrink();
                return _buildCategorySection(context, l10n, category, items);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  List<PragmaInfo> _filterPragmas(List<PragmaInfo> pragmas) {
    if (_searchQuery.isEmpty) return pragmas;
    return pragmas
        .where(
          (p) =>
              p.name.toLowerCase().contains(_searchQuery) ||
              p.description.toLowerCase().contains(_searchQuery) ||
              (p.currentValue?.toLowerCase().contains(_searchQuery) ?? false),
        )
        .toList();
  }

  Widget _buildCategorySection(
    BuildContext context,
    AppLocalizations l10n,
    PragmaCategory category,
    List<PragmaInfo> pragmas,
  ) {
    final title = switch (category) {
      PragmaCategory.performance => l10n.pragmaCategoryPerformance,
      PragmaCategory.durability => l10n.pragmaCategoryDurability,
      PragmaCategory.security => l10n.pragmaCategorySecurity,
      PragmaCategory.debug => l10n.pragmaCategoryDebug,
    };
    final icon = switch (category) {
      PragmaCategory.performance => LucideIcons.gauge,
      PragmaCategory.durability => LucideIcons.save,
      PragmaCategory.security => LucideIcons.shield,
      PragmaCategory.debug => LucideIcons.bug,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: context.themeColors.accentBlue),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          ...pragmas.map((p) => _buildPragmaRow(context, l10n, p)),
        ],
      ),
    );
  }

  Widget _buildPragmaRow(
    BuildContext context,
    AppLocalizations l10n,
    PragmaInfo pragma,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      pragma.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppDesignSystem.monoFontFamily,
                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                        color: context.themeColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: (pragma.currentValue?.isNotEmpty ?? false)
                            ? context.themeColors.success.withValues(alpha: 0.1)
                            : context.themeColors.bgTertiary,
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: Text(
                        pragma.currentValue ?? '—',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppDesignSystem.monoFontFamily,
                          fontFamilyFallback:
                              AppDesignSystem.monoFontFamilyFallback,
                          color: context.themeColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  pragma.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          // Edit button for writable PRAGMAs
          if (pragma.writable)
            IconButton(
              icon: Icon(
                LucideIcons.pencil,
                size: 14,
                color: context.themeColors.accentBlue,
              ),
              tooltip: l10n.pragmaSetValue,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () => _showEditDialog(context, l10n, pragma),
            ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    AppLocalizations l10n,
    PragmaInfo pragma,
  ) {
    final controller = TextEditingController(text: pragma.currentValue ?? '');
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('PRAGMA ${pragma.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.pragmaSetValue,
            hintText: 'new value',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(dialogContext).pop();
              if (value.isNotEmpty) {
                _setPragma(pragma, value);
              }
            },
            child: Text(l10n.commonApply),
          ),
        ],
      ),
    );
  }
}
