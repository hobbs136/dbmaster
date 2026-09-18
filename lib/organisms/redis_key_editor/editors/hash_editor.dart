// 全功能 Redis GUI — 阶段2: Hash 类型编辑器
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class HashEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const HashEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<HashEditor> createState() => _HashEditorState();
}

class _HashEditorState extends State<HashEditor> {
  bool _isLoading = true;
  List<MapEntry<String, String>> _fields = [];
  String? _errorMessage;
  final TextEditingController _newFieldController = TextEditingController();
  final TextEditingController _newValueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHashData();
  }

  @override
  void dispose() {
    _newFieldController.dispose();
    _newValueController.dispose();
    super.dispose();
  }

  Future<void> _loadHashData() async {
    setState(() => _isLoading = true);

    try {
      // 使用 HGETALL 获取所有字段
      final result = await widget.provider.executeQuery(
        'HGETALL ${widget.keyName}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      // 解析键值对
      // RedisResultFormatter 对 HGETALL 返回单行 Map{field: value},
      // 需遍历该 Map 的 entries;空结果/fallback 行('result')跳过。
      final List<MapEntry<String, String>> fields = [];
      for (final row in result) {
        for (final entry in row.entries) {
          if (entry.key == 'result' || entry.key == 'index') continue;
          fields.add(MapEntry(entry.key, entry.value?.toString() ?? ''));
        }
      }

      setState(() {
        _fields = fields;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load hash data: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addField() async {
    if (_newFieldController.text.isEmpty) return;

    try {
      await widget.provider.executeQuery(
        'HSET ${widget.keyName} ${_newFieldController.text} ${_newValueController.text}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      _newFieldController.clear();
      _newValueController.clear();
      await _loadHashData();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add field: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _deleteField(String field) async {
    try {
      await widget.provider.executeQuery(
        'HDEL ${widget.keyName} $field',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      await _loadHashData();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete field: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
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
              _errorMessage!,
              style: TextStyle(color: context.themeColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Fields table
        Expanded(
          child: _fields.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.rows3,
                        size: 48,
                        color: context.themeColors.textMuted,
                      ),
                      const SizedBox(height: AppDesignSystem.space3),
                      Text(
                        'No fields in this hash',
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _fields.length,
                  itemBuilder: (context, index) {
                    final entry = _fields[index];
                    return _buildFieldRow(entry.key, entry.value);
                  },
                ),
        ),

        // Add field section
        Container(
          padding: const EdgeInsets.all(AppDesignSystem.space4),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newFieldController,
                  style: TextStyle(color: context.themeColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Field',
                    labelStyle: TextStyle(color: context.themeColors.textMuted),
                    hintText: 'Enter field name',
                    hintStyle: TextStyle(color: context.themeColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    filled: true,
                    fillColor: context.themeColors.bgTertiary,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: TextField(
                  controller: _newValueController,
                  style: TextStyle(color: context.themeColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Value',
                    labelStyle: TextStyle(color: context.themeColors.textMuted),
                    hintText: 'Enter value',
                    hintStyle: TextStyle(color: context.themeColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    filled: true,
                    fillColor: context.themeColors.bgTertiary,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              ElevatedButton.icon(
                onPressed: _addField,
                icon: const Icon(LucideIcons.plus),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldRow(String field, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Field',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  field,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Value',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          IconButton(
            onPressed: () => _deleteField(field),
            icon: Icon(
              LucideIcons.trash2,
              color: context.themeColors.accentRed,
            ),
            tooltip: 'Delete field',
          ),
        ],
      ),
    );
  }
}
