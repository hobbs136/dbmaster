# 重构与 UX 分析

UI 组件的 UX 对标分析与整体布局审查报告。

| 文件 | 范围 | 日期 | 状态 |
|------|------|------|------|
| `sidebar_ux_analysis.md` | 左侧导航树 UX 优化计划（对比 DBeaver/TablePlus/DataGrip/Navicat/Azure Data Studio/pgAdmin） | 2026-06-09 | 9/10 完成（功能 8 多选批量操作跳过） |
| `layout_review.md` | 整体窗口布局、组件拆分、交互体验、视觉一致性、响应式设计审查 | 2026-06-09 | 14 项优化 + 2 个 bug 修复完成（`9615eee`） |
| `sidebar_tree_review.md` | 侧边栏树形结构审查 | 2026-06-10 | 9 项问题跟踪完成 |
| `header_ux_analysis.md` | Title 栏菜单 UX 分析（对比 DBeaver/TablePlus/DataGrip/VS Code/Figma） | 2026-06-10 | 已落地 |
| `toolbar_ux_analysis.md` | 查询工具栏 UX 分析（对比 DBeaver/TablePlus/DataGrip/Navicat） | 2026-06-10 | 已落地 |
| `product_pain_point_analysis.md` | 产品痛点深度改进方案 — 三大支柱：执行安全网 / Schema Diff 闭环 / 结果到洞察的分析闭环 | 2026-07-08 | 待执行 |
| `ui_color_audit.md` | 配色与视觉 UI 对标审查（DataGrip/Navicat/TablePlus/VS Code/GitHub Dark，40 条经核实的差距 + 三批修复路线图） | 2026-07-23 | 全部三批已落地（批次1/2 合 master；批次3 为设计令牌统一专项，accent 变体选定 A） |

> 这些文档保留作为历史设计依据，与代码现状一致。`layout_review.md` 中关于 AI 浮层拖拽手柄的描述与最新 8 向实现方向一致。