# DbMaster 文档总览

> **入口**：从仓库根进入 `docs/`。本目录是 DbMaster 项目的权威文档中心，按主题分类组织。
> **组织原则**：每个功能/概念/流程只保留一套活跃测试用例、一套活跃设计文档。
> **最后整理**：2026-07-07

---

## 快速导航

| 我想找…… | 去这里 |
|---------|--------|
| 项目整体架构、AI 模块、UI 重设计规范 | [`architecture/`](./architecture/) |
| 某个数据库适配器的实现/规划 | [`adapters/`](./adapters/) |
| 重构/UX 分析报告 | [`refactoring/`](./refactoring/) |
| 测试规范与用例库 | [`test/`](./test/) |
| 商业化模型、定价、购买流程 | [`commerce/pricing.md`](./commerce/pricing.md) |

---

## 目录结构

```
docs/
├── README.md                         ← 本文件
├── _config.yml                       ← GitHub Pages (Jekyll) 配置
│
├── architecture/                     ← 架构与设计
│   ├── adr/                          ← 架构决策记录
│   ├── architecture_overview.md      ← 唯一权威架构总览
│   └── ui-redesign-minimalist-spec.md
│
├── adapters/                         ← 数据库适配器
│   └── sqlserver_implementation.md
│
├── commerce/                         ← 商业化（定价、素材、交接）
├── competitive/                      ← 竞品分析
├── measurement/                      ← 指标方法论
│
├── refactoring/                      ← 重构与 UX 分析
│   ├── README.md
│   └── *.md
│
├── technical/                        ← 技术笔记
├── task_general_db_agent.md          ← 活跃任务文档
│
└── test/                             ← 测试规范
    ├── README.md
    ├── unified_test_spec.md          ← 唯一权威测试用例库
    └── guides/                       ← 测试操作指南
```

---

## 各目录简介

### [`architecture/`](./architecture/) — 架构与设计
项目级架构文档。`architecture_overview.md` 是唯一权威架构总览；`ui-redesign-minimalist-spec.md` 是设计系统规范。AI 模块术语已并入 `architecture_overview.md`。

### [`adapters/`](./adapters/) — 数据库适配器
非主流数据库（SQL Server）的独立实现文档。MySQL、PostgreSQL、SQLite、MongoDB、Redis、Doris、TDengine 等适配器文档见 `architecture_overview.md`。

### [`refactoring/`](./refactoring/) — 重构与 UX 分析
UI 组件的 UX 对标分析（侧边栏、工具栏、标题栏）与整体布局审查报告。详见 [`refactoring/README.md`](./refactoring/README.md)。

### [`test/`](./test/) — 测试规范
测试规范、用例库（`unified_test_spec.md` 为唯一权威）与操作指南。详见 [`test/README.md`](./test/README.md)。

---

## 文档维护约定

1. **新增任务文档**：在 `docs/` 根目录创建 `task_<feature_name>.md`。
2. **新增架构/适配器文档**：直接放入对应主题目录（`architecture/`、`adapters/`）。
3. **新增 UX/重构分析**：放入 `refactoring/`，并在 `refactoring/README.md` 添加条目。
4. **新增测试用例**：在 `test/unified_test_spec.md` 对应章节添加，避免新增分散测试文档。

---

## 相关链接

- 仓库入口：`README.md`
- GitHub Pages 隐私政策源：本地 `dbmaster-github-pages` 仓库中的 `docs/privacy-policy.md`（路径因人而异）
