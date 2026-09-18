import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../models/code_snippet.dart' show SnippetDbFamily;

/// T012: 代码片段快捷命令
/// 输入 / 触发，快速插入常用 SQL 模板
class SnippetCommand {
  final String command;
  final String description;
  final String code;
  final IconData icon;
  final SnippetDbFamily family; // 020-mongo US3 — 按 DB 族过滤

  const SnippetCommand({
    required this.command,
    required this.description,
    required this.code,
    required this.icon,
    this.family = SnippetDbFamily.sql,
  });
}

class SnippetCommands {
  static const List<SnippetCommand> commands = [
    SnippetCommand(
      command: 'sel',
      description: 'SELECT statement',
      code: 'SELECT * FROM table_name;',
      icon: LucideIcons.textSelect,
    ),
    SnippetCommand(
      command: 'selw',
      description: 'SELECT with WHERE',
      code: 'SELECT * FROM table_name\nWHERE condition;',
      icon: LucideIcons.funnel,
    ),
    SnippetCommand(
      command: 'ins',
      description: 'INSERT statement',
      code:
          'INSERT INTO table_name (column1, column2)\nVALUES (value1, value2);',
      icon: LucideIcons.circlePlus,
    ),
    SnippetCommand(
      command: 'upd',
      description: 'UPDATE statement',
      code: 'UPDATE table_name\nSET column1 = value1\nWHERE condition;',
      icon: LucideIcons.pencil,
    ),
    SnippetCommand(
      command: 'del',
      description: 'DELETE statement',
      code: 'DELETE FROM table_name\nWHERE condition;',
      icon: LucideIcons.trash2,
    ),
    SnippetCommand(
      command: 'join',
      description: 'JOIN clause',
      code: 'SELECT * FROM table1\nJOIN table2 ON table1.id = table2.id;',
      icon: LucideIcons.gitMerge,
    ),
    SnippetCommand(
      command: 'ct',
      description: 'CREATE TABLE',
      code:
          'CREATE TABLE table_name (\n  id INT PRIMARY KEY,\n  name VARCHAR(255)\n);',
      icon: LucideIcons.table2,
    ),
    SnippetCommand(
      command: 'idx',
      description: 'CREATE INDEX',
      code: 'CREATE INDEX idx_name ON table_name(column_name);',
      icon: LucideIcons.arrowUpDown,
    ),
    SnippetCommand(
      command: 'case',
      description: 'CASE expression',
      code:
          'CASE\n  WHEN condition1 THEN result1\n  WHEN condition2 THEN result2\n  ELSE default_result\nEND',
      icon: LucideIcons.split,
    ),
    SnippetCommand(
      command: 'func',
      description: 'Aggregate function',
      code:
          'SELECT COUNT(*), MAX(column), MIN(column), AVG(column), SUM(column)\nFROM table_name;',
      icon: LucideIcons.functionSquare,
    ),
    // 020-mongo US3 — Mongo 片段命令（family: mongodb）
    SnippetCommand(
      command: 'mfind',
      description: 'Mongo find',
      code: r'db.collection_name.find({});',
      icon: LucideIcons.search,
      family: SnippetDbFamily.mongodb,
    ),
    SnippetCommand(
      command: 'mfindone',
      description: 'Mongo findOne',
      code: r'db.collection_name.findOne({});',
      icon: LucideIcons.search,
      family: SnippetDbFamily.mongodb,
    ),
    SnippetCommand(
      command: 'mins',
      description: 'Mongo insertOne',
      code: r'db.collection_name.insertOne({ field: value });',
      icon: LucideIcons.circlePlus,
      family: SnippetDbFamily.mongodb,
    ),
    SnippetCommand(
      command: 'mupd',
      description: 'Mongo updateOne with \$set',
      code:
          r'db.collection_name.updateOne({ filter }, { $set: { field: value } });',
      icon: LucideIcons.pencil,
      family: SnippetDbFamily.mongodb,
    ),
    SnippetCommand(
      command: 'mdel',
      description: 'Mongo deleteOne',
      code: r'db.collection_name.deleteOne({ filter });',
      icon: LucideIcons.trash2,
      family: SnippetDbFamily.mongodb,
    ),
    SnippetCommand(
      command: 'magg',
      description: 'Mongo aggregate (\$match + \$group)',
      code:
          r'db.collection_name.aggregate([{$match: { }}, {$group: {_id: null, count: {$sum: 1}}}]);',
      icon: LucideIcons.functionSquare,
      family: SnippetDbFamily.mongodb,
    ),
    SnippetCommand(
      command: 'mcount',
      description: 'Mongo countDocuments',
      code: r'db.collection_name.countDocuments({});',
      icon: LucideIcons.calculator,
      family: SnippetDbFamily.mongodb,
    ),
    SnippetCommand(
      command: 'midx',
      description: 'Mongo createIndex',
      code: r'db.collection_name.createIndex({ field: 1 });',
      icon: LucideIcons.arrowUpDown,
      family: SnippetDbFamily.mongodb,
    ),
  ];
}

