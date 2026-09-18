import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/stored_procedure.dart';
import '../../services/stored_procedure_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../connection/error_boundary.dart';
import '../../theme/app_colors.dart';

class ProcedureExecutorDialog extends StatefulWidget {
  final StoredProcedure procedure;
  final StoredProcedureService service;

  const ProcedureExecutorDialog({
    super.key,
    required this.procedure,
    required this.service,
  });

  @override
  State<ProcedureExecutorDialog> createState() =>
      _ProcedureExecutorDialogState();
}

class _ProcedureExecutorDialogState extends State<ProcedureExecutorDialog> {
  final Map<String, TextEditingController> _paramControllers = {};
  bool _isExecuting = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    for (final param in widget.procedure.parameters) {
      // 只为 IN 和 INOUT 参数创建输入框
      if (param.mode != 'OUT') {
        _paramControllers[param.name] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _paramControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _execute() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isExecuting = true);

    try {
      final params = <String, dynamic>{};
      for (final entry in _paramControllers.entries) {
        final value = entry.value.text.trim();
        // 尝试解析为数字
        if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
          if (value.contains('.')) {
            params[entry.key] = double.parse(value);
          } else {
            params[entry.key] = int.parse(value);
          }
        } else if (value.toLowerCase() == 'true' ||
            value.toLowerCase() == 'false') {
          params[entry.key] = value.toLowerCase() == 'true';
        } else if (value == 'NULL') {
          params[entry.key] = null;
        } else {
          params[entry.key] = value;
        }
      }

      final result = await widget.service.execute(
        widget.procedure.name,
        widget.procedure.type,
        params,
      );

      setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.dlgExecutionFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isExecuting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasParams = _paramControllers.isNotEmpty;

    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          children: [
            _buildTitleBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDesignSystem.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProcedureInfo(context),
                    const SizedBox(height: AppDesignSystem.space4),
                    _buildParamsSection(context, hasParams),
                    const SizedBox(height: AppDesignSystem.space4),
                    if (_result != null) ...[
                      Text(
                        l10n.dlgExecutionResult,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDesignSystem.space2),
                      _buildResultWidget(),
                    ],
                  ],
                ),
              ),
            ),
            _buildFooterButtons(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDesignSystem.radiusLg),
          topRight: Radius.circular(AppDesignSystem.radiusLg),
        ),
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l10n.dlgExecuteRoutine(
              widget.procedure.type == ProcedureType.procedure
                  ? l10n.dlgRoutineProcedure
                  : l10n.dlgRoutineFunction,
            ),
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x),
            color: context.themeColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildProcedureInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dlgRoutineName(widget.procedure.name),
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            l10n.dlgRoutineType(
              widget.procedure.type == ProcedureType.procedure
                  ? 'PROCEDURE'
                  : 'FUNCTION',
            ),
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
          if (widget.procedure.returnType != null) ...[
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              l10n.dlgRoutineReturnType(widget.procedure.returnType!),
              style: TextStyle(
                fontSize: 13,
                color: context.themeColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParamsSection(BuildContext context, bool hasParams) {
    final l10n = AppLocalizations.of(context)!;
    if (hasParams) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dlgParameters,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          ...widget.procedure.parameters.map((param) {
            if (param.mode == 'OUT') return _buildOutParameterRow(param);
            return _buildParameterRow(param);
          }),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Center(
        child: Text(
          l10n.dlgRoutineNoParams,
          style: TextStyle(color: context.themeColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildFooterButtons(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(top: BorderSide(color: context.themeColors.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonClose),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          ElevatedButton.icon(
            onPressed: _isExecuting ? null : _execute,
            icon: _isExecuting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.play, size: 16),
            label: Text(l10n.dlgExecute),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.success,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space5,
                vertical: AppDesignSystem.space2_5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterRow(ProcedureParameter param) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _paramControllers[param.name]!;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      child: Row(
        children: [
          // 参数模式和名称
          SizedBox(
            width: 150,
            child: Text(
              '${param.mode} ${param.name} (${param.dataType})',
              style: TextStyle(
                fontSize: 13,
                color: context.themeColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          // 输入框
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: l10n.dlgEnterValue,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(LucideIcons.copy, size: 16),
                  onPressed: () {
                    final text = controller.text;
                    if (text.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.dlgCopied),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutParameterRow(ProcedureParameter param) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.squareTerminal,
            size: 16,
            color: context.themeColors.accentPurple,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            '${param.mode} ${param.name} (${param.dataType})',
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            l10n.dlgOutputParam,
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultWidget() {
    final l10n = AppLocalizations.of(context)!;
    final result = _result!;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result['returnValue'] != null) ...[
            Row(
              children: [
                Icon(
                  LucideIcons.functionSquare,
                  size: 16,
                  color: context.themeColors.info,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  '${l10n.dlgReturnValueLabel} ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                Text(
                  result['returnValue'].toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    color: context.themeColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space2),
          ],
          Row(
            children: [
              Icon(
                LucideIcons.table2,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.dlgRowsAffected(
                  (result['rowsAffected'] as num?)?.toInt() ?? 0,
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
