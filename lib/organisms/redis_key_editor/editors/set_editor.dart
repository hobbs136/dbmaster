// 全功能 Redis GUI — 阶段2: Set 类型编辑器
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class SetEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const SetEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<SetEditor> createState() => _SetEditorState();
}

class _SetEditorState extends State<SetEditor> {
  bool _isLoading = true;
  Set<String> _members = {};
  String? _errorMessage;
  final TextEditingController _newMemberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSetData();
  }

  @override
  void dispose() {
    _newMemberController.dispose();
    super.dispose();
  }

  Future<void> _loadSetData() async {
    setState(() => _isLoading = true);

    try {
      // 使用 SMEMBERS 获取所有成员
      final result = await widget.provider.executeQuery(
        'SMEMBERS ${widget.keyName}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      setState(() {
        // RedisResultFormatter 数组行结构为 {'index','value'},只取 'value' 列。
        _members = result
            .where((row) => row.containsKey('value'))
            .map((row) => row['value'].toString())
            .toSet();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load set data: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMember() async {
    if (_newMemberController.text.isEmpty) return;

    try {
      await widget.provider.executeQuery(
        'SADD ${widget.keyName} ${_newMemberController.text}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      _newMemberController.clear();
      await _loadSetData();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add member: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _removeMember(String member) async {
    try {
      await widget.provider.executeQuery(
        'SREM ${widget.keyName} $member',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      await _loadSetData();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove member: $e'),
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
        // Info bar
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
              Icon(
                LucideIcons.users,
                size: 20,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'Cardinality: ${_members.length}',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
              ),
            ],
          ),
        ),

        // Members list
        Expanded(
          child: _members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.users,
                        size: 48,
                        color: context.themeColors.textMuted,
                      ),
                      const SizedBox(height: AppDesignSystem.space3),
                      Text(
                        'Empty set',
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members.elementAt(index);
                    return _buildMemberRow(member, index);
                  },
                ),
        ),

        // Add member section
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
                  controller: _newMemberController,
                  style: TextStyle(color: context.themeColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Member',
                    labelStyle: TextStyle(color: context.themeColors.textMuted),
                    hintText: 'Enter member value',
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
                onPressed: _addMember,
                icon: const Icon(LucideIcons.plus),
                label: const Text('SADD'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMemberRow(String member, int index) {
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
          // Index
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.accentPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: context.themeColors.accentPurple,
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),

          // Member value
          Expanded(
            child: Text(
              member,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeSm,
              ),
            ),
          ),

          // Delete button
          IconButton(
            onPressed: () => _removeMember(member),
            icon: Icon(
              LucideIcons.trash2,
              color: context.themeColors.accentRed,
            ),
            tooltip: 'Remove member',
          ),
        ],
      ),
    );
  }
}
