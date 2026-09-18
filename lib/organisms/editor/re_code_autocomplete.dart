import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../models/code_snippet.dart' show SnippetDbFamily;
import '../../services/sql_autocomplete_service.dart'
    show Suggestion, SuggestionType;
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import 're_sql_editor_controller.dart';
import 'snippet_commands.dart' show SnippetCommand, SnippetCommands;

/// T17/T18：CodeAutocomplete 桥接层。
///
/// re_editor 的 [CodeAutocompletePromptsBuilder.build] 是同步签名，而既有
/// SQL/Mongo 补全服务是 async（schema 走内存缓存 + 冷启动查库）。桥接策略：
/// 1. **同步首帧**：token 扫描 + 关键字/函数等静态建议立即返回（随打字即时出框）；
/// 2. **异步刷新**：随后调用完整 async 服务（含表名/列名/上下文分派），完成后
///    通过 viewBuilder 捕获的 [ValueNotifier] 原位刷新列表（代际号防串台）；
/// 3. **片段统一**：`/trigger` 检测复用同一弹窗机制（光标锚定/键盘导航/IME
///    自动消失原生提供），片段模板作为 prompt 词插入。
///
/// 不变量：prompts 恒非空（异步结果为空时回退占位 prompt，避免 re_editor
/// 键盘导航对空列表越界）。
class ReAutocompleteBridge implements CodeAutocompletePromptsBuilder {
  ReAutocompleteBridge({required this.controller});

  /// 所属编辑器门面（取全文/光标绝对偏移喂给 async 服务）。
  final ReSqlEditorController controller;

  /// 是否启用补全（QueryEditorWidget 传 provider.autocompleteEnabled）。
  bool enabled = false;

  /// 是否启用 `/` 片段命令（主编辑器 true，Redis Lua 面板 false）。
  bool snippetsEnabled = false;

  /// 片段族过滤（SQL / MongoDB）。
  SnippetDbFamily? snippetFamily;

  /// async 补全解析器（QueryEditorWidget 注入，按 dbType 分派 SQL/Mongo 服务）。
  Future<List<Suggestion>> Function(String text, int cursorOffset)? resolver;

  /// viewBuilder 每次弹出时捕获的 notifier / 选中回调（供异步刷新与 Tab 选中）。
  ValueNotifier<CodeAutocompleteEditingValue>? activeNotifier;
  ValueChanged<CodeAutocompleteResult>? activeOnSelected;

  /// 片段触发正则（与旧 _insertSnippet/_onTextChanged 相同）。
  static final RegExp _snippetTrigger = RegExp(r'(?:^|\s)/([A-Za-z0-9_]*)$');

  /// 补全 token 的分隔符集合（与旧 _applySuggestion 相同）。
  static const _delimiters = {
    ' ',
    '\n',
    '\t',
    ',',
    '(',
    ')',
    '=',
    '<',
    '>',
    '.',
  };

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final lineText = codeLine.text;
    final offset = selection.extentOffset.clamp(0, lineText.length);
    final before = lineText.substring(0, offset);

    // 1) 片段触发：行内光标前匹配 /trigger
    if (snippetsEnabled) {
      final match = _snippetTrigger.firstMatch(before);
      if (match != null) {
        final filter = match.group(1) ?? '';
        final commands = SnippetCommands.commands
            .where(
              (c) =>
                  c.family == SnippetDbFamily.all ||
                  snippetFamily == null ||
                  c.family == snippetFamily,
            )
            .where(
              (c) =>
                  filter.isEmpty ||
                  c.command.toLowerCase().contains(filter.toLowerCase()) ||
                  c.description.toLowerCase().contains(filter.toLowerCase()),
            )
            .toList();
        if (commands.isEmpty) return null;
        // input 含触发斜杠（及前置空白，与旧 _insertSnippet 的
        // replacementStart = match.start 语义一致），选中后整段替换为模板。
        return CodeAutocompleteEditingValue(
          input: before.substring(match.start),
          prompts: commands.map(ReSnippetPrompt.new).toList(),
          index: 0,
        );
      }
    }

