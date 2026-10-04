//! 结果表格卡（T12 阶段二，design-ai-workbench §8【三】+ §4.4/§5.2）。
//!
//! 四个渲染分支：
//! - **正常态**：折叠元信息 `M 行 · 42ms`（mono 11 textMuted）+ 成功状态图标；
//!   展开态列名 + 前 N 行内嵌只读快照表 [ResultSnapshotTable]；头栏动作
//!   「在舞台打开」（v2 B2：有快照即可开，`snapshotRows` 非空即渲染；M>N
//!   时表尾另有同文案同路由入口「已显示前 N 行 · 共 M 行」+「在舞台打开」
//!   两处并存）；M≤N 不出现截断提示（AC5.2/5.3）。
//! - **空态**（rowCount == 0）：`0 行 · 12ms` + 一行居中 12px 提示，无错误
//!   图标（AC5.6）。
//! - **错误态**（[error] 非空）：左色条 error + triangleAlert 图标 + 摘要
//!   14px + 可折技术详情（mono 11 codeBlockBg）+ ≥1 出口；初始展开可手动
//!   折叠（§8【三】）。错误卡数据由 T13 执行流产生（[WorkbenchErrorCardPayload]），
//!   本组件只负责渲染。
//!
//! 键盘与懒构建语义与 SQL 卡一致（header → 动作钮 → content；Space/Enter
//! 折叠；Esc 回 header；`if (_expanded)` 写死）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../workbench_card_payload.dart';
import 'result_snapshot_table.dart';

/// 工作台错误卡 payload（design §6.2「失败: addAiMessage(卡错误态消息)」的
/// 数据契约；T12 定义渲染分支与挂载格式，数据由 T13 执行流产生）。
///
/// 挂载形态与 SQL/结果卡一致：`AiMessage.toolResultData['workbench'] =
/// toJson()`。与 `workbench_card_payload.dart` 的两类 payload 同族——因
/// T12 文件清单不含该宿主文件，本类落在其渲染分支所在文件（错误卡渲染
/// 归属 result_table_card，见任务书）。
@immutable
class WorkbenchErrorCardPayload {
  static const String kind = 'error_card';

  /// 失败的 SQL（「重试」/「在经典中打开」出口的数据源）。
  final String sql;

  /// 摘要：人类可读、脱敏后的失败原因（14px 正文位）。
  final String summary;

  /// 技术详情（可折叠 mono 块；null = 无详情）。须由调用方先行脱敏。
  final String? detail;

  const WorkbenchErrorCardPayload({
    required this.sql,
    required this.summary,
    this.detail,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'sql': sql,
    'summary': summary,
    if (detail != null) 'detail': detail,
  };

  /// 从 `toolResultData['workbench']` 反序列化；kind 不匹配或关键字段畸形
  /// 返回 null（C-2：未知键忽略，向前兼容）。
  static WorkbenchErrorCardPayload? fromJson(Map<String, dynamic> json) {
    if (json['kind'] != kind) return null;
    final sql = json['sql'];
    final summary = json['summary'];
    if (sql is! String || summary is! String) return null;
    final detail = json['detail'];
    return WorkbenchErrorCardPayload(
      sql: sql,
      summary: summary,
      detail: detail is String ? detail : null,
    );
  }
}

/// 工作台结果表格卡（R5）。[payload] 与 [error] 二选一：error 非空走错误
/// 态渲染分支（此时 payload 应为 null——执行失败无结果数据）。
class ResultTableCard extends StatefulWidget {
  const ResultTableCard({
    super.key,
    this.payload,
    this.error,
    this.onOpenInGrid,
    this.onOpenInClassic,
    this.onRetry,
    this.onOpenErrorInClassic,
  }) : assert(
        payload != null || error != null,
        'payload 与 error 必须提供其一',
      );

  /// 结果数据（null = 错误态卡）。
  final WorkbenchResultCardPayload? payload;

  /// 错误数据（非 null → 错误态渲染分支）。
  final WorkbenchErrorCardPayload? error;

