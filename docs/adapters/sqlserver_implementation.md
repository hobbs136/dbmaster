# SQL Server 适配器实现文档

**版本**: v1.1.1
**日期**: 2026-05-30
**适用范围**: DbMaster v3.2.0+

---

## 1. 架构

SQL Server 适配器是项目中**唯一使用 dart:ffi 直接绑定 FreeTDS DB-Library C API** 的实现。其他数据库适配器（MySQL、PostgreSQL 等）使用 Dart package。

```
Flutter UI (Consumer<AppProvider>)
  → AppProvider → ConnectionProvider → DatabaseService
    → SqlServerAdapter (implements DatabaseAdapter)
      → SqlServerFfiBindings (dart:ffi → sybdb.dll)
        → FreeTDS DB-Library → TDS Protocol → SQL Server
```

### 涉及文件（18 个）

| 文件 | 用途 |
|------|------|
| `lib/services/adapters/sqlserver_adapter.dart` | 核心适配器（~1300 行） |
| `lib/services/adapters/sqlserver_ffi_bindings.dart` | FreeTDS C API FFI 绑定（254 行） |
| `lib/utils/sql_escape_utils.dart` | `[bracket]` 风格标识符转义 |
| `lib/services/database_service.dart:182-183,1099-1109` | 适配器工厂 + TOP 3000 注入 |
| `lib/models/database_models.dart:32-140` | `DatabaseType.sqlserver` 枚举 |
| `lib/organisms/sidebar/builders/sqlserver_tree_builder.dart` | 专属侧边栏树（349 行） |
| `lib/services/ai/prompt_builders/sqlserver_prompt_builder.dart` | T-SQL AI 提示（38 行） |
| `lib/services/schema_diff/schema_sync_service.dart` | DDL 语法差异处理 |
| `lib/services/sql_prompt_service.dart` | T-SQL 性能规则 |
| `lib/services/ai_agent_service.dart` | 引号字符 `"`、自增 `IDENTITY(1,1)` |

---

## 2. 连接管理

### 2.1 连接流程

```
connect(DatabaseConnection)
  ├─ dbinit()                   // 初始化 FreeTDS
  ├─ dblogin()                  // 创建登录对象
  ├─ dbsetlname(user, ...)      // 设置用户名/密码/数据库/应用名/主机名
  ├─ dbsetlshort(port, ...)     // 设置端口
  ├─ tdsdbopen(host, ...)       // 打开连接（fallback: dbopen）
  ├─ dbdead()                   // 健康检查（仅参考，不阻断）
  └─ 验证：执行 SELECT 1        // tdsdbopen 可能返回非空指针但凭证错误
     ├─ dbcmd → dbsqlexec
     ├─ dbresults → dbnextrow 循环消费结果
     └─ dbfreebuf 清理缓冲
```

### 2.2 库加载

按平台搜索 FreeTDS 共享库：
- Windows: `sybdb.dll`（当前目录 → exe目录 → 项目根目录）
- macOS: `libsybdb.dylib`（当前目录 → /opt/homebrew/lib → /usr/local/lib）
- Linux: `libsybdb.so`（当前目录 → /usr/lib）

### 2.3 FreeTDS 可选函数

以下函数在部分 FreeTDS 构建中可能不可用，代码通过 `OrNull` 版本优雅降级：
- `dbdeadOrNull` — 连接状态检查
- `dbcmdrowOrNull` — 读取第一行
- `dbrowsOrNull` — 行数统计

---

## 3. 查询执行与结果读取

### 3.1 executeQuery 流程

```
executeQuery(sql, {database?})
  ├─ useDatabase(database)      // 如果指定了数据库
  ├─ dbfreebuf()                // 清空残留命令缓冲
  ├─ dbcmd(sql)                 // 发送命令
  ├─ dbsqlexec()                // 执行
  ├─ _fetchResults()            // 读取结果 → 检测是否需分页
  │   ├─ dbresults() 循环       // 处理结果集
  │   ├─ dbcmdrow()             // 激活第一行（db-lib 标准流程）
  │   ├─ dbnextrow() 循环       // 尝试读取后续行
  │   └─ 检测 rowsRead < reportedRows → 触发分页回退
  ├─ _fetchRemainingRows()      // 分页补全（仅在 dbnextrow 失效时）
  ├─ dbcount()                  // 受影响行数
  └─ 返回 QueryResult
```

