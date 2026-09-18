import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:re_editor/re_editor.dart';
import '../../services/sql_autocomplete_service.dart' show Suggestion;
import '../../services/sql_validator_service.dart' show ErrorSeverity;
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import 're_code_autocomplete.dart';
import 're_editor_theme.dart';
import 're_sql_editor_controller.dart';
import 'editor_text_style.dart' show EditorTextStyle;

/// T17/T18：基于 re_editor 的 SQL/代码编辑器（全量替换旧 SqlCodeEditor）。
///
/// 行式渲染 + copy-on-write 文本模型 + isolate 高亮，根治 EditableText
/// 单段全文首排的线性卡顿（958K/3MB 粘贴）。行为对齐旧编辑器：
/// 行号 + 校验/安全红点、当前行高亮、四色主题、`/` 片段、SQL/Mongo 补全、
/// 只读、右键菜单（由宿主 GestureDetector 提供）。
class ReSqlEditor extends StatefulWidget {
  final ReSqlEditorController controller;
  final String language;
  final String? hintText;
  final bool readOnly;
  final Map<int, ErrorSeverity> errors;
  final EdgeInsetsGeometry? padding;

  /// 用户编辑回调（程序化设值不触发，与旧 TextField.onChanged 语义一致）。
  final void Function(String)? onChanged;

  /// 光标/选区变化回调（C21 状态条行/列显示）。
  ///
  /// 参数为 1 基逻辑行列（软换行段落经 index2lineIndex 折算）；
  /// 外围 chrome 管线，不触碰编辑器渲染本体（铁律 5）。
  final void Function(int line, int column)? onSelectionChanged;

  /// async 补全解析器（null = 不启用补全；由宿主按 dbType 分派服务）。
  final Future<List<Suggestion>> Function(String text, int cursorOffset)?
  autocompleteResolver;

  /// 是否启用补全（provider.autocompleteEnabled）。
  final bool autocompleteEnabled;

  /// 是否启用 `/` 片段命令。
  final bool snippetsEnabled;

  /// Ctrl+S（re_editor 内建 save intent，无默认处理）转发。
  final VoidCallback? onSaveShortcut;

  const ReSqlEditor({
    super.key,
    required this.controller,
    this.language = 'sql',
    this.hintText,
    this.readOnly = false,
    this.errors = const {},
    this.padding,
    this.onChanged,
    this.onSelectionChanged,
    this.autocompleteResolver,
    this.autocompleteEnabled = false,
    this.snippetsEnabled = false,
    this.onSaveShortcut,
  });

  @override
  State<ReSqlEditor> createState() => _ReSqlEditorState();
}

