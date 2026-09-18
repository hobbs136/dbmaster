# DbMaster PMF 测量方法

> 预提交测量方法文档 — 任何对外发帖/推广活动前必须完成。
> 基于 promotion-strategy v2.1，调整为 Server 侧遥测模型。

## 1. 队列定义

**主队列**: 冷获取 Pro（Server）试用用户。

- 触发条件: `app_first_launch` 带 tracked referrer，且 14 天内 ≥1 `db_connected`
- 队列起点: 首次 `app_first_launch` 的 UTC 日期
- **Warm exclusion**: dev/beta/自己的 install_uuid 通过服务端名单排除

## 2. 指标计算

### D7/D14/D30 留存

```
留存率 = 在窗口内有 session_reopen 的队列成员数 / 队列总成员数
窗口: ±1 自然日 UTC（D14 = 首启日+13 到 +15 自然日）
```

### 冷 Pro 转化

```
冷转化 = 完成 license 激活（machine_code + license_activated）或已核实付款
         AND 可通过 install_uuid join 到冷获取队列
（NOT entries 意向表提交——那只是归因信号，不是转化事件）
```

### Sean Ellis 问卷

```
"如果你不能再使用 DbMaster Server，你会感到……？"
选项: 非常失望 / 有些失望 / 无所谓 / 不再需要
阳性 = "非常失望"
目标: ≥40% 阳性 @ N≥40
```

## 3. N 下限与置信区间

| N 区间 | 处理 |
|---|---|
| <5 | 噪声——不报告百分比，仅记录原始计数 |
| 5-19 | 报告方向 + Wilson 95% CI |
| 20-49 | 可操作——触发决策评估 |
| ≥50 | 可信——精确决策 |

所有百分比必须附带 Wilson 95% 置信区间。

## 4. 重校准决策框架

| 触发 | 阈值 | N 下限 | 决策 |
|---|---|---|---|
| PERSEVERE (留存) | D14≥20% 或 D30≥15% | ≥20 | 继续 |
| PERSEVERE (转化) | ≥1 完成 license 激活或已核实付款 | 1 | 继续 |
| PERSEVERE (niche) | N≥5 + ≥3 用户 feature_used 横跨 ≥5 不同天 + (≥1 冷转化 或 Ellis ≥50%@N≥5) | 5+ | 继续 |
| PIVOT | ≥50 首启 AND 队列 N≥20 AND D14<8% AND 零冷转化 AND niche 不触发 | 50+ | 退回通用工具 |
| INCONCLUSIVE | 安装≥20 但留存 N 在 5-19 | 20 | 延至 W12 |
| SUNSET | 占目标受众 <0.3% 且 D14<8% | ≥80 | 收摊 |
| Sean Ellis | ≥40% "很失望" | ≥40 | 继续 |

**PERSEVERE 赢并列**——任一触发即继续。

## 5. 检查点时间线

| 时间点 | 评估 |
|---|---|
| W4 | 最早队列首次 D14 读数 |
| W8 (初级) | D14 + 冷转化 + Ellis 评估 → 触发表决策 |
| W12 (终局) | 两队列 D30 → 终局决策 |

**W12 补充规则**: 若 <80 Pro 试用安装 → PIVOT-to-generalist 或按时长硬收摊。

## 6. 诚实边界

- **纯 OSS 安装不可测**: 客户端完全离线，无遥测 → OSS 安装数依赖 GitHub clones + release DL（粗代理，非决策性）
- **OSS-to-Pro 转化率分母模糊**: 报为 RANGE，降级为 supporting 指标
- **TDengine-GUI 市场规模是判断估算**: 文档标注来源 + 置信区间
- **intl 队列需 advocate**: W8 前无 advocate → intl 腿推迟
- **Pro 用户 IP 关联存在**: telemetry install_uuid 对付费用户可 join 去匿名（已知边界，license/trial 激活即同意）