### 3.2 db-lib 调用顺序

**标准 db-lib 流程**: `dbresults → dbcmdrow（第一行）→ dbnextrow（后续行）`

必须先调用 `dbcmdrow` 激活第一行，否则 `dbdata` 返回 NULL。

### 3.3 分页回退机制（v1.0.0 新增）

**问题**: 当前 FreeTDS 构建中 `dbnextrow` 返回 FAIL(0)，仅 `dbcmdrow` 能读取第一行。

**方案**: 在 `executeQuery` 中检测首次 `_fetchResults` 返回的行数与 `dbrows` 报告的行数差距。如有差距，自动启动逐行分页：

1. 原始查询 `SELECT TOP 100 * FROM [table]` → 读取到 1 行
2. 检测 `reportedRows=100 > resultCount=1`
3. 生成分页 SQL：`SELECT * FROM [table] ORDER BY (SELECT NULL) OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY`
4. 每个分页查询通过 `dbcmdrow` 读取其首行（即目标行）
5. 合并所有行返回

**限制**:
- 仅处理 `SELECT` 开头的查询
- 不处理含子查询 ORDER BY 的复杂 SQL
- `ORDER BY (SELECT NULL)` 不保证确定性排序
- 1000 行 = 1000 次查询，性能开销较大

---

## 4. useDatabase 与 dbuse

```
useDatabase(dbName)
  ├─ _currentConnection.database == dbName → 跳过
  ├─ dbuse(dbName)
  │   ├─ SUCCEED → 更新 _currentConnection
  │   └─ FAIL → dbcancel + dbfreebuf 清理
  │       └─ executeQuery('SELECT DB_NAME()') 验证
  │           ├─ 匹配 → 更新 _currentConnection
  │           └─ 不匹配 → throw
  └─ calloc.free(dbPtr)
```

`dbuse` 在某些 FreeTDS 构建中误报 FAIL（内部 `dbnextrow` 返回 0），因此需要 `SELECT DB_NAME()` 验证。

---

## 5. 数据类型处理

### 5.1 _convertData 类型映射

| FreeTDS 类型 | Dart 类型 | 转换方式 |
|-------------|-----------|---------|
| SYBINT1/2/4/8 | int | Pointer<Int>.value |
| SYBFLT8/SYBREAL | double | Pointer<Double/Float>.value |
| SYBBIT | bool | Pointer<Uint8>.value != 0 |
| SYBMONEY/MONEY4 | String | String.fromCharCodes(bytes) |
| **SYBDATETIME/DATETIME4/DATETIMN** | **String** | **二进制结构解析 → `yyyy-MM-dd HH:mm:ss`** (v1.1.3 修复) |
| SYBNUMERIC/DECIMAL | String | String.fromCharCodes(bytes) |
| SYBBINARY/VARBINARY/IMAGE | Uint8List | asTypedList |
| SYBCHAR/VARCHAR/TEXT | String | `_decodeStringBytes`（优先 UTF-8） |
| **SYBNVARCHAR/NCHAR/NTEXT** | **String** | **优先 UTF-8 解码，失败则 UTF-16LE** (v1.1.3 修复) |

### 5.2 Unicode 修复（v1.0.0 / v1.1.3）

**v1.0.0 修复前**：`SYBNVARCHAR` 等 Unicode 类型使用逐字节 `String.fromCharCodes`，导致 `"brands"` 显示为 `"b\0r\0a\0n\0d\0s\0"`。

**v1.0.0 修复后**：使用 `Uint16List.view` 正确解码 UTF-16LE：
```dart
final codeUnits = dataPtr.cast<Uint16>().asTypedList(dataLen ~/ 2);
return String.fromCharCodes(codeUnits);
```

