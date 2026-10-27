// 连接失败对话框（连接失败 UX 重构 T5 + 批4 T8 结构化诊断）。
//
// 把连接失败从固定文案 snackbar 升级为模态对话框：人话原因 + 恢复动作 +
// 折叠技术详情 + 复制。与 provider 解耦——重试、重选文件、最新失败均由
// 调用方注入（[ConnectFailureDialog.show]），组件可脱离 provider 单测。
//
// T8 三层结构（P5-1.2）：人话 + 错误码 chip / 实例信息条（codeBlockBg
// mono）/ 每 kind 恢复建议组；主按钮按 kind 映射（authFailed→重输密码、
// networkTimeout→检查主机与代理、sslHandshake→切换 SSL 重试，其余→重试）；
// Raw 驱动消息独立 160 限高承载（不动共享 ActionableError 的 120）；
// 「复制脱敏诊断」按 B-06-R 报告模板组装后整体过 redactConnectDiagnostics。
//
// 重试语义：pending 中主动作 loading 禁点；成功关闭 dialog；失败单实例
// 原地更新（从 latestFailure 取新 failure 刷新，null 沿用旧值），不叠开
// 第二个 dialog。onRetry 抛异常视为失败，按异常消息构造 unknown failure
// 原地展示。原地刷新后复制 payload（含脱敏诊断报告）随 build 重建，
// 不缓存旧失败信息（B-06-R 调用侧铁律）。
//
// 键盘：主动作初始焦点；Enter 触发主动作；Esc 关闭（Focus.onKeyEvent
// 标记 handled，阻断应用级 Esc DismissIntent 造成二次 pop）；Tab 顺序 =
// 主动作 → 关闭（次动作）→ 折叠头 → 复制详情 → 复制脱敏诊断。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../atoms/app_transitions.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/actionable_error.dart';
import '../../models/connection_failure.dart';
import '../../services/update_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_logger.dart';
import '../../utils/connect_diagnostics_redactor.dart';
import '../../utils/secret_redactor.dart';

/// Raw 驱动消息独立承载区限高（UI35-416 目标契约；共享 ActionableError
/// 详情区保持既有 120 不动，其它消费者零波及）。
const double _rawMaxHeight = 160;

/// 连接失败对话框——人话原因 + 恢复动作 + 折叠技术详情 + 复制。
class ConnectFailureDialog extends StatefulWidget {
  /// 创建连接失败对话框。
  const ConnectFailureDialog({
    super.key,
    required this.failure,
    required this.onRetry,
    this.onChooseFile,
    this.latestFailure,
    this.driverName,
    this.environmentLabel,
  });

  /// 当前展示的失败（重试失败后原地替换）。
  final ConnectionFailure failure;

  /// 主动作（重试）；返回 true = 成功关闭，false = 原地更新。
  final Future<bool> Function() onRetry;

  /// fileNotFound 主动作「重新选择文件」；null 时该 kind 主动作退回重试。
  final VoidCallback? onChooseFile;

  /// 重试失败后取最新失败；回调为 null 或返回 null 时沿用旧 [failure]。
  final ConnectionFailure? Function()? latestFailure;

  /// 数据库类型（如 'MySQL'），进脱敏诊断报告「数据库类型」行；null 省略。
  final String? driverName;

  /// 环境标签（production/testing/development），进报告「环境标签」行；
  /// null 省略（B-06-R 报告模板字段）。
  final String? environmentLabel;

