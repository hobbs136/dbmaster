import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../models/database_models.dart';
import '../../providers/app_provider.dart';
import '../../atoms/app_loading.dart';
import '../../l10n/app_localizations.dart';
import 'error_boundary.dart';
import '../../theme/app_colors.dart';

class DatabasePropertiesDialog extends StatefulWidget {
  final String dbName;

  const DatabasePropertiesDialog({super.key, required this.dbName});

  @override
  State<DatabasePropertiesDialog> createState() =>
      _DatabasePropertiesDialogState();
}

class _DatabasePropertiesDialogState extends State<DatabasePropertiesDialog> {
  Map<String, dynamic>? _properties;
  String _size = '';
  String _createSql = '';
  DatabaseType? _dbType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  Future<void> _loadProperties() async {
    final provider = context.read<AppProvider>();
    _dbType = provider.connection.currentServer?.type;

    final props = await provider.getDatabaseProperties(widget.dbName);
    final size = await provider.getDatabaseSize(widget.dbName);
    final createSql = await provider.getCreateDatabaseSql(widget.dbName);

    if (mounted) {
      setState(() {
        _properties = props;
        _size = size;
        _createSql = createSql;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 550,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppDesignSystem.space4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.themeColors.borderLight),
                ),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, color: context.themeColors.accentBlue),
                  const SizedBox(width: AppDesignSystem.space2),
                  Text(
                    l10n.dbPropertiesTitle(widget.dbName),
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSize2xl,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      color: context.themeColors.textMuted,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: AppBrandedLoading(size: 32, label: l10n.commonLoading),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDesignSystem.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPropertyRow(
                        l10n.dbPropertyName,
                        _properties?['name'] ?? widget.dbName,
                      ),
                      // 字符集/排序规则是 MySQL 专属概念，Doris 不适用
                      if (_dbType != DatabaseType.doris) ...[
                        _buildPropertyRow(
                          l10n.dbPropertyCharset,
                          _properties?['charset'] ?? '-',
                        ),
                        _buildPropertyRow(
                          l10n.dbPropertyCollation,
                          _properties?['collation'] ?? '-',
                        ),
                      ],
                      _buildPropertyRow(l10n.dbPropertySize, _size),
                      _buildPropertyRow(
                        l10n.dbPropertyTableCount,
                        '${_properties?['tableCount'] ?? 0}',
                      ),
                      _buildPropertyRow(
                        l10n.dbPropertyViewCount,
                        '${_properties?['viewCount'] ?? 0}',
                      ),
                      _buildPropertyRow(
                        l10n.dbPropertyRoutineCount,
                        '${_properties?['routineCount'] ?? 0}',
                      ),
                      const SizedBox(height: AppDesignSystem.space4),
                      Text(
                        l10n.connCreateStatement,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: AppDesignSystem.space2),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppDesignSystem.space3),
                        decoration: BoxDecoration(
                          color: context.themeColors.bgTertiary,
                          borderRadius: BorderRadius.circular(
                            AppDesignSystem.radiusSm,
                          ),
                          border: Border.all(
                            color: context.themeColors.borderLight,
                          ),
                        ),
                        child: SelectableText(
                          _createSql,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                            color: context.themeColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(AppDesignSystem.space4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _createSql));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.connCreateStatementCopied)),
                      );
                    },
                    icon: const Icon(LucideIcons.copy, size: 14),
                    label: Text(l10n.connCopyCreateStatement),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1_5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CreateDatabaseDialog extends StatefulWidget {
  // 接收当前连接的 DB 类型，据此设置 charset/collation 默认值。
  final DatabaseType? databaseType;

  const CreateDatabaseDialog({super.key, this.databaseType});

  @override
  State<CreateDatabaseDialog> createState() => _CreateDatabaseDialogState();
}

class _CreateDatabaseDialogState extends State<CreateDatabaseDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _charsetController;
  late final TextEditingController _collationController;
  bool _isLoading = false;

  // 按 DB 类型给出 charset/collation 的（默认值, 输入提示）。
  // 原硬编码 MySQL 的 utf8mb4/utf8mb4_unicode_ci，透传到 PG 的 ENCODING/LC_COLLATE
  // 后 PG 拒绝非法编码/locale，导致创建任何 PG 库都失败。PG 编码为 UTF8、排序规则留空走
  // 服务端默认；其它非 MySQL/Doris 类型语义不同或不适用，留空（null → adapter 忽略）。
  (String, String) get _charsetDefaultAndHint => switch (widget.databaseType) {
    // PG 默认留空 → 不发送 ENCODING → 继承 template1 编码（与回归前一致，必成功）；
    // hint 仍给 UTF8 引导需要显式指定编码的高级用户。
    DatabaseType.postgresql => ('', 'UTF8'),
    DatabaseType.mysql || DatabaseType.doris => ('utf8mb4', 'utf8mb4'),
    _ => ('', ''),
  };

  (String, String) get _collationDefaultAndHint =>
      switch (widget.databaseType) {
        DatabaseType.mysql ||
        DatabaseType.doris => ('utf8mb4_unicode_ci', 'utf8mb4_unicode_ci'),
        _ => ('', ''),
      };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _charsetController = TextEditingController(text: _charsetDefaultAndHint.$1);
    _collationController = TextEditingController(
      text: _collationDefaultAndHint.$1,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _charsetController.dispose();
    _collationController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final provider = context.read<AppProvider>();
      final result = await provider.createDatabase(
        name,
        charset: _charsetController.text.trim().isEmpty
            ? null
            : _charsetController.text.trim(),
        collation: _collationController.text.trim().isEmpty
            ? null
            : _collationController.text.trim(),
      );
      if (mounted) {
        if (result) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.dbCreateSuccess(name)),
              backgroundColor: context.themeColors.accentGreen,
            ),
          );
        } else {
          AppErrorHandler.showErrorSnackBar(context, l10n.dbCreateFailed);
        }
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.dbCreateError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.circlePlus, color: context.themeColors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.connectionCreateDatabase,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.dbDialogDbName,
                hintText: AppLocalizations.of(context)!.dbDialogDbNameHint,
                prefixIcon: Icon(LucideIcons.database),
              ),
              autofocus: true,
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            TextField(
              controller: _charsetController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                )!.dbDialogCharsetOptional,
                hintText: _charsetDefaultAndHint.$2,
                prefixIcon: Icon(LucideIcons.languages),
              ),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            TextField(
              controller: _collationController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                )!.dbDialogCollationOptional,
                hintText: _collationDefaultAndHint.$2,
                prefixIcon: Icon(LucideIcons.arrowUpDown),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _create,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.commonCreate),
        ),
      ],
    );
  }
}

