/// 轻量只读结果快照表 —— AI 工作台工具卡内嵌表格。
///
/// 规格：design-ai-workbench §3 D6 ③（R1 重裁）+ §8【三】。
/// 本组件是 T01 性能探针 gate 的载体（P95 ≤ 16.7ms），**性能不变式优先于一切便利**：
/// - 单一垂直 `ListView.builder` + `itemExtent`；无水平滚动视图、无多滚动条、
///   无底栏、无列宽 resizer、无过滤/排序/编辑入口与回调面（只读）；
/// - 行不 keepAlive（`addAutomaticKeepAlives: false`）、无逐行 RepaintBoundary，
///   整表仅一个 `RepaintBoundary`；
/// - 表头独立固定（不随行区滚动）；列宽等分 + 单元格 ellipsis
///   （超宽结果等分压缩；完整视图走「在网格中打开」，由卡负责，本组件不管）。
///
/// 视觉数值（design §8【二】R1 备注）：行高 26 / 表头 28 沿用 VirtualizedDataTable
/// 默认值作为**组件常量**（不新增 token）；高度上限消费 `toolCardContentMaxHeight`
/// token（超出上限取上限，内部滚动）。本组件不 import VirtualizedDataTable。
///
/// 入参约定：[rows] 内层 List 与 [columns] 按下标对齐，且已是展示字符串
/// （由卡侧从 payload 快照转换，见 design §4.4），本组件零转换、零交互。
/// 需要**有界宽度**的父约束（等分列依赖）；高度有界或无界均可（无界时取 token 上限）。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// 只读快照表（molecule 级预览视图，非全功能表格——全功能表格仍是
/// VirtualizedDataTable，经典结果面板专属）。
class ResultSnapshotTable extends StatelessWidget {
  const ResultSnapshotTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  /// 数据行高 26（design §8【二】R1：沿用 VDT 默认值，不新增 token）。
  static const double rowHeight = 26.0;

  /// 表头高 28，独立固定、不随行区滚动（design §8【二】R1：沿用 VDT 默认值）。
  static const double headerHeight = 28.0;

  /// 列名列表（同时决定列数；列宽等分压缩，表头/单元格均 ellipsis）。
  final List<String> columns;

  /// 行数据：外层 = 行，内层 = 与 [columns] 按下标对齐的单元格字符串。
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    // 无列可展示（防御：正常 result 卡 payload 必有列）→ 空占位。
    if (columns.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 高度上限 = min(父约束, token 360)；父高度无界时取 token（§8【三】
        // 「上限 360 / 内部滚动」作为快照区自带性质）。父约束为紧约束时以父为准。
        final double maxHeight =
            constraints.hasBoundedHeight &&
                constraints.maxHeight < AppDesignSystem.toolCardContentMaxHeight
            ? constraints.maxHeight
            : AppDesignSystem.toolCardContentMaxHeight;
        return SizedBox(
          height: maxHeight,
          child: RepaintBoundary(
            child: Column(
              children: [
                _SnapshotHeader(columns: columns),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemExtent: rowHeight,
                    // 性能不变式（T01 gate 载体）：行不保活；行结构极简，
                    // 不加逐行重绘边界，整表单一 RepaintBoundary。
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    cacheExtent: rowHeight * 3,
                    itemBuilder: (context, index) => _SnapshotRow(
                      key: ValueKey('result_snapshot_row_$index'),
                      cells: rows[index],
                      columnCount: columns.length,
                      isEven: index.isEven,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 固定表头：等分列 + ellipsis，不随行区滚动（design §8【三】表头 28）。
class _SnapshotHeader extends StatelessWidget {
  const _SnapshotHeader({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ResultSnapshotTable.headerHeight,
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          for (final name in columns)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 数据行：等分列 + 单元格 ellipsis，斑马纹与经典表格视觉一致，无任何交互。
class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    super.key,
    required this.cells,
    required this.columnCount,
    required this.isEven,
  });

  final List<String> cells;
  final int columnCount;
  final bool isEven;

  @override
  Widget build(BuildContext context) {
    final cellStyle = TextStyle(
      fontSize: 13,
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
      color: context.themeColors.textPrimary,
    );
    return Container(
      decoration: BoxDecoration(
        color: isEven
            ? context.themeColors.bgSecondary
            : context.themeColors.bgPrimary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < columnCount; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                ),
                child: Text(
                  // 防御：行数据短于列数（如 null 键缺位）时补空串，不越界。
                  i < cells.length ? cells[i] : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cellStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
