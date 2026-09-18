import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/er_diagram_service.dart';
import '../../services/er_layout.dart';
import '../../theme/app_theme.dart';
import '../../models/er_diagram.dart';
import 'er_canvas.dart';
import 'er_detail_panel.dart';
import 'error_boundary.dart';
import '../../molecules/dialog_connection_selector.dart';
import '../../utils/app_logger.dart';
import '../../atoms/app_loading.dart';
import '../../providers/app_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

class ERDiagramDialog extends StatefulWidget {
  final ERDiagramService? erDiagramService;
  final String? initialConnectionId;
  final String? initialDatabase;

  const ERDiagramDialog({
    super.key,
    this.erDiagramService,
    this.initialConnectionId,
    this.initialDatabase,
  });

  @override
  State<ERDiagramDialog> createState() => _ERDiagramDialogState();
}

class _ERDiagramDialogState extends State<ERDiagramDialog> {
  ERDiagram? _diagram;
  ERNode? _selectedNode;
  Map<String, dynamic>? _selectedNodeDetails;
  bool _isLoading = true;
  String? _error;
  bool _showIsolated = true;

  String? _selectedConnectionId;
  String? _selectedDatabase;
  List<String> _dialogDatabases = [];
  ERDiagramService? _service;

  final _layoutService = ERLayoutService();

  /// 包裹 ERCanvas 的 RepaintBoundary key，用于 PNG 导出截图。
  final GlobalKey _canvasBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedConnectionId = widget.initialConnectionId;
    _selectedDatabase = widget.initialDatabase;
    if (_selectedConnectionId != null) {
      _loadDatabasesForConnection(_selectedConnectionId!);
      _loadDiagram();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _service = null;
    super.dispose();
  }

  Future<void> _loadDatabasesForConnection(String connectionId) async {
    final provider = context.read<AppProvider>();
    final databases = await provider.connection.dbService.getDatabases(
      connectionId: connectionId,
    );
    if (mounted) {
      setState(() {
        _dialogDatabases = databases;
        // 如果当前选中的数据库不在列表中，且列表不为空，则选择第一个
        if (_selectedDatabase != null &&
            !databases.contains(_selectedDatabase) &&
            databases.isNotEmpty) {
          _selectedDatabase = databases.first;
        }
      });
    }
  }

