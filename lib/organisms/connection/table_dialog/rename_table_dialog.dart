import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../atoms/app_loading.dart';
import '../../../l10n/app_localizations.dart';

class RenameTableDialog extends StatefulWidget {
  final String tableName;

  const RenameTableDialog({super.key, required this.tableName});

  @override
  State<RenameTableDialog> createState() => _RenameTableDialogState();
}

class _RenameTableDialogState extends State<RenameTableDialog> {
  late final TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.tableName);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  /// 空输入禁止提交（契约 C5：空输入必须给用户反馈，禁止静默关闭）。
  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        l10n.tableRenameTable,
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: TextField(
        controller: _controller,
        style: TextStyle(color: context.themeColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: l10n.tableNewTableName,
          labelStyle: TextStyle(
            color: context.themeColors.textMuted,
            fontSize: 12,
          ),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        LoadingButton(
          label: l10n.commonConfirm,
          onPressed: _canSubmit ? _rename : null,
          isLoading: _isLoading,
          backgroundColor: context.themeColors.accentBlue,
        ),
      ],
    );
  }

  Future<void> _rename() async {
    if (!_canSubmit) return;
    if (_controller.text == widget.tableName) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isLoading = true);
    Navigator.pop(context, _controller.text);
  }
}
