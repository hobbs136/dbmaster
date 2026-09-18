# DatabaseService 重构方案

## 当前问题
- 1 个类，1692 行，43 个方法
- 违反单一职责原则：连接管理 + 查询执行 + Schema DDL + 缓存 + 查询取消 全部混在一起
- 被 16 个文件引用，接口不能变

## 重构策略
**Facade + 内部拆分**：保持公开接口不变，内部拆分为多个私有 Manager 类

```
database_service.dart (Facade，对外接口不变)
  ├── _ConnectionState      (连接状态存储)
  ├── _ConnectionManager    (连接生命周期)
  ├── _QueryExecutor       (查询执行 + 缓存 + 取消)
  └── _SchemaManager       (Schema DDL + 元数据查询)
```

## 职责划分

### _ConnectionManager
- `connect()`, `disconnect()`, `disconnectAll()`
- `cancelConnect()`, `setActiveConnection()`
- `isConnecting()`, `hasConnection()`, `isConnectionActive()`
- `testConnection()`

### _QueryExecutor  
- `executeQuery()`, `getExplainPlan()`
- `executeSqlScript()`
- 查询缓存 (queryCache)
- 查询取消 (_startQueryTracking, _stopQueryTracking, cancelQuery, isQueryCancelled)

### _SchemaManager
- **元数据查询**: `getDatabases()`, `getTables()`, `getViews()`, `getProcedures()`, `getFunctions()`
- **表结构**: `getTableColumns()`, `getTableIndexes()`, `getAllTables()`, `getDatabaseInfo()`
- **DDL**: `createDatabase()`, `dropDatabase()`, `createTable()`, `dropTable()`, `renameTable()`, `truncateTable()`
- **列操作**: `addColumn()`, `dropColumn()`, `modifyColumn()`
- **索引操作**: `createIndex()`, `dropIndex()`
- **属性查询**: `getTableProperties()`, `getCreateTableSql()`, `getDatabaseProperties()`, `getDatabaseSize()`, `getCreateDatabaseSql()`
- **表数据**: `getTableData()`, `getTableRowCount()`, `exportTableData()`
- **其他**: `getCharsets()`, `getCollations()`, `exportDatabaseStructure()`, `getServerVersion()`, `useDatabase()`

## 需要更新的文件 (16个)
1. `providers/app_provider.dart`
2. `providers/connection_provider.dart`
3. `providers/tab_provider.dart`
4. `services/sql_autocomplete_service.dart`
5. `services/backup_service.dart`
6. `services/trigger_service.dart`
7. `services/sql_quick_fix_service.dart`
8. `services/performance_analyzer_service.dart`
9. `services/ai_enhanced_service.dart`
10. `services/schema_context_service.dart`
11. `services/er_diagram_service.dart`
12. `services/multi_execution_service.dart`
13. `services/import_service.dart`
14. `services/stored_procedure_service.dart`
15. `models/database_models.dart`
16. `services/connection_manager.dart` (已废弃，但有引用)

## 风险评估
- 高风险：需要修改 16 个引用文件
- 建议：先完成内部拆分，编译通过后逐步更新引用文件