class _ReSqlEditorState extends State<ReSqlEditor> {
  late final ReAutocompleteBridge _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = ReAutocompleteBridge(controller: widget.controller);
    _syncBridgeConfig();
    if (widget.onChanged != null) {
      widget.controller.addTextChangeListener(widget.onChanged!);
    }
    // 选区变化：控制器本身是 ValueNotifier（selection setter 触发
    // notifyListeners），直接挂 listener 即可覆盖光标移动。
    widget.controller.codeController.addListener(_handleSelectionChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleSelectionChange());
  }

  /// 行列换算：逻辑行经 index2lineIndex（软换行折算），列为 extent 偏移。
  void _handleSelectionChange() {
    final cb = widget.onSelectionChanged;
    if (cb == null) return;
    final code = widget.controller.codeController;
    final selection = code.selection;
    final line = code.index2lineIndex(selection.extentIndex) + 1;
    cb(line, selection.extentOffset + 1);
  }

  void _syncBridgeConfig() {
    _bridge.enabled = widget.autocompleteEnabled;
    _bridge.snippetsEnabled = widget.snippetsEnabled;
    _bridge.resolver = widget.autocompleteResolver;
  }

  @override
  void didUpdateWidget(ReSqlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onChanged != widget.onChanged) {
      if (oldWidget.onChanged != null) {
        widget.controller.removeTextChangeListener(oldWidget.onChanged!);
      }
      if (widget.onChanged != null) {
        widget.controller.addTextChangeListener(widget.onChanged!);
      }
    }
    _syncBridgeConfig();
  }

  @override
  void dispose() {
    widget.controller.codeController.removeListener(_handleSelectionChange);
    if (widget.onChanged != null) {
      widget.controller.removeTextChangeListener(widget.onChanged!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useAutocomplete =
        widget.autocompleteResolver != null || widget.snippetsEnabled;
    final editor = CodeEditor(
      controller: widget.controller.codeController,
      focusNode: widget.controller.focusNode,
      autofocus: false,
      readOnly: widget.readOnly,
      wordWrap: true,
      hint: widget.hintText,
      padding: widget.padding ?? const EdgeInsets.all(8),
      style: ReSqlEditorTheme.style(context, widget.language),
      indicatorBuilder: _buildIndicator,
      shortcutsActivatorsBuilder: const _SqlShortcutsActivatorsBuilder(),
      shortcutOverrideActions: _buildOverrideActions(),
      // 折叠分析在 isolate 跑但对 SQL 无收益，关闭省一次全文任务。
      chunkAnalyzer: const NonCodeChunkAnalyzer(),
      // 括号/引号自动配对为新增行为，保持与旧编辑器一致先关。
      autocompleteSymbols: false,
    );
    if (!useAutocomplete) {
      return editor;
    }
    return CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) {
        _bridge.activeNotifier = notifier;
        _bridge.activeOnSelected = onSelected;
        return ReAutocompleteView(
          notifier: notifier,
          onSelected: onSelected,
          bridge: _bridge,
        );
      },
      promptsBuilder: _bridge,
      child: editor,
    );
  }

  Widget _buildIndicator(
    BuildContext context,
    CodeLineEditingController editingController,
    CodeChunkController chunkController,
    CodeIndicatorValueNotifier notifier,
  ) {
    return _SqlLineNumberIndicator(
      controller: editingController,
      notifier: notifier,
      errors: widget.errors,
      textStyle: EditorTextStyle.lineNumberStyle(context),
      focusedTextStyle: EditorTextStyle.lineNumberStyle(
        context,
        isCurrentLine: true,
      ),
      backgroundColor: context.themeColors.bgSecondary,
      rowHighlightColor: context.themeColors.bgTertiary.withValues(alpha: 0.5),
      borderColor: context.themeColors.borderSubtle,
      errorColor: context.themeColors.error,
      warningColor: context.themeColors.warning,
    );
  }

  Map<Type, Action<Intent>> _buildOverrideActions() {
    final actions = <Type, Action<Intent>>{
      // Tab：补全弹窗开着 = 选中建议（旧版平价），否则缩进。
      CodeShortcutIndentIntent: _IndentOrAutocompleteAction(
        bridge: _bridge,
        controller: widget.controller,
      ),
      // Home/End：Smart Home（列 0 ↔ 首个非空白字符切换，旧版平价）。
      CodeShortcutCursorMoveLineEdgeIntent: _SmartHomeAction(
        controller: widget.controller,
      ),
    };
    final onSave = widget.onSaveShortcut;
    if (onSave != null) {
      actions[CodeShortcutSaveIntent] = CallbackAction<CodeShortcutSaveIntent>(
        onInvoke: (intent) {
          onSave();
          return intent;
        },
      );
    }
    return actions;
  }
}

/// Windows/Linux 摘掉 Ctrl+Enter（让位「执行 SQL」）与 Ctrl+Alt+F
/// （让位「格式化」）的快捷键表；其余委托 re_editor 默认。
class _SqlShortcutsActivatorsBuilder implements CodeShortcutsActivatorsBuilder {
  const _SqlShortcutsActivatorsBuilder();

  static const DefaultCodeShortcutsActivatorsBuilder _defaults =
      DefaultCodeShortcutsActivatorsBuilder();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    switch (type) {
      case CodeShortcutType.newLine:
        final defaults = _defaults.build(type) ?? const [];
        // 去掉 Ctrl/Cmd+Enter 系（含 shift 变体），其余（Enter/Shift+Enter/
        // 小键盘 Enter）保留。
        return defaults
            .where(
              (a) =>
                  a is! SingleActivator || (!a.control && !a.meta),
            )
            .toList();
      case CodeShortcutType.replace:
        // Ctrl+Alt+F 与「快速格式化」撞车，禁用替换模式。
        return const [];
      default:
        return _defaults.build(type);
    }
  }
}

class _IndentOrAutocompleteAction extends Action<CodeShortcutIndentIntent> {
  _IndentOrAutocompleteAction({required this.bridge, required this.controller});

  final ReAutocompleteBridge bridge;
  final ReSqlEditorController controller;

  @override
  Object? invoke(CodeShortcutIndentIntent intent) {
    if (bridge.isShowing) {
      bridge.selectActive();
      return intent;
    }
    controller.codeController.applyIndent();
    return intent;
  }
}