  Future<void> _loadDiagram() async {
    final connectionId = _selectedConnectionId;
    if (connectionId == null) return;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<AppProvider>();

      _service = ERDiagramService(provider.connection.dbService);
      final diagram = await provider.connection.withConnection(
        connectionId,
        _selectedDatabase,
        () => _service!.buildERDiagram(),
      );

      _layoutService.applyHierarchicalLayout(
        nodes: diagram.nodes,
        edges: diagram.edges,
      );

      if (!mounted) return;
      setState(() {
        _diagram = diagram;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNodeDetails(ERNode node) async {
    if (_service == null) return;
    try {
      final details = await _service!.getTableDetails(node.tableName);
      if (!mounted) return;
      setState(() {
        _selectedNodeDetails = details;
      });
    } catch (e) {
      AppLogger.d('ERDiagramDialog', 'DEBUG: Error loading node details: $e');
    }
  }

  void _applyHierarchicalLayout() {
    if (_diagram == null) return;

    setState(() {
      _layoutService.applyHierarchicalLayout(
        nodes: _diagram!.nodes,
        edges: _diagram!.edges,
      );
    });
  }

  void _applyForceDirectedLayout() {
    if (_diagram == null) return;

    setState(() {
      _layoutService.applyForceDirectedLayout(
        nodes: _diagram!.nodes,
        edges: _diagram!.edges,
        iterations: 50,
      );
    });
  }

  void _applyCircleLayout() {
    if (_diagram == null) return;

    setState(() {
      _layoutService.applyCircleLayout(nodes: _diagram!.nodes);
    });
  }

  void _handleNodeSelected(ERNode node) {
    setState(() {
      _selectedNode = node;
      _selectedNodeDetails = null;
    });
    _loadNodeDetails(node);
  }

  Future<void> _exportAsPng() async {
    final l10n = AppLocalizations.of(context)!;
    final boundary =
        _canvasBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary == null || _diagram == null) {
      AppErrorHandler.showErrorSnackBar(context, l10n.erDiagramExportNoCanvas);
      return;
    }

    try {
      // pixelRatio=3.0 高清截图（同 chart_export.dart 模式）
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      if (byteData == null) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.erDiagramExportEncodeFailed,
        );
        return;
      }
      final bytes = byteData.buffer.asUint8List();

      // 用户选保存路径
      final result = await FilePicker.platform.saveFile(
        dialogTitle: l10n.erDiagramExportAsPNG,
        fileName: 'er_diagram.png',
        type: FileType.image,
      );
      if (!mounted) return;

      if (result != null && result.isNotEmpty) {
        final path = result.endsWith('.png') ? result : '$result.png';
        await File(path).writeAsBytes(bytes);
        if (!mounted) return;
        AppErrorHandler.showSuccessSnackBar(
          context,
          l10n.erDiagramExportSuccess(path),
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.connExportFailed(e.toString()),
      );
    }
  }

  // TODO: Wire to ER node context menu — implementation is complete, awaiting UI trigger
  // ignore: unused_element
  void _copyTableName() {
    if (_selectedNode == null) return;

    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(ClipboardData(text: _selectedNode!.tableName));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.connCopiedTableName(_selectedNode!.tableName)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.themeColors.bgPrimary,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 1200,
          minHeight: 800,
          maxWidth: 1600,
          maxHeight: 900,
        ),
        child: Column(
          children: [
            DialogConnectionSelector(
              selectedConnectionId: _selectedConnectionId,
              selectedDatabase: _selectedDatabase,
              databases: _dialogDatabases,
              onConnectionChanged: (connectionId) {
                setState(() {
                  _selectedConnectionId = connectionId;
                  _selectedDatabase = null;
                });
                if (connectionId != null) {
                  _loadDatabasesForConnection(connectionId);
                } else {
                  setState(() {
                    _dialogDatabases = [];
                  });
                }
                _loadDiagram();
              },
              onDatabaseChanged: (database) {
                setState(() {
                  _selectedDatabase = database;
                });
                _loadDiagram();
              },
            ),
            _buildHeader(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.network,
            color: context.themeColors.accentBlue,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            l10n.erDiagram,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: AppDesignSystem.fontSize2xl,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space6),
          _buildSearchBox(),
          const Spacer(),
          _buildLayoutButtons(),
          const SizedBox(width: AppDesignSystem.space4),
          _buildFilterButtons(),
          const SizedBox(width: AppDesignSystem.space4),
          _buildExportButton(),
          const SizedBox(width: AppDesignSystem.space2),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: 250,
      height: 32,
      child: TextField(
        decoration: InputDecoration(
          hintText: l10n.erDiagramSearchTables,
          hintStyle: TextStyle(
            color: context.themeColors.textMuted,
            fontSize: 12,
          ),
          prefixIcon: Icon(
            LucideIcons.search,
            color: context.themeColors.textSecondary,
            size: 16,
          ),
          filled: true,
          fillColor: context.themeColors.bgTertiary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space1_5,
          ),
        ),
        style: TextStyle(color: context.themeColors.textPrimary, fontSize: 12),
        onChanged:
            (_) {}, // search filtering deferred — see _getFilteredNodes removal
      ),
    );
  }

