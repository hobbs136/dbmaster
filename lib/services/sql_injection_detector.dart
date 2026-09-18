import 'dart:developer' as developer;

enum Severity { high, medium, low }

class SqlInjectionThreat {
  final String type;
  final String description;
  final Severity severity;
  final String? matchedPattern;
  final String? suggestion;

  SqlInjectionThreat({
    required this.type,
    required this.description,
    required this.severity,
    this.matchedPattern,
    this.suggestion,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'description': description,
    'severity': severity.name,
    'matchedPattern': matchedPattern,
    'suggestion': suggestion,
  };
}

class SqlInjectionDetector {
  static final SqlInjectionDetector _instance =
      SqlInjectionDetector._internal();
  factory SqlInjectionDetector() => _instance;
  SqlInjectionDetector._internal();

  final List<_InjectionPattern> _patterns = [
    _InjectionPattern(
      name: 'UNION注入',
      pattern: RegExp(r'UNION\s+(ALL\s+)?SELECT', caseSensitive: false),
      severity: Severity.high,
      description: '检测到 UNION SELECT 语句，可能用于联合查询注入',
      suggestion: '使用参数化查询，避免直接拼接用户输入',
    ),
    _InjectionPattern(
      name: '注释注入',
      pattern: RegExp(r'(--)|(\/\*)|(\#)', caseSensitive: false),
      severity: Severity.medium,
      description: '检测到SQL注释符号，可能用于截断SQL语句',
      suggestion: '过滤注释符号或使用参数化查询',
    ),
    _InjectionPattern(
      name: '布尔注入',
      pattern: RegExp(r"('\s*(OR|AND)\s+')|('\s*=\s*')", caseSensitive: false),
      severity: Severity.high,
      description: '检测到布尔表达式注入模式',
      suggestion: '使用参数化查询，验证输入格式',
    ),
    _InjectionPattern(
      name: '堆叠查询',
      pattern: RegExp(
        r";\s*(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER)",
        caseSensitive: false,
      ),
      severity: Severity.high,
      description: '检测到分号后跟SQL语句，可能用于堆叠查询注入',
      suggestion: '禁止多语句执行，使用参数化查询',
    ),
    _InjectionPattern(
      name: '危险函数',
      pattern: RegExp(
        r'\b(LOAD_FILE|INTO\s+OUTFILE|INTO\s+DUMPFILE)\b',
        caseSensitive: false,
      ),
      severity: Severity.high,
      description: '检测到文件操作函数，可能用于读取或写入文件',
      suggestion: '限制数据库用户权限，禁用文件操作函数',
    ),
    _InjectionPattern(
      name: '信息收集',
      pattern: RegExp(
        r'\b(INFORMATION_SCHEMA|SYS\.|MYSQL\.)\b',
        caseSensitive: false,
      ),
      severity: Severity.medium,
      description: '检测到系统表访问，可能用于收集数据库信息',
      suggestion: '限制对系统表的访问权限',
    ),
    _InjectionPattern(
      name: '时间盲注',
      pattern: RegExp(
        r'\b(SLEEP|BENCHMARK|WAITFOR)\s*\(',
        caseSensitive: false,
      ),
      severity: Severity.high,
      description: '检测到延时函数，可能用于时间盲注攻击',
      suggestion: '过滤延时函数，限制执行时间',
    ),
    _InjectionPattern(
      name: '编码绕过',
      pattern: RegExp(
        r'(CHAR\s*\(|0x[0-9a-fA-F]+|CONCAT\s*\()',
        caseSensitive: false,
      ),
      severity: Severity.medium,
      description: '检测到编码函数，可能用于绕过过滤',
      suggestion: '使用白名单验证，避免黑名单过滤',
    ),
    _InjectionPattern(
      name: 'EXEC执行',
      pattern: RegExp(r'\b(EXEC|EXECUTE|SP_)\b', caseSensitive: false),
      severity: Severity.high,
      description: '检测到存储过程执行语句',
      suggestion: '限制存储过程执行权限',
    ),
  ];