/// Home 在「首个非空白字符 ↔ 行首」间切换；End 走行尾（旧 _handleSmartHome 平价）。
class _SmartHomeAction
    extends Action<CodeShortcutCursorMoveLineEdgeIntent> {
  _SmartHomeAction({required this.controller});

  final ReSqlEditorController controller;

  @override
  Object? invoke(CodeShortcutCursorMoveLineEdgeIntent intent) {
    final code = controller.codeController;
    if (intent.forward) {
      code.moveCursorToLineEnd();
      return intent;
    }
    final selection = code.selection;
    final lineText = code.codeLines[selection.extentIndex].text;
    var firstNonSpace = 0;
    while (firstNonSpace < lineText.length &&
        (lineText[firstNonSpace] == ' ' || lineText[firstNonSpace] == '\t')) {
      firstNonSpace++;
    }
    final target = selection.extentOffset > firstNonSpace ? firstNonSpace : 0;
    code.selection = CodeLineSelection.collapsed(
      index: selection.extentIndex,
      offset: target,
    );
    return intent;
  }
}

/// 行号指示器：行号 + 当前行为背景 + 校验/安全错误红点（T011/B3 平价）。
///
/// 镜像 re_editor DefaultCodeLineNumber 的渲染模型（吃可见段落 notifier、
/// 逻辑行号经 index2lineIndex 换算、软换行行只标首个视觉行），额外画：
/// 槽位背景/右边框、当前行整行底色、行号左侧 6px 级别色点。
class _SqlLineNumberIndicator extends LeafRenderObjectWidget {
  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final Map<int, ErrorSeverity> errors;
  final TextStyle textStyle;
  final TextStyle focusedTextStyle;
  final Color backgroundColor;
  final Color rowHighlightColor;
  final Color borderColor;
  final Color errorColor;
  final Color warningColor;

