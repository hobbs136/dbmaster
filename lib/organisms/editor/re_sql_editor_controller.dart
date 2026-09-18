import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// T17/T18：re_editor 编辑器门面。
///
/// 对 [QueryEditorWidget] 暴露与旧 [TextEditingController] 路径等价的
/// 「文本读写 + 选区 + 焦点」契约，内部委托 [CodeLineEditingController]：
/// - `text` 设值 = 可撤销整体替换（格式化/历史回填等），光标落文末；
/// - [loadText] = 不可撤销整体替换（tab 切换装载，避免跨 tab undo 污染）；
/// - 文本变更回调只在**用户编辑**时触发（程序化设值静默），与旧
///   `TextField.onChanged` 语义一致，编排层的防抖管线无需感知差异。
class ReSqlEditorController {
  final CodeLineEditingController codeController;
  final FocusNode focusNode = FocusNode();

  final List<void Function(String)> _textListeners = [];
  CodeLines? _lastCodeLines;
  bool _programmatic = false;

  ReSqlEditorController({String? text})
    : codeController = CodeLineEditingController.fromText(text) {
    codeController.addListener(_onCodeControllerNotify);
    _lastCodeLines = codeController.value.codeLines;
  }

  void addTextChangeListener(void Function(String) listener) {
    _textListeners.add(listener);
  }

  void removeTextChangeListener(void Function(String) listener) {
    _textListeners.remove(listener);
  }

  void _onCodeControllerNotify() {
    if (_programmatic) return;
    final value = codeController.value;
    if (identical(_lastCodeLines, value.codeLines)) return;
    _lastCodeLines = value.codeLines;
    final text = codeController.text;
    for (final listener in List.of(_textListeners)) {
      listener(text);
    }
  }

  String get text => codeController.text;

  /// 可撤销整体替换，光标落文末（旧 `.text =` + 收尾设 selection 的合并语义）。
  set text(String value) {
    if (value == codeController.text) return;
    _programmatic = true;
    codeController.text = value;
    _moveCursorToTextEnd();
    _programmatic = false;
    _lastCodeLines = codeController.value.codeLines;
  }

  /// 不可撤销整体替换（tab 切换/外部同步装载），光标归零并清空 undo 历史。
  void loadText(String value) {
    _programmatic = true;
    if (value != codeController.text) {
      codeController.text = value;
      codeController.clearHistory();
    }
    codeController.cancelSelection();
    codeController.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    _programmatic = false;
    _lastCodeLines = codeController.value.codeLines;
  }

  void _moveCursorToTextEnd() {
    final lines = codeController.codeLines;
    final lastIndex = lines.length - 1;
    codeController.selection = CodeLineSelection.collapsed(
      index: lastIndex,
      offset: lines[lastIndex].length,
    );
  }

  void clear() => loadText('');

  /// 以 IME 会话语义整文替换（测试/外部注入用）。
  ///
  /// [CodeLineEditingController.edit] 是「相对当前选区替换」的编辑会话
  /// 语义——直接传全文会在已有内容时变成光标处插入（内容翻倍）。此方法
  /// 先全选再 edit，语义等价旧 `tester.enterText`：整文替换 + 触发
  /// text-change 管线（校验/持久化防抖照常走）。
  void replaceAllText(String text) {
    selectAll();
    codeController.edit(TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    ));
  }

  String get selectedText => codeController.selectedText;

  /// 是否存在有效选区（右键菜单 cut/copy、「执行选中 SQL」判据）。
  bool get hasSelection {
    final selection = codeController.selection;
    return !selection.isCollapsed;
  }

  void selectAll() => codeController.selectAll();

  void copy() => codeController.copy();

  void cut() => codeController.cut();

  void paste() => codeController.paste();

  /// 在光标处插入文本（拖拽表名/侧栏列名插入），可撤销，光标落在插入文本之后。
  void insertAtCursor(String value) => codeController.replaceSelection(value);

  /// 光标位置（1 基），供状态栏显示。
  int get cursorLine => codeController.selection.extentIndex + 1;
  int get cursorColumn => codeController.selection.extentOffset + 1;

  /// 光标所在行文本（含光标前内容），供片段 `/trigger` 检测等行内解析。
  String get currentLineText {
    final selection = codeController.selection;
    return codeController.codeLines[selection.extentIndex].text;
  }

  /// 光标在其所在行内的偏移。
  int get cursorLineOffset => codeController.selection.extentOffset;

  /// 光标的全文绝对偏移（换行计 1 字符）。多行文档为 O(行数)，仅在
  /// 补全服务等需要全文上下文的低频路径调用。
  int get cursorAbsoluteOffset {
    final selection = codeController.selection;
    final lines = codeController.codeLines;
    var offset = 0;
    for (var i = 0; i < selection.extentIndex; i++) {
      offset += lines[i].length + 1;
    }
    return offset + selection.extentOffset;
  }

  void requestFocus() => focusNode.requestFocus();

  void dispose() {
    codeController.removeListener(_onCodeControllerNotify);
    codeController.dispose();
    focusNode.dispose();
  }
}