**v1.1.3 改进**：FreeTDS DB-Library 在 Windows 构建中可能将 `SYBNVARCHAR` 数据以 **UTF-8 单字节流** 返回（而非标准 UTF-16LE）。由于 UTF-16LE 的中文字节流几乎不可能通过 UTF-8 验证，因此改为 **优先尝试 UTF-8 解码**，失败后再回退到 UTF-16LE。同时 `dataLen` 为奇数时直接判定为 UTF-8。

---

## 6. SQL 方言特性

| 特性 | SQL Server | MySQL |
|------|-----------|-------|
| 行限制 | `SELECT TOP N` | `LIMIT N` |
| 分页 | `OFFSET N ROWS FETCH NEXT N ROWS ONLY` | `LIMIT N OFFSET M` |
| 标识符 | `[bracket]` 或 `"` | `` ` `` |
| 自增 | `IDENTITY(1,1)` | `AUTO_INCREMENT` |
| EXPLAIN | `SET SHOWPLAN_XML ON` | `EXPLAIN` |
| 默认端口 | 1433 | 3306 |
| 默认用户 | `sa` | `root` |

---

## 7. Sidebar 树

SQL Server 有专属 `SqlServerTreeBuilder`（区别于 MySQL/PostgreSQL 通用构建器），提供三个全局节点：

| 节点 | 数据来源 |
|------|---------|
| 服务器状态 | 版本、Edition、用户连接数 |
| 进程列表 | `sys.dm_exec_sessions` |
| 用户 | `sys.sql_logins` |

---

## 8. 测试

| 类型 | 文件 | 用例数 | 状态 |
|------|------|--------|------|
| 单元测试 | `test/services/adapters/sqlserver_adapter_test.dart` | 51 | ✅ |
| 集成测试 | `integration_test/sqlserver_integration_test.dart` | 41 | ✅ |
| 人工测试 | 已归档（权威内容见 `unified_test_spec.md §5.8`） | 74 | 待验证 |

集成测试配置：`192.168.x.x:1433`，可通过环境变量 `DBMASTER_SQLSERVER_*` 覆盖。

---

## 9. 已知限制

| 限制 | 严重程度 | 说明 |
|------|---------|------|
| 分页性能 | 中 | 逐行分页，1000 行 = 1000 次往返，大表查询较慢 |
| 分页排序不确定 | 低 | `ORDER BY (SELECT NULL)` 不保证行序一致性 |
| 分页不支持复杂 SQL | 低 | 含 ORDER BY 的查询、非 SELECT 查询不触发分页 |
| 不支持触发器编辑 UI | 低 | 后端支持，前端未接入 |
| 不支持存储过程编辑 UI | 低 | 后端支持，前端未接入 |
| 不支持数据生成 UI | 低 | 需使用 SQL 脚本 |
| 不支持 Windows 集成认证 | 低 | 仅支持 SQL Server 认证 |
| FreeTDS 1.5.x varmax 读取失败 | **高** | `nvarchar(max)`/`varchar(max)`/`varbinary(max)` 列在 `dbnextrow` 时返回 `FAIL(0)`；`getTableData` 已自动 CAST 为 `nvarchar(4000)`/`varchar(8000)`/`varbinary(8000)` workaround；用户手动执行的 `SELECT *` 若包含 varmax 列会报错并提示 CAST。**feature 024 起**：FreeTDS 也会**静默截断** `(max)` 至 ~2048 字符（不报错），查询结果表对 `dbcollen>8000` 的列显示 `✂ 截断` 徽标（列级；真长度不可知。LIMIT：读全 `(max)` 需升级 FreeTDS，本轮不做） |

---

## 10. v1.1.0 TDD 修复详情

### 10.1 Schema Sync — ADD COLUMN 语法
**问题**: SQL Server 不支持 `ALTER TABLE ... ADD COLUMN`，正确语法应为 `ALTER TABLE ... ADD`。
**修复**: `schema_sync_service.dart` 中 `_generateAddColumnSql` 对 SQL Server 省略 `COLUMN` 关键字。

### 10.2 导出表结构 — INDEX 内联语法
**问题**: `CREATE TABLE ... INDEX (cols)` 不是有效 T-SQL；SQL Server 要求索引作为单独的 `CREATE INDEX` 语句。
**修复**: `buildCreateTableExportSql` 不再在 `CREATE TABLE` 中内联 `INDEX`，改为在表创建后输出 `CREATE [UNIQUE] INDEX [...]`。

### 10.3 varchar(max) 类型显示
**问题**: `INFORMATION_SCHEMA.COLUMNS.CHARACTER_MAXIMUM_LENGTH = -1` 被原样显示为 `varchar(-1)`。
**修复**: 新增 `formatColumnType` 静态方法，将 `-1` 映射为 `(max)`，如 `varchar(max)`。

### 10.4 getFunctions 遗漏函数类型
**问题**: 仅查询 `sys.objects` 的 `FN/IF/TF`，遗漏聚合函数 (`AF`)、CLR 标量函数 (`FS`)、CLR 表值函数 (`FT`)。
**修复**: 扩展查询条件为 `('FN','IF','TF','AF','FS','FT')`。

### 10.5 AI 引号字符一致性
**问题**: `SqlServerPromptBuilder.quoteChar` 为 `"`，与 SQL Server 社区惯例 `[bracket]` 不一致；`ai_agent_service.dart` 中同样使用 `"`。
**修复**:
- `SqlServerPromptBuilder.quoteChar` → `'['`
- `ai_agent_service.dart` 新增 `_quoteIdentifier()` 支持不对称引号 `[`/`]`
- **Schema Sync 保持 `"`**: 因 `_getQuoteChar` 使用对称 `$q$name$q` 模式，全局替换为 `[`/`]` 风险过高；`QUOTED_IDENTIFIER ON` 时 `"` 合法

### 10.6 getDatabaseProperties table_count
**问题**: 跨数据库统计表数量时子查询未限定目标数据库，始终返回当前连接库的表数。
**修复**: 使用 `[$dbName].sys.tables` 进行跨数据库计数。

### 10.7 renameColumn sp_rename 健壮性
**问题**: `sp_rename` 要求第一个参数为 `table.column` 字符串（无括号），但传入的表名可能已被 `[bracket]` 包裹。
**修复**: `SqlEscapeUtils` 新增 `unescapeSqlServerIdentifier` 方法；`renameColumn` 先 unescape 再调用 `sp_rename`。

### 10.8 executeSqlScript 限制文档化
**问题**: `executeSqlScript` 使用 `;` 分割脚本，不支持 SQL Server 常用的 `GO` 批处理分隔符。
**修复**: 添加 DartDoc 明确说明该限制。

### 10.9 dbcmdrow 误用导致查询首行数据错误
**问题**: `_fetchResults` 和 `_fetchRemainingRows` 中，代码在调用 `dbnextrow` 定位行指针之前，就通过 `dbcmdrow` 的返回值直接调用 `_readCurrentRow`（内部使用 `dbdata`/`dbdatlen`）。在 db-lib 规范中，`dbdata` 必须在 `dbnextrow` 定位到具体行之后才能调用；提前调用会返回未定义的内部缓冲区数据，表现为"第一列值为 0，其他列为 NULL"。
**修复**:
- 移除 `dbcmdrow` 触发的预读逻辑；`dbcmdrow` 仅保留为调试用的预检（它实际返回 `SUCCEED/FAIL`，不是行数）
- 统一使用 `dbnextrow` 读取所有行（包括第一行），然后再调用 `_readCurrentRow`
- 对第一次 `dbnextrow` 返回 `FAIL(0)` 的情况增加一次重试（与连接验证阶段逻辑一致）
- 同步修复 `_fetchRemainingRows` 中的相同问题

### 10.10 FreeTDS 1.5.x varmax 列读取失败
**问题**: FreeTDS 1.5.16（及可能的 1.5.x）在处理 `nvarchar(max)`/`varchar(max)`/`varbinary(max)` 列的行数据时，`tds72_get_varmax` 内部解析失败，导致 `dbnextrow` 返回 `FAIL(0)` 而非 `REG_ROW(-1)`。该问题不发生在 `nvarchar(n)`/`varchar(n)` 等普通变长类型上。连接状态在 `dbnextrow FAIL` 后会被破坏（socket 关闭），后续查询可能也失败。
**影响**:
- `getTableData` 执行的 `SELECT * FROM table` 若表含 varmax 列，会返回空结果
- 用户在 SQL 编辑器中手动执行含 varmax 列的 `SELECT` 也会失败
**修复**:
- **`getTableData` 自动 CAST**: 在执行数据查询前，先查询 `INFORMATION_SCHEMA.COLUMNS` 获取列类型；对 `nvarchar(max)` 自动替换为 `CAST(col AS nvarchar(4000))`，对 `varchar(max)` 替换为 `CAST(col AS varchar(8000))`，对 `varbinary(max)` 替换为 `CAST(col AS varbinary(8000))`
- **`executeQuery` varmax fallback**: SQL 编辑器中手动执行的 `SELECT` 查询若因 varmax 列失败，`executeQuery` 会自动调用 `sys.dm_exec_describe_first_result_set` 获取结果集元数据，重写查询将所有 varmax 列 CAST 为非 max 类型后重新执行
- **`_fetchResults` 友好报错**: 若 `dbnextrow` 返回 `FAIL(0)` 且未读到任何数据，同时检测到 `dbcollen > 8000` 的列，则抛出明确异常（fallback 失败时显示给用户）
- **FFI 常量补充**: 添加 `XSYBNVARCHAR=231`、`XSYBVARCHAR=167`、`XSYBVARBINARY=165`，并在 `_convertData` 中正确处理这些类型的解码（`XSYBNVARCHAR` 使用 UTF-16LE，`XSYBVARCHAR` 使用单字节字符串，`XSYBVARBINARY` 返回字节数组）

## 11. 变更记录

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-07-15 | feature 024 | **正确性地基一期**：① 日期类型 `datetime2`/`date`/`time`/`datetimeoffset` 手解 16 字节 DBDATETIME2 结构为 ISO（与 SSMS 一致）；② `money`/`smallmoney` 经 `dbconvert` 正确解码（原 `String.fromCharCodes` 乱码修复）；③ `(max)` 列查询结果显示 `✂ 截断` 徽标（列级，4 跳贯穿到 UI + 6 语言 L10n）；④ `DisconnectAware` 在连接失败路径触发 `onDisconnect`（对齐 MySQL）；⑤ EXEC 不冻结：`SET LOCK_TIMEOUT 30000` + fire-and-forget `catchError`（缺陷#2 缓解）；⑥ `implements ProcessListAdapter`（DMV 进程列表 + `KILL <spid>`）+ `implements CharsetAdapter`；⑦ 服务层 `getProcessList` 按 capability 路由。回归：8 个 live 金标准（SS-DEC/PL/CH/DISC/EXEC）全绿 |
| 2026-05-30 | v1.1.3 | **nvarchar 解码与 workaround 改进**：`SYBNVARCHAR` 改为优先 UTF-8 解码；`getTableData`/`varmax fallback` 将普通 nvarchar 的 CAST 目标从 `varchar` 改为 `nvarchar`，避免中文因 collation 不匹配变成 `?` |
| 2026-05-30 | v1.1.3 | **datetime 类型解析修复**：`SYBDATETIME`/`SYBDATETIME4`/`SYBDATETIMN` 从错误的 Latin-1 字符串解码改为正确的 TDS 二进制结构解析；未知类型（如 `datetime2`）增加 `dbconvert` 转换为字符串的回退机制 |
| 2026-05-30 | v1.1.2 | **nvarchar 读取修复**：`_convertData` 增加 UTF-8 解码；`getTableData` 扩展 nvarchar/nchar workaround；`varmax fallback` 增加重连恢复；FreeTDS 版本缺陷提示 |
| 2026-05-30 | v1.1.1 | **FreeTDS varmax 问题 workaround**：`getTableData` 自动 CAST varmax 列、`_fetchResults` 友好报错提示、补充 XSYB* FFI 常量 |
| 2026-05-30 | v1.1.0 | **TDD 修复轮**（12 项）：Schema Sync ADD COLUMN 语法、导出 INDEX 内联、varchar(max) 显示、getFunctions 遗漏类型、PromptBuilder/AI Agent 引号一致性、getDatabaseProperties table_count、renameColumn sp_rename 健壮性、executeSqlScript 文档化限制、**dbcmdrow 误用导致首行数据错误** |
| 2026-05-29 | v1.0.0 | 初始实现文档；修复 Unicode 乱码（UTF-16LE 解码）；添加逐行分页回退；修复 useDatabase 双重触发和残留结果集问题 |

---

## 12. 验证报告（2026-05-30）

### 测试环境
- **服务器**: Microsoft SQL Server 2022 (RTM-CU24-GDR) 16.0.4252.3 (X64) on Linux (CentOS 8)
- **连接**: `192.168.x.x:1433`, `sa` / `<password>`
- **FreeTDS**: v1.4.27 (Windows sybdb.dll)
- **客户端**: Windows 10 (CP936/GBK 编码)

### 测试结果汇总

| 测试类型 | 文件 | 用例数 | 结果 |
|---------|------|--------|------|
| 单元测试 | `test/services/adapters/sqlserver_adapter_test.dart` | 51 | ✅ 全部通过 |
| 集成测试 | `integration_test/sqlserver_integration_test.dart` | 41 | ✅ 全部通过 |
| 调试测试 | `test/sqlserver_*_test.dart` (多个) | - | ⚠️ 发现关键缺陷 |

### 数据库扫描结果

服务器上发现以下数据库：
- `ecommerce`：16 张表，`brands` 表有 1000 行数据
- `master`/`model`/`msdb`/`tempdb`：系统数据库
- 大量遗留 `dbmaster_test_*` 数据库（已清理）

### 发现的关键缺陷

#### 缺陷 1：FreeTDS DB-Library 无法读取 nvarchar 数据（严重程度：高）

**现象**：
- `brands.name` (nvarchar(100)) 的 `dbdatlen` 返回 **0**，数据被读取为 `null`
- 部分通过适配器创建的表（如 `test_chinese`）可以读到 nvarchar 数据，但中文显示为乱码（`æµ‹è¯•ä¸­æ–‡`）

**根因分析**：
1. FreeTDS 1.4.27 DB-Library API 在 Windows 构建中对 nvarchar 列处理存在缺陷
2. 能读到的数据实际是 **UTF-8 编码** 的字节流，但 `_convertData` 对 `SYBCHAR(type=47)` 使用 `String.fromCharCodes(bytes)`（Latin-1 逐字节解码），导致中文乱码
3. 对于 `nvarchar(max)` 列，`dbcollen=0x7fffffff`，`dbnextrow` 返回 `FAIL(0)`，连接状态被破坏

**影响范围**：
- 所有包含 nvarchar/nchar/nvarchar(max)/ntext 列的表
- 手动执行的 `SELECT *` 若包含 nvarchar(max) 列会触发 varmax fallback，但 fallback 因连接状态破坏而失败

**验证详情**：
```
// brands.name (nvarchar(100)) — dbdatlen=0，数据为 null
// brands.logo_url (varchar(255)) — 正常读取
// CAST(name AS varchar(100)) — 可读到数据，但中文变为 "??"
```

#### 缺陷 2：varmax fallback 机制在连接状态破坏后失效（严重程度：高）

**现象**：
当 `SELECT` 查询包含 `nvarchar(max)` 列时：
1. `_fetchResults` 检测到 `dbnextrow` 返回 `FAIL(0)`
2. 抛出 varmax 错误，触发 `_tryVarmaxFallback`
3. fallback 调用 `executeQuery` 发送新 SQL 时，`dbcmd` 返回失败（`发送命令失败`）

**根因**：
- `dbnextrow FAIL` 后 FreeTDS 内部 socket 连接已损坏
- 当前的 `dbcancel` + `dbfreebuf` 清理不足以恢复连接状态
- fallback 在损坏的连接上执行，必然失败

**日志**：
```
[SqlServerAdapter] varmax detected, attempting auto-cast fallback for: SELECT TOP 3 id, name, description FROM dbo.brands
[SqlServerAdapter] varmax fallback failed: Exception: 查询执行失败: Exception: 发送命令失败
```

### 已实施的修复

#### 修复 1：`_convertData` 增加 UTF-8 解码（v1.1.2 → v1.1.3 改进）
- **v1.1.2**：
  - 新增 `_decodeStringBytes` 辅助方法：优先尝试 `utf8.decode`，失败则回退到 Latin-1
  - 对 `SYBCHAR`/`SYBVARCHAR`/`SYBTEXT`/`XSYBVARCHAR` 类型统一使用 `_decodeStringBytes`
  - 对 `SYBNVARCHAR`/`SYBNCHAR`/`SYBNTEXT`/`XSYBNVARCHAR` 类型增加 UTF-8 回退检测：若 UTF-16LE 解码结果包含大量 NUL 字符，说明实际是 UTF-8 编码，回退到 `_decodeStringBytes`
- **v1.1.3 改进**：`SYBNVARCHAR` 等 Unicode 类型改为 **优先尝试 UTF-8 解码**
  - 原因：FreeTDS DB-Library 在 Windows 构建中可能将 `SYBNVARCHAR` 数据以 UTF-8 单字节流返回。原逻辑先尝试 UTF-16LE，若解码结果不含 NUL 字符则不会回退，导致中文乱码。
  - 由于 UTF-16LE 中文字节流几乎不可能通过 UTF-8 验证，`utf8.decode` 成功即可安全判定数据为 UTF-8。
  - `dataLen` 为奇数时直接跳过 UTF-16LE 尝试。
- **验证结果**：通过适配器创建的表，`cn_name` (nvarchar(100)) 中文字符 (`测试中文`) 可正确读取

#### 修复 2：扩展 `getTableData` 的 nvarchar workaround（v1.1.2 → v1.1.3 改进）
- **v1.1.2**：对所有 `nvarchar`/`nchar`/`ntext` 类型统一 CAST 为 `varchar(n)`
  - `nvarchar(max)` → `CAST(col AS nvarchar(4000))`
  - `nvarchar(n)`/`nchar(n)` → `CAST(col AS varchar(n))`
- **v1.1.3 改进**：将普通 `nvarchar`/`nchar`/`ntext` 的 CAST 目标从 `varchar` 改为 `nvarchar`
  - `nvarchar(n)`/`nchar(n)` → `CAST(col AS nvarchar(n))`
  - **原因**：CAST 为 `varchar` 时，若数据库 collation（如 `Chinese_PRC_CI_AS`）不支持某些 Unicode 字符，SQL Server 会将其替换为 `?`。保留 `nvarchar` 可避免中文丢失。

#### 修复 3：`varmax fallback` 增加重连机制（v1.1.2）
- `_tryVarmaxFallback` 捕获 `发送命令失败` 错误时，自动执行 `disconnect()` + `connect()` 恢复连接
- 重连成功后重新构建 fallback SQL 并执行
- 对 `nvarchar` 类型也纳入 fallback 的 CAST 范围

#### 修复 4：FreeTDS 版本检测提示（v1.1.2）
- 连接成功后，若 `_needsVarmaxWorkaround` 为 true，输出警告日志：
  > "当前 FreeTDS 版本 (v1.4.27) 存在已知的 nvarchar/varmax 读取缺陷，已启用自动 CAST workaround。建议升级 FreeTDS 或联系支持团队。"

### 已执行的清理

验证过程中清理了服务器上 **49 个**遗留的 `dbmaster_test_*` 测试数据库，释放了磁盘空间。
