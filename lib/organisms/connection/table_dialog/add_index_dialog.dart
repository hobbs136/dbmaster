import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../providers/app_provider.dart';

class AddIndexDialog extends StatefulWidget {
  final String dbName;
  final String tableName;
  final List<DbColumn> columns;

  const AddIndexDialog({
    super.key,
    required this.dbName,
    required this.tableName,
    required this.columns,
  });

  @override
  State<AddIndexDialog> createState() => _AddIndexDialogState();
}

class _AddIndexDialogState extends State<AddIndexDialog> {
  final _formKey = GlobalKey<FormState>();
  final _indexNameController = TextEditingController();
  final Set<String> _selectedColumns = {};
  bool _isUnique = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _indexNameController.dispose();
    super.dispose();
  }

  Future<void> _createIndex() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedColumns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.indexSelectColumnRequired),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<AppProvider>();
    try {
      final success = await provider.createIndex(
        widget.dbName,
        widget.tableName,
        _indexNameController.text.trim(),
        _selectedColumns.toList(),
        unique: _isUnique,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context, success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.indexCreateFailed(e.toString())),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Text(
        l10n.addIndex,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _indexNameController,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.dbDialogIndexName,
                  labelStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space2,
                    vertical: AppDesignSystem.space1,
                  ),
                  isDense: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.indexNameRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppDesignSystem.space3),
              Row(
                children: [
                  SizedBox(
                    height: 32,
                    child: Switch(
                      value: _isUnique,
                      onChanged: (value) => setState(() => _isUnique = value),
                      activeThumbColor: context.themeColors.accentBlue,
                    ),
                  ),
                  Text(
                    l10n.indexTypeUnique,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Text(
                l10n.indexSelectColumns,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space1),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.borderLight),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: ListView.builder(
                    itemCount: widget.columns.length,
                    itemBuilder: (context, index) {
                      final col = widget.columns[index];
                      final isSelected = _selectedColumns.contains(col.name);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space2,
                        ),
                        title: Text(
                          col.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          col.type,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        ),
                        value: isSelected,
                        activeColor: context.themeColors.accentBlue,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedColumns.add(col.name);
                            } else {
                              _selectedColumns.remove(col.name);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createIndex,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.accentBlue,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(l10n.commonCreate),
        ),
      ],
    );
  }
}
