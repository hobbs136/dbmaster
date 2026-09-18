import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/trigger.dart';
import '../../services/trigger_service.dart';
import '../../theme/app_theme.dart';
import '../../atoms/app_loading.dart';
import '../../l10n/app_localizations.dart';
import '../connection/error_boundary.dart';
import '../../theme/app_colors.dart';

class TriggerEditorDialog extends StatefulWidget {
  final TriggerService service;
  final DatabaseTrigger? existingTrigger;

  const TriggerEditorDialog({
    super.key,
    required this.service,
    this.existingTrigger,
  });

  @override
  State<TriggerEditorDialog> createState() => _TriggerEditorDialogState();
}

class _TriggerEditorDialogState extends State<TriggerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bodyController = TextEditingController();

  TriggerTiming _selectedTiming = TriggerTiming.before;
  final Set<TriggerEvent> _selectedEvents = {TriggerEvent.insert};
  String? _selectedTable;
  List<String> _availableTables = [];

  bool _isLoading = false;
  String? _errorMessage;

  bool get isEditing => widget.existingTrigger != null;

  @override
  void initState() {
    super.initState();
    _loadTables();

    if (widget.existingTrigger != null) {
      _nameController.text = widget.existingTrigger!.name;
      _selectedTiming = widget.existingTrigger!.timing;
      _selectedEvents.clear();
      _selectedEvents.addAll(widget.existingTrigger!.events);
      _selectedTable = widget.existingTrigger!.tableName;
      _bodyController.text = widget.existingTrigger!.body ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);
    try {
      final tables = await widget.service.getTables();
      setState(() {
        _availableTables = tables;
        if (_selectedTable == null && tables.isNotEmpty) {
          _selectedTable = tables.first;
        }
      });
    } catch (e) {
      setState(
        () => _errorMessage = l10n.triggerLoadTablesFailed(e.toString()),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTrigger() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedTable == null) {
      setState(() => _errorMessage = l10n.triggerSelectTableRequired);
      return;
    }

    if (_selectedEvents.isEmpty) {
      setState(() => _errorMessage = l10n.triggerSelectEventRequired);
      return;
    }

    final bodyValidation = widget.service.validateBody(_bodyController.text);
    if (bodyValidation != null) {
      setState(() => _errorMessage = bodyValidation);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final trigger = DatabaseTrigger(
        name: _nameController.text.trim(),
        timing: _selectedTiming,
        events: _selectedEvents.toList(),
        tableName: _selectedTable!,
        body: _bodyController.text.trim(),
      );

      if (widget.existingTrigger != null) {
        await widget.service.update(widget.existingTrigger!.name, trigger);
      } else {
        await widget.service.create(trigger);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingTrigger != null
                  ? l10n.triggerUpdated
                  : l10n.triggerCreated,
            ),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = l10n.triggerSaveFailed(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _testSyntax() async {
    final l10n = AppLocalizations.of(context)!;
    final validation = widget.service.validateBody(_bodyController.text);
    if (validation != null) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.dlgSyntaxError(validation),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.dlgSyntaxLooksGood),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    }
  }

  void _formatCode() {
    final code = _bodyController.text;
    // Simple formatting: capitalize keywords
    final keywords = [
      'insert',
      'update',
      'delete',
      'select',
      'from',
      'where',
      'set',
      'into',
      'values',
      'and',
      'or',
      'not',
      'null',
      'if',
      'then',
      'else',
      'elseif',
      'end if',
      'while',
      'do',
    ];

    var formatted = code;
    for (final keyword in keywords) {
      formatted = formatted.replaceAll(
        RegExp(r'\b' + keyword + r'\b', caseSensitive: false),
        keyword.toUpperCase(),
      );
    }

    setState(() {
      _bodyController.text = formatted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDesignSystem.space4),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_errorMessage != null) _buildErrorMessage(),
                      _buildNameField(),
                      const SizedBox(height: AppDesignSystem.space4),
                      _buildTimingSelector(),
                      const SizedBox(height: AppDesignSystem.space4),
                      _buildEventSelector(),
                      const SizedBox(height: AppDesignSystem.space4),
                      _buildTableSelector(),
                      const SizedBox(height: AppDesignSystem.space4),
                      _buildBodyEditor(),
                      const SizedBox(height: AppDesignSystem.space6),
                      _buildActions(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.zap, color: context.themeColors.warning, size: 24),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            isEditing ? l10n.dlgEditTrigger : l10n.dlgCreateTrigger,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(LucideIcons.x, color: context.themeColors.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space4),
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.error.withValues(alpha: 0.1),
        border: Border.all(color: context.themeColors.error),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.circleAlert,
            color: context.themeColors.error,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: SelectableText(
              _errorMessage!,
              style: TextStyle(color: context.themeColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.triggerNameLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        TextFormField(
          controller: _nameController,
          enabled: !isEditing,
          style: TextStyle(
            fontSize: 13,
            color: context.themeColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: l10n.dlgEnterTriggerName,
            hintStyle: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 12,
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return l10n.triggerNameRequired;
            }
            if (!widget.service.isValidName(value.trim())) {
              return l10n.triggerNameInvalid;
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildTimingSelector() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.triggerTimingLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        Row(
          children: TriggerTiming.values.map((timing) {
            final isSelected = _selectedTiming == timing;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: timing == TriggerTiming.before ? 8 : 0,
                ),
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedTiming = timing);
                  },
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDesignSystem.space3,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? context.themeColors.accentBlue
                          : context.themeColors.bgTertiary,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      border: Border.all(
                        color: isSelected
                            ? context.themeColors.accentBlue
                            : context.themeColors.borderLight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        timing.value,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : context.themeColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildEventSelector() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.triggerEventLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TriggerEvent.values.map((event) {
            final isSelected = _selectedEvents.contains(event);
            return FilterChip(
              label: Text(event.value),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedEvents.add(event);
                  } else {
                    _selectedEvents.remove(event);
                  }
                });
              },
              selectedColor: context.themeColors.accentBlue.withValues(
                alpha: 0.2,
              ),
              checkmarkColor: context.themeColors.accentBlue,
              labelStyle: TextStyle(
                color: isSelected
                    ? context.themeColors.accentBlue
                    : context.themeColors.textSecondary,
                fontSize: 12,
              ),
              backgroundColor: context.themeColors.bgTertiary,
              side: BorderSide(
                color: isSelected
                    ? context.themeColors.accentBlue
                    : context.themeColors.borderLight,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTableSelector() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.triggerTableLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTable,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space2,
              ),
              style: TextStyle(
                fontSize: 13,
                color: context.themeColors.textPrimary,
              ),
              dropdownColor: context.themeColors.bgTertiary,
              items: _availableTables.map((table) {
                return DropdownMenuItem(
                  value: table,
                  child: Text(
                    table,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedTable = value);
              },
              hint: Text(
                l10n.triggerSelectTableHint,
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBodyEditor() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.triggerBodyLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.themeColors.textSecondary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _testSyntax,
              icon: const Icon(LucideIcons.circleCheckBig, size: 14),
              label: Text(l10n.dlgTestSyntax),
              style: TextButton.styleFrom(
                foregroundColor: context.themeColors.success,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space1,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            TextButton.icon(
              onPressed: _formatCode,
              icon: const Icon(LucideIcons.alignLeft, size: 14),
              label: Text(l10n.queryFormat),
              style: TextButton.styleFrom(
                foregroundColor: context.themeColors.textSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space1,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: context.themeColors.bgPrimary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: TextField(
            controller: _bodyController,
            maxLines: null,
            style: TextStyle(
              fontSize: 12,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              color: context.themeColors.textPrimary,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: l10n.triggerBodyHint,
              hintStyle: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 12,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(AppDesignSystem.space3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.themeColors.textSecondary,
            side: BorderSide(color: context.themeColors.borderLight),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space5,
              vertical: AppDesignSystem.space2_5,
            ),
          ),
          child: Text(l10n.commonCancel),
        ),
        const SizedBox(width: AppDesignSystem.space3),
        LoadingButton(
          label: isEditing ? l10n.commonUpdate : l10n.commonCreate,
          onPressed: _saveTrigger,
          isLoading: _isLoading,
          icon: isEditing ? LucideIcons.save : LucideIcons.plus,
        ),
      ],
    );
  }
}