  /// 「在舞台打开」（有快照即可开渲染；T13 注入；宿主侧携带 cardId 组装
  /// AgentResultRef 路由舞台网格，R7 快照语义）。
  final void Function(WorkbenchResultCardPayload payload)? onOpenInGrid;

  /// 「在经典中打开」（T13 注入）。
  final void Function(WorkbenchResultCardPayload payload)?
  onOpenInClassic;

  /// 错误卡「重试」出口（T13 注入）。
  final void Function(WorkbenchErrorCardPayload error)? onRetry;

  /// 错误卡「在经典中打开」出口（T13 注入）。
  final void Function(WorkbenchErrorCardPayload error)? onOpenErrorInClassic;

  /// header 整行（折叠热区 + 焦点宿主）。
  static const Key headerKey = ValueKey('workbench_result_card_header');

  /// 展开态内容区（懒构建守护断言目标，NF1.3）。
  static const Key contentKey = ValueKey('workbench_result_card_content');

  /// 截断提示 + 「在舞台打开」表尾（仅 M>N；与头栏入口同文案同路由）。
  static const Key truncatedFooterKey = ValueKey(
    'workbench_result_card_truncated_footer',
  );

  /// 空态居中提示。
  static const Key emptyHintKey = ValueKey('workbench_result_card_empty_hint');

  /// 错误态摘要。
  static const Key errorSummaryKey = ValueKey('workbench_result_card_error');

  static const Key openInGridButtonKey = ValueKey(
    'workbench_result_card_open_in_grid',
  );
  static const Key openInClassicButtonKey = ValueKey(
    'workbench_result_card_open_in_classic',
  );
  static const Key retryButtonKey = ValueKey('workbench_result_card_retry');

  @override
  State<ResultTableCard> createState() => _ResultTableCardState();
}

/// 结果卡对 payload 的最小视图——已由 T08 的真实类型
/// `WorkbenchResultCardPayload`（`../workbench_card_payload.dart`）直接承担：
/// 本文件 import 该契约文件（单向依赖，无环），T13 构造时直接传实例。
class _ResultTableCardState extends State<ResultTableCard> {
  // 错误卡初始展开、可手动折叠（§8【三】）；其余态初始折叠。
  late bool _expanded = widget.error != null;
  late final FocusNode _headerFocus;
  late final FocusNode _contentFocus;

