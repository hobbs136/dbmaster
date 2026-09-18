// 全功能 Redis GUI — 阶段2: HyperLogLog 编辑器(只读)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class HyperLogLogEditorWidget extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;

  const HyperLogLogEditorWidget({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
  });

  @override
  State<HyperLogLogEditorWidget> createState() =>
      _HyperLogLogEditorWidgetState();
}

class _HyperLogLogEditorWidgetState extends State<HyperLogLogEditorWidget> {
  bool _isLoading = true;
  int? _count;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHyperLogLogInfo();
  }

  Future<void> _loadHyperLogLogInfo() async {
    setState(() => _isLoading = true);

    try {
      // 使用 PFCOUNT 获取基数估计值
      final result = await widget.provider.executeQuery(
        'PFCOUNT ${widget.keyName}',
        connectionId: widget.connectionId,
        database: widget.databaseName,
      );

      if (result.isNotEmpty && result.first.isNotEmpty) {
        _count = int.tryParse(result.first.values.first.toString());
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load HyperLogLog info: $e';
      });
    } finally {
      setState(() => _isLoading = false);
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

    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                LucideIcons.chartColumn,
                color: context.themeColors.accentPurple,
                size: 24,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'HyperLogLog Overview',
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: AppDesignSystem.fontSizeLg,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space4),

          // Count card
          _buildInfoCard(
            context: context,
            title: 'Cardinality Estimate',
            value: _count?.toString() ?? '0',
            icon: LucideIcons.hash,
            iconColor: context.themeColors.accentPurple,
            description:
                'HyperLogLog provides an approximate count of unique elements',
          ),

          const SizedBox(height: AppDesignSystem.space3),

          // Info section
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.accentPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.accentPurple.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.info,
                      size: 16,
                      color: context.themeColors.accentPurple,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      'About HyperLogLog',
                      style: TextStyle(
                        color: context.themeColors.accentPurple,
                        fontSize: AppDesignSystem.fontSizeSm,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space2),
                Text(
                  'HyperLogLog is a probabilistic data structure used to count unique values with minimal memory (12kb + bytes per element).',
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: AppDesignSystem.fontSizeSm,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                Text(
                  'Accuracy: Standard error of ~0.81%',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDesignSystem.space3),

          // Operations info
          Text(
            'Available Operations',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          _buildOperationItem(
            context: context,
            command: 'PFADD',
            description: 'Add elements to the HyperLogLog',
          ),
          _buildOperationItem(
            context: context,
            command: 'PFCOUNT',
            description: 'Get the cardinality estimate',
          ),
          _buildOperationItem(
            context: context,
            command: 'PFMERGE',
            description: 'Merge multiple HyperLogLogs',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Icon(icon, color: iconColor, size: 32),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeXl,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationItem({
    required BuildContext context,
    required String command,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.accentBlue.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              command,
              style: TextStyle(
                color: context.themeColors.accentBlue,
                fontSize: AppDesignSystem.fontSizeXs,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: AppDesignSystem.fontSizeSm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
