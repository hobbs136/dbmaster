// 全功能 Redis GUI — 阶段3: Functions 管理
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../sidebar/tree_item.dart';
import 'redis_function_editor_dialog.dart';
import 'redis_function_view_dialog.dart';
import 'redis_function_execute_dialog.dart';
import '../../molecules/compact_popup_menu_item.dart';

class RedisFunctionsPanel extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;
  final Function(String) onToggleExpand;

  const RedisFunctionsPanel({
    super.key,
    required this.connectionId,
    required this.provider,
    required this.onToggleExpand,
  });

  @override
  State<RedisFunctionsPanel> createState() => _RedisFunctionsPanelState();
}

class _RedisFunctionsPanelState extends State<RedisFunctionsPanel> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _functionLibraries = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFunctions();
  }

  Future<void> _loadFunctions() async {
    setState(() => _isLoading = true);

    try {
      // 接通真实 adapter(原为 mock 数据);functions 仅保留函数名供节点展示
      final libs = await widget.provider.getRedisFunctions(
        connectionId: widget.connectionId,
      );
      setState(() {
        _functionLibraries = libs
            .map(
              (lib) => {
                'name': lib.name,
                'library': lib.name,
                'engine': lib.engine,
                'functions': lib.functions.map((f) => f.name).toList(),
              },
            )
            .toList();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load functions: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => RedisFunctionEditorDialog(
        connectionId: widget.connectionId,
        provider: widget.provider,
        onCreated: () => _loadFunctions(),
      ),
    );
  }

  // #6 — View：拉取库源码并展示只读对话框
  Future<void> _showViewDialog(String libraryName) async {
    showDialog(
      context: context,
      builder: (ctx) => RedisFunctionViewDialog(
        connectionId: widget.connectionId,
        provider: widget.provider,
        libraryName: libraryName,
      ),
    );
  }

  // #6 — Edit：先拉源码，再以编辑模式打开 editor（REPLACE 强制开）
  Future<void> _showEditDialog(String libraryName) async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Redis adapter not available'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
      return;
    }
    String? source;
    try {
      source = await adapter.getRedisFunctionSource(libraryName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load source: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Source not available for "$libraryName" (server may not support '
            'FUNCTION LIST WITHCODE). Cannot edit.',
          ),
          backgroundColor: context.themeColors.accentOrange,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => RedisFunctionEditorDialog(
        connectionId: widget.connectionId,
        provider: widget.provider,
        initialLibraryName: libraryName,
        initialSource: source,
        onCreated: () => _loadFunctions(),
      ),
    );
  }

  // #6 — Execute：调用 FCALL/FCALL_RO
  void _showExecuteDialog(String functionName) {
    showDialog(
      context: context,
      builder: (ctx) => RedisFunctionExecuteDialog(
        connectionId: widget.connectionId,
        provider: widget.provider,
        functionName: functionName,
      ),
    );
  }

  // #6 — Copy function name 到剪贴板
  void _copyName(String name) {
    Clipboard.setData(ClipboardData(text: name));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $name'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showFunctionContextMenu(String libraryName, Offset position) {
    final l10n = AppLocalizations.of(context)!;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(
                LucideIcons.eye,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.browseData),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                LucideIcons.pencil,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.commonEdit),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.accentRed,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.commonDelete,
                style: TextStyle(color: context.themeColors.accentRed),
              ),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (action != null) _handleFunctionAction(libraryName, action);
    });
  }

  Future<void> _handleFunctionAction(String libraryName, String action) async {
    switch (action) {
      case 'view':
        await _showViewDialog(libraryName);
        break;
      case 'edit':
        await _showEditDialog(libraryName);
        break;
      case 'delete':
        await _confirmDeleteLibrary(libraryName);
        break;
    }
  }

  // 新增 — 删除 Function 库(确认 + adapter.deleteRedisFunction)
  Future<void> _confirmDeleteLibrary(String libraryName) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          'Delete Function Library',
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        content: Text(
          'Delete library "$libraryName" and all its functions? This cannot be undone.',
          style: TextStyle(color: context.themeColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.commonDelete,
              style: TextStyle(color: context.themeColors.accentRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      final ok = await adapter.deleteRedisFunction(libraryName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Library deleted' : 'Failed to delete library'),
          backgroundColor: ok
              ? context.themeColors.accentGreen
              : context.themeColors.accentRed,
        ),
      );
      if (ok) _loadFunctions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return TreeItem(
        level: 2,
        icon: LucideIcons.hourglass,
        iconColor: AppDesignSystem.dbRedis,
        label: 'Loading...',
        showArrow: false,
        onTap: () {},
      );
    }

    if (_errorMessage != null) {
      return TreeItem(
        level: 3,
        icon: LucideIcons.circleAlert,
        iconColor: context.themeColors.accentRed,
        label: 'Functions Error',
        showArrow: false,
        onTap: () {},
      );
    }

    final nodes = <Widget>[];

    // Functions 节点
    nodes.add(
      TreeItem(
        level: 2,
        icon: LucideIcons.functionSquare,
        iconColor: context.themeColors.accentPurple,
        label: 'Functions',
        badge: '${_functionLibraries.length}',
        isExpanded: false,
        onTap: () => widget.onToggleExpand('functions'),
        onContextMenu: (pos) {
          showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
            color: context.themeColors.bgTertiary,
            items: [
              CompactPopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.refreshCw,
                      size: 16,
                      color: context.themeColors.textSecondary,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    const Text('Refresh'),
                  ],
                ),
              ),
              CompactPopupMenuItem(
                value: 'create',
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.plus,
                      size: 16,
                      color: context.themeColors.accentGreen,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    const Text('Create Library'),
                  ],
                ),
              ),
            ],
          ).then((action) {
            if (action == 'refresh') _loadFunctions();
            if (action == 'create') _showCreateDialog();
          });
        },
      ),
    );

    // Function Libraries
    for (final lib in _functionLibraries) {
      final libraryName = lib['name'] as String;
      final functions = lib['functions'] as List<dynamic>;

      nodes.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.bookOpen,
          iconColor: context.themeColors.textSecondary,
          label: libraryName,
          badge: '${functions.length}',
          showArrow: true,
          onTap: () {},
          onContextMenu: (pos) => _showFunctionContextMenu(libraryName, pos),
        ),
      );

      // Functions
      for (final func in functions) {
        nodes.add(
          TreeItem(
            level: 4,
            icon: LucideIcons.code,
            iconColor: context.themeColors.textMuted,
            label: func.toString(),
            showArrow: false,
            onTap: () {},
            onContextMenu: (pos) {
              showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
                color: context.themeColors.bgTertiary,
                items: [
                  CompactPopupMenuItem(
                    value: 'execute',
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.play,
                          size: 16,
                          color: context.themeColors.accentGreen,
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        const Text('Execute'),
                      ],
                    ),
                  ),
                  CompactPopupMenuItem(
                    value: 'copy',
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.copy,
                          size: 16,
                          color: context.themeColors.textSecondary,
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        const Text('Copy Name'),
                      ],
                    ),
                  ),
                ],
              ).then((action) {
                if (action == 'execute') {
                  _showExecuteDialog(func.toString());
                } else if (action == 'copy') {
                  _copyName(func.toString());
                }
              });
            },
          ),
        );
      }
    }

    return Column(children: nodes);
  }
}
