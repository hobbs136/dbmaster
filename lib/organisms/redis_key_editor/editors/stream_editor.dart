// 第二波 A4 — Stream 编辑器(写操作 + 消费者组管理)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class StreamEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const StreamEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<StreamEditor> createState() => _StreamEditorState();
}

class _StreamEditorState extends State<StreamEditor> {
  bool _isLoading = true;
  List<Map<String, String>> _entries = [];
  Map<String, String> _streamInfo = {};
  List<Map<String, String>> _groups = [];
  String? _error;
  bool _busy = false;

  final TextEditingController _fieldCtrl = TextEditingController();
  final TextEditingController _valueCtrl = TextEditingController();
  final TextEditingController _trimCtrl = TextEditingController(text: '1000');
  final TextEditingController _groupCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _fieldCtrl.dispose();
    _valueCtrl.dispose();
    _trimCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() {
        _error = 'Redis adapter not available';
        _isLoading = false;
      });
      return;
    }
    try {
      final entries = await adapter.getStreamEntries(widget.keyName);
      Map<String, String> info = {};
      List<Map<String, String>> groups = [];
      try {
        info = await adapter.xinfoStream(widget.keyName);
      } catch (_) {}
      try {
        groups = await adapter.xinfoGroups(widget.keyName);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _streamInfo = info;
        _groups = groups;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load stream: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addEntry() async {
    final field = _fieldCtrl.text.trim();
    final value = _valueCtrl.text;
    if (field.isEmpty) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    setState(() => _busy = true);
    try {
      await adapter.streamAdd(widget.keyName, {field: value});
      if (!mounted) return;
      _fieldCtrl.clear();
      _valueCtrl.clear();
      widget.onChanged?.call();
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('XADD failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEntry(String id) async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      await adapter.streamDelete(widget.keyName, [id]);
      if (!mounted) return;
      widget.onChanged?.call();
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('XDEL failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    }
  }

  Future<void> _trim() async {
    final maxLen = int.tryParse(_trimCtrl.text.trim());
    if (maxLen == null || maxLen < 0) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      final removed = await adapter.streamTrim(widget.keyName, maxLen);
      if (!mounted) return;
      widget.onChanged?.call();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trimmed (~$removed removed to $maxLen)')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('XTRIM failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    }
  }

  Future<void> _createGroup() async {
    final name = _groupCtrl.text.trim();
    if (name.isEmpty) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      final ok = await adapter.streamGroupCreate(widget.keyName, name);
      if (!mounted) return;
      if (ok) {
        _groupCtrl.clear();
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('XGROUP CREATE failed (group may exist)'),
            backgroundColor: context.themeColors.accentOrange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create group failed: $e')));
    }
  }

  Future<void> _destroyGroup(String name) async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      await adapter.streamGroupDestroy(widget.keyName, name);
      if (!mounted) return;
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Destroy group failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: context.themeColors.accentRed,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              _error!,
              style: TextStyle(color: context.themeColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildInfoBar(context),
        _buildAddForm(context),
        _buildToolsRow(context),
        if (_groups.isNotEmpty) _buildGroupsSection(context),
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    'Empty stream',
                    style: TextStyle(color: context.themeColors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, i) =>
                      _buildEntryRow(context, _entries[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildInfoBar(BuildContext context) {
    final length = _streamInfo['length'] ?? '${_entries.length}';
    final groups = _streamInfo['groups'] ?? '${_groups.length}';
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.waves,
            size: 18,
            color: context.themeColors.accentCyan,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'Length: $length',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            'Groups: $groups',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Reload',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildAddForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _fieldCtrl,
              decoration: const InputDecoration(
                labelText: 'Field',
                isDense: true,
              ),
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _valueCtrl,
              decoration: const InputDecoration(
                labelText: 'Value',
                isDense: true,
              ),
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: _busy ? null : _addEntry,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('XADD'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.scissors,
            size: 16,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'XTRIM MAXLEN',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeXs,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _trimCtrl,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '1000',
              ),
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          TextButton.icon(
            onPressed: _trim,
            icon: const Icon(LucideIcons.scissors, size: 16),
            label: const Text('Trim'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.accentPurple.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.users,
                size: 16,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'Consumer Groups (${_groups.length})',
                style: TextStyle(
                  color: context.themeColors.accentPurple,
                  fontSize: AppDesignSystem.fontSizeSm,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Wrap(
            spacing: AppDesignSystem.space2,
            runSpacing: AppDesignSystem.space1,
            children: _groups.map((g) {
              final name = g['name'] ?? '?';
              final pending = g['pending'] ?? '0';
              return Chip(
                avatar: const Icon(LucideIcons.users, size: 16),
                label: Text('$name (pending:$pending)'),
                onDeleted: () => _destroyGroup(name),
                deleteIconColor: context.themeColors.accentRed,
              );
            }).toList(),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _groupCtrl,
                  decoration: const InputDecoration(
                    labelText: 'New group name',
                    isDense: true,
                  ),
                  style: TextStyle(color: context.themeColors.textPrimary),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              ElevatedButton.icon(
                onPressed: _createGroup,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('XGROUP CREATE'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntryRow(BuildContext context, Map<String, String> entry) {
    final id = entry['id'] ?? '?';
    final fieldsStr = entry.entries
        .where((e) => e.key != 'id')
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.themeColors.borderSubtle,
          ),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.accentCyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                id.length > 16 ? '${id.substring(0, 16)}…' : id,
                style: TextStyle(
                  color: context.themeColors.accentCyan,
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            flex: 3,
            child: Text(
              fieldsStr.isEmpty ? '(no fields)' : fieldsStr,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeXs,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              LucideIcons.trash2,
              size: 16,
              color: context.themeColors.accentRed,
            ),
            tooltip: 'XDEL',
            onPressed: () => _deleteEntry(id),
          ),
        ],
      ),
    );
  }
}