  List<SqlInjectionThreat> analyze(String sql) {
    developer.log('🔒 开始SQL注入检测', name: 'SqlInjectionDetector');

    final threats = <SqlInjectionThreat>[];

    for (final pattern in _patterns) {
      final matches = pattern.pattern.allMatches(sql);
      if (matches.isNotEmpty) {
        for (final match in matches) {
          threats.add(
            SqlInjectionThreat(
              type: pattern.name,
              description: pattern.description,
              severity: pattern.severity,
              matchedPattern: match.group(0),
              suggestion: pattern.suggestion,
            ),
          );
        }
      }
    }

    developer.log(
      '✅ SQL注入检测完成，发现 ${threats.length} 个潜在威胁',
      name: 'SqlInjectionDetector',
    );

    return threats;
  }

  bool isSafe(String sql) {
    final threats = analyze(sql);
    return threats.where((t) => t.severity == Severity.high).isEmpty;
  }

  String sanitize(String input) {
    developer.log('🧹 开始清理输入', name: 'SqlInjectionDetector');

    var sanitized = input;

    sanitized = sanitized.replaceAll("'", "''");
    sanitized = sanitized.replaceAll('\\', '\\\\');
    sanitized = sanitized.replaceAll('\x00', '\\x00');
    sanitized = sanitized.replaceAll('\n', '\\n');
    sanitized = sanitized.replaceAll('\r', '\\r');
    sanitized = sanitized.replaceAll('\x1a', '\\x1a');

    developer.log('✅ 输入清理完成', name: 'SqlInjectionDetector');

    return sanitized;
  }

  String generateThreatReport(String sql, List<SqlInjectionThreat> threats) {
    if (threats.isEmpty) {
      return '✅ 未检测到SQL注入威胁，SQL语句看起来安全！';
    }

    final buffer = StringBuffer();

    buffer.writeln('🔒 SQL注入威胁检测报告');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln('检测到 ${threats.length} 个潜在威胁：');
    buffer.writeln();

    final highSeverity = threats
        .where((t) => t.severity == Severity.high)
        .toList();
    final mediumSeverity = threats
        .where((t) => t.severity == Severity.medium)
        .toList();
    final lowSeverity = threats
        .where((t) => t.severity == Severity.low)
        .toList();

    if (highSeverity.isNotEmpty) {
      buffer.writeln('### 🔴 高危威胁 (${highSeverity.length})');
      buffer.writeln();
      for (final threat in highSeverity) {
        buffer.writeln('**${threat.type}**');
        buffer.writeln('- 描述: ${threat.description}');
        if (threat.matchedPattern != null) {
          buffer.writeln('- 匹配模式: `${threat.matchedPattern}`');
        }
        buffer.writeln('- 建议: ${threat.suggestion}');
        buffer.writeln();
      }
    }

    if (mediumSeverity.isNotEmpty) {
      buffer.writeln('### 🟡 中危威胁 (${mediumSeverity.length})');
      buffer.writeln();
      for (final threat in mediumSeverity) {
        buffer.writeln('**${threat.type}**');
        buffer.writeln('- 描述: ${threat.description}');
        if (threat.matchedPattern != null) {
          buffer.writeln('- 匹配模式: `${threat.matchedPattern}`');
        }
        buffer.writeln('- 建议: ${threat.suggestion}');
        buffer.writeln();
      }
    }

    if (lowSeverity.isNotEmpty) {
      buffer.writeln('### 🟢 低危威胁 (${lowSeverity.length})');
      buffer.writeln();
      for (final threat in lowSeverity) {
        buffer.writeln('**${threat.type}**');
        buffer.writeln('- 描述: ${threat.description}');
        buffer.writeln('- 建议: ${threat.suggestion}');
        buffer.writeln();
      }
    }

    buffer.writeln('### 🛡️ 安全建议');
    buffer.writeln();
    buffer.writeln('1. **使用参数化查询**: 永远不要直接拼接用户输入到SQL语句中');
    buffer.writeln('2. **输入验证**: 对所有用户输入进行白名单验证');
    buffer.writeln('3. **最小权限原则**: 数据库用户只授予必要的权限');
    buffer.writeln('4. **错误处理**: 不要向用户显示详细的数据库错误信息');
    buffer.writeln('5. **Web应用防火墙**: 使用WAF检测和阻止SQL注入攻击');
    buffer.writeln('6. **定期审计**: 定期检查代码和数据库访问日志');

    return buffer.toString();
  }
}

class _InjectionPattern {
  final String name;
  final RegExp pattern;
  final Severity severity;
  final String description;
  final String suggestion;

  _InjectionPattern({
    required this.name,
    required this.pattern,
    required this.severity,
    required this.description,
    required this.suggestion,
  });
}
