import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// CardView - 卡片视图展示查询结果
/// 以卡片网格形式展示每一行数据
class CardView extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const CardView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (data.isEmpty) {
      return _buildEmptyState(context, l10n);
    }

    final columns = data.first.keys.toList();
    final mainColumns = columns.take(10).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = (constraints.maxWidth / 300).floor().clamp(
            1,
            4,
          );

          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 1.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.length,
            itemBuilder: (context, index) {
              return DataCard(
                row: data[index],
                mainColumns: mainColumns,
                allColumns: columns,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.rows2,
            size: 48,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.resultsNoDataTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.resultsNoDataCardMessage,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// DataCard - 单个数据卡片
class DataCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<String> mainColumns;
  final List<String> allColumns;

  const DataCard({
    super.key,
    required this.row,
    required this.mainColumns,
    required this.allColumns,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col in mainColumns)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppDesignSystem.space0_5,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        '$col:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row[col]?.toString() ?? 'NULL',
                        style: TextStyle(
                          fontSize: 12,
                          color: row[col] == null
                              ? context.themeColors.textMuted
                              : context.themeColors.textPrimary,
                          fontStyle: row[col] == null ? FontStyle.italic : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
