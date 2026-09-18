# 侧边栏树形结构审查

> 对比基准：DBeaver、TablePlus、DataGrip、Navicat
> 审查日期：2026-06-10

---

## 一、各数据库类型树形结构一览

### 1. MySQL / Doris

```
🗄️ MySQL Connection
├── 📁 mydb  (15t 3v 2p)         ← DB 概要徽章 ✅
│   ├── 📋 Tables (15)           ← 行数徽章 ✅
│   │   ├── 📋 users    1.2K     ← 表名 + 行数 ✅
│   │   │   ├── 📝 id INT [PK] [NN] [= auto_increment]  ← 列详情 ✅
│   │   │   ├── 📝 name VARCHAR(100) [NN] [= '']
│   │   │   ├── 🔑 PRIMARY (id)
│   │   │   └── 🔗 fk_user_role (user_id → roles.id)
│   │   └── 📋 orders   15K
│   ├── 👁️ Views (3)
│   │   ├── 👁️ active_users
│   │   └── 👁️ order_summary
│   ├── ⚙️ Procedures (2)
│   │   ├── ▶ sp_create_order
│   │   └── ▶ sp_cleanup
│   └── ⚡ Triggers (1)
│       └── ⚡ trg_audit_log  (BEFORE INSERT)
├── 📁 test_db                   ← DB 概要徽章 ✅
├── ──────────────────────────────────────────────   ← 分隔线
├── 🖥️ Server                    ← 全局节点 ✅
│   ├── ℹ️ MySQL 8.0.35
│   ├── ⏱️ Uptime: 12d 3h 15m
│   ├── 👥 15 active / 2 running
│   ├── 📊 1.5M queries
│   └── 🎛️ Max Connections: 151 | Buffer Pool: 128M | Charset: utf8mb4
└── 📊 Performance              ← 全局节点 ✅
    ├── root • Sleep • 0s
    ├── app • Query • 2m 30s    ← 长查询黄色 ⚠️
    └── ... and 12 more
```

**信息量**：⭐⭐⭐⭐ 很丰富
**视觉效果**：TreeItem 统一组件，层级缩进清晰，emoji + icon 混合
**缺失**：系统数据库（mysql, sys, performance_schema）无特殊标注（兄弟 module 之前修了 `_isSystemDatabase` 但仅限 DB 名称加方括号，MySQL 全局节点未区分）

---

### 2. PostgreSQL

```
🗄️ PostgreSQL Connection
├── 📁 [pg_catalog]              ← 系统库方括号 ✅
├── 📁 mydb  (12t 4v 1p)         ← DB 概要 ✅
│   ├── 📋 Tables (12)
│   │   └── 📋 users    5.2K     ← 行数 ✅
│   ├── 👁️ Views (4)
│   └── ⚙️ Procedures (1)
├── 🖥️ Server                    ← 全局节点 ✅ 已修复
│   ├── ℹ️ PostgreSQL 16.3
│   ├── ⏱️ Uptime: 5d 12h
│   ├── 👥 8 connections
│   ├── 📦 256 MB
└── 📊 Process List              ← 全局节点 ✅ 已修复
    ├── postgres · psql (active)
    └── app_user · app (idle)
```

**信息量**：⭐⭐⭐⭐ 全局节点已补充
**视觉效果**：TreeItem，`dbPostgresql` 蓝色系 ✅
**缺失**：无（已修复）

---

### 3. SQL Server

```
🗄️ SQL Server Connection
├── 📁 mydb  (8t 2v 3p)         ← DB 概要 ✅
│   ├── 📋 Tables (8)
│   └── ...（标准 SQL 对象树）
├── ──────────────────────────
├── 🖥️ Server Status            ← 全局节点 ✅
│   ├── version: 2019
│   ├── edition: Enterprise
│   ├── user_connections: 25
│   └── blocked_requests: 0
├── 📋 Process List              ← 全局节点 ✅
│   ├── SSMS (sleeping)  SPID: 52 | DB: master
│   └── ... (最多10条)
└── 👥 Users                     ← 全局节点 ✅
    ├── sa  (SQL_LOGIN)
    └── app_user  (SQL_LOGIN)
```

**信息量**：⭐⭐⭐⭐ 完整
**视觉效果**：TreeItem ✅（已统一，之前用 ListTile）

---

### 4. SQLite

```
🗄️ SQLite Connection             ← 无 DB 层（扁平化 ✅）
├── 📋 Tables (5)
│   └── 📋 users  (3 cols)
│       ├── 📝 id INTEGER [PK]
│       └── 📝 name TEXT
├── 👁️ Views (2)
├── 🔑 Indexes (4)
├── ⚡ Triggers (1)
└── ──────────────────────────
    └── 📊 Database Info
        └── ℹ️ SQLite 3.43.1
```

**信息量**：⭐⭐⭐ 扁平化设计适合单文件数据库
**视觉效果**：L2 直接显示对象分类（跳过 DB 层），节省一层缩进
**缺失**：无行数显示（SQLite 表行数需要 COUNT，成本较高但可实现）

---

### 5. MongoDB

```
🗄️ MongoDB Connection
├── 📁 mydb  (3c)                ← c=collections, DB 概要 ✅
│   ├── 📦 Collections (3)       ← 自己命名 Collections ✅
│   │   ├── 📦 users   1.2K      ← 文档计数 ✅
│   │   │   ├── 📄 {_id: ObjectId, name: String, ...}  ← Schema ✅
│   │   │   └── 🔑 Indexes (2)
│   │   └── 📦 orders
│   ├── 👁️ Views (1)
│   └── 📁 GridFS Buckets (1)
├── ──────────────────────────
└── 🖥️ Server                    ← 全局节点 ✅
    ├── ℹ️ MongoDB 7.0.5
    ├── 💻 Host: localhost:27017
    ├── ⏱️ Uptime: 3d 5h
    └── 💾 Storage: wiredTiger
```

