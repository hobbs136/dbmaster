import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../object_tabs/table_properties_content.dart';

/// 表属性 dialog 薄壳（T16 J4：body 已提取为 [TablePropertiesContent]，
/// 本类仅为保留既有 dialog 公开构造面的兼容壳；主入口（树右键
/// Properties/查看 DDL）已迁主标签栏对象 tab）。
class TablePropertiesDialog extends StatelessWidget {
  final String tableName;
  final String dbName;
  final String? connectionId;

  /// 初始选中的 tab 索引（U17 表右键「查看 DDL」直达 CREATE Statement）。
  final int initialTabIndex;

  const TablePropertiesDialog({
    super.key,
    required this.tableName,
    required this.dbName,
    this.connectionId,
    this.initialTabIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.table2, color: context.themeColors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              tableName,
              style: TextStyle(color: context.themeColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: TablePropertiesContent(
          tableName: tableName,
          dbName: dbName,
          connectionId: connectionId,
          initialTabIndex: initialTabIndex,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
