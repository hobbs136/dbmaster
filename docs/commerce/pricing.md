# DbMaster 商业化模型

> **权威文档** — 2026-07-29 定稿。客户端全免费 + Server ¥399/年订阅。

## 1. 产品形态

```
┌──────────────────────────────────────────────────────┐
│        DbMaster Desktop — 完全免费                    │
│                                                      │
│  查询编辑器  ·  Schema 浏览器  ·  8 种数据库连接       │
│  Cockpit DDL 影响分析  ·  EXPLAIN 索引推荐            │
│  慢查询诊断面板  ·  手动 Data Sync                    │
│  AI Agent（工具循环）· AI 对话（多轮/流式/推理）       │
│  Schema Diff 同步  ·  Data Import                    │
│  SSH 隧道  ·  MongoDB 集群  ·  数据导出               │
│                                                      │
│  全部功能 — 零付费墙 — 无限连接/Tab/AI 使用            │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  每个手动操作 = Server 自动化的一次广告          │  │
│  │  "定时自动跑这个 → 部署 DbMaster Server"        │  │
│  └────────────────────────────────────────────────┘  │
│                          ↓                           │
│              DbMaster Server ¥399/年/实例              │
│                                                      │
│  🤖 自动化引擎                                        │
│  ├── 定时 Data Sync（分页/重试/失败通知）              │
│  ├── 定时健康巡检（缺索引/表膨胀/连接状态/报告）       │
│  ├── 慢查询周报（TOP N + EXPLAIN + 索引建议）          │
│  └── Schema 变更检测（即时告警）                       │
│                                                      │
│  👥 团队协作                                          │
│  ├── 共享连接（一人配，全员用）                        │
│  ├── 团队查询库（保存/搜索/标签）                      │
│  ├── DDL 审批流程（1-2 人审批）                        │
│  └── 活动日志（谁干了什么）                            │
│                                                      │
│  🔔 通知：Slack / Email / Webhook                     │
└──────────────────────────────────────────────────────┘
```

## 2. 定价

| 产品 | 价格 | 说明 |
|---|---|---|
| DbMaster Desktop | **免费** | 全功能，零付费墙，8 种数据库，无限连接/Tab/AI |
| DbMaster Server | **¥399/年/实例** | 定时自动化 + 团队协作。一个实例覆盖一个团队的所有数据库 |

### 常见问题

**Q: Desktop 以后会收费吗？**
A: 不会。Desktop 是永久免费产品，所有数据库连接和 AI 功能都不限量。这是承诺，不是限时优惠。

**Q: 谁需要 Server？**
A: 没有专职 DBA 的 2-5 人开发团队。如果你每天手动做 Data Sync、每周手动查慢查询、担心有人改表结构没人知道——Server 替你自动化这些。

**Q: Server 怎么部署？**
A: Docker 单容器部署在你自己的服务器上（或任何 Linux VPS）。数据库凭证只存在你的服务器里，不上传第三方。

**Q: 怎么购买？**
A: 访问 [dbmaster.tech](https://dbmaster.tech) 提交购买表单 → 付款确认 → 自动签发 Ed25519 离线 license → 导入 Server 即可激活。license 绑定机器指纹，支持换绑。

**Q: 有试用吗？**
A: Desktop 完全免费——你可以先用 Desktop 的手动操作体验所有功能。当你觉得"这个操作要是能定时自动跑就好了"的时候，就是 Server 的试用场景。

## 3. 废弃的历史策略（仅供参考）

以下策略已在 2026-07-29 废弃：

| 废弃策略 | 日期 | 废弃原因 |
|---|---|---|
| Free/Pro 门禁 | 2026-07-29 | Desktop 全免费，无需门禁 |
| MAS 订阅 (IAP) | 2026-07-29 | Desktop 不收费，不上 App Store 订阅 |
| 桌面端离线 license | 2026-07-29 | Desktop 不需要 license |
| 双仓 Pro fork | 2026-07-29 | Pro 功能全部在 public 仓免费开放 |
| OSS 分发渠道（open-core 部分） | 2026-07-29 | 不再区分 OSS/Pro，分发渠道策略仍适用 |

## 4. 相关文档

- ADR 0001（已 superseded）：`docs/architecture/adr/0001-tier-freeze.md`
- macOS 沙盒技术笔记：`docs/technical/macos_sandbox_notes.md`
- DBX 副业可行性决策：`.workflows/dbx-side-business-feasibility/03-recommend.md`
