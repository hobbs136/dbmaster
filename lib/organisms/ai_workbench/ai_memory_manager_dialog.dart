//! AI 记忆管理对话框（T3）。
//!
//! 按「全局 / 当前连接」两个分区列出 AI 记忆（subject + content + 时间 +
//! 来源），支持新增/编辑/删除；删除走确认 AlertDialog（先例
//! `mcp_token_dialog.dart`），服务操作失败用 SnackBar 反馈。
//! 当前连接 id 由调用方传入——连接未选时连接分区显示引导空态。
//! 数据面是 `AiMemoryService` 单例（SharedPreferences 分键存储），
//! 本对话框只做展示与增删改触发。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_memory_item.dart';
import '../../services/ai/ai_memory_service.dart';
import '../../theme/app_colors.dart';

/// 打开 AI 记忆管理对话框。
///
/// [connectionId] 为当前连接 id（由调用方传入）；null = 未选连接，
/// 连接分区显示引导空态。
Future<void> showAiMemoryManagerDialog(
  BuildContext context, {
  String? connectionId,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 560,
        height: 520,
        child: AiMemoryManagerDialog(connectionId: connectionId),
      ),
    ),
  );
}

class AiMemoryManagerDialog extends StatefulWidget {
  const AiMemoryManagerDialog({super.key, this.connectionId});

  /// 当前连接 id；null = 未选连接（连接分区显示引导空态）。
  final String? connectionId;

  @override
  State<AiMemoryManagerDialog> createState() => _AiMemoryManagerDialogState();
}

class _AiMemoryManagerDialogState extends State<AiMemoryManagerDialog> {
  final AiMemoryService _service = AiMemoryService();