  @override
  void initState() {
    super.initState();
    _headerFocus = FocusNode(onKeyEvent: _onHeaderKeyEvent);
    _contentFocus = FocusNode(onKeyEvent: _onContentKeyEvent);
    _headerFocus.addListener(_onFocusChanged);
    _contentFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _headerFocus.removeListener(_onFocusChanged);
    _contentFocus.removeListener(_onFocusChanged);
    _headerFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  KeyEventResult _onHeaderKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isActivate =
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (isActivate && node.hasPrimaryFocus) {
      _toggle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && !node.hasPrimaryFocus) {
      _headerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onContentKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _headerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 快照行转换：行 Map + 列名 → List<List<String>>（ResultSnapshotTable 入参
  // 约定）。null → 'NULL' 沿经典 VirtualizedDataTable 显示惯例。
  // ──────────────────────────────────────────────────────────────────────────

  List<List<String>> _displayRows(WorkbenchResultCardPayload payload) {
    return payload.snapshotRows
        .map(
          (row) => payload.columns
              .map((column) => row[column]?.toString() ?? 'NULL')
              .toList(growable: false),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final error = widget.error;
    // §8【一】③：左色条承载状态——成功（含空结果）= success，错误 = error。
    final statusColor = error != null ? colors.error : colors.success;
    final headerFocused = _headerFocus.hasFocus;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: headerFocused ? colors.accentBlue : colors.borderStrong,
          width: headerFocused ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // 左色条用 Stack+Positioned（卡处无界高度宿主，Row+stretch 会强制
      // h=Infinity 断言失败）。
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 3, color: statusColor),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context, error),
                // 懒构建（NF1.3）：折叠态不构建内容。
                if (_expanded) _buildContent(context, error),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WorkbenchErrorCardPayload? error) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final payload = widget.payload;

    // 折叠态元信息（§8【三】）：
    // - 错误态：triangleAlert + 摘要（省略号截断，折叠可自描述）；
    // - 空态：`0 行 · ms`，无错误图标（居中提示在内容区）；
    // - 正常态：成功图标 + `M 行 · 42ms`（mono 11 textMuted）。
    final Widget meta;
    if (error != null) {
      meta = Flexible(
        child: Text(
          error.summary,
          key: ResultTableCard.errorSummaryKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      );
    } else if (payload != null && payload.isEmpty) {
      meta = Flexible(
        child: Text(
          l10n.workbenchEmptyResult(payload.rowCount, payload.durationMs),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _metaStyle(colors),
        ),
      );
    } else if (payload != null) {
      meta = Flexible(
        child: Text(
          l10n.workbenchResultMeta(payload.rowCount, payload.durationMs),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _metaStyle(colors),
        ),
      );
    } else {
      meta = Flexible(
        child: Text(
          l10n.workbenchErrorDetail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _metaStyle(colors),
        ),
      );
    }

    final Widget? statusIcon;
    if (error != null) {
      statusIcon = Icon(LucideIcons.triangleAlert, size: 16, color: colors.error);
    } else if (payload != null && payload.isEmpty) {
      // 空态无错误图标（AC5.6）：中性弱化图标标识结果载体。
      statusIcon = Icon(LucideIcons.inbox, size: 16, color: colors.textMuted);
    } else if (payload != null) {
      statusIcon = Icon(
        LucideIcons.circleCheckBig,
        size: 16,
        color: colors.success,
      );
    } else {
      statusIcon = null;
    }

    return SizedBox(
      key: ResultTableCard.headerKey,
      height: AppDesignSystem.toolCardHeaderHeight,
      child: InkWell(
        focusNode: _headerFocus,
        // 点击即聚焦（同 SqlToolCard：整行可点折叠 + 键盘可达）。
        onTap: () {
          _headerFocus.requestFocus();
          _toggle();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
          child: Row(
            children: [
              if (statusIcon != null) ...[
                statusIcon,
                const SizedBox(width: AppDesignSystem.space2),
              ],
              meta,
              const Spacer(),
              if (error == null && widget.payload != null)
                _buildNormalActions(context),
              if (error != null) _buildErrorActions(context),
              const SizedBox(width: AppDesignSystem.space1),
              Icon(
                _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _metaStyle(ThemeColors colors) => TextStyle(
    fontSize: 11,
    fontFamily: AppDesignSystem.monoFontFamily,
    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    color: colors.textMuted,
  );

  /// 正常态 header 动作：「在舞台打开」（v2 B2：有快照即可开——显示条件从
  /// 仅 M>N（`isTruncated`）放宽为 `snapshotRows.isNotEmpty`）+「在经典中打开」。
  Widget _buildNormalActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final payload = widget.payload;
    final showGrid = payload != null && payload.snapshotRows.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGrid) ...[
          _CardActionButton(
            buttonKey: ResultTableCard.openInGridButtonKey,
            icon: LucideIcons.table,
            label: l10n.workbenchOpenInStage,
            color: colors.accentBlue,
            onTap: () => widget.onOpenInGrid?.call(payload),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
        ],
        _CardActionButton(
          buttonKey: ResultTableCard.openInClassicButtonKey,
          icon: LucideIcons.externalLink,
          label: l10n.workbenchActionOpenInClassic,
          color: colors.accentBlue,
          onTap: () => widget.onOpenInClassic?.call(payload!),
        ),
      ],
    );
  }

  /// 错误态出口（≥1 出口由 T13 注入回调保证；未注入的出口不渲染）。
  Widget _buildErrorActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final error = widget.error!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onRetry != null)
          _CardActionButton(
            buttonKey: ResultTableCard.retryButtonKey,
            icon: LucideIcons.refreshCw,
            label: l10n.commonRetry,
            color: colors.accentBlue,
            onTap: () => widget.onRetry?.call(error),
          ),
        if (widget.onRetry != null && widget.onOpenErrorInClassic != null)
          const SizedBox(width: AppDesignSystem.space1_5),
        if (widget.onOpenErrorInClassic != null)
          _CardActionButton(
            buttonKey: ResultTableCard.openInClassicButtonKey,
            icon: LucideIcons.externalLink,
            label: l10n.workbenchActionOpenInClassic,
            color: colors.accentBlue,
            onTap: () => widget.onOpenErrorInClassic?.call(error),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, WorkbenchErrorCardPayload? error) {
    final payload = widget.payload;
    if (error != null) {
      return _buildErrorContent(context, error);
    }
    if (payload == null) return const SizedBox.shrink();
    if (payload.isEmpty) {
      return _buildEmptyContent(context, payload);
    }
    return _buildResultContent(context, payload);
  }

  /// 正常态展开：快照表 + （M>N）截断提示表尾。
  Widget _buildResultContent(
    BuildContext context,
    WorkbenchResultCardPayload payload,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      key: ResultTableCard.contentKey,
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2,
        0,
        AppDesignSystem.space2,
        AppDesignSystem.space2,
      ),
      child: Focus(
        focusNode: _contentFocus,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ResultSnapshotTable(
              columns: payload.columns,
              rows: _displayRows(payload),
            ),
            if (payload.isTruncated) ...[
              const SizedBox(height: AppDesignSystem.space2),
              Row(
                key: ResultTableCard.truncatedFooterKey,
                children: [
                  Expanded(
                    child: Text(
                      l10n.workbenchResultTruncated(
                        payload.snapshotRows.length,
                        payload.rowCount,
                      ),
                      style: _metaStyle(colors),
                    ),
                  ),
                  // 表尾「在舞台打开」（仅 M>N；v2 B2 保留原位同文案同路由，
                  // 与头栏入口并存）。
                  _CardActionButton(
                    buttonKey: ResultTableCard.openInGridButtonKey,
                    icon: LucideIcons.table,
                    label: l10n.workbenchOpenInStage,
                    color: colors.accentBlue,
                    onTap: () => widget.onOpenInGrid?.call(payload),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 空态展开：一行居中 12px 提示（无错误图标，AC5.6）。
  Widget _buildEmptyContent(
    BuildContext context,
    WorkbenchResultCardPayload payload,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      key: ResultTableCard.contentKey,
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      child: Focus(
        focusNode: _contentFocus,
        child: SizedBox(
          key: ResultTableCard.emptyHintKey,
          width: double.infinity,
          child: Text(
            l10n.workbenchEmptyResultHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ),
      ),
    );
  }

  /// 错误态展开：摘要 14px + 可折技术详情（mono 11 codeBlockBg）。
  /// 出口按钮在 header 动作区（≥1 出口由回调注入保证）。
  Widget _buildErrorContent(
    BuildContext context,
    WorkbenchErrorCardPayload error,
  ) {
    final colors = context.themeColors;
    return Padding(
      key: ResultTableCard.contentKey,
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2,
        0,
        AppDesignSystem.space2,
        AppDesignSystem.space2,
      ),
      child: Focus(
        focusNode: _contentFocus,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              error.summary,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colors.textPrimary,
              ),
            ),
            if (error.detail != null && error.detail!.isNotEmpty) ...[
              const SizedBox(height: AppDesignSystem.space2),
              _ErrorDetailBlock(detail: error.detail!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 可折技术详情（mono 11 / codeBlockBg；标题行点击折叠，初始展开）。
class _ErrorDetailBlock extends StatefulWidget {
  const _ErrorDetailBlock({required this.detail});

  final String detail;

  @override
  State<_ErrorDetailBlock> createState() => _ErrorDetailBlockState();
}

class _ErrorDetailBlockState extends State<_ErrorDetailBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.codeBlockBg,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      l10n.workbenchErrorDetail,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 14,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              child: SelectableText(
                widget.detail,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// header 动作钮（与 sql_tool_card 同款紧凑形态）。
class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: buttonKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space1,
          vertical: AppDesignSystem.space0_5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: AppDesignSystem.space1),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
