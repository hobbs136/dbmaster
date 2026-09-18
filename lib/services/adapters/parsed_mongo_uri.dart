/// 解析 MongoDB 连接串的结果（spec 044 US3 / PD-7）。
///
/// 由 [ParsedMongoUri.parse] 产出——纯静态、无副作用，连接表单在保存前
/// 调用以**剥离凭据**（FR-007）：密码绝不进 [credentialFreeUri] 或 extra，
/// 仅经 [password] → `DbServer.password` → `SecureStorageService` vault。
/// C08 起解析器本体放本文件（UI 表单层可直引，不经 adapter——铁律 3）；
/// `MongoDBAdapter.parseConnectionString` 保留为薄委托。
class ParsedMongoUri {
  const ParsedMongoUri({
    this.username,
    this.password,
    required this.credentialFreeUri,
    required this.isSrv,
    required this.useSSL,
    this.authSource,
  });

  /// 已 URL-decode 的用户名（无凭据时为 null）。
  final String? username;

  /// 已 URL-decode 的密码（原始值）。
  /// - null：无密码（`mongodb://host` 或 `mongodb://user@host`）
  /// - ''：空密码（`mongodb://user:@host`）
  /// → `DbServer.password` → SecureStorage；绝不进 URI/extra。
  final String? password;

  /// scheme + hosts + path + query，**无 userinfo**。
  /// 解析后断言：整串不含 `@`（userinfo 已剥离干净，FR-007）。
  final String credentialFreeUri;

  /// scheme 是否为 `mongodb+srv://`（SRV 需 `await Db.create`，PD-6）。
  final bool isSrv;

  /// 从 `ssl=true` / `tls=true` 查询参数推断。
  final bool useSSL;

  /// 从 `authSource=` 查询参数取（无则 null）。
  final String? authSource;

  /// 解析 MongoDB 连接串，剥离凭据。失败（空串/非法 scheme/SRV 多 host）抛
  /// [FormatException]；若剥离后 credentialFreeUri 仍含 @ 则抛 [StateError]。
  ///
  /// 实现自 spec 044（原 `MongoDBAdapter.parseConnectionString`，C08 移入本类：
  /// 纯函数无 adapter 依赖，表单层校验/收集可直接使用）。
  static ParsedMongoUri parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      throw const FormatException('空连接串');
    }

    const srvPrefix = 'mongodb+srv://';
    const mongoPrefix = 'mongodb://';
    final bool isSrv;
    final String afterScheme;
    if (s.startsWith(srvPrefix)) {
      isSrv = true;
      afterScheme = s.substring(srvPrefix.length);
    } else if (s.startsWith(mongoPrefix)) {
      isSrv = false;
      afterScheme = s.substring(mongoPrefix.length);
    } else {
      throw FormatException('非法 scheme（须 mongodb:// 或 mongodb+srv://）: $raw');
    }
    final scheme = isSrv ? srvPrefix : mongoPrefix;

    // authority = scheme 后到首个 / ? # 之前；tail = 含分隔符的剩余（path?query#frag）
    final delim = afterScheme.indexOf(RegExp(r'[/?#]'));
    final authority = delim < 0 ? afterScheme : afterScheme.substring(0, delim);
    final tail = delim < 0 ? '' : afterScheme.substring(delim);

    // userinfo 在**最后一个** @ 之前（密码可能含编码的 %40，不是真 @）
    final atIdx = authority.lastIndexOf('@');
    final String userinfo;
    final String hostsSection;
    if (atIdx < 0) {
      userinfo = '';
      hostsSection = authority;
    } else {
      userinfo = authority.substring(0, atIdx);
      hostsSection = authority.substring(atIdx + 1);
    }

    // userinfo 在**第一个** : 处分 user/password（解码前切分，编码的 %3A 不干扰）
    String? username;
    String? password;
    if (userinfo.isNotEmpty) {
      final colonIdx = userinfo.indexOf(':');
      if (colonIdx < 0) {
        username = Uri.decodeComponent(userinfo);
      } else {
        username = Uri.decodeComponent(userinfo.substring(0, colonIdx));
        password = Uri.decodeComponent(userinfo.substring(colonIdx + 1));
      }
    }

    // SRV 不允许多 host（逗号）
    if (isSrv && hostsSection.contains(',')) {
      throw FormatException('mongodb+srv:// 不支持多 host（逗号）: $raw');
    }

    final credentialFreeUri = scheme + hostsSection + tail;

    // FR-007 断言：剥离后整串不含 @（userinfo 未泄漏）
    if (credentialFreeUri.contains('@')) {
      throw StateError('credentialFreeUri 仍含 @（userinfo 未剥离）: $credentialFreeUri');
    }

    // 解析 query：ssl/tls/authSource
    var useSSL = false;
    String? authSource;
    final query = _querySubstring(tail);
    if (query != null) {
      for (final pair in query.split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        final k = eq < 0 ? pair : pair.substring(0, eq);
        final v = eq < 0 ? '' : pair.substring(eq + 1);
        if (k == 'ssl' || k == 'tls') {
          if (v == 'true' || v == '') useSSL = true;
        } else if (k == 'authSource') {
          authSource = v.isEmpty ? null : Uri.decodeComponent(v);
        }
      }
    }

    return ParsedMongoUri(
      username: username,
      password: password,
      credentialFreeUri: credentialFreeUri,
      isSrv: isSrv,
      useSSL: useSSL,
      authSource: authSource,
    );
  }

  /// 取 tail 中 `?` 后、`#` 前的 query 子串；无则 null。
  static String? _querySubstring(String tail) {
    final q = tail.indexOf('?');
    if (q < 0) return null;
    var rest = tail.substring(q + 1);
    final hash = rest.indexOf('#');
    if (hash >= 0) rest = rest.substring(0, hash);
    return rest;
  }
}
