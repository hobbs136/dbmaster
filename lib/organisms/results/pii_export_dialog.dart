import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../services/export_service.dart' show PiiMaskAction;
import '../../services/pii_masker.dart';
import '../../theme/app_theme.dart';

/// 用户在 PII 导出对话框确认的选择（格式 + 每列脱敏动作）。
///
/// 对话框只负责收集选择并返回——导出由**调用方**（持有活 context 的一方）
/// 执行。灰屏事故（2026-08-17）根因之一：对话框 pop 自己之后把已失效的
/// dialog context 传入导出链，success/error 反馈在死 context 上抛错，触发
/// ErrorReporter 级联。见 results_widget._showExportDialog。
class PiiExportSelection {
  final String format;
  final Map<String, PiiMaskAction> columnActions;
  const PiiExportSelection(this.format, this.columnActions);
}

/// R4: PII 智能导出对话框（多步流程）。
///
/// 流程：Step1 选格式 → Step2 PII 检测（高亮 + 每列脱敏选项）→ Step3 确认导出。
/// 默认脱敏策略：高敏感列（身份证/银行卡）→ drop，普通 PII → mask，非 PII → keep。
/// 确认后返回 [PiiExportSelection]，由调用方走 ExportService.exportWithMasking。
class PiiExportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> data;

  /// 源查询 SQL（审计用，可为 null）
  final String? sourceSql;

  const PiiExportDialog({super.key, required this.data, this.sourceSql});

  /// 便捷调用：弹出对话框；确认返回选择结果，取消/关闭返回 null。
  static Future<PiiExportSelection?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> data,
    String? sourceSql,
  }) {
    return showDialog<PiiExportSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PiiExportDialog(data: data, sourceSql: sourceSql),
    );
  }

  @override
  State<PiiExportDialog> createState() => _PiiExportDialogState();
}

class _PiiExportDialogState extends State<PiiExportDialog> {
  int _step = 0; // 0=格式, 1=PII, 2=确认
  String _format = 'csv';
  late Map<String, PiiMaskAction> _columnActions;
  late Map<String, PiiColumnDetection> _detections;
  final _masker = PIIMasker();

  @override
  void initState() {
    super.initState();
    _detectAndInitActions();
  }

