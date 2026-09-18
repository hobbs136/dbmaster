// C11 · 渲染器注册化 —— 表格渲染器（原 ResultViewMode.table 三分支之一）。
//
// 行为与迁移前 results_widget._buildTableView 逐项保持：全部交互状态
// （过滤/排序/编辑/右键）由宿主经 TableViewInteraction 桥提供，渲染器
// 只做参数转发，不拥有状态。
// C12：同时声明 nosqlDocument / redisKeyValue 形态——文档/键值是新形态的
// 默认视图（注册序在前），表格保留为可切换兜底（拍平视图不因换脸丢失）。
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/result_renderer_plugin.dart';
import '../virtualized_data_table.dart';

class TableResultRenderer implements ResultRendererPlugin {
  const TableResultRenderer();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'sql-result-renderer',
        icon: LucideIcons.table2,
        displayName: (l10n) => l10n.viewModeTable,
      );

  @override
  String get viewModeId => 'table';

  @override
  Set<ResultDataShape> get supportedShapes => const {
        ResultDataShape.sqlRows,
        ResultDataShape.nosqlDocument,
        ResultDataShape.redisKeyValue,
      };

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) {
    final tableView = renderContext.tableView;
    return VirtualizedDataTable(
      columns: renderContext.columns,
      data: renderContext.rows,
      columnTypes: renderContext.columnTypes,
      truncatedColumns: renderContext.result.truncatedColumns,
      onFilterChanged: tableView?.onFilterChanged,
      onFilterCleared: tableView?.onFilterCleared,
      onSortToggle: tableView?.onSortToggle,
      activeFilters: tableView?.filterService.filters,
      sortState: tableView?.sortState,
      filterService: tableView?.filterService,
      onCellEdit: tableView?.onCellEdit,
      activeCellEdit: tableView?.activeCellEdit,
      onEditConfirm: tableView?.onEditConfirm,
      onEditCancel: tableView?.onEditCancel,
      pendingEdits: tableView?.pendingEdits,
      onCellContextMenu: tableView?.onCellContextMenu,
      onHeaderContextMenu: tableView?.onHeaderContextMenu,
      onJsonCellDoubleTap: tableView?.onJsonCellDoubleTap,
    );
  }
}