    if (!enabled || resolver == null) return null;

    // 2) token 扫描（行内回扫分隔符，与旧 _applySuggestion 等价——
    //    旧实现扫描全文 but 分隔符含 \n，行内扫描等价）
    var prefixStart = 0;
    for (var i = before.length - 1; i >= 0; i--) {
      if (_delimiters.contains(before[i])) {
        prefixStart = i + 1;
        break;
      }
    }
    final input = before.substring(prefixStart);

    // 3) 同步返回占位（prompts 恒非空）；真实建议由弹窗视图在挂载后经
    //    [refreshSuggestions] 拉取——视图持有当次 show 的 notifier，写回
    //    顺序天然正确（早期版本从 build 直接调度异步，resolver 微任务级
    //    完成时 viewBuilder 尚未捕获新 notifier，结果被丢弃）。
    return CodeAutocompleteEditingValue(
      input: input,
      prompts: _pendingPrompts(input),
      index: 0,
    );
  }

  List<CodePrompt> _pendingPrompts(String input) {
    return [RePendingPrompt(word: input)];
  }

  /// 弹窗视图拉取真实建议：读**当前**控制器状态（全文 + 光标，永远新鲜），
  /// 结果写回视图持有的 notifier（input 未变时生效）。
  Future<void> refreshSuggestions(
    ValueNotifier<CodeAutocompleteEditingValue> notifier,
  ) async {
    final resolver = this.resolver;
    if (resolver == null || !enabled) return;
    final input = notifier.value.input;
    try {
      final suggestions = await resolver(
        controller.text,
        controller.cursorAbsoluteOffset,
      );
      if (notifier.value.input != input) return; // 已被新输入取代
      final prompts = suggestions.take(10).map(ReSuggestionPrompt.new).toList();
      if (prompts.isEmpty) return; // 保持占位（「正在获取建议…」）
      notifier.value = notifier.value.copyWith(prompts: prompts, index: 0);
    } catch (_) {
      // 补全失败保持占位，不打断输入
    }
  }

  /// 弹窗是否处于展示状态（Tab 键选中、Esc 关闭判据）。
  bool get isShowing =>
      activeNotifier != null && activeNotifier!.value.prompts.isNotEmpty;

  /// 模拟「选中当前项」（Tab 键平价：旧版 Tab 应用建议）。
  void selectActive() {
    final notifier = activeNotifier;
    final onSelected = activeOnSelected;
    if (notifier == null || onSelected == null) return;
    onSelected(notifier.value.autocomplete);
  }

  /// 关闭弹窗。re_editor 0.10.0 未暴露公开 dismiss，用「选区微调触发
  /// selection-only 通知」驱动内部 dismiss（_updateAutoCompleteState(false)）。
  void dismissActive() {
    final code = controller.codeController;
    if (code.isComposing) return;
    final selection = code.selection;
    final nudged = selection.extentOffset > 0
        ? selection.copyWith(extentOffset: selection.extentOffset - 1)
        : selection.copyWith(extentOffset: selection.extentOffset + 1);
    code.selection = nudged;
    code.selection = selection;
  }
}

/// 普通补全建议（表/列/关键字/函数等）。
class ReSuggestionPrompt extends CodePrompt {
  final Suggestion suggestion;

  ReSuggestionPrompt(this.suggestion) : super(word: suggestion.text);

  @override
  CodeAutocompleteResult get autocomplete =>
      CodeAutocompleteResult.fromWord(suggestion.text);

  @override
  bool match(String input) =>
      input.isEmpty ||
      (word != input && word.toLowerCase().startsWith(input.toLowerCase()));

  @override
  bool operator ==(Object other) =>
      other is ReSuggestionPrompt && other.suggestion == suggestion;

  @override
  int get hashCode => suggestion.hashCode;
}

/// `/trigger` 片段命令：word 为命令名（展示/匹配），插入内容为模板。
class ReSnippetPrompt extends CodePrompt {
  final SnippetCommand command;

