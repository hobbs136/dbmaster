/// RFC3339 UTC 时间串 → 本地时区短显示（U17）。
///
/// server 全部时间戳是 RFC3339 UTC（如 `2026-08-13T10:30:00Z`）。此前部分
/// 对话框直接字符串切片展示（approval / MCP token——显示的是 UTC 值，与
/// 本地时间差数小时），另一部分各自手写 `tryParse().toLocal()` + 拼串
/// （drift ×3 / health ×1）——统一收敛到这里。
///
/// 解析失败原样返回输入（损坏/非标准串不至于变成空白）。
String formatRfc3339Local(String iso, {bool withSeconds = false}) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  String two(int v) => v.toString().padLeft(2, '0');
  final base = '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
  return withSeconds ? '$base:${two(dt.second)}' : base;
}
