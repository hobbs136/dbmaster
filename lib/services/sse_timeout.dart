/// SSE 主查询通道三层共享超时（sleep-resume 修复批 T3）。
///
/// 三层语义与取值锚定（论证全文见 `.specs/tasks-sleep-resume-fix.md` D3——
/// **禁止一刀切 total timeout 覆盖慢查询**，SSE 长流上健康慢查询合法地跑
/// 几分钟）：
///
/// | 层 | 语义 | 取值 | server 侧证据 |
/// |---|---|---|---|
/// | 首字节 first-byte | `client.send()` → 响应头到达 | 30s | handler 立即返回 SSE 响应（查询在 spawn 任务里跑，`gateway/src/handlers.rs:410-421`），头部到达 = RTT 级，30s 覆盖慢 WAN |
/// | 空闲 idle | 行流上任意一行（含 `:` keep-alive 注释行）到达即重置看门狗 | 45s | server 每 15s 发一条 SSE keep-alive（`handlers.rs:420` `KeepAlive::new().interval(15s)`），45s = 3× 间隔，容忍丢 2 条 |
/// | 总兜底 total | 整个 send→drain 的绝对上界 | `timeoutMs + 30s`；缺省 630s | statement timeout 钳 `[1s, 600s]`（`handlers.rs:149-150`；缺省 `gw_query_timeout_secs`=30s，`core/src/config.rs:217`）；+30s buffer 覆盖 complete 事件后 server 侧 registry 清理 + 审计落库尾部时延。缺省时无法预知部署方覆写，取钳上限 600s+30s。此层是「server 只发 keep-alive 永不终态」的极端病态兜底，健康路径永不触发 |
///
/// **耦合提醒（server 侧调整时同步复核）**：idle 须 ≥ 3× server keep-alive
/// 间隔（当前 15s）；server 改 keep-alive 周期时须同步复核 [idle] 取值。
///
/// [firstByte]/[idle] 为可变 static 而非 const：供测试注入缩短值（生产代码
/// 只读，勿写）。
library;

import 'dart:async';

/// SSE 主查询通道三层超时常量 + 带层名的 TimeoutException 工厂。
///
/// 层名（first-byte / idle / total）进异常消息，取证时区分挂死形态
/// （server accept 不响应 / 流中途停发 / 只发 keep-alive 永不终态）。
class SseTimeouts {
  SseTimeouts._();

  /// 首字节（`client.send` → 响应头到达）超时：30s。
  ///
  /// 可变 static（非 const）：仅供测试注入缩短值；生产代码只读，勿写。
  /// 注：不加 `@visibleForTesting`——9 处生产消费方跨文件引用，注解会
  /// 产生 invalid_use_of_visible_for_testing warning（实证见 T3）。
  static Duration firstByte = const Duration(seconds: 30);

  /// 空闲超时：45s。行流上任意一行（含 `:` keep-alive 注释行）到达即重置。
  ///
  /// 可变 static（非 const）：仅供测试注入缩短值；生产代码只读，勿写。
  static Duration idle = const Duration(seconds: 45);

  /// server statement timeout 钳制上限（`handlers.rs:149-150`）：600s。
  ///
  /// 可变 static（非 const）：仅供测试注入缩短值；生产代码只读，勿写。
  static Duration serverCeiling = const Duration(seconds: 600);

  /// total 层尾部 buffer（complete 后 registry 清理 + 审计落库时延）：30s。
  ///
  /// 可变 static（非 const）：仅供测试注入缩短值；生产代码只读，勿写。
  static Duration buffer = const Duration(seconds: 30);

  /// 总兜底：`timeoutMs + 30s`；缺省（无法预知部署方覆写）取钳上限
  /// `600s + 30s`。仅聚合版（toList）接此层；生成器版不接（D3 已裁决）。
  static Duration totalFor(int? timeoutMs) => timeoutMs == null
      ? serverCeiling + buffer
      : Duration(milliseconds: timeoutMs) + buffer;

  /// first-byte 层 `Future.timeout` 的 onTimeout：抛带层名的超时异常。
  static Never firstByteThrower() => throw TimeoutException(
    'first-byte: no response headers within ${firstByte.inMilliseconds}ms',
    firstByte,
  );

  /// idle 层 `Stream.timeout` 的 onTimeout：向行流注入带层名的超时异常
  /// （注入后下游 toList/await-for 即刻失败，watchdog 不再重置）。
  static void idleSinkTimeout(EventSink<String> sink) => sink.addError(
    TimeoutException(
      'idle: no SSE lines (incl. keep-alive) within ${idle.inMilliseconds}ms',
      idle,
    ),
  );

  /// total 层 `Future.timeout` 的 onTimeout：抛带层名的超时异常。
  static Never totalThrower(Duration total) => throw TimeoutException(
    'total: SSE stream did not complete within ${total.inMilliseconds}ms',
    total,
  );
}
