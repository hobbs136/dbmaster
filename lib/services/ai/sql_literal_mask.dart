/// SQL 字面量 / 注释掩码（等长空格替换）——结构扫描类守卫的共享前置处理。
///
/// 提取自 `ReadonlySqlValidator._maskLiterals`（Fix-G「提取不改行为」：
/// 校验器侧改为委托调用，默认参数下行为逐字节一致）。用途：扫描分号 /
/// 关键词 / 限定名之前先掩码字面量与注释，否则 `WHERE note = 'please
/// delete me'`、`/* ; */`、`FROM/*c*/otherdb.t` 等形态会误伤 / 漏判。
///
/// 纯函数、零 IO；services 层禁 import material（组件级 §0 MUST NOT 2）。
library;

/// 把 [sql] 中的字符串字面量与注释内容替换为等长空格（引号与注释定界符
/// 原位保留——掩码后串与原串等长，扫描命中的偏移仍可对回原语句）。
///
/// - 单引号字符串、行注释（`--` 至行尾）、块注释（`/* ... */`，未闭合
///   掩到串尾）恒掩码——各目标方言的通用字面量/注释形态；
/// - [maskQuotedIdentifiers] = true（默认，`ReadonlySqlValidator` 口径）
///   时双引号 / 反引号段同样掩码（MySQL 语义下二者可为字符串）；
///   = false 时双引号 / 反引号段保持可见——限定名扫描（AC4.4 库级执法）
///   专用：引界标识符（`` `db`.t `` / `"db".t` / `[db].t`）必须参与比对，
///   否则 `` FROM `otherdb`.`t` `` 会被掩码吞掉形成逃逸洞。代价是双引号
///   字符串内若恰含 FROM/JOIN 限定名形态会误拦（fail-closed 方向，可
///   接受；单引号字符串不受影响）。
String maskSqlLiteralsAndComments(
  String sql, {
  bool maskQuotedIdentifiers = true,
}) {
  final StringBuffer buf = StringBuffer();
  int i = 0;
  while (i < sql.length) {
    final String ch = sql[i];
    if (ch == "'" || (maskQuotedIdentifiers && (ch == '"' || ch == '`'))) {
      int j = i + 1;
      while (j < sql.length) {
        if (sql[j] == ch) {
          // 引号转义（'' / "" / ``）仍在字面量内
          if (j + 1 < sql.length && sql[j + 1] == ch) {
            j += 2;
            continue;
          }
          break;
        }
        if (sql[j] == r'\' && ch != '`' && j + 1 < sql.length) {
          j += 2; // 反斜杠转义
          continue;
        }
        j++;
      }
      buf.write(ch);
      for (int k = i + 1; k < j && k < sql.length; k++) {
        buf.write(' ');
      }
      if (j < sql.length) buf.write(ch);
      i = j + 1;
    } else if (ch == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      int j = i;
      while (j < sql.length && sql[j] != '\n') {
        j++;
      }
      for (int k = i; k < j; k++) {
        buf.write(' ');
      }
      i = j;
    } else if (ch == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      int j = i + 2;
      while (j + 1 < sql.length && !(sql[j] == '*' && sql[j + 1] == '/')) {
        j++;
      }
      final int end = j + 1 < sql.length ? j + 2 : sql.length;
      for (int k = i; k < end; k++) {
        buf.write(' ');
      }
      i = end;
    } else {
      buf.write(ch);
      i++;
    }
  }
  return buf.toString();
}
