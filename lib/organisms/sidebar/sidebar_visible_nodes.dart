// SidebarWidget 拆分（plan §3.4）：可见节点 key 构建纯函数库。
//
// 从 `_SidebarWidgetState._rebuildVisibleNodeKeys` 及其 helper
// （_addSchemaLeafKeys / _addGlobalNodeKeys / _addSQLiteKeys /
// _filterDatabases）原样迁移。输入 AppProvider 数据快照 + 三份展开集合 +
// schema 缓存 + 搜索词，输出与树渲染顺序一致的有序 key 列表，供
// ↑↓ 键盘导航与 type-to-select 使用。纯计算、不持状态、不依赖
// BuildContext。
//
// 注意：此处的搜索过滤规则是 SidebarTree 内部过滤（sidebar_tree.dart）
// 之外的第二份实现，需人工保持一致（拆分前即如此，行为不变）。
import '../../models/database_models.dart';
import '../../providers/app_provider.dart';
import 'sidebar_current_connection.dart';

/// 构建可见节点的有序 key 列表（用于 ↑↓ 导航）。
///
/// key 前缀约定：
/// - `conn:<cid>` 连接节点
/// - `cat:<cid>[:db][:schema]:<category>` 分类节点（tables/views/...）
/// - `db:<cid>:<db>` 数据库节点
/// - `schema:<cid>:<db>:<schema>` schema 节点
/// - `table:<cid>:<db>[:<schema>]:<table>` 表节点
/// - `view:/proc:/func:` 视图/存储过程/函数叶子（C19 统一：函数前缀
///   `func:`，与 Enter 处理器/树内选中态同构——原 `fn:` 仅本文件使用，
///   三处不一致导致 Enter 失效与选中态错位）
/// - `savedquery:<cid>:<id>` 保存查询
/// - `col:/idx:/fk:<tk前缀>:<name>` 列/索引/外键叶子
/// - `<cid>:<全局节点后缀>` 连接级全局节点（performance 等）
/// 注意：`db:`/`table:` 等前缀是**可见节点 key**（导航用）；展开集合
/// （expandedDatabases/expandedTables）存**裸 key**（`cid:db` /
/// `cid:db:table`），两层格式勿混（C19 修复的键盘双格式 bug 即源于此）。
List<String> buildVisibleSidebarNodeKeys({
  required AppProvider provider,
  required Set<String> expandedItems,
  required Set<String> expandedDatabases,
  required Set<String> expandedTables,
  required Map<String, DbTable> loadedTableSchemas,
  required Map<String, List<ForeignKey>> loadedTableForeignKeys,
  required String searchQuery,
}) {
  final keys = <String>[];
  final sq = searchQuery.toLowerCase();

  // C22-1 单实例树：key 集只含当前连接（与 SidebarTree 渲染同源锚定）；
  // 无当前连接时返回空（键盘导航随之静默——树上没有可导航行）。
  final current = resolveSidebarCurrentConnection(provider);
  if (current == null) return keys;

  for (final conn in [current]) {
    // 搜索过滤
    if (sq.isNotEmpty &&
        !conn.name.toLowerCase().contains(sq) &&
        !conn.host.toLowerCase().contains(sq)) {
      // 检查是否有匹配的数据库/表
      final dbs = provider.connection.getConnectionDatabases(conn.id);
      bool hasMatch = false;
      if (dbs.any((d) => d.toLowerCase().contains(sq))) {
        hasMatch = true;
      } else {
        for (final d in dbs) {
          final cached = provider.connection.getCachedDatabase(conn.id, d);
          if (cached != null &&
              (cached.tables.any((t) => t.name.toLowerCase().contains(sq)) ||
                  cached.views.any((v) => v.toLowerCase().contains(sq)) ||
                  cached.procedures.any(
                    (p) => p.toLowerCase().contains(sq),
                  ))) {
            hasMatch = true;
            break;
          }
        }
      }
      if (!hasMatch) continue;
    }

    final isConnected = provider.isConnectionConnected(conn.id);
    final connKey = 'conn:${conn.id}';
    keys.add(connKey);

    if (!isConnected || !expandedItems.contains(conn.id)) continue;

    // Connection-level Saved Queries
    final savedQueries = provider.savedQueriesForConnection(conn.id);
    final filteredQueries = sq.isEmpty
        ? savedQueries
        : savedQueries.where((q) {
            return q.title.toLowerCase().contains(sq) ||
                q.sql.toLowerCase().contains(sq);
          }).toList();
    final savedQueriesCatKey = 'cat:${conn.id}:saved_queries';
    keys.add(savedQueriesCatKey);
    // C19 裸 key 契约：SavedQueriesSection 存「cid:saved_queries」
    if (expandedItems.contains('${conn.id}:saved_queries')) {
      for (final q in filteredQueries) {
        keys.add('savedquery:${conn.id}:${q.id}');
      }
    }

    if (conn.type.isFlatFileTree) {
      _addSQLiteKeys(keys, provider, conn.id, sq, expandedItems);
      continue;
    }

    final dbs = _filterDatabases(provider, conn.id, sq);
    for (final db in dbs) {
      final dbKey = 'db:${conn.id}:$db';
      keys.add(dbKey);
      // 展开集合存裸 key（cid:db）——与树渲染/toggleDatabase/prune 同契约
      // （C19 统一：此前这里查「db:cid:db」前缀格式，鼠标展开的库其子
      // 节点永远进不了键盘导航 key 集）。
      if (!expandedDatabases.contains('${conn.id}:$db')) continue;

      final cached = provider.connection.getCachedDatabase(conn.id, db);
      if (cached == null) continue;

      if (cached.tables.isNotEmpty) {
        final filteredTables = sq.isEmpty
            ? cached.tables
            : cached.tables
                  .where((t) => t.name.toLowerCase().contains(sq))
                  .toList();
        if (filteredTables.isNotEmpty) {
          final catKey = 'cat:${conn.id}:$db:tables';
          keys.add(catKey);
          // 树装配（泛 SQL 共享树）存裸 key「cid:db:tables」
          if (expandedItems.contains('${conn.id}:$db:tables')) {
            for (final t in filteredTables) {
              keys.add('table:${conn.id}:$db:${t.name}');
              // 列/索引/外键纳入键盘导航
              _addSchemaLeafKeys(
                keys,
                '${conn.id}:$db:${t.name}',
                prefix: '${conn.id}:$db:${t.name}',
                expandedTables: expandedTables,
                loadedTableSchemas: loadedTableSchemas,
                loadedTableForeignKeys: loadedTableForeignKeys,
              );
            }
          }
        }
      }
      if (cached.views.isNotEmpty) {
        final filteredViews = sq.isEmpty
            ? cached.views
            : cached.views
                  .where((v) => v.toLowerCase().contains(sq))
                  .toList();
        if (filteredViews.isNotEmpty) {
          final catKey = 'cat:${conn.id}:$db:views';
          keys.add(catKey);
          if (expandedItems.contains('${conn.id}:$db:views')) {
            for (final v in filteredViews) {
              keys.add('view:${conn.id}:$db:$v');
            }
          }
        }
      }
      if (cached.procedures.isNotEmpty) {
        final filteredProcs = sq.isEmpty
            ? cached.procedures
            : cached.procedures
                  .where((p) => p.toLowerCase().contains(sq))
                  .toList();
        if (filteredProcs.isNotEmpty) {
          final catKey = 'cat:${conn.id}:$db:procedures';
          keys.add(catKey);
          if (expandedItems.contains('${conn.id}:$db:procedures')) {
            for (final p in filteredProcs) {
              keys.add('proc:${conn.id}:$db:$p');
            }
          }
        }
      }

      // T008 — schema-aware node keys for keyboard navigation
      if (cached.schemas.isNotEmpty) {
        for (final schema in cached.schemas) {
          final schemaKey = 'schema:${conn.id}:$db:${schema.name}';
          keys.add(schemaKey);
          // PG 插件树存裸 key「cid:db:schema:name」
          final schemaStoreKey = '${conn.id}:$db:schema:${schema.name}';
          if (!expandedItems.contains(schemaStoreKey)) continue;

          if (schema.tables.isNotEmpty) {
            final filteredTables = sq.isEmpty
                ? schema.tables
                : schema.tables
                      .where((t) => t.name.toLowerCase().contains(sq))
                      .toList();
            if (filteredTables.isNotEmpty) {
              final catKey = 'cat:$schemaKey:tables';
              keys.add(catKey);
              if (expandedItems.contains('$schemaStoreKey:tables')) {
                for (final t in filteredTables) {
                  keys.add('table:${conn.id}:$db:${schema.name}:${t.name}');
                  // 列/索引/外键纳入键盘导航（schema 感知）
                  _addSchemaLeafKeys(
                    keys,
                    '${conn.id}:$db:${schema.name}:${t.name}',
                    prefix: '${conn.id}:$db:${schema.name}:${t.name}',
                    expandedTables: expandedTables,
                    loadedTableSchemas: loadedTableSchemas,
                    loadedTableForeignKeys: loadedTableForeignKeys,
                  );
                }
              }
            }
          }
          if (schema.views.isNotEmpty) {
            final filteredViews = sq.isEmpty
                ? schema.views
                : schema.views
                      .where((v) => v.toLowerCase().contains(sq))
                      .toList();
            if (filteredViews.isNotEmpty) {
              final catKey = 'cat:$schemaKey:views';
              keys.add(catKey);
              if (expandedItems.contains('$schemaStoreKey:views')) {
                for (final v in filteredViews) {
                  keys.add('view:${conn.id}:$db:$v');
                }
              }
            }
          }
          if (schema.functions.isNotEmpty) {
            final filteredFns = sq.isEmpty
                ? schema.functions
                : schema.functions
                      .where((f) => f.toLowerCase().contains(sq))
                      .toList();
            if (filteredFns.isNotEmpty) {
              final catKey = 'cat:$schemaKey:functions';
              keys.add(catKey);
              if (expandedItems.contains('$schemaStoreKey:functions')) {
                for (final f in filteredFns) {
                  keys.add('func:${conn.id}:$db:$f');
                }
              }
            }
          }
          if (schema.procedures.isNotEmpty) {
            final filteredProcs = sq.isEmpty
                ? schema.procedures
                : schema.procedures
                      .where((p) => p.toLowerCase().contains(sq))
                      .toList();
            if (filteredProcs.isNotEmpty) {
              final catKey = 'cat:$schemaKey:procedures';
              keys.add(catKey);
              if (expandedItems.contains('$schemaStoreKey:procedures')) {
                for (final p in filteredProcs) {
                  keys.add('proc:${conn.id}:$db:$p');
                }
              }
            }
          }
        }
      }
    }

    // 全局节点：连接级别展开项（Server/Performance/Users 等）
    _addGlobalNodeKeys(keys, conn.id, conn.type, expandedItems);
  }

  return keys;
}