class DropDatabaseConfirmDialog extends StatefulWidget {
  final String dbName;
  final int tableCount;
  final int viewCount;

  const DropDatabaseConfirmDialog({
    super.key,
    required this.dbName,
    this.tableCount = 0,
    this.viewCount = 0,
  });

  @override
  State<DropDatabaseConfirmDialog> createState() =>
      _DropDatabaseConfirmDialogState();
}

class _DropDatabaseConfirmDialogState extends State<DropDatabaseConfirmDialog> {
  final _controller = TextEditingController();
  bool _isConfirmed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final typed = _controller.text.trim();
    final target = widget.dbName.trim();
    final match = typed.toLowerCase() == target.toLowerCase();
    if (match != _isConfirmed) {
      setState(() => _isConfirmed = match);
    }
  }

  void _confirm() {
    if (_isConfirmed) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    // Build consequence warning items
    final warnings = <String>[];
    if (widget.tableCount > 0) {
      warnings.add(
        l10n.objectCountWarning(widget.tableCount, l10n.objectTypeTable),
      );
    }
    if (widget.viewCount > 0) {
      warnings.add(
        l10n.objectCountWarning(widget.viewCount, l10n.objectTypeView),
      );
    }

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.triangleAlert, color: context.themeColors.error),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              l10n.confirmDeleteDatabase,
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dropDatabaseWarning(widget.dbName),
            style: TextStyle(color: colors.textSecondary),
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space3),
            Container(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(
                  color: context.themeColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.triangleAlert,
                            color: context.themeColors.error,
                            size: 16,
                          ),
                          const SizedBox(width: AppDesignSystem.space2),
                          Expanded(
                            child: SelectableText(
                              '• $warning',
                              style: TextStyle(
                                color: context.themeColors.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      l10n.allDataWillBeLost,
                      style: TextStyle(
                        color: context.themeColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: AppDesignSystem.space3),
            Container(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(
                  color: context.themeColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    color: context.themeColors.error,
                    size: 20,
                  ),
                  SizedBox(width: AppDesignSystem.space2),
                  Expanded(
                    child: SelectableText(
                      l10n.dbOperationCannotBeUndone,
                      style: TextStyle(
                        color: context.themeColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.typeNameToConfirm(widget.dbName),
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              hintText: widget.dbName,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isConfirmed ? _confirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isConfirmed
                ? context.themeColors.error
                : colors.textMuted,
          ),
          child: Text(
            l10n.commonDelete,
            style: TextStyle(
              color: _isConfirmed ? Colors.white : colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// T016 — type-to-confirm dialog for DROP TABLE operations
class DropTableConfirmDialog extends StatefulWidget {
  final String tableName;
  final String dbName;

  const DropTableConfirmDialog({
    super.key,
    required this.tableName,
    required this.dbName,
  });

  @override
  State<DropTableConfirmDialog> createState() => _DropTableConfirmDialogState();
}

class _DropTableConfirmDialogState extends State<DropTableConfirmDialog> {
  final _controller = TextEditingController();
  bool _isConfirmed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final typed = _controller.text.trim();
    final target = widget.tableName.trim();
    final match = typed.toLowerCase() == target.toLowerCase();
    if (match != _isConfirmed) {
      setState(() => _isConfirmed = match);
    }
  }

  void _confirm() {
    if (_isConfirmed) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.triangleAlert, color: context.themeColors.error),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              l10n.confirmDropTable,
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dropTablePermanentWarning(
              '${widget.dbName}.${widget.tableName}',
            ),
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  color: context.themeColors.error,
                  size: 20,
                ),
                SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: SelectableText(
                    l10n.dropTableDataLossWarning,
                    style: TextStyle(
                      color: context.themeColors.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.typeNameToConfirm(widget.tableName),
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              hintText: widget.tableName,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isConfirmed ? _confirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isConfirmed
                ? context.themeColors.error
                : colors.textMuted,
          ),
          child: Text(
            l10n.commonDelete,
            style: TextStyle(
              color: _isConfirmed ? Colors.white : colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