**信息量**：⭐⭐⭐⭐ 完整，Schema 推断是亮点
**视觉效果**：TreeItem 组件，颜色 `dbMongodb` 绿色系 ✅
**缺失**：刚刚修复了展开问题，现在可正常使用

---

### 6. Redis

```
🗄️ Redis Connection
├── 📁 db0                        ← Redis DB 节点
│   ├── 🔑 Keys (1.2K)           ← 类型采样 ✅
│   │   ├── 📝 String (500)
│   │   │   ├── 🔑 user:1:name
│   │   │   ├── 🔑 user:2:name
│   │   │   └── 🔑 config:global
│   │   ├── 📊 Hash (300)
│   │   ├── 📋 List (200)
│   │   ├── 👥 Set (100)
│   │   ├── 📈 Sorted Set (80)
│   │   └── 📡 Stream (20)
│   ├── 📁 Namespaces            ← 命名空间分析 ✅
│   │   ├── 🏷️ user: (250)
│   │   ├── 🏷️ cache: (180)
│   │   └── 🏷️ session: (100)
│   └── ⏱️ Expiring Soon         ← TTL 监控 ✅
├── ──────────────────────────
└── 🖥️ Server                    ← 全局节点
    ├── ℹ️ redis_version: 7.2
    ├── 💾 used_memory_human: 256MB
    ├── 👥 connected_clients: 42
    └── 📊 total_commands_processed: 1.5M
```

**信息量**：⭐⭐⭐⭐⭐ 最丰富——类型分布 + 命名空间 + TTL 三维护分析
**视觉效果**：TreeItem，`dbRedis` 红色系 ✅
**缺失**：全局节点在分隔线以下是空的（未展开时无内容提示）

---

### 7. Snowflake

```
🗄️ Snowflake Connection
├── 📁 mydb  (5t 2v)             ← DB 概要 ✅
│   └── ...（标准 SQL 对象树）
├── ──────────────────────────
├── 💾 Warehouse Info            ← 全局节点 ✅
│   ├── Warehouse: COMPUTE_WH
│   ├── Database: MYDB
│   └── Schema: PUBLIC
├── ⚙️ Session Info              ← 全局节点 ✅
│   ├── Timezone: America/LA
│   └── Autocommit: true
└── 👥 Users & Roles             ← 全局节点 ✅
    ├── Users
    │   └── ANALYST (Active)
    └── Roles
        └── SYSADMIN (Granted: 3)
```

**信息量**：⭐⭐⭐ Warehouse/Session 信息独特且有用
**视觉效果**：TreeItem ✅（已统一，之前用 ListTile）

---

### 8. Elasticsearch

```
🗄️ Elasticsearch Connection
├── 📁 my_index  (3t)            ← ES 索引作为 DB
│   └── ...（标准 SQL 对象树）
├── ──────────────────────────
├── 🖥️ Cluster Health           ← 全局节点 ✅
│   ├── status: connected
│   ├── version: 8.11
│   └── luceneVersion: 9.8
├── 💾 Indices                   ← 全局节点 ✅
│   ├── my_index (index)
│   └── logs-2024 (index)
└── 🌐 Nodes                     ← 全局节点 ✅
    ├── indices: 15
    ├── documents: 1.2M
    └── storeSize: 5.20 GB
```

**信息量**：⭐⭐⭐
**视觉效果**：TreeItem ✅（已统一，之前用 ListTile）

---

### 9. TDengine

```
🗄️ TDengine Connection
├── 📁 mydb
│   ├── 🟣 SuperTables (2)
│   │   └── 📁 meters  (4 cols, 3 tags)
│   │       ├── 📝 ts TIMESTAMP [PK]
│   │       ├── 📝 current FLOAT
│   │       ├── 📝 voltage INT
│   │       ├── 📝 phase FLOAT
│   │       ├── 🏷️ location VARCHAR
│   │       ├── 🏷️ group_id INT
│   │       └── 🏷️ model VARCHAR
│   └── 📋 Tables (10)
│       └── (标准 SQL 树)
```

**信息量**：⭐⭐⭐⭐ SuperTable 的列+标签层次展示很好
**视觉效果**：TreeItem，`dbTDengine` 紫色系 ✅

---

## 二、全局问题汇总

### 已修复 ✅ (2026-06-10)

| # | 问题 | 修复 |
|---|------|------|
| 1 | SqlServerTreeBuilder 用 ListTile | 改为 TreeItem(level: 2) |
| 2 | SnowflakeTreeBuilder 用 ListTile | 改为 TreeItem(level: 2) |
| 3 | ElasticsearchTreeBuilder 用 ListTile | 改为 TreeItem(level: 2) |
| 4 | 硬编码 contentPadding | 统一为 TreeItem level 缩进系统 |
| 5 | PostgreSQL 无全局节点 | 新增 postgresql_tree_builder.dart |
| 6 | 全局节点键盘不可达 | _addGlobalNodeKeys() 收录所有全局节点 |

### 🟡 待处理

| # | 问题 | 影响 |
|---|------|------|
| 8 | 无索引/外键"单击跳转到定义" | DBeaver 双击索引名可跳转到关联表 |
| 9 | SQLite DB Info 用硬编码 Padding 而非标准 level | 视觉不一致 |

### 🟢 细节（已验证，无需修改）

| # | 说明 |
|---|------|
| 7 | Redis 全局节点已完整实现（Server/Memory/Stats/Config/SlowLog，均用 TreeItem 渲染） |
| 10 | MongoDB Server Info 已有实时数据渲染 |
