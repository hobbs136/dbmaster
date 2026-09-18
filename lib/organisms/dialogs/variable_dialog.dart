import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class VariableDialog extends StatefulWidget {
  final List<String> variables;

  const VariableDialog({super.key, required this.variables});

  static Future<Map<String, String>?> show(
    BuildContext context,
    List<String> variables,
  ) async {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => VariableDialog(variables: variables),
    );
  }

  @override
  State<VariableDialog> createState() => _VariableDialogState();
}

class _VariableDialogState extends State<VariableDialog> {
  late final List<TextEditingController> _controllers;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controllers = widget.variables
        .map((_) => TextEditingController())
        .toList();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(
            LucideIcons.notebookPen,
            color: context.themeColors.accentPurple,
            size: 24,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            l10n.dlgFillVariables,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.variables.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: TextFormField(
                  controller: _controllers[index],
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.variables[index],
                    labelStyle: TextStyle(
                      color: context.themeColors.textSecondary,
                    ),
                    hintText: l10n.dlgEnterVariableValue(
                      widget.variables[index],
                    ),
                    hintStyle: TextStyle(color: context.themeColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusMd,
                      ),
                      borderSide: BorderSide(
                        color: context.themeColors.borderLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusMd,
                      ),
                      borderSide: BorderSide(
                        color: context.themeColors.borderLight,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusMd,
                      ),
                      borderSide: BorderSide(
                        color: context.themeColors.accentPurple,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: context.themeColors.bgPrimary,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.dlgVariableRequired(widget.variables[index]);
                    }
                    return null;
                  },
                ),
              );
            }),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.commonCancel,
            style: TextStyle(color: context.themeColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final values = <String, String>{};
              for (var i = 0; i < widget.variables.length; i++) {
                values[widget.variables[i]] = _controllers[i].text.trim();
              }
              Navigator.of(context).pop(values);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.accentPurple,
            foregroundColor: Colors.white,
          ),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
