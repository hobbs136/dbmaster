// 全功能 Redis GUI — 阶段2: List 类型编辑器
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class ListEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const ListEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<ListEditor> {
  bool _isLoading = true;
  List<String> _elements = [];
  String? _errorMessage;
  final TextEditingController _newElementController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadListData();
  }

  @override
  void dispose() {
    _newElementController.dispose();
    super.dispose();
  }

  Future<void> _loadListData() async {
    setState(() => _isLoading = true);

    try {
      // 使用 LRANGE 获取所有元素
      final result = await widget.provider.executeQuery(
        'LRANGE ${widget.keyName} 0 -1',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      setState(() {
        // RedisResultFormatter 数组行结构为 {'index','value'},只取 'value' 列。
        _elements = result
            .where((row) => row.containsKey('value'))
            .map((row) => row['value'].toString())
            .toList();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load list data: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pushElement({bool left = true}) async {
    if (_newElementController.text.isEmpty) return;

    try {
      final command = left ? 'LPUSH' : 'RPUSH';
      await widget.provider.executeQuery(
        '$command ${widget.keyName} ${_newElementController.text}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      _newElementController.clear();
      await _loadListData();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to push element: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _popElement({bool left = true}) async {
    try {
      final command = left ? 'LPOP' : 'RPOP';
      await widget.provider.executeQuery(
        '$command ${widget.keyName}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      await _loadListData();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pop element: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _deleteElement(int index) async {
    try {
      // LREM 删除指定索引的元素(需要先获取值再删除)
      final element = _elements[index];
      await widget.provider.executeQuery(
        'LREM ${widget.keyName} 1 $element',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      await _loadListData();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete element: $e'),
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
        // Operations bar
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
          child: Row(
            children: [
              Text(
                'Length: ${_elements.length}',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _elements.isEmpty
                    ? null
                    : () => _popElement(left: true),
                icon: const Icon(LucideIcons.arrowLeft, size: 20),
                tooltip: 'LPOP (Left Pop)',
              ),
              IconButton(
                onPressed: _elements.isEmpty
                    ? null
                    : () => _popElement(left: false),
                icon: const Icon(LucideIcons.arrowRight, size: 20),
                tooltip: 'RPOP (Right Pop)',
              ),
            ],
          ),
        ),

        // Elements list
        Expanded(
          child: _elements.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.list,
                        size: 48,
                        color: context.themeColors.textMuted,
                      ),
                      const SizedBox(height: AppDesignSystem.space3),
                      Text(
                        'Empty list',
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: _elements.length,
                  onReorder: (oldIndex, newIndex) {
                    // TODO: 实现重新排序(需要先删除再插入)
                  },
                  itemBuilder: (context, index) {
                    return _buildElementRow(index, _elements[index]);
                  },
                ),
        ),

        // Add element section
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
                  controller: _newElementController,
                  style: TextStyle(color: context.themeColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Element',
                    labelStyle: TextStyle(color: context.themeColors.textMuted),
                    hintText: 'Enter element value',
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
                onPressed: () => _pushElement(left: true),
                icon: const Icon(LucideIcons.arrowLeft, size: 18),
                label: const Text('LPUSH'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignSystem.accentPrimary,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              ElevatedButton.icon(
                onPressed: () => _pushElement(left: false),
                icon: const Icon(LucideIcons.arrowRight, size: 18),
                label: const Text('RPUSH'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.accentGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildElementRow(int index, String element) {
    return Container(
      key: ValueKey(index),
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
          // Index
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: context.themeColors.accentBlue,
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),

          // Element value
          Expanded(
            child: Text(
              element,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeSm,
              ),
            ),
          ),

          // Delete button
          IconButton(
            onPressed: () => _deleteElement(index),
            icon: Icon(
              LucideIcons.trash2,
              color: context.themeColors.accentRed,
            ),
            tooltip: 'Delete element',
          ),
        ],
      ),
    );
  }
}