  ReSnippetPrompt(this.command) : super(word: command.command);

  @override
  CodeAutocompleteResult get autocomplete =>
      CodeAutocompleteResult.fromWord(command.code);

  @override
  bool match(String input) =>
      input.isEmpty ||
      word.toLowerCase().contains(input.replaceAll('/', '').toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is ReSnippetPrompt && other.command == command;

  @override
  int get hashCode => command.hashCode;
}

/// 占位项：异步结果未到位 / 无匹配。word = 当前输入，选中为无害 no-op。
class RePendingPrompt extends CodePrompt {
  RePendingPrompt({required super.word});

  @override
  CodeAutocompleteResult get autocomplete =>
      CodeAutocompleteResult.fromWord(word);

  @override
  bool match(String input) => true;
}

/// 补全弹窗视图（CodeAutocomplete.viewBuilder 载体）。
///
/// 视觉沿用旧 SQLAutocomplete / SnippetCommandsOverlay 的行样式
/// （图标 + 名称 + 类型徽标 + 描述），键盘导航由 re_editor 原生处理，
/// 本视图只消费 notifier 的 index 做高亮 + 鼠标交互。
class ReAutocompleteView extends StatefulWidget implements PreferredSizeWidget {
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;
  final ReAutocompleteBridge bridge;

  const ReAutocompleteView({
    super.key,
    required this.notifier,
    required this.onSelected,
    required this.bridge,
  });

  @override
  Size get preferredSize => const Size(400, 320);

