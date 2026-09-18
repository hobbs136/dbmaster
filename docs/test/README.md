# DbMaster 测试文档总索引

**版本**: v3.4.0  
**日期**: 2026-07-15  
**适用范围**: DbMaster v3.2.0+  
**自动化覆盖**: ~3,235 单元/Widget 用例 / 210 测试文件；含集成约 ~3,753 用例 / 233 测试文件

---

## 📁 目录结构（路径已统一）

所有测试用例文档集中在 `docs/test/`，布局固定：

```
docs/test/
├── README.md                 # 本索引
├── unified_test_spec.md      # 🎯 唯一权威测试用例规格
└── guides/                   # 操作指南（如何写/跑测试）
    ├── integration_test_authoring_guide.md
    └── soak_test_procedure.md
```

> **路径约定**：新增测试用例一律加到 `unified_test_spec.md`，**禁止**新建 per-feature / per-database 测试文档；新操作指南放 `guides/`。

---

## 📋 核心文档

| # | 文档 | 用途 |
|---|------|------|
| 1 | **[unified_test_spec.md](./unified_test_spec.md)** | 🎯 唯一权威测试入口（自动化 + 人工） |
| 2 | [README.md](./README.md)（本文档） | 文档导航 |
| 3 | **[architecture_overview.md](../architecture/architecture_overview.md)** | 项目架构全景 |
| 4 | [guides/integration_test_authoring_guide.md](./guides/integration_test_authoring_guide.md) | 集成测试编写指南 |
| 5 | [guides/soak_test_procedure.md](./guides/soak_test_procedure.md) | 长时 soak 测试流程 |

运行/验收报告属一次性内部产物，不入开源仓库。

---

## 🗂️ 快速导航（按功能域）

### 核心基础设施
- 主题系统 → `unified_test_spec.md §2.1`
- 国际化 → `unified_test_spec.md §2.2`
- 快捷键 → `unified_test_spec.md §2.3`
- 设置 → `unified_test_spec.md §2.4`

### 状态管理
- Providers → `unified_test_spec.md §3`

### 数据模型
- Models → `unified_test_spec.md §4`

### 数据库适配器
- MySQL → `unified_test_spec.md §5.1`
- PostgreSQL → `unified_test_spec.md §5.2`
- MongoDB → `unified_test_spec.md §5.3`
- Redis → `unified_test_spec.md §5.4`
- SQLite → `unified_test_spec.md §5.5`
- Doris → `unified_test_spec.md §5.6`
- TDengine → `unified_test_spec.md §5.7`
- SQL Server → `unified_test_spec.md §5.8`
- Elasticsearch → `unified_test_spec.md §5.9`
- Snowflake → `unified_test_spec.md §5.10`

### AI 系统
- AI 基础服务 → `unified_test_spec.md §6.1`
- AI 高阶服务 → `unified_test_spec.md §6.2`
- AI Panel UI → `unified_test_spec.md §6.3`

### SQL 与查询
- 查询服务 → `unified_test_spec.md §7`
- 查询优化器 → `unified_test_spec.md §7.3`

### Schema / ER / 导入导出
- Schema 分析 → `unified_test_spec.md §8.1`
- Schema Diff → `unified_test_spec.md §8.2`
- ER 图 → `unified_test_spec.md §8.3`
- 导入/导出/备份 → `unified_test_spec.md §8.4`

### 安全与认证
- 安全 → `unified_test_spec.md §9`

### UI 组件
- Atoms/Molecules → `unified_test_spec.md §10`
- 编辑器 → `unified_test_spec.md §11`
- 结果展示 → `unified_test_spec.md §12`
- 侧边栏 → `unified_test_spec.md §13`
- 连接/对话框 → `unified_test_spec.md §14`
- AI/Entity/Task 面板 → `unified_test_spec.md §15`

### 页面与端到端
- 页面/屏幕 → `unified_test_spec.md §16`
- 集成测试 → `unified_test_spec.md §19`
- 用户旅程 → `unified_test_spec.md §20`
- 回归测试 → `unified_test_spec.md §21`

---

## ✅ 回归测试执行清单

### 1. 单元测试全量
```bash
flutter test
```

### 2. 代码分析
```bash
flutter analyze lib/
dart analyze lib/
```

### 3. 核心集成测试
```bash
flutter test integration_test/mysql_integration_test.dart
flutter test integration_test/postgresql_integration_test.dart
flutter test integration_test/sqlite_integration_test.dart
flutter test integration_test/doris_integration_test.dart
flutter test integration_test/export_backup_test.dart
flutter test integration_test/schema_diff_sync_test.dart
flutter test integration_test/user_journey_test.dart
```

### 4. 手动回归测试（必须）
参见 `unified_test_spec.md §21` 回归测试清单。

---

## 📦 归档说明

历史分散测试文档已整合至 `unified_test_spec.md`；归档副本属内部文档，不入开源仓库。

---

## 📝 文档维护规范

1. **新增功能** → 在 `unified_test_spec.md` 对应章节添加测试用例；禁止新增独立的 per-feature 测试文档。
2. **新增自动化测试** → 更新 `unified_test_spec.md` 中对应模块的测试状态。
3. **发现覆盖缺口** → 在 `unified_test_spec.md` 中添加 `🔴 待补充` 条目。
4. **测试用例编号**: 遵循 `[层级]-[模块]-[序号]` 格式（如 `AD-MYSQL-001`）。
5. **优先级标记**: P0（阻塞发布）/ P1（影响体验）/ P2（可延后）/ P3（未来）。
6. **新指南落点**: 操作指南 → `guides/`，用例 → `unified_test_spec.md`（运行报告属内部文档）。

---

## 🔗 其他相关文档

- [架构全景文档](../architecture/architecture_overview.md) — 项目完整架构、30+ 功能模块

---

*最后更新: 2026-07-15*
