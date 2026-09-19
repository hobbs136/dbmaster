// 连接失败对话框（连接失败 UX 重构 T5）。
//
// 把连接失败从固定文案 snackbar 升级为模态对话框：人话原因 + 恢复动作 +
// 折叠技术详情 + 复制。与 provider 解耦——重试、重选文件、最新失败均由
// 调用方注入（[ConnectFailureDialog.show]），组件可脱离 provider 单测。
//
// 重试语义：pending 中主动作 loading 禁点；成功关闭 dialog；失败单实例
// 原地更新（从 latestFailure 取新 failure 刷新，null 沿用旧值），不叠开
// 第二个 dialog。onRetry 抛异常视为失败，按异常消息构造 unknown failure
// 原地展示。
//
// 键盘：主动作初始焦点；Enter 触发主动作；Esc 关闭（Focus.onKeyEvent
// 标记 handled，阻断应用级 Esc DismissIntent 造成二次 pop）；Tab 顺序 =
// 主动作 → 关闭（次动作）→ 折叠头 → 复制详情。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../atoms/app_transitions.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/actionable_error.dart';
import '../../models/connection_failure.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_logger.dart';
import '../../utils/secret_redactor.dart';

/// 连接失败对话框——人话原因 + 恢复动作 + 折叠技术详情 + 复制。
class ConnectFailureDialog extends StatefulWidget {
  /// 创建连接失败对话框。
  const ConnectFailureDialog({
    super.key,
    required this.failure,
    required this.onRetry,
    this.onChooseFile,
    this.latestFailure,
  });

  /// 当前展示的失败（重试失败后原地替换）。
  final ConnectionFailure failure;

  /// 主动作（重试）；返回 true = 成功关闭，false = 原地更新。
  final Future<bool> Function() onRetry;

  /// fileNotFound 主动作「重新选择文件」；null 时该 kind 主动作退回重试。
  final VoidCallback? onChooseFile;

  /// 重试失败后取最新失败；回调为 null 或返回 null 时沿用旧 [failure]。
  final ConnectionFailure? Function()? latestFailure;

  /// 以模态对话框展示连接失败（重试失败后由组件原地刷新，不叠开新实例）。
  static Future<void> show(
    BuildContext context, {
    required ConnectionFailure failure,
    required Future<bool> Function() onRetry,
    VoidCallback? onChooseFile,
    ConnectionFailure? Function()? latestFailure,
  }) {
    return context.showAnimatedDialog<void>(
      barrierDismissible: false,
      builder: (_) => ConnectFailureDialog(
        failure: failure,
        onRetry: onRetry,
        onChooseFile: onChooseFile,
        latestFailure: latestFailure,
      ),
    );
  }

  @override
  State<ConnectFailureDialog> createState() => _ConnectFailureDialogState();
}

class _ConnectFailureDialogState extends State<ConnectFailureDialog> {
  final FocusNode _keyboardFocusNode = FocusNode();
  late ConnectionFailure _failure;
  bool _pending = false;
  bool _detailsExpanded = false;

  @override
  void initState() {
    super.initState();
    _failure = widget.failure;
  }

  /// 当前是否为「重新选择文件」主动作形态（fileNotFound + 回调非空）。
  bool get _chooseFileMode =>
      _failure.kind == ConnectionFailureKind.fileNotFound &&
      widget.onChooseFile != null;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (!_pending) unawaited(_runPrimaryAction());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _runPrimaryAction() async {
    if (_chooseFileMode) {
      Navigator.of(context).pop();
      widget.onChooseFile?.call();
      return;
    }
    await _runRetry();
  }

