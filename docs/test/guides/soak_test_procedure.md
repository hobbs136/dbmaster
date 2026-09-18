# DbMaster 8小时稳定性测试流程

**目的**：为 `REG-M007`（8 小时稳定性，见 `unified_test_spec.md §21`）等稳定性用例提供可执行、可量化的验证。
**适用范围**：DbMaster v3.2.0+（Windows 桌面版，其他平台可参考）
**作者工具**：`scripts/uitest/soak.py` + `scripts/capture_window.py`（已存在）

---

## 1. 文档立场

`unified_test_spec.md §21` 把 8 小时稳定性（`REG-M007`）标记为 **"仅人工 / 无法自动化"**。这种描述低估了工具能力。

实际上：
- **真正的 8 小时"什么都不做等"是浪费** —— 静止应用不暴露 leak，必须混合 UI 操作。
- **操作系统级指标可以全程采样** —— 内存、句柄、UI 假死、错误计数。
- **可以分 3 档** —— L1/L2/L3 适配不同 CI/发版场景。
- **失败判定可量化** —— 内存/句柄增长阈值明确。

本文档给出三档方案 + 自动跑工具 + 量化判定。

---

## 2. 测试分级

| 等级 | 时长 | 采样间隔 | 动作间隔 | 适用场景 | 入口 |
|---|---|---|---|---|---|
| **L1 Smoke** | 10 min | 10 s | 5 s | 提交/CI gate | `python scripts/uitest/soak.py` |
| **L2 Standard** | 60 min | 15 s | 10 s | 夜间任务 | `python scripts/uitest/soak.py -d 60 -i 15 -a 10` |
| **L3 Release** | 480 min (8h) | 30 s | 30 s | 发版前周末 | `python scripts/uitest/soak.py -d 480 -i 30 -a 30` |

注：
- 动作间隔越短，操作密度越大，暴露问题越快。L1 的 5s 间隔在 10 分钟内跑 100+ 动作，相当于 L3 的 8 小时。
- 8 小时 (L3) 主要意义是覆盖**长周期才出现的资源回收问题**（GC 周期、缓存刷新、Provider 重建）。

---

## 3. 监测指标

每 `interval` 秒采样一次进程级数据：

| 指标 | 来源 | 健康范围（10 分钟） | 含义 |
|---|---|---|---|
| `Working Set (KB)` | `GetProcessMemoryInfo` | 漂移 < ±30% | 当前物理内存占用 |
| `Peak Working Set (KB)` | 同上 | 单调 | 启动以来最高占用 |
| `Pagefile Usage (KB)` | 同上 | 不持续上涨 | 内存压力 |
| `Page Fault Count` | 同上 | 斜率稳定 | 缓存命中率 |
| `GDI Handles` | `GetGuiResources(0)` | 185 ± 20 | GDI 对象泄漏（如未释放的 widget） |
| `USER Handles` | `GetGuiResources(1)` | 70 ± 10 | USER 对象泄漏（窗口/控件） |
| `IsHungAppWindow` | `IsHungAppWindow` | 永不为 true | UI 线程假死 |
| `actions_executed` | 计数器 | 与预期吻合 | UI 响应次数 |

输出位置：`screenshots/ui_test/soak/metrics.csv` + `metrics.json`。

---

## 4. 操作剧本（每轮自动跑）

```
主题切换     | settings    | 缩放1280    | 缩放1920
命令面板     | conn_0      | new_tab     |
AI 面板      | conn_1      | close_tab   |
```

11 个动作轮换执行，每个间隔 `action_every` 秒。覆盖：
- 主题切换（视觉切换 + 资源重建）
- 各种 Dialog 打开/关闭
- 连接切换（多 Provider 重建）
- Tab 生命周期（最易出 leak 的地方）
- 窗口缩放（LayoutProvider 重建）

不点击会产生真实 DB 流量或 AI 调用的按钮 —— 避免外部依赖污染指标。

---

## 5. 通过/失败判定

```
PASS 当且仅当所有下列条件成立：
  - 内存 Working Set 末值较首值变化在 ±50% 以内
  - GDI Handles 末值较首值增长不超过 100%
  - USER Handles 末值较首值增长不超过 100%
  - 全程 IsHungAppWindow = false
  - 末 30% 样本的内存斜率 < 1 KB/s
```

判定在 `scripts/uitest/soak.py:verdict()` 中。

---

## 6. 跑 L1 Smoke (10 分钟)

```bash
$env:PYTHONIOENCODING="utf-8"
$env:PYTHONUTF8="1"
python scripts\uitest\soak.py
```

**预期**：
- 33 张快照写入 `screenshots/ui_test/soak/`
- 30 行以上 CSV
- 报告 `screenshots/ui_test/soak/soak_report.md`
- 退出码 0 (PASS) 或 1 (FAIL)

> 验证跑（3 分钟）已确认基础设施工作：ws_delta -19.1%, GDI 0%, USER 0%, 0 hung。详见 `screenshots/ui_test/soak/soak_report.md` 中 2026-06-30 17:39 的 run。

---

## 7. 跑 L2 Standard (1 小时)

```bash
python scripts\uitest\soak.py -d 60 -i 15 -a 10
```

适合夜间任务。早上看报告。

---

## 8. 跑 L3 Release (8 小时)

```bash
python scripts\uitest\soak.py -d 480 -i 30 -a 30
```

需要：
- 不锁屏 / 不睡眠（设置 `powercfg /change standby-timeout-ac 0`）
- 关闭 Windows 自动更新窗口
- 后台无其他重负载
- 周末或长假无人值守时跑

---

## 9. 历史 bug 案例（可作为泄漏检测参考）

内部 bug 记录（PurchaseProvider 流泄漏案例）描述了真实案例：
- `PurchaseProvider.dispose()` 未取消 `StreamSubscription`
- 每次 `pumpWidget` 重建 Provider 都泄漏一个 listener
- 集成测试日志出现 `Bad state: Stream has already been listened to`

如果 L2+ 跑动后报告出现：
- USER handles 单调上涨（每次操作 +1~3）→ 立刻看 `lib/providers/*` 的 `dispose()` 是否漏 `cancel()`
- GDI handles 单调上涨 → 看 dialog/widget 是否漏 `dispose()`
- Working Set 单调上涨 + 末段斜率高 → 怀疑 Dart heap 泄漏，可用 `flutter run --observatory-port=...` 进一步分析

---

## 10. 与现有文档的差异

| 项目 | 现有文档 | 本流程 |
|---|---|---|
| 时长 | 8h 固定 | 10min / 1h / 8h 三档 |
| 自动化 | 仅人工 | 进程指标 + 操作 + 判定全自动化 |
| 通过标准 | "内存/响应" | 量化阈值（5 个指标） |
| 输出 | 主观判断 | Markdown 报告 + CSV + JSON + 截图 |
| 历史对照 | 无 | 与内部 bug 记录关联 |

建议下次更新 `unified_test_spec.md §21` 时把 `REG-M007` 标为 **"可用本流程半自动覆盖"**，并指向本文件。
