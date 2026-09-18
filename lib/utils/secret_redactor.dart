/// 敏感片段脱敏——错误发送给 AI / 写日志前调用（spec FR-011 + constitution 安全）。
///
/// 屏蔽：连接串密码（password=/pwd=）、`://user:pass@host`、
/// `Authorization: Bearer …`、`api_key=/apikey=`。SQL 默认不脱敏
///（错误里的失败 SQL 通常对诊断必不可少）；传 [redactSql]=true 时
///（用户数据导入等 PII 场景）额外屏蔽 `VALUES (...)` 字面量。
String redactSecrets(String input, {bool redactSql = false}) {
  var out = input;
  out = out.replaceAllMapped(
    RegExp(
      r'''(password|pwd)\s*=\s*('[^']*'|"[^"]*"|[^\s;,]+)''',
      caseSensitive: false,
    ),
    (_) => '***',
  );
  out = out.replaceAllMapped(
    RegExp(r'://([^:/\s]+):(.+)@'), // 贪婪到最后一个 @，兼容密码中含 @
    (m) => '://${m[1]}:***@',
  );
  out = out.replaceAllMapped(
    RegExp(r'(authorization\s*:\s*bearer\s+)[^\s;]+', caseSensitive: false),
    (m) => '${m[1]}***',
  );
  out = out.replaceAllMapped(
    RegExp(r'(api_?key)\s*=\s*[^\s;,]+', caseSensitive: false),
    (_) => '***',
  );
  if (redactSql) {
    out = out.replaceAllMapped(
      RegExp(r'VALUES\s*\(([^)]*)\)', caseSensitive: false),
      (_) => 'VALUES (***)',
    );
  }
  return out;
}