  /// 以模态对话框展示连接失败（重试失败后由组件原地刷新，不叠开新实例）。
  static Future<void> show(
    BuildContext context, {
    required ConnectionFailure failure,
    required Future<bool> Function() onRetry,
    VoidCallback? onChooseFile,
    ConnectionFailure? Function()? latestFailure,
    String? driverName,
    String? environmentLabel,
  }) {
    return context.showAnimatedDialog<void>(
      barrierDismissible: false,
      builder: (_) => ConnectFailureDialog(
        failure: failure,
        onRetry: onRetry,
        onChooseFile: onChooseFile,
        latestFailure: latestFailure,
        driverName: driverName,
        environmentLabel: environmentLabel,
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
      AppLogger.e(
        'ConnectFailureDialog',
        'Retry threw an exception',
        error,
        stackTrace,
      );
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
            // 三层结构 + 建议组可能超出对话框默认限高，内容整体可滚动。
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ActionableError(
                    message: _plainMessage(l10n, _failure.kind),
                    style: ActionableErrorStyle.body,
                  ),
                  _buildInstanceBar(context),
                  _buildSuggestions(context, l10n),
                  const SizedBox(height: AppDesignSystem.space4),
                  _buildActionRow(context, l10n),
                  const SizedBox(height: AppDesignSystem.space2),
                  _buildTechnicalDetails(context, l10n),
                ],
              ),
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

  /// 实例信息条（T8 三层结构第二层）：codeBlockBg mono 底 + 错误码 chip +
  /// 连接目标。无错误码且无目标时整条不渲染。
  Widget _buildInstanceBar(BuildContext context) {
    final colors = context.themeColors;
    final errorCode = _failure.errorCode;
    final target = _failure.target;
    final hasCode = errorCode.isNotEmpty;
    final hasTarget = target != null && target.isNotEmpty;
    if (!hasCode && !hasTarget) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppDesignSystem.space2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1 + 2,
        ),
        decoration: BoxDecoration(
          color: colors.codeBlockBg,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Row(
          children: [
            if (hasCode) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1 + 2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: colors.textMuted),
                ),
                child: Text(
                  errorCode,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
            ],
            if (hasTarget)
              Expanded(
                child: Text(
                  target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 恢复建议区（T8 三层结构第三层）：每 kind 恰 3 条专属建议 + 通用尾
  /// 3 条（重试确认 / 展开 Raw / 复制脱敏诊断）。仅有专属建议组的 kind
  /// （authFailed / networkTimeout / sslHandshake）渲染；其余 kind 保持
  /// T5 既有形态（空占位不占高度）。
  Widget _buildSuggestions(BuildContext context, AppLocalizations l10n) {
    final kindSpecific = switch (_failure.kind) {
      ConnectionFailureKind.authFailed => [
        l10n.connectFailureSuggestionAuthCredentials,
        l10n.connectFailureSuggestionAuthHostRule,
        l10n.connectFailureSuggestionAuthSshTunnel,
      ],
      ConnectionFailureKind.networkTimeout => [
        l10n.connectFailureSuggestionTimeoutHostPort,
        l10n.connectFailureSuggestionTimeoutProxy,
        l10n.connectFailureSuggestionTimeoutRemote,
      ],
      ConnectionFailureKind.sslHandshake => [
        l10n.connectFailureSuggestionSslMode,
        l10n.connectFailureSuggestionSslCa,
        l10n.connectFailureSuggestionSslServer,
      ],
      _ => null,
    };
    if (kindSpecific == null) return const SizedBox.shrink();
    final suggestions = [
      ...kindSpecific,
      l10n.connectFailureSuggestionRetry,
      l10n.connectFailureSuggestionRaw,
      l10n.connectFailureSuggestionCopy,
    ];
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesignSystem.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.connectFailureRecoveryTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: AppDesignSystem.fontWeightSemibold,
            ),
          ),
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(top: AppDesignSystem.space1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      LucideIcons.circleCheck,
                      size: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AppDesignSystem.fontSizeSm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 主动作文案（P5-1.3 映射）：authFailed→重输密码、networkTimeout→检查
  /// 主机与代理、sslHandshake→切换 SSL 重试；其余（含 fileNotFound 无回调
  /// 回落）→ 既有 Retry。动作为定位入口或重测——对话框未注入编辑入口
  /// 回调时统一回落重测（重试），不越权改连接配置。
  String _primaryLabel(AppLocalizations l10n) {
    if (_chooseFileMode) return l10n.connectFailureChooseFile;
    return switch (_failure.kind) {
      ConnectionFailureKind.authFailed => l10n.connectFailureReenterPassword,
      ConnectionFailureKind.networkTimeout => l10n.connectFailureCheckHostProxy,
      ConnectionFailureKind.sslHandshake => l10n.connectFailureSwitchSslRetry,
      _ => l10n.connectFailureRetry,
    };
  }

  /// 动作区：复制详情 + 复制脱敏诊断 + 关闭 + 主动作。用 Wrap 右对齐——
  /// 长文案语言放不下时优雅换行，不溢出。
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
          order: const NumericFocusOrder(4),
          child: _CopyDetailsButton(
            payload: _redactedDiagnosticsPayload(l10n),
            label: l10n.connectFailureCopyRedacted,
          ),
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
            label: Text(_primaryLabel(l10n)),
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
              onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppDesignSystem.space2,
                ),
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
        if (_detailsExpanded) ...[
          ActionableError(message: '', details: _displayDetailItems(l10n)),
          const SizedBox(height: AppDesignSystem.space1),
          _buildRawSection(context, l10n),
        ],
      ],
    );
  }

