// 连接失败「复制诊断」payload 专用脱敏（B-06-R，批4 T8）。
//
// 实现依据 = .specs/tasks-v3.5-ui.md B-06 节 B-06-R 格式规范
// （security-reviewer-max 定稿 2026-10-27，逐字冻结）：
// - 纯函数、无 IO、不依赖 l10n（正则对中英文 payload 同样生效）；
// - 输入 = 组装完成的 Markdown 诊断报告全文，输出 = 脱敏后全文；
// - 内部第一步 redactSecrets(input, redactSql: false)，次序 R1→R4 固定
//   串行、每条作用于上一条输出；
// - 掩码 token 全集仅三种：`***`（凭据值与系统用户名段）、`**`（IPv4
//   被掩末段）、`…`（U+2026 单字符，IPv6 被掩部分），不得新增。
//
// 明示不掩清单（防当遗漏顺手补上）：DB 用户名（含 'alice'@'ip' 与
// ://alice:***@host 中的 alice）、命名 hostname、端口号、普通 UNC
// server/share、localhost/127.0.0.1/::1、SQL 文本（redactSql 恒 false）。
//
// 已知限制（B-06-R 第 8 条，接受不修）：四段式 Windows 版本号被 R2 误掩
// （过掩无害）；redactSecrets 贪婪至最后 @ 的多 URL 过度消费为既有层已知
// 限制，本层不得顺手修；/home/<服务账户> 同样被 R4 掩。
//
// 不改 redactSecrets 既有语义与其它调用方。

import 'secret_redactor.dart';

/// 连接失败诊断 payload 脱敏——调用侧铁律：剪贴板路径任何分支不得绕过
/// 本函数（含重试失败后 latestFailure 原地刷新重建 payload 的路径）；
/// 报告先组装、后整体单次过本函数。
String redactConnectDiagnostics(String payload) {
  var out = redactSecrets(payload, redactSql: false); // R1
  out = _redactIpv4LastOctet(out); // R2
  out = _redactIpv6(out); // R3
  out = _redactSystemUsernames(out); // R4
  return out;
}

/// R2：IPv4 末段掩码——四组点分 1-3 位数字（词边界），非 127.0.0.1 时
/// 末组替换 `**`；不做 0-255 校验（过掩无害）。IPv4-mapped 形态
/// `::ffff:10.0.0.5` 同样经本条 → `::ffff:10.0.0.**`（冒号后词边界成立）。
final RegExp _ipv4Pattern = RegExp(
  r'\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b',
);

String _redactIpv4LastOctet(String input) =>
    input.replaceAllMapped(_ipv4Pattern, (match) {
      if (match[0] == '127.0.0.1') return match[0]!;
      return '${match[1]}.${match[2]}.${match[3]}.**';
    });

/// R3：IPv6 掩码——匹配 IPv6 形态字面量（≥2 冒分 hex 组、至多 8 组端口
/// 粘连前缀不计入），非 `::1` 且不含 IPv4 尾段时保留按书写顺序前两组
/// hex、其余整体替换 `…`（U+2026）。后随 `:port` 不被吞掉，输出形如
/// `2001:db8:…:5432`（视觉粘连为已知代价接受）。
///
/// 边界守卫：lookbehind 排除从 hex/冒号/点中间起匹配（防 IPv4-mapped
/// 尾段粘连误掩）；lookahead 排除后随点分数字（含 IPv4 尾段的形态交 R2
/// 处理）；匹配含 `.` 时跳过（嵌入式 IPv4 形态）；恰两组无可掩部分原样。
final RegExp _ipv6Pattern = RegExp(
  r'(?<![0-9A-Fa-f:.])[0-9A-Fa-f]{1,4}(?::{1,2}[0-9A-Fa-f]{1,4}){1,7}(?![\d.])',
);

String _redactIpv6(String input) =>
    input.replaceAllMapped(_ipv6Pattern, (match) {
      final literal = match[0]!;
      if (literal == '::1' || literal.contains('.')) return literal;
      final groups = literal.split(':');
      if (groups.length <= 2) return literal;
      return '${groups[0]}:${groups[1]}:…';
    });

/// R4：系统用户名掩码（跨 OS 统一、不按运行平台分支）——
/// `<盘符>:\Users\<seg>` / `<盘符>:/Users/<seg>`（盘符 A-Z 大小写不敏感）、
/// `/Users/<seg>`、`/home/<seg>`：seg 至下一路径分隔符（`\` 或 `/`）为止
/// （含空格/冒号等用户名内字符，B-06-R 冻结原文——含空格用户名完整掩，
/// 批4 修复轮 P3-①/D-1），无尾分隔符同样掩；`~<name>` → `~***`（裸 `~`
/// 保留，name 同「至下一分隔符」语义）；`\\<server>\<name>$` →
/// `\\<server>\***$`（普通 `\\<server>\<share>` 保留）。
final RegExp _usersHomePattern = RegExp(
  r'([A-Za-z]:[\\/]Users[\\/]|[\\/](?:Users|home)[\\/])([^\\/]+)',
);

final RegExp _tildeNamePattern = RegExp(r'~([^\\/]+)');

final RegExp _uncHomeSharePattern = RegExp(r'(\\\\[^\\/]+\\)([^\\/]+)\$');

String _redactSystemUsernames(String input) {
  var out = input.replaceAllMapped(
    _usersHomePattern,
    (match) => '${match[1]}***',
  );
  out = out.replaceAllMapped(_tildeNamePattern, (_) => '~***');
  out = out.replaceAllMapped(
    _uncHomeSharePattern,
    (match) => '${match[1]}***\$',
  );
  return out;
}