  @override
  void initState() {
    super.initState();
    // 服务懒加载持久化记忆；完成后刷新一次（initialize 幂等）。
    unawaited(
      _service.initialize().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _l10n.aiMemoryTitle,
            style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Expanded(
            child: ListView(
              children: [
                _buildSectionHeader(
                  _l10n.aiMemoryGlobalSection,
                  scope: AiMemoryScope.global,
                  canAdd: true,
                ),
                ..._buildMemoryList(
                  _service.listGlobal(),
                  emptyKey: _l10n.aiMemoryEmpty,
                ),
                const SizedBox(height: AppDesignSystem.space4),
                _buildSectionHeader(
                  _l10n.aiMemoryConnectionSection,
                  scope: AiMemoryScope.connection,
                  canAdd: widget.connectionId != null,
                ),
                ..._buildConnectionSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 分区头。[scope] 显式声明本分区的记忆作用域——新增按钮按该 scope 落库，
  /// 不再由 connectionId 在场与否推断（连接在场时全局分区头也能新增全局
  /// 记忆，R-1）。
  Widget _buildSectionHeader(
    String label, {
    required AiMemoryScope scope,
    required bool canAdd,
  }) {
    final colors = context.themeColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.h4.copyWith(color: colors.textSecondary),
          ),
        ),
        if (canAdd)
          IconButton(
            tooltip: _l10n.aiMemoryAdd,
            icon: Icon(LucideIcons.plus, size: 16, color: colors.textSecondary),
            onPressed: () => _add(scope),
          ),
      ],
    );
  }

  /// 连接分区：未选连接 → 引导空态；已选 → 记忆列表（可空态）。
  List<Widget> _buildConnectionSection() {
    final connectionId = widget.connectionId;
    if (connectionId == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space3),
          child: Text(
            _l10n.aiMemoryNoConnectionSelected,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.themeColors.textMuted,
            ),
          ),
        ),
      ];
    }
    return _buildMemoryList(
      _service.listForConnection(connectionId),
      emptyKey: _l10n.aiMemoryEmpty,
    );
  }

  List<Widget> _buildMemoryList(
    List<AiMemoryItem> items, {
    required String emptyKey,
  }) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
          child: Text(
            emptyKey,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.themeColors.textMuted,
            ),
          ),
        ),
      ];
    }
    return List<Widget>.generate(items.length, (i) => _buildItemTile(items[i]));
  }

  Widget _buildItemTile(AiMemoryItem item) {
    final colors = context.themeColors;
    final sourceLabel = item.source == AiMemorySource.agent
        ? _l10n.aiMemorySourceAgent
        : _l10n.aiMemorySourceManual;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.subject ?? _l10n.aiMemoryNoSubject,
                  style: AppTextStyles.code.copyWith(
                    fontSize: 12,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.content,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$sourceLabel · ${_formatMillis(item.updatedAt)}',
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          IconButton(
            tooltip: _l10n.aiMemoryEdit,
            icon: Icon(LucideIcons.pencil, size: 16, color: colors.textMuted),
            onPressed: () => _edit(item),
          ),
          IconButton(
            tooltip: _l10n.aiMemoryDelete,
            icon: Icon(LucideIcons.trash2, size: 16, color: colors.error),
            onPressed: () => _delete(item),
          ),
        ],
      ),
    );
  }

  // ==================== 操作 ====================

  Future<void> _add(AiMemoryScope scope) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _MemoryEditorDialog(scope: scope, connectionId: widget.connectionId),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _edit(AiMemoryItem item) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MemoryEditorDialog(
        scope: item.scope,
        connectionId: item.connectionId,
        existing: item,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  /// 删除：确认 AlertDialog（先例 mcp_token_dialog._revoke）→ 服务删除，
  /// 失败 SnackBar。
  Future<void> _delete(AiMemoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.aiMemoryDeleteTitle),
        content: Text(_l10n.aiMemoryDeleteBody(_previewOf(item))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.aiMemoryDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.remove(item);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_l10n.aiMemoryOperationFailed(error.toString()))),
    );
  }

  /// 确认框预览文案：优先 subject，否则取 content 首行并截断。
  String _previewOf(AiMemoryItem item) {
    final raw = (item.subject ?? item.content).replaceAll('\n', ' ').trim();
    if (raw.length <= 40) return raw;
    return '${raw.substring(0, 40)}…';
  }

  /// 毫秒时间戳 → `YYYY-MM-DD HH:MM`（技术格式，与 rfc3339 短显示一致）。
  String _formatMillis(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// 单条记忆的编辑对话框（新增/编辑共用）。
class _MemoryEditorDialog extends StatefulWidget {
  const _MemoryEditorDialog({
    required this.scope,
    this.connectionId,
    this.existing,
  });

  final AiMemoryScope scope;
  final String? connectionId;

  /// 非空 = 编辑既有条目；空 = 新增。
  final AiMemoryItem? existing;

  @override
  State<_MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<_MemoryEditorDialog> {
  late final TextEditingController _subjectController = TextEditingController(
    text: widget.existing?.subject ?? '',
  );
  late final TextEditingController _contentController = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  String? _contentError;
  bool _saving = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? _l10n.aiMemoryAdd : _l10n.aiMemoryEdit,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: _l10n.aiMemorySubjectLabel,
                hintText: _l10n.aiMemorySubjectHint,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            TextField(
              controller: _contentController,
              maxLines: 4,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: _l10n.aiMemoryContentLabel,
                errorText: _contentError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_l10n.cancel),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_l10n.aiMemorySave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _contentError = _l10n.aiMemoryContentRequired);
      return;
    }
    setState(() {
      _saving = true;
      _contentError = null;
    });
    try {
      final service = AiMemoryService();
      final existing = widget.existing;
      if (existing == null) {
        await service.add(
          scope: widget.scope,
          connectionId: widget.connectionId,
          subject: _subjectController.text,
          content: content,
        );
      } else {
        await service.update(
          existing.copyWith(subject: _subjectController.text, content: content),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l10n.aiMemoryOperationFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
