// 全功能 Redis GUI — 阶段2: ZSet 类型编辑器
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class ZSetEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const ZSetEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<ZSetEditor> createState() => _ZSetEditorState();
}

class _ZSetEditorState extends State<ZSetEditor> {
  bool _isLoading = true;
  List<MapEntry<double, String>> _members = [];
  String? _errorMessage;
  final TextEditingController _newMemberController = TextEditingController();
  final TextEditingController _newScoreController = TextEditingController(
    text: '0',
  );

  @override
  void initState() {
    super.initState();
    _loadZSetData();
  }

  @override
  void dispose() {
    _newMemberController.dispose();
    _newScoreController.dispose();
    super.dispose();
  }

  Future<void> _loadZSetData() async {
    setState(() => _isLoading = true);

    try {
      // 使用 ZRANGE 获取所有成员(带分数)
      final result = await widget.provider.executeQuery(
        'ZRANGE ${widget.keyName} 0 -1 WITHSCORES',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      // 解析 member-score 对
      // 注意:RedisResultFormatter 对数组返回 {'index','value'} 两行结构,
      // 必须读 'value' 列,不能取 values.first(那是行号)。
      final List<MapEntry<double, String>> members = [];
      for (var i = 0; i < result.length; i += 2) {
        if (i + 1 < result.length &&
            result[i].containsKey('value') &&
            result[i + 1].containsKey('value')) {
          final member = result[i]['value'].toString();
          final score =
              double.tryParse(result[i + 1]['value'].toString()) ?? 0.0;
          members.add(MapEntry(score, member));
        }
      }

      setState(() {
        _members = members;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load zset data: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMember() async {
    if (_newMemberController.text.isEmpty) return;

    try {
      await widget.provider.executeQuery(
        'ZADD ${widget.keyName} ${_newScoreController.text} ${_newMemberController.text}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      _newMemberController.clear();
      _newScoreController.text = '0';
      await _loadZSetData();
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
        'ZREM ${widget.keyName} $member',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      await _loadZSetData();
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
        // Header
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
                LucideIcons.arrowUpDown,
                size: 20,
                color: context.themeColors.accentOrange,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'Members: ${_members.length}',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
              ),
            ],
          ),
        ),

        // Members list (sorted by score)
        Expanded(
          child: _members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.arrowUpDown,
                        size: 48,
                        color: context.themeColors.textMuted,
                      ),
                      const SizedBox(height: AppDesignSystem.space3),
                      Text(
                        'Empty sorted set',
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
                    final entry = _members[index];
                    return _buildMemberRow(entry.key, entry.value, index);
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
              // Score input
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _newScoreController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.themeColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Score',
                    labelStyle: TextStyle(color: context.themeColors.textMuted),
                    hintText: '0',
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

              // Member input
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

              // Add button
              ElevatedButton.icon(
                onPressed: _addMember,
                icon: const Icon(LucideIcons.plus),
                label: const Text('ZADD'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMemberRow(double score, String member, int index) {
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
          // Rank
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.accentOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: context.themeColors.accentOrange,
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),

          // Score
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: AppDesignSystem.accentPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              score.toStringAsFixed(2),
              style: TextStyle(
                color: AppDesignSystem.accentPrimary,
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.bold,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
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