  void _detectAndInitActions() {
    _detections = {};
    _columnActions = {};
    if (widget.data.isEmpty) return;

    final columns = widget.data.first.keys.toList();
    // 采样最多 50 行用于检测
    final sampleRows = widget.data.take(50).toList();

    for (final col in columns) {
      final sampleValues = sampleRows.map((r) => r[col]).toList();
      final detection = _masker.detectColumnPii(
        columnName: col,
        sampleValues: sampleValues,
      );
      _detections[col] = detection;
      // 默认策略
      if (detection.hasPii) {
        _columnActions[col] = detection.sensitivity == PiiSensitivity.high
            ? PiiMaskAction
                  .drop // 高敏感默认删除
            : PiiMaskAction.mask; // 普通 PII 默认掩码
      } else {
        _columnActions[col] = PiiMaskAction.keep; // 非 PII 保留
      }
    }
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Icon(LucideIcons.download, color: colors.accentBlue, size: 18),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            _l10n.toolbarExport,
            style: AppTextStyles.h4.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepIndicator(colors),
            const SizedBox(height: AppDesignSystem.space4),
            if (_step == 0) _buildFormatStep(colors),
            if (_step == 1) _buildPiiStep(colors),
            if (_step == 2) _buildConfirmStep(colors),
          ],
        ),
      ),
      actions: _buildActions(colors),
    );
  }

  /// 原型 import/export-wizard 步骤指示器：20px 圆点三态
  /// （done=success+check / active=accent+序号 / pending=bgTertiary+描边），
  /// 标签随行、1px 连接线。
  Widget _buildStepIndicator(ThemeColors colors) {
    final labels = [
      _l10n.piiExportStepFormat,
      _l10n.piiExportStepScan,
      _l10n.piiExportStepConfirm,
    ];
    return Row(
      children: List.generate(3, (i) {
        final active = i == _step;
        final done = i < _step;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? colors.success
                      : active
                      ? colors.accentBlue
                      : colors.bgTertiary,
                  border: Border.all(
                    color: done || active
                        ? Colors.transparent
                        : colors.borderLight,
                  ),
                ),
                child: done
                    ? const Icon(
                        LucideIcons.check,
                        size: 12,
                        color: AppDesignSystem.textInverted,
                      )
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: AppDesignSystem.fontSizeXs,
                          fontWeight: AppDesignSystem.fontWeightSemibold,
                          color: active
                              ? AppDesignSystem.textInverted
                              : colors.textSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: active
                        ? AppDesignSystem.fontWeightSemibold
                        : AppDesignSystem.fontWeightMedium,
                    color: active ? colors.accentBlue : colors.textSecondary,
                  ),
                ),
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 1,
                    color: done ? colors.borderLight : colors.borderColor,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  /// Step 1: 格式选择——紧凑分区头 + 原型 radio-chip 语汇
  /// （选中 = accentSubtle 底 + accent 描边/文本；未选中 = borderLight 描边 + 次级文本）。
  Widget _buildFormatStep(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l10n.exportSelectFormat,
          style: AppTextStyles.caption.copyWith(
            color: colors.textSecondary,
            fontWeight: AppDesignSystem.fontWeightSemibold,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2_5),
        Wrap(
          spacing: AppDesignSystem.space2,
          runSpacing: AppDesignSystem.space2,
          children: [
            _formatChip('csv', 'CSV', colors),
            _formatChip('json', 'JSON', colors),
            _formatChip('excel', 'Excel', colors),
          ],
        ),
      ],
    );
  }

  Widget _formatChip(String value, String label, ThemeColors colors) {
    final selected = _format == value;
    return InkWell(
      onTap: () => setState(() => _format = value),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space1_5,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentSubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(
            color: selected ? colors.accentBlue : colors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeSm,
            fontWeight: selected
                ? AppDesignSystem.fontWeightSemibold
                : AppDesignSystem.fontWeightMedium,
            color: selected ? colors.accentBlue : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Step 2: PII 检测 + 每列脱敏选项
  Widget _buildPiiStep(ThemeColors colors) {
    final piiCols = _detections.entries.where((e) => e.value.hasPii).toList();
    if (piiCols.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space6),
        child: Column(
          children: [
            Icon(LucideIcons.circleCheckBig, color: colors.success, size: 40),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              _l10n.piiExportNoPiiTitle,
              style: AppTextStyles.h4.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              _l10n.piiExportNoPiiSubtitle,
              style: AppTextStyles.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l10n.piiExportDetectedCount(piiCols.length),
              style: AppTextStyles.caption.copyWith(color: colors.warning),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            // 单容器行列表（settings 安全规则区同款语汇）
            Container(
              decoration: BoxDecoration(
                color: colors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < piiCols.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: colors.borderSubtle,
                      ),
                    _buildPiiColumnRow(
                      piiCols[i].key,
                      piiCols[i].value,
                      colors,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPiiColumnRow(
    String col,
    PiiColumnDetection detection,
    ThemeColors colors,
  ) {
    final isHigh = detection.sensitivity == PiiSensitivity.high;
    final levelColor = isHigh ? colors.error : colors.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Row(
        children: [
          Icon(
            isHigh ? LucideIcons.circleAlert : LucideIcons.triangleAlert,
            size: 16,
            color: levelColor,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  col,
                  style: AppTextStyles.code.copyWith(
                    color: colors.textPrimary,
                    fontWeight: AppDesignSystem.fontWeightSemibold,
                  ),
                ),
                Text(
                  '${detection.patternName ?? "PII"}'
                  '${isHigh ? ' ${_l10n.piiExportHighSensitivity}' : ''}',
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          DropdownButton<PiiMaskAction>(
            value: _columnActions[col],
            items: [
              DropdownMenuItem(
                value: PiiMaskAction.keep,
                child: Text(_l10n.piiExportKeep),
              ),
              DropdownMenuItem(
                value: PiiMaskAction.mask,
                child: Text(_l10n.piiExportMask),
              ),
              DropdownMenuItem(
                value: PiiMaskAction.hash,
                child: Text(_l10n.piiExportHash),
              ),
              DropdownMenuItem(
                value: PiiMaskAction.drop,
                child: Text(_l10n.piiExportDrop),
              ),
            ],
            onChanged: (v) =>
                setState(() => _columnActions[col] = v ?? PiiMaskAction.keep),
            underline: const SizedBox.shrink(),
            isDense: true,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Step 3: 确认——汇总单容器行列表 + 脚注
  Widget _buildConfirmStep(ThemeColors colors) {
    final piiCount = _columnActions.values
        .where((a) => a != PiiMaskAction.keep)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.circleCheckBig, color: colors.success, size: 40),
        const SizedBox(height: AppDesignSystem.space3),
        Text(
          _l10n.piiExportReadyTitle,
          style: AppTextStyles.h4.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Column(
            children: [
              _confirmRow(
                _l10n.piiExportSummaryFormat,
                _format.toUpperCase(),
                colors,
              ),
              Divider(
                height: 1,
                color: colors.borderSubtle,
              ),
              _confirmRow(
                _l10n.piiExportSummaryRows,
                '${widget.data.length}',
                colors,
              ),
              Divider(
                height: 1,
                color: colors.borderSubtle,
              ),
              _confirmRow(
                _l10n.piiExportSummaryPiiColumns,
                '$piiCount',
                colors,
              ),
            ],
          ),
        ),
        if (piiCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppDesignSystem.space2),
            child: Text(
              _l10n.piiExportFootnote,
              style: AppTextStyles.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _confirmRow(String label, String value, ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontWeight: AppDesignSystem.fontWeightSemibold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 原型 footer 动作词汇：ghost 取消 + outline 上一步 + accent 主按钮。
  List<Widget> _buildActions(ThemeColors colors) {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_l10n.commonCancel),
      ),
      if (_step > 0)
        OutlinedButton.icon(
          onPressed: () => setState(() => _step--),
          icon: const Icon(LucideIcons.arrowLeft, size: 16),
          label: Text(_l10n.exportStepBack),
        ),
      const SizedBox(width: AppDesignSystem.space2),
      FilledButton(
        onPressed: _next,
        child: Text(_step == 2 ? _l10n.resultsExport : _l10n.exportStepNext),
      ),
    ];
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    // 最终确认：只返回选择，导出由调用方用其（仍然存活的）context 执行。
    Navigator.pop(context, PiiExportSelection(_format, Map.of(_columnActions)));
  }
}
