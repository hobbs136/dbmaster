// 第三波 C3 — Lua 脚本工作台(本地脚本 + EVALSHA 同步)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../models/redis_script.dart';
import '../../../services/redis_script_service.dart';
import '../editor/re_sql_editor.dart';
import '../editor/re_sql_editor_controller.dart';

class RedisLuaPanel extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;

  const RedisLuaPanel({
    super.key,
    required this.connectionId,
    required this.provider,
  });

  @override
  State<RedisLuaPanel> createState() => _RedisLuaPanelState();
}

class _RedisLuaPanelState extends State<RedisLuaPanel> {
  final RedisScriptService _scripts = RedisScriptService();
  final TextEditingController _nameCtrl = TextEditingController();
  final ReSqlEditorController _codeCtrl = ReSqlEditorController();
  final TextEditingController _keysCtrl = TextEditingController();
  final TextEditingController _argsCtrl = TextEditingController();

  List<RedisScript> _list = [];
  RedisScript? _selected;
  String _result = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _keysCtrl.dispose();
    _argsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    final list = await _scripts.getScripts(connectionId: widget.connectionId);
    if (!mounted) return;
    setState(() => _list = list);
  }

  void _select(RedisScript s) {
    setState(() {
      _selected = s;
      _nameCtrl.text = s.name;
      _codeCtrl.text = s.code;
      _result = '';
      _error = null;
    });
  }

  void _newScript() {
    setState(() {
      _selected = null;
      _nameCtrl.clear();
      _codeCtrl.clear();
      _keysCtrl.clear();
      _argsCtrl.clear();
      _result = '';
      _error = null;
    });
    _codeCtrl.requestFocus();
  }

  List<String> _parseList(String text) =>
      text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text;
    if (name.isEmpty || code.trim().isEmpty) {
      _snack('Name and code required', context.themeColors.accentOrange);
      return;
    }
    final now = DateTime.now();
    final script = RedisScript(
      id: _selected?.id ?? now.millisecondsSinceEpoch.toString(),
      name: name,
      code: code,
      isGlobal: false,
      connectionId: widget.connectionId,
      sha1: _selected?.sha1,
      createdAt: _selected?.createdAt ?? now,
      modifiedAt: now,
    );
    setState(() => _busy = true);
    final themeColors = context.themeColors;
    try {
      await _scripts.saveScript(script);
      _selected = script;
      if (!mounted) return;
      await _loadList();
      _snack('Saved', themeColors.accentGreen);
    } catch (e) {
      _snack('Save failed: $e', themeColors.accentRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncToServer() async {
    final code = _codeCtrl.text;
    if (code.trim().isEmpty) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    setState(() => _busy = true);
    try {
      // SCRIPT LOAD 拿 sha,写回本地 sha1(接通 B3)
      final sha = await adapter.scriptLoad(code);
      if (_selected != null) {
        final updated = _selected!.copyWith(
          sha1: sha,
          modifiedAt: DateTime.now(),
        );
        await _scripts.saveScript(updated);
        _selected = updated;
        await _loadList();
      }
      if (!mounted) return;
      final short = sha.length > 12 ? sha.substring(0, 12) : sha;
      _snack('Synced, SHA: $short...', context.themeColors.accentGreen);
    } catch (e) {
      _snack('Sync failed: $e', context.themeColors.accentRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    final code = _codeCtrl.text;
    if (code.trim().isEmpty) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    final keys = _parseList(_keysCtrl.text);
    final args = _parseList(_argsCtrl.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 传 sha 启用 EVALSHA(B3 接线),NOSCRIPT 自动 fallback
      final result = await adapter.evalLua(
        code,
        keys,
        args,
        sha: _selected?.sha1,
      );
      if (!mounted) return;
      setState(() => _result = result?.toString() ?? '(nil)');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_selected == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          'Delete script?',
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        content: Text(
          _selected!.name,
          style: TextStyle(color: context.themeColors.textSecondary),
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
    await _scripts.deleteScript(_selected!.id);
    _newScript();
    await _loadList();
  }

  Future<void> _flushServer() async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      final ok = await adapter.scriptFlush();
      if (!mounted) return;
      _snack(
        ok ? 'Server script cache flushed' : 'Flush failed',
        ok ? context.themeColors.accentGreen : context.themeColors.accentRed,
      );
    } catch (e) {
      _snack('Flush failed: $e', context.themeColors.accentRed);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 600,
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 220, child: _buildScriptList()),
                Container(width: 1, color: Theme.of(context).dividerColor),
                Expanded(child: _buildEditor()),
                Container(width: 1, color: Theme.of(context).dividerColor),
                SizedBox(width: 260, child: _buildExecPane()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.code,
            color: AppDesignSystem.accentPrimary,
            size: 24,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Text(
              'Lua Scripts',
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeLg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.list,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  'Scripts (${_list.length})',
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.plus, size: 18),
                tooltip: 'New script',
                onPressed: _newScript,
              ),
            ],
          ),
        ),
        Expanded(
          child: _list.isEmpty
              ? Center(
                  child: Text(
                    'No scripts',
                    style: TextStyle(color: context.themeColors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: _list.length,
                  itemBuilder: (context, i) {
                    final s = _list[i];
                    final selected = _selected?.id == s.id;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      title: Text(
                        s.name,
                        style: TextStyle(
                          color: context.themeColors.textPrimary,
                          fontSize: AppDesignSystem.fontSizeSm,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        s.sha1 != null ? 'synced' : 'local',
                        style: TextStyle(
                          color: s.sha1 != null
                              ? context.themeColors.accentGreen
                              : context.themeColors.textMuted,
                          fontSize: AppDesignSystem.fontSizeXs,
                        ),
                      ),
                      onTap: () => _select(s),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        // toolbar
        Container(
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: context.themeColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Script name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Wrap(
                spacing: AppDesignSystem.space1,
                runSpacing: AppDesignSystem.space1,
                children: [
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(LucideIcons.save, size: 16),
                    label: const Text('Save'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _syncToServer,
                    icon: const Icon(LucideIcons.cloudUpload, size: 16),
                    label: const Text('Sync'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: const Text('Delete'),
                  ),
                  TextButton.icon(
                    onPressed: _flushServer,
                    icon: const Icon(LucideIcons.sprayCan, size: 16),
                    label: const Text('Flush'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ReSqlEditor(
            controller: _codeCtrl,
            language: 'lua',
            hintText: 'return redis.call("GET", KEYS[1])',
          ),
        ),
      ],
    );
  }

  Widget _buildExecPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KEYS (comma separated)',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space1),
              TextField(
                controller: _keysCtrl,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'key1, key2',
                ),
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Text(
                'ARGV (comma separated)',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space1),
              TextField(
                controller: _argsCtrl,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'arg1, arg2',
                ),
              ),
              const SizedBox(height: AppDesignSystem.space2),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _run,
                  icon: const Icon(LucideIcons.play, size: 18),
                  label: const Text('Run (EVALSHA→EVAL)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.themeColors.accentBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: context.themeColors.accentRed,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                      fontSize: AppDesignSystem.fontSizeXs,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  child: SelectableText(
                    _result.isEmpty ? '(no result yet)' : _result,
                    style: TextStyle(
                      color: context.themeColors.textPrimary,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                      fontSize: AppDesignSystem.fontSizeXs,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
