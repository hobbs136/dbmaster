// 全功能 Redis GUI — 阶段3: Function 编辑器对话框(接通真实 FUNCTION LOAD)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../atoms/app_loading.dart';

class RedisFunctionEditorDialog extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;
  final VoidCallback? onCreated;

  /// #6 — 编辑模式：传入则用现有 library 名 + 源码预填。预填时 library 名
  /// 字段锁定（Lua shebang 内嵌 name=，改名需新建库），REPLACE 强制开。
  /// 缺省（创建模式）保持原行为。
  final String? initialLibraryName;
  final String? initialSource;

  const RedisFunctionEditorDialog({
    super.key,
    required this.connectionId,
    required this.provider,
    this.onCreated,
    this.initialLibraryName,
    this.initialSource,
  });

  @override
  State<RedisFunctionEditorDialog> createState() =>
      _RedisFunctionEditorDialogState();
}

class _RedisFunctionEditorDialogState extends State<RedisFunctionEditorDialog> {
  final TextEditingController _libraryController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  // REPLACE 选项(覆盖同名库)
  bool _replace = false;

  /// #6 — 是否处于编辑模式（initialLibraryName 非空）。
  bool get _isEditMode => widget.initialLibraryName != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _libraryController.text = widget.initialLibraryName!;
      // #6 — 编辑模式：把源码里的 shebang 行剥掉预填进 code 框
      // （_createLibrary 会在保存时重新加 shebang，避免重复 #!lua name= 行）。
      final src = widget.initialSource ?? '';
      _codeController.text = _stripShebang(src);
      _replace = true; // 编辑必然 REPLACE
    }
  }

  /// 去掉首行的 `#!lua name=xxx` shebang（保留函数体）。
  String _stripShebang(String source) {
    if (source.isEmpty) return '';
    final lines = source.split('\n');
    if (lines.isNotEmpty && lines[0].startsWith('#!')) {
      return lines.sublist(1).join('\n');
    }
    return source;
  }

  @override
  void dispose() {
    _libraryController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// 插入 Redis Functions 示例模板(含 register_function 调用)。
  void _insertTemplate() {
    _codeController.text =
        "redis.register_function('myfunction', function(keys, args)\n    return 'Hello Redis!'\nend)\n";
  }

  Future<void> _createLibrary() async {
    final l10n = AppLocalizations.of(context)!;
    final libraryName = _libraryController.text.trim();
    if (libraryName.isEmpty || _codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.redisLibNameCodeRequired),
          backgroundColor: context.themeColors.accentOrange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // 构造合法 FUNCTION LOAD 载荷(shebang + Lua body),走 adapter.loadRedisFunction
    // 绕过 executeQuery 的 _parseCommand,避免 Lua 多行/引号被破坏
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.redisAdapterNotAvailable),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
      return;
    }

    try {
      final luaBody = '#!lua name=$libraryName\n${_codeController.text}';
      final ok = await adapter.loadRedisFunction(luaBody, replace: _replace);

      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.redisLibraryCreated),
            backgroundColor: context.themeColors.accentGreen,
          ),
        );
        Navigator.pop(context);
        widget.onCreated?.call();
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.redisLibraryCreateFailedSyntax),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.redisLibraryCreateFailed(e.toString())),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        // #6 — 编辑模式用不同标题
        _isEditMode ? 'Edit Function Library' : l10n.redisLibraryTitle,
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Library name
            Text(
              l10n.redisLibraryNameLabel,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            TextField(
              controller: _libraryController,
              // #6 — 编辑模式锁定库名（shebang 内嵌 name=，改名需新建库）
              readOnly: _isEditMode,
              style: TextStyle(color: context.themeColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'mylib',
                labelStyle: TextStyle(color: context.themeColors.textMuted),
                hintText: l10n.redisLibraryUsageHint,
                hintStyle: TextStyle(color: context.themeColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                filled: true,
                fillColor: context.themeColors.bgTertiary,
              ),
              autofocus: !_isEditMode,
            ),
            const SizedBox(height: AppDesignSystem.space3),

            // Lua code header + insert template button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.redisLuaCodeLabel,
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _insertTemplate,
                  icon: const Icon(LucideIcons.code, size: 16),
                  label: Text(l10n.redisInsertExample),
                ),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space2),
            TextField(
              controller: _codeController,
              maxLines: null,
              minLines: 8,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeSm,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              decoration: InputDecoration(
                hintText:
                    "redis.register_function('myfunction', function(keys, args)\n  return 'Hello Redis!'\nend)",
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                filled: true,
                fillColor: context.themeColors.bgTertiary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),

            // REPLACE option
            // 新增 REPLACE 开关；#6 编辑模式强制开 + 锁定
            Row(
              children: [
                Switch(
                  value: _replace,
                  onChanged: _isEditMode
                      ? null
                      : (v) => setState(() => _replace = v),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    l10n.redisReplaceExisting,
                    style: TextStyle(
                      color: context.themeColors.textSecondary,
                      fontSize: AppDesignSystem.fontSizeXs,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space3),

            // Info
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
                        'Redis Functions (Redis 7.0+)',
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
                    l10n.redisLibraryInfoText,
                    style: TextStyle(
                      color: context.themeColors.textSecondary,
                      fontSize: AppDesignSystem.fontSizeXs,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        LoadingButton(
          // #6 — 编辑模式按钮文案
          label: _isEditMode ? 'Save Changes' : l10n.redisCreateLibrary,
          onPressed: _createLibrary,
          isLoading: _isLoading,
          backgroundColor: context.themeColors.accentBlue,
        ),
      ],
    );
  }
}
