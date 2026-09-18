//! MCP personal-token management dialog (dbx-response T04b / decision D7).
//!
//! Lists the Server's long-lived `/mcp` tokens (`GET /api/mcp/tokens`),
//! creates new ones (POST — the plaintext is displayed exactly once with a
//! copy affordance, then never retrievable), and revokes them
//! (DELETE + confirm). The plaintext lives only in dialog state — it is
//! never written to SharedPreferences or secure storage.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/rfc3339.dart';
import '../../../services/server_connection.dart';
import '../../../models/mcp_token.dart';
import '../../../services/mcp_token_api_service.dart';
import '../../../theme/app_colors.dart';

/// Opens the MCP token management dialog.
Future<void> showMcpTokenDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const Dialog(
      child: SizedBox(width: 560, height: 500, child: _McpTokenDialog()),
    ),
  );
}

class _McpTokenDialog extends StatefulWidget {
  const _McpTokenDialog();

  @override
  State<_McpTokenDialog> createState() => _McpTokenDialogState();
}

class _McpTokenDialogState extends State<_McpTokenDialog> {
  late final McpTokenApiService _api;
  Future<List<McpTokenInfo>>? _future;
  final _nameController = TextEditingController();
  final Set<String> _revoking = {};

  /// One-time plaintext view state. Memory only — cleared on dialog close.
  McpTokenCreated? _created;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _api = McpTokenApiService();
    _refresh();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _refresh() {
    // Not connected: build() short-circuits before FutureBuilder consumes
    // _future; skip the round-trip (would only reject + unhandled Future).
    if (!_api.isConnected) return;
    final future = _api.list();
    // 关闭对话框时在途请求的拒绝无 FutureBuilder 监听者 → unhandled zone
    // error 打到 ErrorBoundary（2026-08-22 灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
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
            _l10n.mcpTokensTitle,
            style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Expanded(
            child: !_api.isConnected
                ? _buildNotConnected(colors)
                : (_created != null
                      ? _buildCreated(colors)
                      : _buildList(colors)),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnected(ThemeColors colors) {
    return Center(
      child: Text(
        _l10n.mcpTokensNotConnected,
        style: AppTextStyles.body.copyWith(color: colors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// One-time plaintext view after create. Replaces the whole body until
  /// the user dismisses it — there is no way back to this screen once left.
  Widget _buildCreated(ThemeColors colors) {
    final created = _created;
    if (created == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.keyRound, size: 18, color: colors.success),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                _l10n.mcpTokensOnceTitle(created.name),
                style: AppTextStyles.h4.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            color: colors.bgSecondary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: colors.borderColor),
          ),
          child: SelectableText(
            created.token,
            style: AppTextStyles.code.copyWith(fontSize: 13),
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Row(
          children: [
            Icon(LucideIcons.triangleAlert, size: 16, color: colors.warning),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                _l10n.mcpTokensOnceWarning,
                style: AppTextStyles.caption.copyWith(color: colors.warning),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space3),
        // U17：配置引导——直接给出可复制的 MCP 端点（server 主端口 + /mcp），
        // 此前只有「把它配置到 MCP 客户端」的泛化文案，用户得自己猜 URL。
        Row(
          children: [
            Icon(LucideIcons.cable, size: 16, color: colors.textSecondary),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                _l10n.mcpTokensEndpointHint,
                style: AppTextStyles.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppDesignSystem.space2),
                decoration: BoxDecoration(
                  color: colors.bgSecondary,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: colors.borderColor),
                ),
                child: SelectableText(
                  _mcpEndpoint,
                  style: AppTextStyles.code.copyWith(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            IconButton(
              tooltip: _l10n.mcpTokensCopy,
              icon: const Icon(LucideIcons.copy, size: 16),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _mcpEndpoint));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_l10n.mcpTokensEndpointCopied)),
                  );
                }
              },
            ),
          ],
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: created.token));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_l10n.mcpTokensCopied)),
                  );
                }
              },
              icon: const Icon(LucideIcons.copy, size: 16),
              label: Text(_l10n.mcpTokensCopy),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            FilledButton(
              onPressed: () {
                setState(() => _created = null);
                _nameController.clear();
                _refresh();
              },
              child: Text(_l10n.mcpTokensDone),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildList(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _l10n.mcpTokensIntro,
          style: AppTextStyles.caption.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _l10n.mcpTokensNameHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            FilledButton.icon(
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.plus, size: 16),
              label: Text(_l10n.mcpTokensCreate),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: FutureBuilder<List<McpTokenInfo>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    snapshot.error.toString(),
                    style: AppTextStyles.caption.copyWith(color: colors.error),
                  ),
                );
              }
              final tokens = snapshot.data ?? const [];
              if (tokens.isEmpty) return _buildEmpty(colors);
              return ListView.separated(
                itemCount: tokens.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _buildRow(colors, tokens[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeColors colors) {
    return Center(
      child: Text(
        _l10n.mcpTokensEmpty,
        style: AppTextStyles.body.copyWith(color: colors.textMuted),
      ),
    );
  }

  Widget _buildRow(ThemeColors colors, McpTokenInfo token) {
    final busy = _revoking.contains(token.id);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(LucideIcons.keyRound, size: 18),
      title: Text(
        token.name,
        style: AppTextStyles.body.copyWith(color: colors.textPrimary),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            token.tokenPrefix,
            style: AppTextStyles.code.copyWith(fontSize: 11),
          ),
          Text(
            '${_l10n.mcpTokensCreatedAt(_shortDate(token.createdAt))}'
            ' · '
            '${_l10n.mcpTokensLastUsed(token.lastUsedAt == null ? _l10n.mcpTokensNeverUsed : _shortDate(token.lastUsedAt!))}',
            style: AppTextStyles.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
      trailing: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: _l10n.mcpTokensRevoke,
              icon: Icon(LucideIcons.trash2, size: 18, color: colors.error),
              onPressed: () => _revoke(token),
            ),
    );
  }

  /// RFC3339 → `YYYY-MM-DD HH:MM`（U17：转本地时区，此前显示 UTC 值）。
  String _shortDate(String iso) => formatRfc3339Local(iso);

  /// MCP 端点 = server 主端口 + `/mcp`（与 server mcp/src/lib.rs 的
  /// MCP_ENDPOINT 契约一致）。取不到连接 URL 时退化为裸路径提示。
  String get _mcpEndpoint {
    final base = ServerConnection().serverUrl;
    return (base == null || base.isEmpty) ? '/mcp' : '$base/mcp';
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final created = await _api.create(name: _nameController.text);
      if (mounted) setState(() => _created = created);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _revoke(McpTokenInfo token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.mcpTokensRevokeTitle),
        content: Text(_l10n.mcpTokensRevokeBody(token.name, token.tokenPrefix)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.mcpTokensRevoke),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _revoking.add(token.id));
    try {
      await _api.revoke(token.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _revoking.remove(token.id));
    }
  }
}