  @override
  State<ReAutocompleteView> createState() => _ReAutocompleteViewState();
}

class _ReAutocompleteViewState extends State<ReAutocompleteView> {
  String? _pulledInput;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: widget.notifier,
      builder: (context, value, _) {
        // 占位态（真实建议未到位）→ 视图拉取一次。视图持有当次 show 的
        // notifier，异步结果直接写回，不存在 build 期竞态。
        if (_pulledInput != value.input) {
          _pulledInput = value.input;
          if (value.prompts.firstOrNull is RePendingPrompt) {
            Future.microtask(
              () => widget.bridge.refreshSuggestions(widget.notifier),
            );
          }
        }
        return _buildPopup(context, value);
      },
    );
  }

  Widget _buildPopup(BuildContext context, CodeAutocompleteEditingValue value) {
    final l10n = AppLocalizations.of(context);
    final tc = context.themeColors;
    return Material(
      color: tc.bgSecondary,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      elevation: 8,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 400),
        decoration: BoxDecoration(
          border: Border.all(color: tc.borderColor),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, value),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: value.prompts.length,
                itemBuilder: (context, index) =>
                    _buildItem(context, value, index),
              ),
            ),
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
              ),
              decoration: BoxDecoration(
                color: tc.bgTertiary,
                border: Border(top: BorderSide(color: tc.borderLight)),
              ),
              child: Row(
                children: [
                  _hint(context, '↑↓', l10n?.commonNavigate ?? 'Navigate'),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  _hint(context, 'Tab', l10n?.commonSelect ?? 'Select'),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  _hint(context, 'Esc', l10n?.commonClose ?? 'Close'),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    CodeAutocompleteEditingValue value,
  ) {
    final tc = context.themeColors;
    final isSnippet =
        value.prompts.isNotEmpty && value.prompts.first is ReSnippetPrompt;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: tc.bgTertiary,
        border: Border(bottom: BorderSide(color: tc.borderLight)),
      ),
      child: Row(
        children: [
          Icon(
            isSnippet ? LucideIcons.zap : LucideIcons.sparkles,
            size: 14,
            color: tc.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            isSnippet ? 'Snippet Commands' : 'SQL Autocomplete',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: tc.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space1_5,
              vertical: AppDesignSystem.space0_5,
            ),
            decoration: BoxDecoration(
              color: tc.bgHover,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '${value.prompts.length} items',
              style: TextStyle(fontSize: 11, color: tc.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    CodeAutocompleteEditingValue value,
    int index,
  ) {
    final prompt = value.prompts[index];
    final isSelected = index == value.index;
    final tc = context.themeColors;

    final IconData icon;
    final Color iconColor;
    final String label;
    final String title;
    final String? detail;
    if (prompt is ReSuggestionPrompt) {
      final s = prompt.suggestion;
      icon = _typeIcon(s.type);
      iconColor = _typeColor(context, s.type);
      label = _typeLabel(s.type);
      title = s.text;
      detail = s.detail;
    } else if (prompt is ReSnippetPrompt) {
      icon = prompt.command.icon;
      iconColor = tc.accentBlue;
      label = 'SNIPPET';
      title = '/${prompt.command.command}';
      detail = prompt.command.description;
    } else {
      icon = LucideIcons.hourglass;
      iconColor = tc.textMuted;
      label = '…';
      title = prompt.word.isEmpty ? ' ' : prompt.word;
      detail = '正在获取建议…';
    }

    return MouseRegion(
      onEnter: (_) {
        if (value.index != index) {
          widget.notifier.value = value.copyWith(index: index);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelected(value.autocomplete),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          decoration: BoxDecoration(
            color: isSelected ? tc.bgActive : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: tc.borderLight,
                width: index == value.prompts.length - 1 ? 0 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    color: isSelected ? tc.textPrimary : iconColor,
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (detail != null) ...[
                const SizedBox(width: AppDesignSystem.space2),
                Flexible(
                  child: Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: tc.textMuted),
                  ),
                ),
              ],
              const SizedBox(width: AppDesignSystem.space2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: iconColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String key, String label) {
    final tc = context.themeColors;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1,
            vertical: 1,
          ),
          decoration: BoxDecoration(
            color: tc.bgHover,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: tc.borderLight),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 11,
              color: tc.textSecondary,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space1),
        Text(label, style: TextStyle(fontSize: 11, color: tc.textMuted)),
      ],
    );
  }

  // 类型视觉映射与旧 SQLAutocomplete 一致（复用同套语义色）
  Color _typeColor(BuildContext context, SuggestionType type) {
    switch (type) {
      case SuggestionType.keyword:
        return context.themeColors.accentPurple;
      case SuggestionType.table:
      case SuggestionType.collection:
        return context.themeColors.info;
      case SuggestionType.column:
      case SuggestionType.field:
        return context.themeColors.accentBlue;
      case SuggestionType.function:
        return context.themeColors.warning;
      case SuggestionType.datatype:
        return context.themeColors.error;
      case SuggestionType.operator:
        return context.themeColors.warning;
      case SuggestionType.method:
        return context.themeColors.accentPurple;
    }
  }

  String _typeLabel(SuggestionType type) {
    switch (type) {
      case SuggestionType.keyword:
        return 'KEYWORD';
      case SuggestionType.table:
        return 'TABLE';
      case SuggestionType.column:
        return 'COLUMN';
      case SuggestionType.function:
        return 'FUNCTION';
      case SuggestionType.datatype:
        return 'TYPE';
      case SuggestionType.operator:
        return 'OPERATOR';
      case SuggestionType.collection:
        return 'COLLECTION';
      case SuggestionType.field:
        return 'FIELD';
      case SuggestionType.method:
        return 'METHOD';
    }
  }

  IconData _typeIcon(SuggestionType type) {
    switch (type) {
      case SuggestionType.keyword:
        return LucideIcons.code;
      case SuggestionType.table:
        return LucideIcons.table2;
      case SuggestionType.column:
        return LucideIcons.columns2;
      case SuggestionType.function:
        return LucideIcons.functionSquare;
      case SuggestionType.datatype:
        return LucideIcons.braces;
      case SuggestionType.operator:
        return LucideIcons.calculator;
      case SuggestionType.collection:
        return LucideIcons.database;
      case SuggestionType.field:
        return LucideIcons.clipboardList;
      case SuggestionType.method:
        return LucideIcons.terminal;
    }
  }
}