  Widget _buildLayoutButtons() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        _buildHeaderButton(
          icon: LucideIcons.rows2,
          tooltip: l10n.erDiagramHierarchicalLayout,
          onPressed: _applyHierarchicalLayout,
        ),
        _buildHeaderButton(
          icon: LucideIcons.audioLines,
          tooltip: l10n.erDiagramForceDirectedLayout,
          onPressed: _applyForceDirectedLayout,
        ),
        _buildHeaderButton(
          icon: LucideIcons.circle,
          tooltip: l10n.erDiagramCircleLayout,
          onPressed: _applyCircleLayout,
        ),
        _buildHeaderButton(
          icon: LucideIcons.refreshCw,
          tooltip: l10n.erDiagramResetLayout,
          onPressed: () {
            if (_diagram != null) {
              _layoutService.resetLayout(nodes: _diagram!.nodes);
              setState(() {});
            }
          },
        ),
      ],
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: context.themeColors.textSecondary, size: 18),
        onPressed: onPressed,
        padding: const EdgeInsets.all(AppDesignSystem.space1),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildFilterButtons() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        _buildFilterChip(
          label: l10n.erDiagramShowIsolated,
          isSelected: _showIsolated,
          onSelected: (value) {
            setState(() {
              _showIsolated = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? context.themeColors.textPrimary
              : context.themeColors.textSecondary,
          fontSize: 11,
        ),
      ),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: context.themeColors.accentBlue.withValues(alpha: 0.2),
      checkmarkColor: context.themeColors.accentBlue,
      backgroundColor: context.themeColors.bgTertiary,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      labelStyle: TextStyle(fontSize: 11),
    );
  }

  Widget _buildExportButton() {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: Icon(
        LucideIcons.download,
        color: context.themeColors.textSecondary,
        size: 18,
      ),
      color: context.themeColors.bgSecondary,
      onSelected: (value) {
        if (value == 'png') {
          _exportAsPng();
        }
      },
      itemBuilder: (context) => [
        CompactPopupMenuItem(
          value: 'png',
          child: Row(
            children: [
              Icon(
                LucideIcons.image,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              SizedBox(width: AppDesignSystem.space2),
              Text(l10n.erDiagramExportAsPNG, style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        // 注：JPG 选项移除 — Flutter 的 toByteData 仅支持 PNG，原 JPG 菜单项
        // 是静默无操作的假桩（onSelected 只匹配 'png'）。如确需 JPG，需引入
        // image 包做 PNG→JPG 转码，成本远高于价值。
      ],
    );
  }

  Widget _buildCloseButton() {
    return IconButton(
      icon: Icon(
        LucideIcons.x,
        color: context.themeColors.textSecondary,
        size: 20,
      ),
      onPressed: () => Navigator.of(context).pop(),
      padding: const EdgeInsets.all(AppDesignSystem.space1),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context)!;
    if (_isLoading) {
      return Center(
        child: AppBrandedLoading(size: 32, label: l10n.erDiagramLoading),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              color: context.themeColors.error,
              size: 48,
            ),
            const SizedBox(height: AppDesignSystem.space4),
            Text(
              l10n.erDiagramErrorLoading,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            SelectableText(
              _error!,
              style: TextStyle(color: context.themeColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDesignSystem.space4),
            ElevatedButton(
              onPressed: _loadDiagram,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
              ),
              child: Text(l10n.erDiagramRetry),
            ),
          ],
        ),
      );
    }

    if (_diagram == null) {
      return Center(
        child: Text(
          l10n.erDiagramNoData,
          style: TextStyle(color: context.themeColors.textSecondary),
        ),
      );
    }

    return Row(
      children: [
        // Canvas area
        Expanded(
          // RepaintBoundary 包裹 ERCanvas，使 _exportAsPng 能截到完整画布
          child: RepaintBoundary(
            key: _canvasBoundaryKey,
            child: ERCanvas(
              diagram: _diagram!,
              selectedNode: _selectedNode,
              onNodeSelected: _handleNodeSelected,
              showIsolated: _showIsolated,
            ),
          ),
        ),

        // Detail panel
        if (_selectedNodeDetails != null)
          ERDetailPanel(
            tableDetails: _selectedNodeDetails!,
            onClose: () {
              setState(() {
                _selectedNode = null;
                _selectedNodeDetails = null;
              });
            },
          ),
      ],
    );
  }
}
