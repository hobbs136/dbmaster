import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../services/code_snippet_service.dart';
import '../../models/code_snippet.dart';
import '../dialogs/variable_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_logger.dart';
import 'error_boundary.dart';

/// 代码片段面板
/// 显示可用的 SQL 代码片段模板
class CodeSnippetsPanel extends StatefulWidget {
  final CodeSnippetService? service; // Optional, null = auto-create
  final void Function(CodeSnippet)? onSnippetSelected; // Simpler callback
  final VoidCallback? onClose; // Optional close callback

  const CodeSnippetsPanel({
    super.key,
    this.service,
    this.onSnippetSelected,
    this.onClose,
  });

  @override
  State<CodeSnippetsPanel> createState() => _CodeSnippetsPanelState();
}

class _CodeSnippetsPanelState extends State<CodeSnippetsPanel> {
  late final CodeSnippetService _service;
  String _searchQuery = '';
  String _selectedCategory = 'all';
  StreamSubscription<String>? _errorSubscription;

  static const List<String> _categoryKeys = [
    'all',
    'dml',
    'ddl',
    'query',
    'utility',
    'custom',
  ];

  String _categoryLabel(String key, AppLocalizations l10n) {
    switch (key) {
      case 'all':
        return l10n.snippetCategoryAll;
      case 'dml':
        return l10n.snippetCategoryDML;
      case 'ddl':
        return l10n.snippetCategoryDDL;
      case 'query':
        return l10n.snippetCategoryQuery;
      case 'utility':
        return l10n.snippetCategoryUtility;
      case 'custom':
        return l10n.snippetCategoryCustom;
      default:
        return key;
    }
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CodeSnippetService();
    if (widget.service == null) {
      _service.init().then((_) {
        if (mounted) setState(() {});
      });
    }

    // Listen to error stream
    _errorSubscription = _service.errorStream.listen(
      (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppErrorHandler.showErrorSnackBar(
            context,
            l10n.connErrorWithMessage(error),
          );
        }
      },
      onError: (err, stack) {
        AppLogger.e('CodeSnippetsPanel', 'Error stream failure', err, stack);
      },
    );
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    // Only dispose if we created our own service
    if (widget.service == null) {
      _service.dispose();
    }
    super.dispose();
  }

  // Computed property for filtered snippets
  List<CodeSnippet> get _filteredSnippets {
    var snippets = _service.getAllSnippets();

    if (_selectedCategory != 'all') {
      snippets = snippets
          .where((s) => s.category.toLowerCase() == _selectedCategory)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      snippets = _service.searchSnippets(_searchQuery);
    }

    return snippets;
  }

  @override
  Widget build(BuildContext context) {
    final filteredSnippets = _filteredSnippets;

    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          left: BorderSide(color: context.themeColors.accentPurple, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          _buildSearchBar(context),
          _buildCategoryTabs(context),
          Expanded(
            child: filteredSnippets.isEmpty
                ? _buildEmptyState()
                : _buildSnippetList(filteredSnippets),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final allSnippets = _service.getAllSnippets();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.code,
            color: context.themeColors.accentPurple,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            '代码片段',
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.accentPurple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
            ),
            child: Text(
              '${allSnippets.length}',
              style: TextStyle(
                color: context.themeColors.accentPurple,
                fontSize: 12,
              ),
            ),
          ),
          if (widget.onClose != null) ...[
            const SizedBox(width: AppDesignSystem.space2),
            IconButton(
              icon: Icon(
                LucideIcons.x,
                color: context.themeColors.textSecondary,
                size: 20,
              ),
              onPressed: widget.onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderColor),
        ),
      ),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: l10n.connSearchSnippetsHint,
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          hintStyle: TextStyle(color: context.themeColors.textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: context.themeColors.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: context.themeColors.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: context.themeColors.accentPurple),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
        ),
        style: TextStyle(color: context.themeColors.textPrimary, fontSize: 13),
      ),
    );
  }

  Widget _buildCategoryTabs(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categoryKeys.length,
        itemBuilder: (context, index) {
          final category = _categoryKeys[index];
          final isSelected = _selectedCategory == category;
          final l10n = AppLocalizations.of(context)!;

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space1,
            ),
            child: ChoiceChip(
              label: Text(_categoryLabel(category, l10n)),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = category),
              selectedColor: context.themeColors.accentPurple,
              backgroundColor: context.themeColors.bgPrimary,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : context.themeColors.textPrimary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSnippetList(List<CodeSnippet> snippets) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: snippets.length,
      itemBuilder: (context, index) {
        return _buildSnippetCard(snippets[index]);
      },
    );
  }

  Widget _buildSnippetCard(CodeSnippet snippet) {
    final l10n = AppLocalizations.of(context)!;
    final variables = snippet.variables.join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getCategoryIcon(snippet.category),
                color: context.themeColors.accentPurple,
                size: 20,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  snippet.name,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1_5,
                  vertical: AppDesignSystem.space0_5,
                ),
                decoration: BoxDecoration(
                  color: context.themeColors.accentPurple.withValues(
                    alpha: 0.2,
                  ),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  snippet.category,
                  style: TextStyle(
                    color: context.themeColors.accentPurple,
                    fontSize: 11,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  ),
                ),
              ),
              if (snippet.usageCount > 0) ...[
                const SizedBox(width: AppDesignSystem.space1_5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space2,
                    vertical: AppDesignSystem.space0_5,
                  ),
                  decoration: BoxDecoration(
                    color: context.themeColors.accentPurple.withValues(
                      alpha: 0.2,
                    ),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusLg,
                    ),
                  ),
                  child: Text(
                    '${snippet.usageCount}',
                    style: TextStyle(
                      color: context.themeColors.accentPurple,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          Text(
            snippet.description,
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 12,
            ),
          ),
          if (variables.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space1_5),
            Text(
              '变量: $variables',
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: AppDesignSystem.space2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showCodePreview(snippet);
                  },
                  icon: const Icon(LucideIcons.eye, size: 16),
                  label: Text(l10n.connPreview),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDesignSystem.space2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _handleSnippetTap(snippet);
                  },
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: Text(l10n.connInsert),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.themeColors.accentPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDesignSystem.space2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'DML':
        return LucideIcons.pencil;
      case 'DDL':
        return LucideIcons.table2;
      case 'Query':
        return LucideIcons.search;
      case 'Utility':
        return LucideIcons.wrench;
      case 'Custom':
        return LucideIcons.user;
      default:
        return LucideIcons.code;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.searchX,
            color: context.themeColors.textMuted,
            size: 48,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            '没有找到匹配的片段',
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSnippetTap(CodeSnippet snippet) async {
    String finalContent = snippet.content;

    if (snippet.variables.isNotEmpty) {
      final values = await VariableDialog.show(context, snippet.variables);
      if (values == null) return; // User cancelled

      // Substitute variables into content
      finalContent = snippet.content;
      for (final varName in snippet.variables) {
        final value = values[varName] ?? '';
        finalContent = finalContent.replaceAll('{{$varName}}', value);
      }

      // Create substituted snippet
      final substitutedSnippet = snippet.copyWith(content: finalContent);

      // Update usage count
      await _service.incrementUsage(snippet.id);
      if (mounted) setState(() {}); // Refresh UI to show updated usage count

      // Notify parent with substituted content
      widget.onSnippetSelected?.call(substitutedSnippet);
    } else {
      // Simple snippet - just update usage and notify
      await _service.incrementUsage(snippet.id);
      if (mounted) setState(() {}); // Refresh UI to show updated usage count
      widget.onSnippetSelected?.call(snippet);
    }
  }

  void _showCodePreview(CodeSnippet snippet) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.code, color: context.themeColors.accentPurple),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              snippet.name,
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              snippet.content,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }
}