/// SnippetCommandsOverlay - 代码片段命令浮层
class SnippetCommandsOverlay extends StatelessWidget {
  final String filter;
  final void Function(SnippetCommand) onSelected;
  final VoidCallback onDismiss;
  final Offset cursorPosition;
  final SnippetDbFamily? currentFamily; // 020-mongo US3 — null=显示全部
  final int
  selectedIndex; // 021-mongo-snippet-overlay-wiring — keyboard selection

  const SnippetCommandsOverlay({
    super.key,
    required this.filter,
    required this.onSelected,
    required this.onDismiss,
    required this.cursorPosition,
    this.currentFamily,
    this.selectedIndex = 0,
  });

  List<SnippetCommand> get _filteredCommands {
    // 020-mongo US3 — 按当前连接 DB 族过滤（all 或未指定时显示全部）
    final byFamily = SnippetCommands.commands.where(
      (c) =>
          c.family == SnippetDbFamily.all ||
          currentFamily == null ||
          c.family == currentFamily,
    );
    if (filter.isEmpty) return byFamily.toList();
    return byFamily
        .where(
          (c) =>
              c.command.toLowerCase().contains(filter.toLowerCase()) ||
              c.description.toLowerCase().contains(filter.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final commands = _filteredCommands;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            left: cursorPosition.dx,
            top: cursorPosition.dy + 20,
            child: Material(
              color: context.themeColors.bgSecondary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              elevation: 8,
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 280,
                  maxWidth: 320,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: context.themeColors.borderColor),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space3,
                      ),
                      decoration: BoxDecoration(
                        color: context.themeColors.bgTertiary,
                        border: Border(
                          bottom: BorderSide(
                            color: context.themeColors.borderLight,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.zap,
                            size: 14,
                            color: context.themeColors.accentBlue,
                          ),
                          const SizedBox(width: AppDesignSystem.space2),
                          Text(
                            'Snippets',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.themeColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${commands.length} items',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 命令列表
                    if (commands.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No matching snippets',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.themeColors.textMuted,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: commands.length,
                          itemBuilder: (context, index) {
                            final cmd = commands[index];
                            final isSelected = index == selectedIndex;
                            return _buildCommandItem(context, cmd, isSelected);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandItem(
    BuildContext context,
    SnippetCommand cmd,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () => onSelected(cmd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? context.themeColors.accentBlue.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: context.themeColors.borderLight),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: context.themeColors.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Icon(
                cmd.icon,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '/${cmd.command}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? context.themeColors.accentBlue
                          : context.themeColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space0_5),
                  Text(
                    cmd.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                LucideIcons.arrowLeft,
                size: 14,
                color: context.themeColors.accentBlue,
              ),
          ],
        ),
      ),
    );
  }
}