  const _SqlLineNumberIndicator({
    required this.controller,
    required this.notifier,
    required this.errors,
    required this.textStyle,
    required this.focusedTextStyle,
    required this.backgroundColor,
    required this.rowHighlightColor,
    required this.borderColor,
    required this.errorColor,
    required this.warningColor,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _SqlLineNumberRenderObject(
      controller: controller,
      notifier: notifier,
      errors: errors,
      textStyle: textStyle,
      focusedTextStyle: focusedTextStyle,
      backgroundColor: backgroundColor,
      rowHighlightColor: rowHighlightColor,
      borderColor: borderColor,
      errorColor: errorColor,
      warningColor: warningColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _SqlLineNumberRenderObject renderObject,
  ) {
    renderObject
      ..controller = controller
      ..notifier = notifier
      ..errors = errors
      ..textStyle = textStyle
      ..focusedTextStyle = focusedTextStyle
      ..backgroundColor = backgroundColor
      ..rowHighlightColor = rowHighlightColor
      ..borderColor = borderColor
      ..errorColor = errorColor
      ..warningColor = warningColor;
  }
}

class _SqlLineNumberRenderObject extends RenderBox {
  _SqlLineNumberRenderObject({
    required CodeLineEditingController controller,
    required CodeIndicatorValueNotifier notifier,
    required Map<int, ErrorSeverity> errors,
    required TextStyle textStyle,
    required TextStyle focusedTextStyle,
    required Color backgroundColor,
    required Color rowHighlightColor,
    required Color borderColor,
    required Color errorColor,
    required Color warningColor,
  }) : _controller = controller,
       _notifier = notifier,
       _errors = errors,
       _textStyle = textStyle,
       _focusedTextStyle = focusedTextStyle,
       _backgroundColor = backgroundColor,
       _rowHighlightColor = rowHighlightColor,
       _borderColor = borderColor,
       _errorColor = errorColor,
       _warningColor = warningColor;

  static const int _minNumberCount = 3;
  static const double _rightPadding = 8;
  static const double _dotSize = 6;
  static const double _dotGap = 4;

  CodeLineEditingController _controller;
  CodeIndicatorValueNotifier _notifier;
  Map<int, ErrorSeverity> _errors;
  TextStyle _textStyle;
  TextStyle _focusedTextStyle;
  Color _backgroundColor;
  Color _rowHighlightColor;
  Color _borderColor;
  Color _errorColor;
  Color _warningColor;

  final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  set controller(CodeLineEditingController value) {
    if (_controller != value) {
      if (attached) {
        _controller.removeListener(_onCodeLineChanged);
        value.addListener(_onCodeLineChanged);
      }
      _controller = value;
      markNeedsLayout();
    }
  }

  set notifier(CodeIndicatorValueNotifier value) {
    if (_notifier != value) {
      if (attached) {
        _notifier.removeListener(markNeedsPaint);
        value.addListener(markNeedsPaint);
      }
      _notifier = value;
      markNeedsPaint();
    }
  }

  set errors(Map<int, ErrorSeverity> value) {
    _errors = value;
    markNeedsPaint();
  }

  set textStyle(TextStyle value) {
    if (_textStyle != value) {
      _textStyle = value;
      markNeedsLayout();
    }
  }

  set focusedTextStyle(TextStyle value) {
    if (_focusedTextStyle != value) {
      _focusedTextStyle = value;
      markNeedsPaint();
    }
  }

  set backgroundColor(Color value) {
    _backgroundColor = value;
    markNeedsPaint();
  }

  set rowHighlightColor(Color value) {
    _rowHighlightColor = value;
    markNeedsPaint();
  }

  set borderColor(Color value) {
    _borderColor = value;
    markNeedsPaint();
  }

  set errorColor(Color value) {
    _errorColor = value;
    markNeedsPaint();
  }

  set warningColor(Color value) {
    _warningColor = value;
    markNeedsPaint();
  }

  @override
  void attach(covariant PipelineOwner owner) {
    _controller.addListener(_onCodeLineChanged);
    _notifier.addListener(markNeedsPaint);
    super.attach(owner);
  }

  @override
  void detach() {
    _controller.removeListener(_onCodeLineChanged);
    _notifier.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    assert(
      constraints.maxHeight > 0 && constraints.maxHeight != double.infinity,
      'SqlLineNumberIndicator should have an explicit height.',
    );
    final digits = _controller.codeLines.length.toString().length;
    _textPainter.text = TextSpan(
      text: '0' * (digits > _minNumberCount ? digits : _minNumberCount),
      style: _textStyle,
    );
    _textPainter.layout();
    final width = _textPainter.width + _rightPadding + _dotSize + _dotGap;
    size = Size(width > 36 ? width : 36, constraints.maxHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final value = _notifier.value;
    // 槽位背景 + 右边框（旧 LineNumbers 视觉平价）
    final bgPaint = Paint()..color = _backgroundColor;
    canvas.drawRect(offset & size, bgPaint);
    final borderPaint = Paint()
      ..color = _borderColor
      ..strokeWidth = 1;
    canvas.drawLine(
      offset + Offset(size.width, 0),
      offset + Offset(size.width, size.height),
      borderPaint,
    );
    if (value == null || value.paragraphs.isEmpty) {
      return;
    }

    canvas.save();
    canvas.clipRect(offset & size);
    // 当前行底色
    for (final paragraph in value.paragraphs) {
      if (paragraph.index == value.focusedIndex) {
        final rowPaint = Paint()..color = _rowHighlightColor;
        canvas.drawRect(
          Rect.fromLTWH(
            offset.dx,
            offset.dy + paragraph.offset.dy,
            size.width,
            paragraph.height,
          ),
          rowPaint,
        );
        break;
      }
    }

    int firstLineIndex = _controller.index2lineIndex(
      value.paragraphs.first.index,
    );
    final rowHeight = EditorTextStyle.fontSize * EditorTextStyle.lineHeight;
    for (final paragraph in value.paragraphs) {
      final lineNumber = firstLineIndex + 1;
      final isFocused = paragraph.index == value.focusedIndex;
      _textPainter.text = TextSpan(
        text: lineNumber.toString(),
        style: isFocused ? _focusedTextStyle : _textStyle,
      );
      _textPainter.layout();
      final numberX = offset.dx +
          size.width -
          _rightPadding -
          _textPainter.width;
      _textPainter.paint(canvas, Offset(numberX, offset.dy + paragraph.offset.dy));

      // 错误红点（首个视觉行垂直居中）
      final severity = _errors[lineNumber];
      if (severity != null) {
        final dotPaint = Paint()..color = _severityColor(severity);
        final rowCenter = offset.dy +
            paragraph.offset.dy +
            (paragraph.height < rowHeight
                ? paragraph.height / 2
                : rowHeight / 2);
        canvas.drawCircle(
          Offset(numberX - _dotGap - _dotSize / 2, rowCenter),
          _dotSize / 2,
          dotPaint,
        );
      }
      firstLineIndex += _controller.codeLines[paragraph.index].lineCount;
    }
    canvas.restore();
  }

  Color _severityColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.error:
        return _errorColor;
      case ErrorSeverity.warning:
        return _warningColor;
      case ErrorSeverity.info:
        // 编辑器 severity info 用蓝（VS Code 惯例），与 info 青令牌有意区分
        return const Color(0xFF4099FF);
    }
  }

  void _onCodeLineChanged() {
    if (!attached) {
      return;
    }
    final digits = _controller.codeLines.length.toString().length;
    final minDigits = digits > _minNumberCount ? digits : _minNumberCount;
    _textPainter.text = TextSpan(
      text: '0' * minDigits,
      style: _textStyle,
    );
    _textPainter.layout();
    final need = _textPainter.width + _rightPadding + _dotSize + _dotGap;
    if ((need > 36 ? need : 36) != size.width) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }
}
