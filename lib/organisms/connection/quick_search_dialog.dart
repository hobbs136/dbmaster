import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../l10n/app_localizations.dart';
// SqlEscapeUtils + DatabaseType（表名按连接库类型正确引用）
import '../../models/database_models.dart';
import '../../utils/sql_escape_utils.dart';

enum SearchObjectType { table, view, procedure, column, connection, database }

class SearchObject {
  final String name;
  final String path;
  final SearchObjectType type;
  final String? connectionId;
  final String? databaseName;
  final IconData icon;
  final String? columnName;

  SearchObject({
    required this.name,
    required this.path,
    required this.type,
    this.connectionId,
    this.databaseName,
    required this.icon,
    this.columnName,
  });

  String get displayPath => path;
}

class QuickSearchDialog extends StatefulWidget {
  const QuickSearchDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const QuickSearchDialog(),
    );
  }

  @override
  State<QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends State<QuickSearchDialog> {
  late TextEditingController _searchController;
  late FocusNode _focusNode;
  List<SearchObject> _allObjects = [];
  List<SearchObject> _filteredObjects = [];
  int _selectedIndex = 0;
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    // Key handling is attached directly to this node so it is owned by a single
    // widget (the TextField below). Do NOT wrap in a KeyboardListener too:
    // sharing one FocusNode across a Focus widget and the TextField triggers a
    // Windows focus/IME feedback loop that hangs the app (release-only).
    _focusNode = FocusNode(onKeyEvent: _onKeyEvent);
    _buildSearchIndex();
    _filteredObjects = List.from(_allObjects);
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _buildSearchIndex() {
    final provider = context.read<AppProvider>();
    final objects = <SearchObject>[];

    for (final server in provider.connection.savedConnections) {
      objects.add(
        SearchObject(
          name: server.name,
          path: server.name,
          type: SearchObjectType.connection,
          connectionId: server.id,
          icon: _getIconForType(SearchObjectType.connection),
        ),
      );

      final databases = provider.connection.getConnectionDatabases(server.id);
      for (final dbName in databases) {
        objects.add(
          SearchObject(
            name: dbName,
            path: '${server.name} / $dbName',
            type: SearchObjectType.database,
            connectionId: server.id,
            databaseName: dbName,
            icon: _getIconForType(SearchObjectType.database),
          ),
        );

        final db = provider.connection.getCachedDatabase(server.id, dbName);
        if (db != null) {
          for (final table in db.tables) {
            objects.add(
              SearchObject(
                name: table.name,
                path: '${server.name} / $dbName / ${table.name}',
                type: SearchObjectType.table,
                connectionId: server.id,
                databaseName: dbName,
                icon: _getIconForType(SearchObjectType.table),
              ),
            );

            for (final column in table.columns) {
              objects.add(
                SearchObject(
                  name: column.name,
                  path:
                      '${server.name} / $dbName / ${table.name} / ${column.name}',
                  type: SearchObjectType.column,
                  connectionId: server.id,
                  databaseName: dbName,
                  columnName: column.name,
                  icon: _getIconForType(SearchObjectType.column),
                ),
              );
            }
          }

          for (final viewName in db.views) {
            objects.add(
              SearchObject(
                name: viewName,
                path: '${server.name} / $dbName / $viewName',
                type: SearchObjectType.view,
                connectionId: server.id,
                databaseName: dbName,
                icon: _getIconForType(SearchObjectType.view),
              ),
            );
          }

          for (final procName in db.procedures) {
            objects.add(
              SearchObject(
                name: procName,
                path: '${server.name} / $dbName / $procName',
                type: SearchObjectType.procedure,
                connectionId: server.id,
                databaseName: dbName,
                icon: _getIconForType(SearchObjectType.procedure),
              ),
            );
          }
        }
      }
    }

    setState(() {
      _allObjects = objects;
    });
  }

  /// 模糊匹配：检查 query 的所有字符是否按顺序出现在 target 中
  /// 例如 "usr" 匹配 "users", "user_profiles"
  bool _fuzzyMatch(String query, String target) {
    if (query.isEmpty) return true;
    var qi = 0;
    for (var ti = 0; ti < target.length && qi < query.length; ti++) {
      if (target[ti] == query[qi]) qi++;
    }
    return qi == query.length;
  }

  /// 按数据库类型用正确引号包裹表名（修写死反引号在 SQL Server/PG/SQLite 上非法）。
  /// 委托 [SqlEscapeUtils.escapeIdentifierForType]；null 类型回落反引号（保持旧行为）。
  String _quoteTable(String name, DatabaseType? type) {
    if (type == null) return SqlEscapeUtils.escapeMySqlIdentifier(name);
    return SqlEscapeUtils.escapeIdentifierForType(name, type);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredObjects = List.from(_allObjects);
      } else {
        _filteredObjects = _allObjects.where((obj) {
          final name = obj.name.toLowerCase();
          final path = obj.path.toLowerCase();
          // 先精确包含匹配，再模糊匹配
          return name.contains(query) ||
              path.contains(query) ||
              _fuzzyMatch(query, name) ||
              _fuzzyMatch(query, path);
        }).toList();
      }
      _selectedIndex = _filteredObjects.isNotEmpty ? 0 : -1;
    });
  }

  Future<void> _selectObject(SearchObject object) async {
    final provider = context.read<AppProvider>();

    if (object.connectionId != null) {
      provider.switchToConnection(object.connectionId!);
    }

    if (object.databaseName != null) {
      provider.changeDatabase(object.databaseName!);
      // 显式选库覆写 switchToConnection 内置的「默认第一个库」tab 同步
      // （工具栏库芯片与执行库跟随，2026-08-27 修复；对象浏览走
      // openQueryTab 自带上下文不受影响）；方向 A（2026-09-04）：跟随式
      // 覆写——已绑定上下文的活跃 tab 不动。
      provider.followActiveTabDatabase(object.databaseName!);
    }

    if (object.type == SearchObjectType.table &&
        object.connectionId != null &&
        object.databaseName != null) {
      // 用 adapter.getDefaultBrowseQuery 生成正确浏览 SQL（引用符 + limit 语法按库类型；
      // 原写死 `name` LIMIT 100 在 SQL Server 无 LIMIT、PG/SQLite 引号错）。adapter 不可用时回落。
      final adapter = provider.dbService.getAdapter(object.connectionId!);
      final fallbackType = provider.connection
          .getServerById(object.connectionId)
          ?.type;
      final sql =
          adapter?.getDefaultBrowseQuery(object.name) ??
          'SELECT * FROM ${_quoteTable(object.name, fallbackType)} LIMIT 100';
      await provider.openQueryTab(
        object.connectionId!,
        object.databaseName!,
        sql: sql,
      );
      if (!mounted) return;
      final newTabIndex = provider.activeTabIndex;
      provider.tab.renameTab(
        newTabIndex,
        '${AppLocalizations.of(context)!.searchDialogTitle} ${object.name}',
      );
      provider.requestEditorFocus();
    }

    Navigator.pop(context, object);
  }

  /// Handles list-navigation keys on the search field's FocusNode.
  /// Returns [KeyEventResult.handled] for navigation keys (so the TextField
  /// does not also move the caret / submit), [KeyEventResult.ignored] otherwise
  /// so normal typing flows through.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // 空结果时跳过导航——否则 clamp(0, length-1)=clamp(0,-1) 在 debug 抛断言
    // （原被常驻 Command Palette 条目掩盖；spec 040 移除该条目后暴露）。
    if (_filteredObjects.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(
          0,
          _filteredObjects.length - 1,
        );
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(
          0,
          _filteredObjects.length - 1,
        );
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_filteredObjects.isNotEmpty) {
        _selectObject(_filteredObjects[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToSelected() {
    const itemHeight = 40.0;
    final targetOffset = _selectedIndex * itemHeight;
    if (_listScrollController.hasClients) {
      _listScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The search TextField owns _focusNode (onKeyEvent attached in initState);
    // no separate KeyboardListener/Focus wrapper is needed.
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      child: Container(
        width: 650,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearchField(l10n),
            Flexible(child: _buildResultsList(l10n)),
            _buildFooter(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.search,
            size: 20,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeLg,
                color: context.themeColors.textPrimary,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                hintStyle: TextStyle(
                  fontSize: AppDesignSystem.fontSizeLg,
                  color: context.themeColors.textMuted,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onSubmitted: (_) {
                if (_filteredObjects.isNotEmpty) {
                  _selectObject(_filteredObjects[_selectedIndex]);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(AppLocalizations l10n) {
    if (_filteredObjects.isEmpty) {
      return _buildEmptyState(l10n);
    }

    return ListView.builder(
      controller: _listScrollController,
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      itemCount: _filteredObjects.length,
      itemExtent: 40,
      itemBuilder: (context, index) {
        final object = _filteredObjects[index];
        final isSelected = index == _selectedIndex;

        return _SearchResultItem(
          object: object,
          isSelected: isSelected,
          onTap: () => _selectObject(object),
        );
      },
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.searchX,
            size: 48,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            l10n.searchNoResults,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeLg,
              color: context.themeColors.textMuted,
            ),
          ),
          if (_searchController.text.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              l10n.searchTryDifferentKeywords,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: context.themeColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          top: BorderSide(color: context.themeColors.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.keyboard,
            size: 14,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(width: AppDesignSystem.space1),
          _buildShortcutHint('↑↓', l10n.searchNavigate),
          _buildShortcutHint('Enter', l10n.searchSelect),
          _buildShortcutHint('Esc', l10n.searchClose),
          const Spacer(),
          Text(
            l10n.searchResultsCount(_filteredObjects.length),
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: context.themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutHint(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: AppDesignSystem.space3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            key,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: context.themeColors.textSecondary,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            label,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: context.themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(SearchObjectType type) {
    switch (type) {
      case SearchObjectType.connection:
        return LucideIcons.link;
      case SearchObjectType.database:
        return LucideIcons.database;
      case SearchObjectType.table:
        return LucideIcons.table2;
      case SearchObjectType.view:
        return LucideIcons.eye;
      case SearchObjectType.procedure:
        return LucideIcons.code;
      case SearchObjectType.column:
        return LucideIcons.columns2;
    }
  }
}

class _SearchResultItem extends StatelessWidget {
  final SearchObject object;
  final bool isSelected;
  final VoidCallback onTap;

  const _SearchResultItem({
    required this.object,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? context.themeColors.accentBlue.withValues(alpha: 0.15)
              : null,
          border: isSelected
              ? Border(
                  left: BorderSide(
                    color: context.themeColors.accentBlue,
                    width: 3,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Icon(
                object.icon,
                size: 18,
                color: isSelected
                    ? context.themeColors.accentBlue
                    : context.themeColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    object.name,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeMd,
                      color: context.themeColors.textPrimary,
                      fontWeight: isSelected
                          ? AppDesignSystem.fontWeightMedium
                          : AppDesignSystem.fontWeightRegular,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppDesignSystem.space0_5),
                  Text(
                    object.displayPath,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: context.themeColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _buildTypeBadge(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(BuildContext context, AppLocalizations l10n) {
    String label;
    Color color;

    switch (object.type) {
      case SearchObjectType.connection:
        label = l10n.searchTypeConnection;
        color = context.themeColors.info;
        break;
      case SearchObjectType.database:
        label = l10n.searchTypeDatabase;
        color = context.themeColors.warning;
        break;
      case SearchObjectType.table:
        label = l10n.searchTypeTable;
        color = context.themeColors.accentBlue;
        break;
      case SearchObjectType.view:
        label = l10n.searchTypeView;
        color = context.themeColors.success;
        break;
      case SearchObjectType.procedure:
        label = l10n.searchTypeProcedure;
        color = context.themeColors.error;
        break;
      case SearchObjectType.column:
        label = l10n.searchTypeColumn;
        color = context.themeColors.textMuted;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: AppDesignSystem.fontSizeXs, color: color),
      ),
    );
  }
}
