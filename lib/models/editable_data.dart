import 'package:flutter/material.dart';

// 编辑模式枚举 - 简化为只保留查看和内联编辑
enum EditMode {
  view, // 查看模式
  inline, // 内联编辑模式
}

// 单元格编辑状态类
class CellEditState {
  final int rowIndex;
  final String columnName;
  final Object? originalValue;
  Object? currentValue;
  final TextEditingController controller;

  CellEditState({
    required this.rowIndex,
    required this.columnName,
    required this.originalValue,
    required this.currentValue,
    required this.controller,
  });

  bool get hasChanged => originalValue != currentValue;

  void dispose() {
    controller.dispose();
  }
}

// 编辑结果
class EditResult {
  final bool success;
  final String? errorMessage;
  final String? generatedSql;
  final int? affectedRows;

  EditResult({
    required this.success,
    this.errorMessage,
    this.generatedSql,
    this.affectedRows,
  });

  factory EditResult.success({String? sql, int? rows}) {
    return EditResult(success: true, generatedSql: sql, affectedRows: rows);
  }

  factory EditResult.error(String message) {
    return EditResult(success: false, errorMessage: message);
  }
}

// 导航方向
enum NavigationDirection {
  next, // Tab / Enter
  previous, // Shift+Tab
  up, // Up arrow
  down, // Down arrow
}

// 编辑操作类型
enum EditActionType {
  none,
  cellEdit, // 单个单元格编辑
  batchEdit, // 批量编辑
  addNewRow, // 添加新行
  deleteRow, // 删除行
}

// 待处理的单元格修改
class PendingCellChange {
  final int rowIndex;
  final String columnName;
  final Object? originalValue;
  Object? newValue;

  PendingCellChange({
    required this.rowIndex,
    required this.columnName,
    required this.originalValue,
    required this.newValue,
  });

  bool get hasChanged => originalValue != newValue;

  // 生成单元格的唯一标识
  String get cellKey => '${rowIndex}_$columnName';
}
