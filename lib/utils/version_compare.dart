/// 版本字符串比较（U15）。
///
/// 项目实际并存两种 tag 风格，必须都能比：
/// - **CalVer 日期式** `v2026-07-27`——tech-site 下载直链用的这套（当前主
///   发布格式）；
/// - **SemVer** `v1.7.0`——历史遗留 tag；server 侧（Cargo `0.1.0`）也是
///   这套。
///
/// 返回：`-1`（a < b）/ `0`（相等）/ `1`（a > b）；**两种风格互比（如
/// `1.7.0` vs `2026-07-27`）无法判定次序，返回 null**——调用方应按「版本
/// 不一致但不可排序」处理（展示 + 链接），不得宣称「有新版本」。
int? compareVersions(String a, String b) {
  final na = _normalize(a);
  final nb = _normalize(b);
  if (na == null || nb == null) return null;
  final aDate = _dateOnly(na) != null;
  final bDate = _dateOnly(nb) != null;
  if (aDate && bDate) return na.compareTo(nb); // ISO 日期字典序 = 时间序
  if (aDate != bDate) return null; // 跨风格：不可判定
  return _compareSemver(na, nb);
}

/// 是否日期式版本（CalVer `YYYY-MM-DD`，允许 `v` 前缀）。
bool isDateVersion(String v) =>
    _dateOnly(_normalize(v) ?? '') != null;

String? _normalize(String v) {
  var s = v.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus); // 剥 build 号（0.0.1+1 → 0.0.1）
  return s.isEmpty ? null : s;
}

/// `2026-07-27`（剥前缀/build 后）→ 原样返回；否则 null。
String? _dateOnly(String s) {
  final match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  return match == null ? null : s;
}

/// 语义化版本逐段数值比较（`0.2.0` < `0.10.0`；缺段补 0）。
/// 非数字段（如 `1.0.0-beta` 的 `-beta`）整体退回字符串比较，够用即可——
/// 项目 tag 无 pre-release 约定。
int _compareSemver(String a, String b) {
  final sa = a.split('.');
  final sb = b.split('.');
  final n = sa.length > sb.length ? sa.length : sb.length;
  for (var i = 0; i < n; i++) {
    final ea = i < sa.length ? sa[i] : '0';
    final eb = i < sb.length ? sb[i] : '0';
    final na = int.tryParse(ea);
    final nb = int.tryParse(eb);
    if (na != null && nb != null) {
      if (na != nb) return na < nb ? -1 : 1;
    } else {
      final c = ea.compareTo(eb);
      if (c != 0) return c < 0 ? -1 : 1;
    }
  }
  return 0;
}
