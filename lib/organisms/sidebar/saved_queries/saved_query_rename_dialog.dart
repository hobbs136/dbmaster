import 'package:flutter/material.dart';

import '../../../atoms/app_loading.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// Simple dialog for renaming a saved query.
class SavedQueryRenameDialog extends StatefulWidget {
  final String initialTitle;
  final ValueChanged<String> onSave;

  const SavedQueryRenameDialog({
    super.key,
    required this.initialTitle,
    required this.onSave,
  });

  @override
  State<SavedQueryRenameDialog> createState() => _SavedQueryRenameDialogState();
}

class _SavedQueryRenameDialogState extends State<SavedQueryRenameDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;

    return AlertDialog(
      title: Text(l10n?.queryHistoryRename ?? 'Rename'),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n?.queryHistoryRename ?? 'Rename',
        ),
        onSubmitted: (value) {
          widget.onSave(value.trim());
          Navigator.of(context).pop();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n?.commonCancel ?? 'Cancel'),
        ),
        LoadingButton(
          label: l10n?.commonSave ?? 'Save',
          onPressed: () {
            widget.onSave(_controller.text.trim());
            Navigator.of(context).pop();
          },
          backgroundColor: colors.accentBlue,
        ),
      ],
    );
  }
}
