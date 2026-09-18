// C12b · Redis 键值渲染器——原型 result-panel-redis「键值视图」。
//
// 数据现实：Redis 查询结果来自命令输出（RedisResultFormatter 行集），不含
// 键类型 / TTL / 编码元数据——那套元信息在键浏览器（RedisKeyEditorDialog）
// 链路。v1 按行形状自适应成卡：
// - 单行多标量字段（HGETALL 平铺 {field: value}）→ Hash 卡（Field/Value 表）
// - 单行单字段（GET → {result: ...} 等）→ String 卡（mono 值块 + 长度脚注）
// - 多行（SCAN 游标 / LRANGE 等）→ 每行一张通用字段卡
// TTL/编码留待结果元数据通道扩展（renderContext 按需扩展位）后补。
// JSON 树 / 表格视图仍可切换（jsonTree / table 同声明 redisKeyValue）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/result_renderer_plugin.dart';
import '../../../theme/app_theme.dart';

class KeyValueResultRenderer implements ResultRendererPlugin {
  const KeyValueResultRenderer();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'key-value-result-renderer',
        icon: LucideIcons.braces,
        displayName: (l10n) => l10n.viewModeKeyValue,
      );

  @override
  String get viewModeId => 'keyValue';

  @override
  Set<ResultDataShape> get supportedShapes => const {ResultDataShape.redisKeyValue};

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) {
    return _KeyValueCardList(
      rows: renderContext.rows,
      keyHint: _keyFromCommand(renderContext.result.statement.sql),
    );
  }

  /// 从命令文本提取键名（`GET user:1001` → user:1001，HGETALL/STRLEN 同），
  /// 作为单卡标题（原型卡头即 Key 名）。解析失败返回 null → 退 #index。
  static String? _keyFromCommand(String sql) {
    final tokens = sql.trim().split(RegExp(r'\s+'));
    if (tokens.length < 2) return null;
    var key = tokens[1];
    if (key.length >= 2 &&
        ((key.startsWith("'") && key.endsWith("'")) ||
            (key.startsWith('"') && key.endsWith('"')))) {
      key = key.substring(1, key.length - 1);
    }
    return key.isEmpty ? null : key;
  }
}

class _KeyValueCardList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  /// 命令中的键名（单卡时作标题；多卡各行为独立项，标题退序号）。
  final String? keyHint;

  const _KeyValueCardList({required this.rows, this.keyHint});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final title = rows.length == 1
            ? (keyHint ?? '#$index')
            : '#$index';
        return Padding(
          padding: const EdgeInsets.only(bottom: AppDesignSystem.space4),
          child: row.length > 1
              ? _HashCard(row: row, title: title)
              : _StringCard(
                  title: title,
                  fieldName: row.keys.first,
                  value: row.values.first,
                ),
        );
      },
    );
  }
}

/// Hash 卡：Field/Value 双列表（原型 user:1001:profile 形态）。
class _HashCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final String title;

  const _HashCard({required this.row, required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    return _CardShell(
      title: title,
      typeBadgeColor: colors.warning,
      typeBadgeLabel: 'Hash',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Table(
          border: TableBorder.all(color: colors.borderLight),
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(2),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: colors.bgSecondary),
              children: [
                _headerCell(context, l10n.keyValueField),
                _headerCell(context, l10n.keyValueValue),
              ],
            ),
            for (final entry in row.entries)
              TableRow(
                children: [
                  _bodyCell(context, entry.key),
                  _bodyCell(context, '${entry.value}'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(BuildContext context, String text) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  Widget _bodyCell(BuildContext context, String text) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

/// String 卡：mono 值块 + 长度脚注（原型 user:1001 形态）。
class _StringCard extends StatelessWidget {
  final String title;
  final String fieldName;
  final dynamic value;

  const _StringCard({
    required this.title,
    required this.fieldName,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final text = value?.toString() ?? '(nil)';
    return _CardShell(
      title: title,
      typeBadgeColor: colors.success,
      typeBadgeLabel: 'String',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SelectableText(
              text,
              style: TextStyle(
                fontSize: 12,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.keyValueFieldLabel(fieldName),
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.keyValueLengthLabel(text.length),
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// 卡壳：标题 + 类型徽章（String=success / Hash=warning，原型色映射）。
class _CardShell extends StatelessWidget {
  final String title;
  final Color typeBadgeColor;
  final String typeBadgeLabel;
  final Widget child;

  const _CardShell({
    required this.title,
    required this.typeBadgeColor,
    required this.typeBadgeLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderLight)),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: typeBadgeColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeBadgeLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          child,
        ],
      ),
    );
  }
}
