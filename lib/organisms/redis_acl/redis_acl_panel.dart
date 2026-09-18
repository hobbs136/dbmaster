// 第四波 D4 — ACL 管理(Redis 6.0+;<6 友好提示)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';

class RedisAclPanel extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;

  const RedisAclPanel({
    super.key,
    required this.connectionId,
    required this.provider,
  });

  @override
  State<RedisAclPanel> createState() => _RedisAclPanelState();
}

class _RedisAclPanelState extends State<RedisAclPanel> {
  List<String> _users = const [];
  String? _selected;
  Map<String, String> _rules = const {};
  bool _loading = true;
  bool _unsupported = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() {
        _error = 'Redis adapter not available';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await adapter.aclList();
      // <6 时 ACL LIST 空 + WHOAMI 也空 → 标记不支持
      if (users.isEmpty) {
        final who = await adapter.aclWhoami();
        if (!mounted) return;
        if (who.isEmpty) setState(() => _unsupported = true);
      }
      if (!mounted) return;
      setState(() {
        _users = users;
        _selected = null;
        _rules = const {};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ACL LIST 行格式为 `user <name> on/off <rules...>`，提取用户名。
  String _userNameOf(String aclLine) {
    final parts = aclLine.split(' ');
    return parts.length >= 2 && parts.first == 'user' ? parts[1] : aclLine;
  }

  Future<void> _select(String name) async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      final rules = await adapter.aclGetuser(_userNameOf(name));
      if (!mounted) return;
      setState(() {
        _selected = name;
        _rules = rules;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _addUser() async {
    final result = await showDialog<_AclUserInput>(
      context: context,
      builder: (ctx) => const _AclSetUserDialog(),
    );
    if (result == null) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    final rules = result.rules
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final ok = await adapter.aclSetUser(result.name, rules);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'User ${result.name} saved' : 'ACL SETUSER failed'),
        backgroundColor: ok
            ? context.themeColors.accentGreen
            : context.themeColors.accentRed,
      ),
    );
    if (ok) _load();
  }

  Future<void> _delUser(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          'Delete user $name?',
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.accentRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    final success = await adapter.aclDelUser(_userNameOf(name));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'User $name deleted' : 'Delete failed'),
        backgroundColor: success
            ? context.themeColors.accentGreen
            : context.themeColors.accentRed,
      ),
    );
    if (success) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 520,
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppDesignSystem.space2),
              child: Text(
                _error!,
                style: TextStyle(
                  color: context.themeColors.accentRed,
                  fontSize: AppDesignSystem.fontSizeXs,
                ),
              ),
            ),
          const SizedBox(height: AppDesignSystem.space3),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(LucideIcons.shieldCheck, color: AppDesignSystem.dbRedis, size: 24),
        const SizedBox(width: AppDesignSystem.space3),
        Expanded(
          child: Text(
            'ACL · Users (${_users.length})',
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: AppDesignSystem.fontSizeLg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _addUser,
          icon: const Icon(LucideIcons.userPlus, size: 18),
          label: const Text('Add User'),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          tooltip: 'Reload',
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_unsupported) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.ban,
              size: 48,
              color: context.themeColors.accentOrange,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              'ACL requires Redis 6.0+',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: AppDesignSystem.fontSizeLg,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              'This server does not support ACL commands.',
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: AppDesignSystem.fontSizeSm,
              ),
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 220, child: _buildUserList()),
        Container(width: 1, color: Theme.of(context).dividerColor),
        Expanded(child: _buildDetail()),
      ],
    );
  }

  Widget _buildUserList() {
    if (_users.isEmpty) {
      return Center(
        child: Text(
          'No users',
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, i) {
        final name = _users[i];
        final selected = _selected == name;
        return ListTile(
          dense: true,
          selected: selected,
          leading: Icon(
            LucideIcons.user,
            size: 18,
            color: selected
                ? context.themeColors.accentBlue
                : context.themeColors.textSecondary,
          ),
          title: Text(
            name,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _select(name),
        );
      },
    );
  }

  Widget _buildDetail() {
    if (_selected == null) {
      return Center(
        child: Text(
          'Select a user to view rules',
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selected!,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_selected != null && _userNameOf(_selected!) != 'default')
                TextButton.icon(
                  onPressed: () => _delUser(_selected!),
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: context.themeColors.accentRed,
                  ),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: context.themeColors.accentRed),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _rules.isEmpty
              ? Center(
                  child: Text(
                    'No rules data',
                    style: TextStyle(color: context.themeColors.textMuted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space3,
                  ),
                  children: _rules.entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppDesignSystem.space1,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${e.key}: ',
                                style: TextStyle(
                                  color: AppDesignSystem.accentPrimary,
                                  fontFamily: AppDesignSystem.monoFontFamily,

                                  fontFamilyFallback:
                                      AppDesignSystem.monoFontFamilyFallback,
                                  fontSize: AppDesignSystem.fontSizeXs,
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  e.value,
                                  style: TextStyle(
                                    color: context.themeColors.textPrimary,
                                    fontFamily: AppDesignSystem.monoFontFamily,

                                    fontFamilyFallback:
                                        AppDesignSystem.monoFontFamilyFallback,
                                    fontSize: AppDesignSystem.fontSizeXs,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _AclUserInput {
  final String name;
  final String rules;
  const _AclUserInput(this.name, this.rules);
}

class _AclSetUserDialog extends StatefulWidget {
  const _AclSetUserDialog();
  @override
  State<_AclSetUserDialog> createState() => _AclSetUserDialogState();
}

class _AclSetUserDialogState extends State<_AclSetUserDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _rulesCtrl = TextEditingController(
    text: '>password ~* +@all',
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rulesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        'ACL SETUSER',
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: TextStyle(color: context.themeColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            TextField(
              controller: _rulesCtrl,
              maxLines: 3,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              decoration: const InputDecoration(
                labelText: 'Rules (space separated)',
                hintText: '>pass ~prefix:* +@all -@dangerous',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _AclUserInput(_nameCtrl.text.trim(), _rulesCtrl.text),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
