// ============================================================================
// EditorFocusState - SQL 编辑器焦点跟踪（spec 040 Phase 2.2）
// ----------------------------------------------------------------------------
// GlobalShortcutsWrapper 的 HardwareKeyboard 监听器与编辑器焦点链 onKeyEvent 是
// 两条独立管线：编辑器获焦时 F5/Ctrl+S/Ctrl+Shift+F 会被两边各跑一次（双触发）。
// 本模块跟踪已注册的编辑器焦点节点，供全局处理器查询「主焦点是否在编辑器内」，
// 从而在编辑器获焦时让位（return false），仅无编辑器获焦时全局兜底。
//
// 用 Set + 查询 FocusManager.primaryFocus（而非每节点 listener）避免多编辑器（多
// 标签页）下的 listener 触发顺序竞态。
// ============================================================================

import 'package:flutter/widgets.dart';

final Set<FocusNode> _editorFocusNodes = <FocusNode>{};

/// 注册一个 SQL 编辑器焦点节点（QueryEditorWidget.initState 调用）。
void registerEditorFocusNode(FocusNode node) {
  _editorFocusNodes.add(node);
}

/// 注销（QueryEditorWidget.dispose 调用，须在焦点节点 dispose 前）。
void unregisterEditorFocusNode(FocusNode node) {
  _editorFocusNodes.remove(node);
}

/// 当前主焦点是否在某个 SQL 编辑器内。
bool get isSqlEditorFocused =>
    _editorFocusNodes.contains(FocusManager.instance.primaryFocus);