/// 为已展开且 schema 已加载的表追加 col/idx/fk 节点键（键盘导航 / type-to-select）。
/// [prefix] 必须与树渲染时 colKeyOf/idxKeyOf/fkKeyOf 的键基一致。
// 列/索引/外键纳入键盘导航
void _addSchemaLeafKeys(
  List<String> keys,
  String tk, {
  required String prefix,
  required Set<String> expandedTables,
  required Map<String, DbTable> loadedTableSchemas,
  required Map<String, List<ForeignKey>> loadedTableForeignKeys,
}) {
  if (!expandedTables.contains(tk)) return;
  final schema = loadedTableSchemas[tk];
  if (schema == null) return;
  for (final col in schema.columns) {
    keys.add('col:$prefix:${col.name}');
  }
  for (final idx in schema.indexes) {
    keys.add('idx:$prefix:${idx.name}');
  }
  final fks = loadedTableForeignKeys[tk];
  if (fks != null) {
    for (final fk in fks) {
      keys.add('fk:$prefix:${fk.name}');
    }
  }
}

void _addGlobalNodeKeys(
  List<String> keys,
  String cid,
  DatabaseType type,
  Set<String> expandedItems,
) {
  // 各数据库类型的全局节点 key 后缀（分隔线以下）
  const pgs = [
    'mysql_server',
    'performance',
    'redis_server_info',
    'redis_memory',
    'redis_client_info',
    'redis_stats',
    'redis_config',
    'redis_slowlog',
    'sqlserver_status',
    'sqlserver_process',
    'sqlserver_users',
    'snow_warehouse',
    'snow_session',
    'snow_users',
    'es_health',
    'es_indices',
    'es_nodes',
    'pg_server',
    'pg_process',
    'mongodb_server_info',
  ];
  for (final suffix in pgs) {
    final key = '$cid:$suffix';
    if (expandedItems.contains(key)) keys.add(key);
  }
}

