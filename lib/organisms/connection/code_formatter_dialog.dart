import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/formatter_models.dart';
import '../../services/sql_formatter_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

/// SQL 代码格式化对话框
class CodeFormatterDialog extends StatefulWidget {
  final String initialSql;
  final Function(String) onFormatApplied;

  const CodeFormatterDialog({
    super.key,
    required this.initialSql,
    required this.onFormatApplied,
  });

  @override
  State<CodeFormatterDialog> createState() => _CodeFormatterDialogState();
}

class _CodeFormatterDialogState extends State<CodeFormatterDialog> {
  final SqlFormatterService _formatterService = SqlFormatterService();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  final TextEditingController _presetNameController = TextEditingController();
  final TextEditingController _presetDescController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  FormatterOptions _options = const FormatterOptions();
  List<FormatterPreset> _presets = [];
  String? _selectedPresetId;
  bool _isFormatting = false;
  late AppLocalizations _l10n;

  // 撤销/重做栈
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _inputController.text = widget.initialSql;
    _loadPresets();
    _formatSql();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    _presetNameController.dispose();
    _presetDescController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    final presets = await _formatterService.loadPresets();
    setState(() {
      _presets = presets;
      if (_selectedPresetId == null && presets.isNotEmpty) {
        _selectedPresetId = presets.first.id;
        _options = presets.first.options;
      }
    });
  }

  void _formatSql() {
    setState(() => _isFormatting = true);

    // 添加到撤销栈
    if (_undoStack.isEmpty || _undoStack.last != _inputController.text) {
      _undoStack.add(_inputController.text);
      if (_undoStack.length > 20) _undoStack.removeAt(0);
      _redoStack.clear();
    }

    final formatted = _formatterService.format(_inputController.text, _options);
    _outputController.text = formatted;

    // 保存到历史
    _formatterService.addHistory(_inputController.text, formatted, _options);

    setState(() => _isFormatting = false);
  }

  void _undo() {
    if (_undoStack.length > 1) {
      _redoStack.add(_undoStack.removeLast());
      _inputController.text = _undoStack.last;
      _formatSql();
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      final text = _redoStack.removeLast();
      _inputController.text = text;
      _undoStack.add(text);
      _formatSql();
    }
  }

  void _applyToEditor() {
    widget.onFormatApplied(_outputController.text);
    Navigator.of(context).pop();
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _outputController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_l10n.copiedToClipboard),
        backgroundColor: context.themeColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _applyPreset(FormatterPreset preset) {
    setState(() {
      _selectedPresetId = preset.id;
      _options = preset.options;
    });
    _formatSql();
  }

  void _showSavePresetDialog() {
    _presetNameController.clear();
    _presetDescController.clear();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.themeColors.bgSecondary,
        title: Text(
          _l10n.formatterSavePreset,
          style: TextStyle(color: dialogContext.themeColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _presetNameController,
              style: TextStyle(color: dialogContext.themeColors.textPrimary),
              decoration: InputDecoration(
                labelText: _l10n.formatterPresetName,
                labelStyle: TextStyle(
                  color: dialogContext.themeColors.textMuted,
                ),
                hintText: _l10n.hintFormatName,
                hintStyle: TextStyle(
                  color: dialogContext.themeColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            TextField(
              controller: _presetDescController,
              style: TextStyle(color: dialogContext.themeColors.textPrimary),
              decoration: InputDecoration(
                labelText: _l10n.description,
                labelStyle: TextStyle(
                  color: dialogContext.themeColors.textMuted,
                ),
                hintText: _l10n.hintOptionalDescription,
                hintStyle: TextStyle(
                  color: dialogContext.themeColors.textMuted,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_presetNameController.text.isNotEmpty) {
                final navigator = Navigator.of(dialogContext);
                final preset = FormatterPreset(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: _presetNameController.text,
                  description: _presetDescController.text.isEmpty
                      ? _l10n.formatterCustomPreset
                      : _presetDescController.text,
                  options: _options,
                  createdAt: DateTime.now(),
                );
                await _formatterService.savePreset(preset);
                await _loadPresets();
                setState(() => _selectedPresetId = preset.id);
                if (mounted) {
                  navigator.pop();
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
            ),
            child: Text(_l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePreset(String presetId) async {
    await _formatterService.deletePreset(presetId);
    await _loadPresets();
    if (_selectedPresetId == presetId && _presets.isNotEmpty) {
      setState(() {
        _selectedPresetId = _presets.first.id;
        _options = _presets.first.options;
      });
    }
  }

  void _updateOption(Function(FormatterOptions) updater) {
    setState(() {
      _options = updater(_options);
      _selectedPresetId = null; // 自定义设置时取消预设选择
    });
    _formatSql();
  }

  @override
  Widget build(BuildContext context) {
    _l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: context.themeColors.bgPrimary,
      child: Container(
        width: 1000,
        height: 700,
        padding: const EdgeInsets.all(AppDesignSystem.space4),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: AppDesignSystem.space4),
            Expanded(child: _buildContent()),
            const SizedBox(height: AppDesignSystem.space4),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(LucideIcons.alignLeft, color: context.themeColors.accentBlue),
        const SizedBox(width: AppDesignSystem.space2),
        Text(
          _l10n.formatterSqlFormat,
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontSize: AppDesignSystem.fontSize2xl,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPresetId,
              dropdownColor: context.themeColors.bgTertiary,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 13,
              ),
              hint: Text(
                _l10n.formatterSelectPreset,
                style: TextStyle(color: context.themeColors.textSecondary),
              ),
              items: _presets
                  .map(
                    (preset) => DropdownMenuItem(
                      value: preset.id,
                      child: Row(
                        children: [
                          Text(preset.name),
                          if (preset.isBuiltIn) ...[
                            const SizedBox(width: AppDesignSystem.space2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDesignSystem.space1,
                                vertical: AppDesignSystem.space0_5,
                              ),
                              decoration: BoxDecoration(
                                color: context.themeColors.accentBlue
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(
                                  AppDesignSystem.radiusSm,
                                ),
                              ),
                              child: Text(
                                _l10n.formatterBuiltIn,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.themeColors.accentBlue,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  final preset = _presets.firstWhere((p) => p.id == id);
                  _applyPreset(preset);
                }
              },
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        IconButton(
          onPressed: _showSavePresetDialog,
          icon: Icon(
            LucideIcons.save,
            size: 18,
            color: context.themeColors.textSecondary,
          ),
          tooltip: _l10n.formatterSaveAsPreset,
        ),
        if (_selectedPresetId != null &&
            !_presets.firstWhere((p) => p.id == _selectedPresetId).isBuiltIn)
          IconButton(
            onPressed: () => _deletePreset(_selectedPresetId!),
            icon: Icon(
              LucideIcons.trash2,
              size: 18,
              color: context.themeColors.error,
            ),
            tooltip: _l10n.formatterDeletePreset,
          ),
        const SizedBox(width: AppDesignSystem.space2),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            LucideIcons.x,
            size: 20,
            color: context.themeColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：输入和预览
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildEditorToolbar(),
              const SizedBox(height: AppDesignSystem.space2),
              Expanded(child: _buildInputEditor()),
              const SizedBox(height: AppDesignSystem.space2),
              Divider(color: context.themeColors.borderLight),
              const SizedBox(height: AppDesignSystem.space2),
              Expanded(child: _buildOutputEditor()),
            ],
          ),
        ),
        const SizedBox(width: AppDesignSystem.space4),
        // 右侧：选项面板
        SizedBox(width: 280, child: _buildOptionsPanel()),
      ],
    );
  }

  Widget _buildEditorToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Row(
        children: [
          _ToolbarIconButton(
            icon: LucideIcons.undo,
            tooltip: _l10n.shortcutUndo,
            onPressed: _undoStack.length > 1 ? _undo : null,
          ),
          _ToolbarIconButton(
            icon: LucideIcons.redo,
            tooltip: _l10n.shortcutRedo,
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
          VerticalDivider(width: 16, color: context.themeColors.borderLight),
          ElevatedButton.icon(
            onPressed: _isFormatting ? null : _formatSql,
            icon: _isFormatting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.wandSparkles, size: 16),
            label: Text(_l10n.formatterFormat),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space1_5,
              ),
              minimumSize: Size.zero,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(LucideIcons.copy, size: 14),
            label: Text(
              _l10n.formatterCopyResult,
              style: const TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.textSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1_5,
              ),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputEditor() {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.themeColors.borderLight),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.pencil,
                  size: 14,
                  color: context.themeColors.textMuted,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  _l10n.formatterInput,
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              maxLines: null,
              expands: true,
              style: TextStyle(
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 13,
                height: 1.6,
                color: context.themeColors.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(AppDesignSystem.space3),
                hintText: _l10n.formatterHintInputSql,
                hintStyle: TextStyle(color: context.themeColors.textMuted),
              ),
              onChanged: (_) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) _formatSql();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputEditor() {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.themeColors.borderLight),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.eye,
                  size: 14,
                  color: context.themeColors.success,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  _l10n.preview,
                  style: TextStyle(
                    color: context.themeColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              child: TextField(
                controller: _outputController,
                maxLines: null,
                readOnly: true,
                style: TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 13,
                  height: 1.6,
                  color: context.themeColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.themeColors.borderLight),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 16,
                  color: context.themeColors.accentBlue,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  _l10n.formatterOptions,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(_l10n.formatterIndent),
                  const SizedBox(height: AppDesignSystem.space2),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioTile(
                          title: _l10n.formatterSpace,
                          value: false,
                          groupValue: _options.useTabs,
                          onChanged: (v) =>
                              _updateOption((o) => o.copyWith(useTabs: v)),
                        ),
                      ),
                      Expanded(
                        child: _buildRadioTile(
                          title: _l10n.formatterTab,
                          value: true,
                          groupValue: _options.useTabs,
                          onChanged: (v) =>
                              _updateOption((o) => o.copyWith(useTabs: v)),
                        ),
                      ),
                    ],
                  ),
                  if (!_options.useTabs) ...[
                    const SizedBox(height: AppDesignSystem.space2),
                    Row(
                      children: [
                        Text(
                          '${_l10n.formatterIndentSize}:',
                          style: TextStyle(
                            color: context.themeColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: AppDesignSystem.space3),
                        Expanded(
                          child: Slider(
                            value: _options.indentSize.toDouble(),
                            min: 2,
                            max: 8,
                            divisions: 3,
                            label: '${_options.indentSize}',
                            activeColor: context.themeColors.accentBlue,
                            onChanged: (v) => _updateOption(
                              (o) => o.copyWith(indentSize: v.toInt()),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${_options.indentSize}',
                            style: TextStyle(
                              color: context.themeColors.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  Divider(height: 24, color: context.themeColors.borderLight),
                  _buildSectionTitle(_l10n.formatterKeywords),
                  const SizedBox(height: AppDesignSystem.space2),
                  _buildSwitchTile(
                    title: _l10n.formatterUppercaseKeywords,
                    value: _options.uppercaseKeywords,
                    onChanged: (v) =>
                        _updateOption((o) => o.copyWith(uppercaseKeywords: v)),
                  ),
                  _buildSwitchTile(
                    title: _l10n.formatterAlignKeywords,
                    value: _options.alignKeywords,
                    onChanged: (v) =>
                        _updateOption((o) => o.copyWith(alignKeywords: v)),
                  ),
                  Divider(height: 24, color: context.themeColors.borderLight),
                  _buildSectionTitle(_l10n.format),
                  const SizedBox(height: AppDesignSystem.space2),
                  _buildSwitchTile(
                    title: _l10n.formatterPreserveComments,
                    value: _options.preserveComments,
                    onChanged: (v) =>
                        _updateOption((o) => o.copyWith(preserveComments: v)),
                  ),
                  _buildSwitchTile(
                    title: _l10n.formatterNewlineBeforeParentheses,
                    value: _options.breakBeforeBrackets,
                    onChanged: (v) => _updateOption(
                      (o) => o.copyWith(breakBeforeBrackets: v),
                    ),
                  ),
                  _buildSwitchTile(
                    title: _l10n.formatterCompactMode,
                    value: _options.compactMode,
                    onChanged: (v) =>
                        _updateOption((o) => o.copyWith(compactMode: v)),
                  ),
                  Divider(height: 24, color: context.themeColors.borderLight),
                  _buildSectionTitle(_l10n.formatterCommaStyle),
                  const SizedBox(height: AppDesignSystem.space2),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioTile(
                          title: _l10n.formatterEnd,
                          value: 'trailing',
                          groupValue: _options.commaStyle,
                          onChanged: (v) =>
                              _updateOption((o) => o.copyWith(commaStyle: v)),
                        ),
                      ),
                      Expanded(
                        child: _buildRadioTile(
                          title: _l10n.formatterStart,
                          value: 'leading',
                          groupValue: _options.commaStyle,
                          onChanged: (v) =>
                              _updateOption((o) => o.copyWith(commaStyle: v)),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 24, color: context.themeColors.borderLight),
                  _buildSectionTitle(_l10n.formatterMaxLineLength),
                  const SizedBox(height: AppDesignSystem.space2),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _options.maxLineLength.toDouble(),
                          min: 60,
                          max: 160,
                          divisions: 10,
                          label: '${_options.maxLineLength}',
                          activeColor: context.themeColors.accentBlue,
                          onChanged: (v) => _updateOption(
                            (o) => o.copyWith(maxLineLength: v.toInt()),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${_options.maxLineLength}',
                          style: TextStyle(
                            color: context.themeColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: context.themeColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.themeColors.accentBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildRadioTile<T>({
    required String title,
    required T value,
    required T groupValue,
    required ValueChanged<T> onChanged,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1_5,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? context.themeColors.accentBlue.withOpacity(0.1)
              : null,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(
            color: isSelected
                ? context.themeColors.accentBlue
                : context.themeColors.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 16,
              color: isSelected
                  ? context.themeColors.accentBlue
                  : context.themeColors.textMuted,
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? context.themeColors.textPrimary
                    : context.themeColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: context.themeColors.textSecondary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space4,
              vertical: AppDesignSystem.space2_5,
            ),
          ),
          child: Text(_l10n.commonCancel),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        ElevatedButton.icon(
          onPressed: _applyToEditor,
          icon: const Icon(LucideIcons.check, size: 16),
          label: Text(_l10n.formatterApplyToEditor),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space4,
              vertical: AppDesignSystem.space2_5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 工具栏图标按钮
class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: onPressed != null
          ? context.themeColors.textSecondary
          : context.themeColors.textMuted,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
