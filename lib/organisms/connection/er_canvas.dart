import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../models/er_diagram.dart';
import 'er_node_widget.dart';
import 'er_edge_widget.dart';
import '../../theme/app_colors.dart';

class ERCanvas extends StatefulWidget {
  final ERDiagram diagram;
  final ERNode? selectedNode;
  final Function(ERNode)? onNodeSelected;
  final Function(Offset)? onCanvasDrag;
  final bool showIsolated;

  const ERCanvas({
    super.key,
    required this.diagram,
    this.selectedNode,
    this.onNodeSelected,
    this.onCanvasDrag,
    this.showIsolated = true,
  });

  @override
  State<ERCanvas> createState() => _ERCanvasState();
}

class _ERCanvasState extends State<ERCanvas> {
  final TransformationController _transformationController =
      TransformationController();
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerView();
    });
  }

  @override
  void didUpdateWidget(ERCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagram != widget.diagram) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerView();
      });
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _centerView() {
    if (!mounted || widget.diagram.nodes.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final node in widget.diagram.nodes) {
      minX = minX < node.position.dx ? minX : node.position.dx;
      minY = minY < node.position.dy ? minY : node.position.dy;
      maxX = maxX > node.position.dx + 200 ? maxX : node.position.dx + 200;
      maxY = maxY > node.position.dy + 100 ? maxY : node.position.dy + 100;
    }

    final contentWidth = maxX - minX + 200;
    final contentHeight = maxY - minY + 200;

    final screenSize = MediaQuery.of(context).size;
    final scaleX = screenSize.width / contentWidth;
    final scaleY = screenSize.height / contentHeight;
    _currentScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.3, 2.0);

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    _transformationController.value = Matrix4.identity()
      ..translate(
        screenSize.width / 2 - centerX * _currentScale,
        screenSize.height / 2 - centerY * _currentScale,
      )
      ..scale(_currentScale);
  }

  void _resetView() {
    _centerView();
  }

  void _zoomIn() {
    final current = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (current * 1.2).clamp(0.1, 5.0);
    _applyScale(newScale / current);
  }

  void _zoomOut() {
    final current = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (current / 1.2).clamp(0.1, 5.0);
    _applyScale(newScale / current);
  }

  void _applyScale(double factor) {
    final currentMatrix = _transformationController.value.clone();
    final translation = currentMatrix.getTranslation();
    currentMatrix.setIdentity();
    currentMatrix.translate(translation.x, translation.y);
    currentMatrix.scale(factor, factor);
    _transformationController.value = currentMatrix;
  }

  void _handleNodeTap(ERNode node) {
    widget.onNodeSelected?.call(node);
  }

  @override
  Widget build(BuildContext context) {
    final displayedNodes = widget.showIsolated
        ? widget.diagram.nodes
        : widget.diagram.connectedNodes;

    double minX = 0, minY = 0;
    double maxX = 2000, maxY = 1500;

    if (displayedNodes.isNotEmpty) {
      minX = double.infinity;
      minY = double.infinity;
      maxX = double.negativeInfinity;
      maxY = double.negativeInfinity;
      for (final node in displayedNodes) {
        if (node.position.dx < minX) minX = node.position.dx;
        if (node.position.dy < minY) minY = node.position.dy;
        if (node.position.dx + 220 > maxX) maxX = node.position.dx + 220;
        if (node.position.dy + 120 > maxY) maxY = node.position.dy + 120;
      }
      minX -= 100;
      minY -= 100;
      maxX += 100;
      maxY += 100;
    }

    return Stack(
      children: [
        Container(
          color: context.themeColors.bgPrimary,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.05,
            maxScale: 5.0,
            boundaryMargin: const EdgeInsets.all(500),
            constrained: false,
            child: GestureDetector(
              onTapDown: (details) {
                final matrix = _transformationController.value.clone();
                matrix.invert();
                final point = MatrixUtils.transformPoint(
                  matrix,
                  details.localPosition,
                );
                for (final node in displayedNodes) {
                  if (point.dx >= node.position.dx &&
                      point.dx <= node.position.dx + 200 &&
                      point.dy >= node.position.dy &&
                      point.dy <= node.position.dy + 100) {
                    _handleNodeTap(node);
                    break;
                  }
                }
              },
              child: SizedBox(
                width: maxX - minX + 500,
                height: maxY - minY + 500,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: SizedBox(
                        width: maxX - minX + 500,
                        height: maxY - minY + 500,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ...widget.diagram.edges.map((edge) {
                              if (!displayedNodes.contains(edge.fromNode) ||
                                  !displayedNodes.contains(edge.toNode)) {
                                return const SizedBox.shrink();
                              }
                              return EREdgeWidget(
                                edge: edge,
                                isHighlighted:
                                    widget.selectedNode != null &&
                                    (edge.fromNode == widget.selectedNode ||
                                        edge.toNode == widget.selectedNode),
                              );
                            }),
                            ...displayedNodes.map((node) {
                              return Positioned(
                                left: node.position.dx - minX + 250,
                                top: node.position.dy - minY + 250,
                                child: ERNodeWidget(
                                  key: ValueKey(node.tableName),
                                  node: node,
                                  isSelected: widget.selectedNode == node,
                                  isHighlighted:
                                      widget.selectedNode != null &&
                                      _isConnected(node, widget.selectedNode!),
                                  onTap: () => _handleNodeTap(node),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(right: 16, bottom: 16, child: _buildToolbar()),
        Positioned(left: 16, bottom: 16, child: _buildStatusBar()),
      ],
    );
  }

  bool _isConnected(ERNode node1, ERNode node2) {
    return widget.diagram.edges.any(
      (edge) =>
          (edge.fromNode == node1 && edge.toNode == node2) ||
          (edge.fromNode == node2 && edge.toNode == node1),
    );
  }

  Widget _buildToolbar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolbarButton(
            icon: LucideIcons.zoomIn,
            tooltip: l10n.erDiagramZoomIn,
            onPressed: _zoomIn,
          ),
          Divider(height: 1, color: context.themeColors.dividerColor),
          _buildToolbarButton(
            icon: LucideIcons.zoomOut,
            tooltip: l10n.erDiagramZoomOut,
            onPressed: _zoomOut,
          ),
          Divider(height: 1, color: context.themeColors.dividerColor),
          _buildToolbarButton(
            icon: LucideIcons.maximize2,
            tooltip: l10n.erDiagramFitToScreen,
            onPressed: _resetView,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: context.themeColors.textSecondary, size: 18),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildStatusBar() {
    final l10n = AppLocalizations.of(context)!;
    final scale = _transformationController.value.getMaxScaleOnAxis();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusItem(
            l10n.sidebarTables,
            widget.diagram.tableCount.toString(),
            LucideIcons.table2,
          ),
          const SizedBox(width: AppDesignSystem.space4),
          _buildStatusItem(
            l10n.erDiagramRelations,
            widget.diagram.relationshipCount.toString(),
            LucideIcons.link,
          ),
          const SizedBox(width: AppDesignSystem.space4),
          _buildStatusItem(
            l10n.erDiagramZoom,
            '${(scale * 100).toInt()}%',
            LucideIcons.scan,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: context.themeColors.textSecondary, size: 14),
        const SizedBox(width: AppDesignSystem.space1_5),
        Text(
          '$label: $value',
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