  Future<void> _runRetry() async {
    if (_pending) return;
    setState(() => _pending = true);
    var success = false;
    ConnectionFailure? updated;
    try {
      success = await widget.onRetry();
      if (!success) updated = widget.latestFailure?.call();
    } catch (error, stackTrace) {
      // 重试抛异常 = 失败：按异常消息构造 unknown failure 原地展示
      // （不崩、不关）。异常文本经展示层 redactSecrets 呈现。
      AppLogger.e('ConnectFailureDialog', 'Retry threw an exception', error,
          stackTrace);
      updated = ConnectionFailure(
        kind: ConnectionFailureKind.unknown,
        errorCode: '',
        rawMessage: error.toString(),
        occurredAt: DateTime.now(),
      );
    }
    if (!mounted) return;
    setState(() {
      _pending = false;
      if (!success && updated != null) _failure = updated;
    });
    if (success) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Focus(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _onKeyEvent,
      child: AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        surfaceTintColor: Colors.transparent,
        title: _buildTitle(context),
        content: SizedBox(
          width: 480,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ActionableError(
                  message: _plainMessage(l10n, _failure.kind),
                  style: ActionableErrorStyle.body,
                ),
                const SizedBox(height: AppDesignSystem.space4),
                _buildActionRow(context, l10n),
                const SizedBox(height: AppDesignSystem.space2),
                _buildTechnicalDetails(context, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final colors = context.themeColors;
    return Row(
      children: [
        Icon(LucideIcons.circleAlert, size: 20, color: colors.error),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: Text(
            AppLocalizations.of(context)!.connectFailureTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AppDesignSystem.fontSizeLg,
              fontWeight: AppDesignSystem.fontWeightSemibold,
            ),
          ),
        ),
      ],
    );
  }

  /// 动作区：复制详情 + 关闭 + 主动作。用 Wrap 右对齐——长文案语言
  /// （如 fileNotFound 的「重新选择文件」）放不下时优雅换行，不溢出。
  Widget _buildActionRow(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppDesignSystem.space2,
      runSpacing: AppDesignSystem.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: _CopyDetailsButton(payload: _copyPayload(l10n)),
        ),
        FocusTraversalOrder(
          order: const NumericFocusOrder(1),
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
            child: Text(l10n.commonClose),
          ),
        ),
        FocusTraversalOrder(
          order: const NumericFocusOrder(0),
          child: FilledButton.icon(
            autofocus: true,
            onPressed: _pending ? null : _runPrimaryAction,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accentBlue,
              foregroundColor: Colors.white,
            ),
            icon: _pending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _chooseFileMode
                        ? LucideIcons.folderOpen
                        : LucideIcons.refreshCw,
                    size: 16,
                  ),
            label: Text(
              _chooseFileMode
                  ? l10n.connectFailureChooseFile
                  : l10n.connectFailureRetry,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTechnicalDetails(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: Semantics(
            expanded: _detailsExpanded,
            button: true,
            child: InkWell(
              onTap: () =>
                  setState(() => _detailsExpanded = !_detailsExpanded),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedRotation(
                      turns: _detailsExpanded ? 0.5 : 0,
                      duration: AppDesignSystem.durationFast,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      l10n.connectFailureTechnicalDetails,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AppDesignSystem.fontSizeSm,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 折叠时不构建详情子树（含路径/语句等敏感内容），展开后才挂到树上。
        if (_detailsExpanded)
          ActionableError(message: '', details: _detailItems(l10n)),
      ],
    );
  }

  String _plainMessage(AppLocalizations l10n, ConnectionFailureKind kind) =>
      switch (kind) {
        ConnectionFailureKind.fileLocked => l10n.connectFailureFileLocked,
        ConnectionFailureKind.fileNotFound => l10n.connectFailureFileNotFound,
        ConnectionFailureKind.permissionDenied =>
          l10n.connectFailurePermissionDenied,
        ConnectionFailureKind.notADatabase => l10n.connectFailureNotADatabase,
        ConnectionFailureKind.corrupt => l10n.connectFailureCorrupt,
        ConnectionFailureKind.authFailed => l10n.connectFailureAuthFailed,
        ConnectionFailureKind.unreachable => l10n.connectFailureUnreachable,
        ConnectionFailureKind.unknown => l10n.connectFailureUnknown,
      };

  /// 技术详情键值行——failure 字段为 null/空的行不渲染（原始异常恒有）。
  List<ErrorDetail> _detailItems(AppLocalizations l10n) {
    final items = <ErrorDetail>[];
    if (_failure.errorCode.isNotEmpty) {
      items.add(
        ErrorDetail(label: l10n.connectFailureErrorCode, value: _failure.errorCode),
      );
    }
    final statement = _failure.offendingStatement;
    if (statement != null && statement.isNotEmpty) {
      items.add(
        ErrorDetail(label: l10n.connectFailureStatement, value: statement),
      );
    }
    final target = _failure.target;
    if (target != null && target.isNotEmpty) {
      items.add(ErrorDetail(label: l10n.connectFailureFile, value: target));
    }
    items.add(
      ErrorDetail(label: l10n.connectFailureRawError, value: _failure.rawMessage),
    );
    return items;
  }

  /// 复制详情 payload = 人话 + 全部技术详情纯文本；逐段过 redactSecrets，
  /// 与 ActionableError 自带复制口（payload 已含 details）语义一致。
  String _copyPayload(AppLocalizations l10n) {
    final buf =
        StringBuffer(redactSecrets(_plainMessage(l10n, _failure.kind)));
    final items = _detailItems(l10n);
    if (items.isNotEmpty) {
      buf.write('\n\n');
      buf.write(items
          .map((item) => '${item.label}: ${redactSecrets(item.value)}')
          .join('\n'));
    }
    return buf.toString();
  }
}

/// 「复制详情」按钮——复制 [payload] 并短暂显示已复制反馈（对齐
/// ActionableError 自带复制钮行为）。
class _CopyDetailsButton extends StatefulWidget {
  const _CopyDetailsButton({required this.payload});

  final String payload;

  @override
  State<_CopyDetailsButton> createState() => _CopyDetailsButtonState();
}

class _CopyDetailsButtonState extends State<_CopyDetailsButton> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.payload));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(_copied ? LucideIcons.check : LucideIcons.copy, size: 14),
      label: Text(_copied ? l10n.errorCopied : l10n.connectFailureCopyDetails),
    );
  }
}
