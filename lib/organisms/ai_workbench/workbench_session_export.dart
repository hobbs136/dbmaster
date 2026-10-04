//! AI 会话导出入口 UI（AI-SEX 批 T3，登记 docs/test/unified_test_spec.md §6.13）。
//!
//! 会话条目菜单「导出会话」（workbench_session_list_view.dart，rail 窄列与
//! 舞台 sessionList tab 双形态同源）→ 选项对话框 → FilePicker 保存 →
//! snackbar 反馈 + 导出审计。格式契约与序列化全部由
//! [AiSessionExportService]（T1）承载，本文件只做入口编排：
//! - 任一取消点（对话框取消 / 文件选择取消）= 零副作用零反馈；
//! - 消息快照在对话框确认时点一次性取（List.unmodifiable，只读访问器）；
//! - 错误反馈文案经 `redactSecrets` 脱敏后展示。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_conversation_session.dart';
import '../../models/database_models.dart';
import '../../models/workbench_context_lock.dart';
import '../connection/error_boundary.dart';
import '../../providers/app_provider.dart';
import '../../services/ai/ai_session_export_service.dart';
import '../../services/audit_log_service.dart';
import '../../services/export_service.dart';
import '../../services/update_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_logger.dart';
import '../../utils/secret_redactor.dart';

/// 审计格式常量（与既有 export_service 的 'csv'/'json' 同层取值空间）。
const String kAiSessionExportAuditFormat = 'ai_session_json';

/// 会话导出：选项对话框 → FilePicker 保存 → snackbar + 审计。
///
/// 任一取消点（对话框/文件选择）= 零副作用零反馈。写盘/选择器异常 →
/// 错误 snackbar（文案经 [redactSecrets] 脱敏）；审计失败仅记日志，
/// 不影响导出结果。默认 [savePathPicker] 为 FilePicker saveFile 包装、
/// 默认 [exportAuditLogger] 为 `AuditLogService().logExportEvent`，
/// 两者均为注入接缝（widget 测试覆盖用，FilePicker 平台插件测试不 mock）。
Future<void> showAiSessionExportDialog(
  BuildContext context,
  AiConversationSession session, {
  @visibleForTesting
  Future<String?> Function(String suggestedFileName)? savePathPicker,
  @visibleForTesting
  Future<void> Function({required String format, required int rowCount})?
      exportAuditLogger,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context)!;

  // ① 选项对话框（取消 = 零副作用零反馈；pop(false) = 用户主动去勾后确认）。
  final bool? includeData = await showDialog<bool>(
    context: context,
    builder: (_) => const _AiSessionExportDialog(),
  );
  if (includeData == null) return;
  if (!context.mounted) return;

  // ② 消息快照（确认时点一次性取）+ meta 组装。
  final AppProvider app = context.read<AppProvider>();
  final List<AiMessage> messages = List<AiMessage>.unmodifiable(
    app.aiPanel.aiConversationService.messagesForSession(session.id),
  );
  final AiSessionExportMeta meta = AiSessionExportMeta(
    appVersion: UpdateService.instance.appVersion,
    aiProvider: app.selectedAiProvider,
    aiModel: app.selectedAiModel,
    locale: Localizations.localeOf(context).toLanguageTag(),
    exportedAt: DateTime.now(),
    contextConnectionName: _resolveContextConnectionName(app, session),
  );

  // ③ FilePicker 保存（取消 = 零副作用零反馈；fileName 用 T1 命名规则）。
  final Future<String?> Function(String suggestedFileName) picker =
      savePathPicker ??
      _defaultSavePathPicker(l10n.workbenchSessionExportTitle);
  final String? pickedPath;
  try {
    pickedPath = await picker(
      AiSessionExportService.exportFileName(session.title, meta.exportedAt),
    );
  } catch (e) {
    // 跨异步用 context 前显式守卫（_showFailure 内部亦再查一次）。
    if (context.mounted) _showFailure(context, l10n, e);
    return;
  }
  if (pickedPath == null) return;

  // ④ 选了路径 → 构建信封 + 写盘（后缀补全沿 ExportService 既有口径）。
  final String path = ExportService.ensureExtension(pickedPath, 'json');
  try {
    final String content = AiSessionExportService.encodeEnvelope(
      AiSessionExportService.buildEnvelope(
        session: session,
        messages: messages,
        meta: meta,
        options: AiSessionExportOptions(includeToolResultData: includeData),
      ),
    );
    await File(path).writeAsString(content, flush: true);
  } catch (e) {
    if (context.mounted) _showFailure(context, l10n, e);
    return;
  }

  // ⑤ 成功反馈 + 审计（审计失败仅记日志，不影响导出结果）。
  if (!context.mounted) return;
  AppErrorHandler.showSuccessSnackBar(
    context,
    l10n.workbenchSessionExportSuccess(path),
  );
  try {
    final Future<void> Function({required String format, required int rowCount})
    logger = exportAuditLogger ?? _defaultExportAuditLogger;
    await logger(format: kAiSessionExportAuditFormat, rowCount: messages.length);
  } catch (e) {
    AppLogger.w('AiSessionExport', 'audit log failed: $e');
  }
}

/// 上下文连接名解析：会话锁定快照的 connectionId → ConnectionProvider
/// 保存列表查连接名；无锁定 / 查不到 → null。
String? _resolveContextConnectionName(
  AppProvider app,
  AiConversationSession session,
) {
  final WorkbenchContextLock? lock = WorkbenchContextLock.fromMetadata(
    session.metadata,
  );
  if (lock == null) return null;
  for (final DbServer server in app.connection.savedConnections) {
    if (server.id == lock.connectionId) return server.name;
  }
  return null;
}

/// 默认保存路径选择器：FilePicker saveFile（json 单扩展，标题用导出对话框
/// 同一 l10n 键——原生对话框标题无独立 key，复用任务书允许键集）。
Future<String?> Function(String suggestedFileName) _defaultSavePathPicker(
  String dialogTitle,
) {
  return (String suggestedFileName) => FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: suggestedFileName,
    type: FileType.custom,
    allowedExtensions: const <String>['json'],
  );
}

/// 默认审计回调：导出事件审计（format/rowCount 同既有导出口径）。
Future<void> _defaultExportAuditLogger({
  required String format,
  required int rowCount,
}) {
  return AuditLogService().logExportEvent(format: format, rowCount: rowCount);
}

/// 失败反馈：错误 snackbar，error 文案经 redactSecrets 脱敏。
void _showFailure(BuildContext context, AppLocalizations l10n, Object error) {
  if (!context.mounted) return;
  AppErrorHandler.showErrorSnackBar(
    context,
    l10n.workbenchSessionExportFailed(redactSecrets(error.toString())),
  );
}

/// 导出选项对话框（私有）：标题 + 说明 + 轻量选项复选框（默认勾选 =
/// 含查询结果数据）。确认 pop(当前勾选值) / 取消 pop(null)——null 即
/// 取消（零副作用），false 仅在用户主动去勾后确认时出现。
class _AiSessionExportDialog extends StatefulWidget {
  const _AiSessionExportDialog();

  @override
  State<_AiSessionExportDialog> createState() => _AiSessionExportDialogState();
}

class _AiSessionExportDialogState extends State<_AiSessionExportDialog> {
  bool _includeData = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.workbenchSessionExportTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.workbenchSessionExportHint,
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          CheckboxListTile(
            value: _includeData,
            onChanged: (value) => setState(() => _includeData = value ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              l10n.workbenchSessionExportIncludeData,
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_includeData),
          child: Text(l10n.export),
        ),
      ],
    );
  }
}
