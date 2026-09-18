/// NoSQL 注入威胁严重级别（镜像 SqlInjectionThreat）。
enum NoSqlThreatSeverity { critical, high, medium, low }

/// 单条 NoSQL 注入威胁。镜像 SqlInjectionThreat 结构。
class NoSqlThreat {
  final String type;
  final String description;
  final String location;
  final NoSqlThreatSeverity severity;
  final String mitigation;

  NoSqlThreat({
    required this.type,
    required this.description,
    required this.location,
    required this.severity,
    required this.mitigation,
  });
}

/// MongoDB / NoSQL 注入检测（纯函数，无副作用）。
///
/// 镜像 SqlInjectionDetector 的公开形状，覆盖 research D6 列出的模式：
/// `$where` JS 注入、`$function`/`$accumulator`、操作符注入（`$gt`/`$ne`/`$regex`
/// 认证绕过）、字符串字段传入 `$` 对象、用户构造的 `RegExp`。
class NoSqlInjectionDetector {
  List<NoSqlThreat> analyze(String query) {
    final threats = <NoSqlThreat>[];
    final lower = query.toLowerCase();

    _checkWhereJs(query, lower, threats);
    _checkFunctionOperators(query, lower, threats);
    _checkOperatorInjection(query, lower, threats);
    _checkRegexInjection(query, lower, threats);
    _checkRawObjectSyntax(query, threats);

    return threats;
  }

  void _checkWhereJs(
    String query,
    String lower,
    List<NoSqlThreat> threats,
  ) {
    // $where 接受 JS 字符串，可在服务端执行任意代码
    final whereIdx = lower.indexOf('\$where');
    if (whereIdx != -1) {
      threats.add(
        NoSqlThreat(
          type: '服务端 JS 执行',
          description:
              '使用了 \$where 操作符——它会在 MongoDB 服务端执行 JavaScript，是最高风险的注入向量',
          location: query.substring(whereIdx),
          severity: NoSqlThreatSeverity.critical,
          mitigation: '改用标准查询操作符（\$eq/\$in 等）。如必须用 \$where，确保不拼接任何外部输入',
        ),
      );
    }
  }

  void _checkFunctionOperators(
    String query,
    String lower,
    List<NoSqlThreat> threats,
  ) {
    // $function / $accumulator 允许执行 JS
    for (final op in ['\$function', '\$accumulator']) {
      final idx = lower.indexOf(op.toLowerCase());
      if (idx != -1) {
        threats.add(
          NoSqlThreat(
            type: '聚合表达式注入',
            description: '$op 允许在聚合管道中执行 JavaScript（body 字段），存在代码注入风险',
            location: query.substring(idx),
            severity: NoSqlThreatSeverity.high,
            mitigation: '避免在 \$function.body 中拼接外部输入；优先使用内置表达式运算符',
          ),
        );
      }
    }
  }

  void _checkOperatorInjection(
    String query,
    String lower,
    List<NoSqlThreat> threats,
  ) {
    // 认证字段上的 $gt:'' / $ne:null / $regex 绕过（经典 NoSQL 注入）
    final authRegex = RegExp(
      r'''['"]?(user|username|login|email|pass|password|pwd|token|apikey|api_key)['"]?\s*:\s*\{\s*\$(gt|gte|lt|lte|ne|nin|regex|where|in)\b''',
      caseSensitive: false,
    );
    final match = authRegex.firstMatch(query);
    if (match != null) {
      threats.add(
        NoSqlThreat(
          type: '认证绕过（操作符注入）',
          description:
              '认证字段 "${match.group(1)}" 上出现 \$${match.group(2)} 操作符——攻击者常以此构造 {\$ne: null} / {\$gt: ""} 绕过登录',
          location: match.group(0)!,
          severity: NoSqlThreatSeverity.critical,
          mitigation: '对来自用户的认证输入做类型校验（必须为字符串），拒绝对象/数组形态的查询参数',
        ),
      );
    }

    // 通用的 {$ne: null} / {$gt: ''} 模式
    final neRegex = RegExp(
      r'''\$\s*(ne|nin)\s*:\s*(null|['"]{2})''',
      caseSensitive: false,
    );
    if (neRegex.hasMatch(query)) {
      threats.add(
        NoSqlThreat(
          type: '通配匹配',
          description: '出现 \$ne/\$nin 配合 null/空串——典型的“匹配任意非空值”注入模式',
          location: neRegex.firstMatch(query)!.group(0)!,
          severity: NoSqlThreatSeverity.high,
          mitigation: '校验输入类型与取值范围，不要把用户输入直接作为查询操作符',
        ),
      );
    }
  }

  void _checkRegexInjection(
    String query,
    String lower,
    List<NoSqlThreat> threats,
  ) {
    // 用户可控的 $regex 可能引发 ReDoS 或通配绕过
    final regexIdx = lower.indexOf('\$regex');
    if (regexIdx != -1) {
      threats.add(
        NoSqlThreat(
          type: '正则注入 / ReDoS',
          description:
              '使用 \$regex 且模式可能来自用户输入——可导致拒绝服务（灾难性回溯）或认证绕过',
          location: query.substring(regexIdx),
          severity: NoSqlThreatSeverity.medium,
          mitigation: '对正则源做白名单校验；优先用前缀锚定的 \$regex 或文本索引；设置执行超时',
        ),
      );
    }
  }

  void _checkRawObjectSyntax(String query, List<NoSqlThreat> threats) {
    // 直接传入 JS 字面量（含 $ 开头的键）且整体以 {} 包裹——提示应使用参数化构造
    final dollarKeyRegex = RegExp(r'''['"]?\$\w+['"]?\s*:''');
    if (dollarKeyRegex.hasMatch(query) &&
        query.contains('RegExp(')) {
      threats.add(
        NoSqlThreat(
          type: '用户 RegExp 构造',
          description: '检测到 RegExp(...) 与查询混用——若正则内容来自用户输入，等同于 \$regex 注入',
          location: 'RegExp(...)',
          severity: NoSqlThreatSeverity.medium,
          mitigation: '不要用用户输入构造 RegExp；使用预定义的正则或转义元字符',
        ),
      );
    }
  }

  /// 生成可读威胁报告，格式与 SqlInjectionDetector.generateThreatReport 对齐。
  String generateThreatReport(String query, List<NoSqlThreat> threats) {
    if (threats.isEmpty) {
      return '✅ 未检测到 NoSQL 注入风险，查询看起来安全！';
    }

    final buffer = StringBuffer();
    buffer.writeln('🛡️ NoSQL 注入安全分析报告');
    buffer.writeln('=' * 50);
    buffer.writeln();
    buffer.writeln('原始查询:');
    buffer.writeln('```javascript');
    buffer.writeln(query);
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('⚠️ 检测到 ${threats.length} 个潜在风险：');
    buffer.writeln();

    for (var i = 0; i < threats.length; i++) {
      final t = threats[i];
      buffer.writeln('### ${i + 1}. ${t.type} [${t.severity}]');
      buffer.writeln();
      buffer.writeln('**风险描述**: ${t.description}');
      buffer.writeln('**定位**: `${t.location}`');
      buffer.writeln('**修复建议**: ${t.mitigation}');
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }
}