void _addSQLiteKeys(
  List<String> keys,
  AppProvider provider,
  String cid,
  String sq,
  Set<String> expandedItems,
) {
  final cached = provider.connection.getCachedDatabase(cid, 'main');
  if (cached == null) return;

  if (cached.tables.isNotEmpty) {
    final filteredTables = sq.isEmpty
        ? cached.tables
        : cached.tables
              .where((t) => t.name.toLowerCase().contains(sq))
              .toList();
    if (filteredTables.isNotEmpty) {
      final catKey = 'cat:$cid:main:tables';
      keys.add(catKey);
      // SQLite 插件树存裸 key「cid:main:tables」
      if (expandedItems.contains('$cid:main:tables')) {
        for (final t in filteredTables) {
          keys.add('table:$cid:main:${t.name}');
        }
      }
    }
  }
  if (cached.views.isNotEmpty) {
    final filteredViews = sq.isEmpty
        ? cached.views
        : cached.views.where((v) => v.toLowerCase().contains(sq)).toList();
    if (filteredViews.isNotEmpty) {
      final catKey = 'cat:$cid:main:views';
      keys.add(catKey);
      if (expandedItems.contains('$cid:main:views')) {
        for (final v in filteredViews) {
          keys.add('view:$cid:main:$v');
        }
      }
    }
  }
}