  /// Raw 驱动消息独立承载区（UI35-416）：限高 160 滚动 + 等宽小字 +
  /// bgTertiary 语汇（沿 ActionableError 详情区词汇）；展示文本过
  /// redactSecrets（与展示边界既有口径一致）。
  Widget _buildRawSection(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.connectFailureRawError,
          style: AppTextStyles.caption.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _rawMaxHeight),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                redactSecrets(_failure.rawMessage),
                style: const TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
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
        ConnectionFailureKind.networkTimeout =>
          l10n.connectFailureNetworkTimeout,
        ConnectionFailureKind.sslHandshake => l10n.connectFailureSslHandshake,
        ConnectionFailureKind.unknown => l10n.connectFailureUnknown,
      };

  /// 技术详情键值行——failure 字段为 null/空的行不渲染（原始异常恒有）。
  List<ErrorDetail> _detailItems(AppLocalizations l10n) {
    final items = <ErrorDetail>[];
    if (_failure.errorCode.isNotEmpty) {
      items.add(
        ErrorDetail(
          label: l10n.connectFailureErrorCode,
          value: _failure.errorCode,
        ),
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
      ErrorDetail(
        label: l10n.connectFailureRawError,
        value: _failure.rawMessage,
      ),
    );
    return items;
  }

  /// 展示用详情行 = [_detailItems] 去掉 Raw（Raw 独立 160 限高承载）。
  List<ErrorDetail> _displayDetailItems(AppLocalizations l10n) => _detailItems(
    l10n,
  ).where((item) => item.label != l10n.connectFailureRawError).toList();

  /// 复制详情 payload = 人话 + 全部技术详情纯文本；逐段过 redactSecrets，
  /// 与 ActionableError 自带复制口（payload 已含 details）语义一致。
  String _copyPayload(AppLocalizations l10n) {
    final buf = StringBuffer(redactSecrets(_plainMessage(l10n, _failure.kind)));
    final items = _detailItems(l10n);
    if (items.isNotEmpty) {
      buf.write('\n\n');
      buf.write(
        items
            .map((item) => '${item.label}: ${redactSecrets(item.value)}')
            .join('\n'),
      );
    }
    return buf.toString();
  }

  /// 脱敏诊断报告 payload（B-06-R 模板，小节顺序冻结）：标题 + 列表
  /// （App 版本 / 数据库类型 / 环境标签 / 错误码空则省略行 / 连接目标
  /// code span）+ 原始错误 fenced block。连接名/数据库名/系统用户名/
  /// 时间戳/机器码禁入报告（occurredAt 不进）。环境标签行落冻结字面三值
  /// （[_frozenEnvironmentLabel]，B-06-R「production | testing |
  /// development」跨语言稳定可 grep）。报告先组装、后整体单次过
  /// redactConnectDiagnostics；随 build 重建，重试失败原地刷新后
  /// 自动取新 failure（不缓存旧失败信息）。
  String _redactedDiagnosticsPayload(AppLocalizations l10n) {
    final appVersion = UpdateService.instance.appVersion.split('+').first;
    final buf = StringBuffer('# DbMaster 连接诊断\n\n');
    buf.writeln('- App 版本: $appVersion');
    final driver = widget.driverName;
    if (driver != null && driver.isNotEmpty) {
      buf.writeln('- 数据库类型: $driver');
    }
    final environment = widget.environmentLabel;
    if (environment != null && environment.isNotEmpty) {
      buf.writeln('- 环境标签: ${_frozenEnvironmentLabel(environment, l10n)}');
    }
    if (_failure.errorCode.isNotEmpty) {
      buf.writeln('- 错误码: ${_failure.errorCode}');
    }
    final target = _failure.target;
    if (target != null && target.isNotEmpty) {
      buf.writeln('- 连接目标: `$target`');
    }
    buf.write('\n## 原始错误\n\n```\n');
    buf.write(_failure.rawMessage);
    buf.write('\n```\n');
    return redactConnectDiagnostics(buf.toString());
  }

  /// 环境标签冻结字面值解析（B-06-R：「环境标签: production | testing |
  /// development」，跨语言稳定可 grep）。[environmentLabel] 语义 = 枚举
  /// name 或其本地化显示名由调用方传入（UI 弹窗内展示不受影响，仅报告
  /// payload 行冻结）：冻结三值直通；本地化显示名按当前 locale 反解析
  /// 为枚举 name；未识别值原样保留（不猜）。UI 弹窗内不消费本方法。
  String _frozenEnvironmentLabel(String label, AppLocalizations l10n) {
    if (label == 'production' || label == 'testing' || label == 'development') {
      return label;
    }
    if (label == l10n.environmentProduction) return 'production';
    if (label == l10n.environmentTesting) return 'testing';
    if (label == l10n.environmentDevelopment) return 'development';
    return label;
  }
}

/// 「复制详情」按钮——复制 [payload] 并短暂显示已复制反馈（对齐
/// ActionableError 自带复制钮行为）；[label] 缺省为既有「复制详情」，
/// 脱敏诊断按钮复用同一 2s 反馈先例。
class _CopyDetailsButton extends StatefulWidget {
  const _CopyDetailsButton({required this.payload, this.label});

  final String payload;

  /// 正常态文案；null = 既有 connectFailureCopyDetails。
  final String? label;

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
      label: Text(
        _copied
            ? l10n.errorCopied
            : (widget.label ?? l10n.connectFailureCopyDetails),
      ),
    );
  }
}
