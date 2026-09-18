// 全功能 Redis GUI — 阶段2: 键值编辑器对话框(+ A0 类型识别层)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../redis_key_editor/editors/string_editor.dart';
import '../redis_key_editor/editors/hash_editor.dart';
import '../redis_key_editor/editors/list_editor.dart';
import '../redis_key_editor/editors/set_editor.dart';
import '../redis_key_editor/editors/zset_editor.dart';
import '../redis_key_editor/editors/stream_editor.dart';
import '../redis_key_editor/editors/json_editor.dart';
import '../redis_key_editor/editors/hyperloglog_editor_widget.dart';
import '../redis_key_editor/editors/bitmap_editor.dart';
import '../redis_key_editor/editors/bitfield_editor.dart';
import '../redis_key_editor/editors/geo_editor.dart';

class RedisKeyEditorDialog extends StatefulWidget {
  final String keyName;
  final String type;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;

  const RedisKeyEditorDialog({
    super.key,
    required this.keyName,
    required this.type,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
  });

  @override
  State<RedisKeyEditorDialog> createState() => _RedisKeyEditorDialogState();
}

class _RedisKeyEditorDialogState extends State<RedisKeyEditorDialog> {
  bool _isLoading = false;
  // A0 — 有效视图类型。Redis TYPE 只返回 string/zset 等,
  // bitmap/bitfield(底层 string)、geo(底层 zset)需用户手动选择查看方式。
  late String _effectiveType;

  @override
  void initState() {
    super.initState();
    _effectiveType = widget.type;
    _loadKeyData();
  }

  /// 当前 raw 类型可切换的视图选项。
  List<String> _viewOptions() {
    switch (widget.type.toLowerCase()) {
      case 'string':
        return const ['string', 'bitmap', 'bitfield'];
      case 'zset':
        return const ['zset', 'geo'];
      default:
        return [widget.type];
    }
  }

  void _switchView(String type) {
    if (_effectiveType.toLowerCase() == type) return;
    setState(() {
      _effectiveType = type;
    });
  }

  Future<void> _loadKeyData() async {
    setState(() => _isLoading = true);

    try {
      // 各 editor 自管数据加载(initState 内 GET/HGETALL 等)。
      // dialog 级仅做 UX 缓冲,让 editor 有时间挂载并显示自己的 loading 态。
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 600,
          maxWidth: 900,
          minHeight: 400,
          maxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(context),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppDesignSystem.space3),
                          Text(
                            'Loading key data...',
                            style: TextStyle(
                              color: context.themeColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildEditor(context),
            ),

            // Footer
            _buildFooter(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getTypeIcon(_effectiveType),
            color: context.themeColors.textSecondary,
            size: 24,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.keyName,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Type: ${_getTypeDisplayName(_effectiveType)}',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                ),
                // A0 — 视图切换(string↔bitmap/bitfield,zset↔geo)
                if (_viewOptions().length > 1) ...[
                  const SizedBox(height: AppDesignSystem.space2),
                  Wrap(
                    spacing: AppDesignSystem.space1,
                    runSpacing: AppDesignSystem.space1,
                    children: _viewOptions().map((t) {
                      final selected = _effectiveType.toLowerCase() == t;
                      return ChoiceChip(
                        label: Text(_getTypeDisplayName(t)),
                        selected: selected,
                        onSelected: (_) => _switchView(t),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Footer 仅保留 Close —— 各 editor 自管 save:
  /// Hash/List/Set/ZSet/Stream 走内联 add/delete 即时落库;
  /// String/JSON 走内联 Save 按钮 → adapter.runCommand。
  Widget _buildFooter(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    // A0 — 按 _effectiveType 分发(支持手动切换 bitmap/bitfield/geo)
    switch (_effectiveType.toLowerCase()) {
      case 'string':
        return StringEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'hash':
        return HashEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'list':
        return ListEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'set':
        return SetEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'zset':
        return ZSetEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'stream':
        return StreamEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'json':
      case 'rejson-rl':
        return JsonEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'hyperloglog':
        return HyperLogLogEditorWidget(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      // A0 — bitmap/bitfield/geo 占位,A1/A2/A3 替换为真 editor
      case 'bitmap':
        return BitmapEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'bitfield':
        return BitfieldEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      case 'geo':
        return GeoEditor(
          keyName: widget.keyName,
          connectionId: widget.connectionId,
          databaseName: widget.databaseName,
          provider: widget.provider,
        );
      default:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.circleHelp,
                size: 48,
                color: context.themeColors.textMuted,
              ),
              const SizedBox(height: AppDesignSystem.space3),
              Text(
                'Unknown type: $_effectiveType',
                style: TextStyle(color: context.themeColors.textSecondary),
              ),
            ],
          ),
        );
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'string':
        return LucideIcons.type;
      case 'hash':
        return LucideIcons.rows3;
      case 'list':
        return LucideIcons.list;
      case 'set':
        return LucideIcons.users;
      case 'zset':
        return LucideIcons.arrowUpDown;
      case 'stream':
        return LucideIcons.waves;
      case 'json':
      case 'rejson-rl':
        return LucideIcons.code;
      case 'hyperloglog':
        return LucideIcons.chartColumn;
      // A0 — 新类型 icon
      case 'bitmap':
        return LucideIcons.grid3x3;
      case 'bitfield':
        return LucideIcons.brackets;
      case 'geo':
        return LucideIcons.mapPin;
      default:
        return LucideIcons.circleHelp;
    }
  }

  String _getTypeDisplayName(String type) {
    switch (type.toLowerCase()) {
      case 'string':
        return 'String';
      case 'hash':
        return 'Hash';
      case 'list':
        return 'List';
      case 'set':
        return 'Set';
      case 'zset':
        return 'Sorted Set';
      case 'stream':
        return 'Stream';
      case 'json':
      case 'rejson-rl':
        return 'JSON';
      case 'hyperloglog':
        return 'HyperLogLog';
      // A0 — 新类型显示名
      case 'bitmap':
        return 'Bitmap';
      case 'bitfield':
        return 'Bitfield';
      case 'geo':
        return 'Geo';
      default:
        return type;
    }
  }
}