List<String> _filterDatabases(AppProvider provider, String cid, String sq) {
  final all = provider.connection.getConnectionDatabases(cid);
  if (sq.isEmpty) return all;
  return all.where((db) {
    if (db.toLowerCase().contains(sq)) return true;
    final cached = provider.connection.getCachedDatabase(cid, db);
    if (cached != null) {
      if (cached.tables.any((t) => t.name.toLowerCase().contains(sq))) {
        return true;
      }
      if (cached.views.any((v) => v.toLowerCase().contains(sq))) {
        return true;
      }
      if (cached.procedures.any((p) => p.toLowerCase().contains(sq))) {
        return true;
      }
    }
    return true; // uncached DB stays
  }).toList();
}

/// 从节点 key 提取用于 type-to-select 的显示名。
///
/// savedquery 通过 provider 反查标题；其余按前缀切 key 段。
String sidebarNodeDisplayName(String key, AppProvider provider) {
  if (key.startsWith('conn:')) return key.substring(5);
  if (key.startsWith('db:')) {
    final parts = key.substring(3).split(':');
    return parts.length >= 2 ? parts[1] : '';
  }
  // T009 — extract schema name for type-to-select
  if (key.startsWith('schema:')) {
    final parts = key.substring(7).split(':');
    return parts.length >= 3 ? parts[2] : key.substring(7);
  }
  if (key.startsWith('savedquery:')) {
    final queryId = key.substring(key.lastIndexOf(':') + 1);
    final query = provider.getSavedQueryById(queryId);
    return query?.title ?? queryId;
  }
  // schema 叶子——返回叶子名（最后一段），用于 type-to-select
  if (key.startsWith('col:') ||
      key.startsWith('idx:') ||
      key.startsWith('fk:')) {
    return key.substring(key.lastIndexOf(':') + 1);
  }
  // cat / table / view / proc — extract the name part after the second colon
  final secondColon = key.indexOf(':', key.indexOf(':') + 1);
  if (secondColon >= 0) {
    return key.substring(secondColon + 1);
  }
  return key;
}
