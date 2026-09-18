// C01a · UI 插件注册框架 —— 结果渲染器插件接口（C3 消费）。
//
// 对应原型「结果面板渲染器」（sql / nosql / redis 等徽章）。
// C11 已把 results_widget.dart 的 ResultViewMode 固定三分支
// （table / chart / card）迁入可注册渲染器并删除该枚举；C12 增加
// NoSQL 文档 / Redis 键值渲染器；C13 对接 T27 流式。
import 'package:flutter/widgets.dart';

import '../models/execution_result.dart';
import '../models/result_data_shape.dart';
import '../models/result_filter.dart'
    show ColumnFilter, ColumnDataType, ResultFilterService;
import '../organisms/connection/column_filter_widget.dart' show SortState;
import '../organisms/results/virtualized_data_table.dart' show CellEditState;
import 'plugin_descriptor.dart';

// C12：ResultDataShape 枚举移至 models 层（ExecutionResult.dataShape 需要
// 序列化携带，避免 models → plugins 反向依赖）；此处 re-export 保持
// 既有 import（渲染器/注册表/宿主）零改动。
export '../models/result_data_shape.dart';

/// 表格视图交互桥（C11）：表格渲染器与宿主管线之间的全部回调与状态。
///
/// 宿主持有过滤/排序/行搜索/单元格编辑的交互状态与处理器（这些管线
/// 跨视图共享——切到 chart 再切回 table 过滤仍生效），渲染器只做参数
/// 转发，不拥有状态。字段与迁移前 results_widget._buildTableView 的
/// VirtualizedDataTable 参数逐项对齐。
class TableViewInteraction {
  final ResultFilterService filterService;
  final SortState? sortState;

  /// 过滤/排序变更回调（触发宿主重跑管线）。
  final void Function(ColumnFilter filter) onFilterChanged;
  final void Function(String columnName) onFilterCleared;
  final void Function(String columnName) onSortToggle;

  /// 单元格编辑回调（U07/D1-A：编辑在宿主入口被拦下提示，写回另立项）。
  final void Function(int rowIndex, String columnName, dynamic value)?
  onCellEdit;
  final CellEditState? activeCellEdit;
  final void Function(String cellKey, String newValue)? onEditConfirm;
  final void Function(String cellKey)? onEditCancel;
  final Map<String, dynamic>? pendingEdits;

  /// 右键 / JSON 双击交互。
  final void Function(
    int rowIndex,
    String columnName,
    dynamic value,
    Offset position,
  )?
  onCellContextMenu;
  final void Function(String columnName, Offset globalPosition)?
  onHeaderContextMenu;
  final void Function(int rowIndex, String columnName, dynamic value)?
  onJsonCellDoubleTap;

  const TableViewInteraction({
    required this.filterService,
    required this.onFilterChanged,
    required this.onFilterCleared,
    required this.onSortToggle,
    this.sortState,
    this.onCellEdit,
    this.activeCellEdit,
    this.onEditConfirm,
    this.onEditCancel,
    this.pendingEdits,
    this.onCellContextMenu,
    this.onHeaderContextMenu,
    this.onJsonCellDoubleTap,
  });
}

/// 渲染上下文：渲染器所需的结果数据与其执行元信息。
///
/// C11 起携带过滤管线产物（[rows] / [columns] / [columnTypes]——宿主
/// 保证所有渲染器消费同一份过滤后数据）与两个可选交互面（AI 趋势回调 /
/// 表格交互桥）。C12 为 Redis 卡片（TTL/编码/长度）继续按需扩展；
/// C13 流式对接后 [result] 可为分块累积中的中间态。
@immutable
class ResultRenderContext {
  final ExecutionResult result;

  /// 过滤/排序/行搜索管线产物（所有渲染器消费同一份，切换视图不丢过滤）。
  final List<Map<String, dynamic>> rows;

  /// 列序（宿主从数据首行 keys 提取）。
  final List<String> columns;

  /// 列类型检测结果（宿主 filterService 检测后镜像）。
  final Map<String, ColumnDataType> columnTypes;

  /// AI 趋势分析回调（chart 渲染器消费；宿主注入门控与 provider 配置
  /// 获取，null 时 ChartView 不显示按钮）。
  final Future<String> Function()? onAiTrendRequest;

  /// 表格交互桥（表格渲染器消费；其他渲染器忽略）。
  final TableViewInteraction? tableView;

  const ResultRenderContext({
    required this.result,
    required this.rows,
    required this.columns,
    required this.columnTypes,
    this.onAiTrendRequest,
    this.tableView,
  });
}

/// 结果渲染器插件（C3 消费）。
///
/// C11 起 table / chart / card 三渲染器经 bootstrap 注册；C12 增加
/// `json` / `document` / `keyValue` 等扩展模式。
abstract interface class ResultRendererPlugin {
  PluginDescriptor get descriptor;

  /// 视图模式 id（命名规范：小驼峰，与原 ResultViewMode 枚举名对齐——
  /// `table` / `chart` / `card`；C12 起 `json` / `document` / `keyValue`）。
  /// 字符串而非枚举：渲染器可注册宿主不认识的新模式（视图切换 UI 按注册
  /// 表生成）。
  String get viewModeId;

  /// 本渲染器可处理的结果形态（如表格渲染器声明 sqlRows + nosqlDocument）。
  Set<ResultDataShape> get supportedShapes;

  /// 渲染结果视图。
  Widget build(BuildContext context, ResultRenderContext renderContext);
}
