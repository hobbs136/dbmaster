import 'package:flutter/material.dart';

/// PII (Personally Identifiable Information) 数据脱敏服务
///
/// 支持多种敏感数据类型的自动检测和脱敏处理
/// 纯本地实现，不上传任何数据到云端
class PIIMasker {
  static final PIIMasker _instance = PIIMasker._internal();
  factory PIIMasker() => _instance;
  PIIMasker._internal();

  /// 是否启用脱敏
  bool _enabled = true;
  bool get enabled => _enabled;
  set enabled(bool value) => _enabled = value;

  /// PII 检测模式配置
  final Map<String, PIIPattern> _patterns = {
    'email': PIIPattern(
      name: 'Email',
      description: 'Email Address',
      regex: RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
      maskType: MaskType.email,
    ),
    'phone': PIIPattern(
      name: 'Phone',
      description: 'Phone Number',
      regex: RegExp(r'\b1[3-9]\d{9}\b'),
      maskType: MaskType.partial,
      maskOptions: MaskOptions(
        preservePrefix: 3,
        preserveSuffix: 4,
        maskChar: '*',
      ),
    ),
    'id_card': PIIPattern(
      name: 'ID Card',
      description: 'Chinese ID Card',
      regex: RegExp(r'\b\d{17}[\dXx]\b|\b\d{15}\b'),
      maskType: MaskType.partial,
      maskOptions: MaskOptions(
        preservePrefix: 6,
        preserveSuffix: 4,
        maskChar: '*',
      ),
    ),
    'credit_card': PIIPattern(
      name: 'Credit Card',
      description: 'Credit/Debit Card',
      regex: RegExp(r'\b(?:\d{4}[-\s]?){3}\d{4}\b'),
      maskType: MaskType.creditCard,
    ),
    'bank_card': PIIPattern(
      name: 'Bank Card',
      description: 'Bank Account',
      regex: RegExp(r'\b\d{16,19}\b'),
      maskType: MaskType.partial,
      maskOptions: MaskOptions(
        preservePrefix: 4,
        preserveSuffix: 4,
        maskChar: '*',
      ),
    ),
    'password': PIIPattern(
      name: 'Password',
      description: 'Password Field',
      regex: RegExp(
        r'(password|passwd|pwd)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      maskType: MaskType.full,
    ),
    'ip_address': PIIPattern(
      name: 'IP',
      description: 'IP Address',
      regex: RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
      maskType: MaskType.partial,
      maskOptions: MaskOptions(
        preservePrefix: 0,
        preserveSuffix: 3,
        maskChar: '*',
      ),
    ),
  };

  Map<String, PIIPattern> get patterns => Map.unmodifiable(_patterns);

  /// For testing only
  @visibleForTesting
  Map<String, PIIPattern> get debugPatterns => _patterns;

  /// Check if a specific pattern is enabled
  bool isPatternEnabled(String key) => _patterns[key]?.enabled ?? false;

  /// 设置特定模式的启用状态
  void setPatternEnabled(String patternKey, bool enabled) {
    if (_patterns.containsKey(patternKey)) {
      _patterns[patternKey] = _patterns[patternKey]!.copyWith(enabled: enabled);
    }
  }

  /// 检测并脱敏单个值
  ///
  /// [value] 原始值
  /// [columnName] 列名（用于基于列名的智能检测）
  /// [columnType] 列类型（可选）
  ///
  /// 返回：脱敏后的值，如果未检测到 PII 则返回原值
  String maskValue(Object? value, {String? columnName, String? columnType}) {
    if (!_enabled || value == null) return value?.toString() ?? '';

    final strValue = value.toString();
    if (strValue.isEmpty) return '';

    // 基于列名的启发式检测
    final columnHint = _getColumnHint(columnName);
    if (columnHint != null) {
      final pattern = _patterns[columnHint];
      if (pattern != null &&
          pattern.enabled &&
          pattern.regex.hasMatch(strValue)) {
        return _applyMask(strValue, pattern);
      }
    }

    // 基于内容正则检测
    String result = strValue;
    for (final entry in _patterns.entries) {
      final pattern = entry.value;
      if (!pattern.enabled) continue;

      if (pattern.regex.hasMatch(result)) {
        result = _applyMask(result, pattern);
      }
    }

    return result;
  }

  /// 批量脱敏查询结果
  ///
  /// [rows] 查询结果行
  /// [columns] 列信息（可选，用于智能检测）
  ///
  /// 返回：脱敏后的结果
  List<Map<String, dynamic>> maskRows(
    List<Map<String, dynamic>> rows, {
    List<Map<String, dynamic>>? columns,
  }) {
    if (!_enabled || rows.isEmpty) return rows;

    return rows.map((row) {
      final maskedRow = <String, dynamic>{};
      for (final entry in row.entries) {
        final columnName = entry.key;
        final value = entry.value;

        // 检查是否是敏感列
        if (_isSensitiveColumn(columnName)) {
          maskedRow[columnName] = maskValue(value, columnName: columnName);
        } else {
          maskedRow[columnName] = value;
        }
      }
      return maskedRow;
    }).toList();
  }

  /// 基于列名判断是否是敏感列
  bool _isSensitiveColumn(String columnName) {
    final lowerName = columnName.toLowerCase();
    final sensitiveKeywords = [
      'password',
      'passwd',
      'pwd',
      'secret',
      'token',
      'key',
      'email',
      'mail',
      'phone',
      'mobile',
      'tel',
      'id_card',
      'idcard',
      'identity',
      'ssn',
      'credit',
      'card',
      'bank',
      'account_no',
      'name',
      'full_name',
      'real_name',
      'username',
      'address',
      'ip',
      'cookie',
      'session',
    ];

    return sensitiveKeywords.any((keyword) => lowerName.contains(keyword));
  }

  /// 基于列名获取检测提示
  String? _getColumnHint(String? columnName) {
    if (columnName == null) return null;

    final lowerName = columnName.toLowerCase();

    if (lowerName.contains('email') || lowerName.contains('mail'))
      return 'email';
    if (lowerName.contains('phone') ||
        lowerName.contains('mobile') ||
        lowerName.contains('tel'))
      return 'phone';
    if (lowerName.contains('id_card') ||
        lowerName.contains('idcard') ||
        lowerName.contains('identity'))
      return 'id_card';
    if (lowerName.contains('credit') || lowerName.contains('card'))
      return 'credit_card';
    if (lowerName.contains('bank')) return 'bank_card';
    if (lowerName.contains('password') ||
        lowerName.contains('passwd') ||
        lowerName.contains('pwd'))
      return 'password';
    if (lowerName.contains('ip')) return 'ip_address';

    return null;
  }

  /// 应用脱敏
  String _applyMask(String value, PIIPattern pattern) {
    switch (pattern.maskType) {
      case MaskType.full:
        return (pattern.maskOptions?.maskChar ?? '*') * value.length;
      case MaskType.partial:
        final options = pattern.maskOptions!;
        final prefixLen = options.preservePrefix.clamp(0, value.length);
        final suffixLen = options.preserveSuffix.clamp(
          0,
          value.length - prefixLen,
        );

        final prefix = value.substring(0, prefixLen);
        final suffix = value.length > suffixLen
            ? value.substring(value.length - suffixLen)
            : '';
        final middleLength = value.length - prefixLen - suffixLen;
        final masked = middleLength > 0 ? options.maskChar * middleLength : '';
        return '$prefix$masked$suffix';
      case MaskType.email:
        final atIndex = value.indexOf('@');
        if (atIndex <= 0) return value;

        final local = value.substring(0, atIndex);
        final domain = value.substring(atIndex);

        if (local.length <= 2) {
          return '${local[0]}***$domain';
        }

        final prefix = local.substring(0, 2);
        return '$prefix***$domain';
      case MaskType.creditCard:
        final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
        if (digitsOnly.length < 4) return value;

        final last4 = digitsOnly.substring(digitsOnly.length - 4);
        final maskedLen = value.length - 4;
        final masked = '*' * maskedLen;
        return '$masked$last4';
      case MaskType.hash:
        return '[HASHED]';
      case MaskType.redact:
        return '[REDACTED]';
    }
  }

  /// 获取脱敏统计信息
  Map<String, int> getMaskingStats(List<Map<String, dynamic>> rows) {
    final stats = <String, int>{};

    for (final row in rows) {
      for (final entry in row.entries) {
        final value = entry.value?.toString() ?? '';
        for (final patternEntry in _patterns.entries) {
          if (patternEntry.value.regex.hasMatch(value)) {
            stats[patternEntry.key] = (stats[patternEntry.key] ?? 0) + 1;
          }
        }
      }
    }

    return stats;
  }

  /// R4: 检测某列是否含 PII（列名启发式 + 采样值内容检测）。
  ///
  /// 供导出对话框高亮 PII 列 + 决定默认脱敏动作用。
  /// 列名命中（如 email/phone/id_card）→ 标记为该 pattern；
  /// 否则采样最多 [sampleSize] 个值，任一命中正则 → 标记。
  /// 高敏感（身份证/银行卡/信用卡/密码）sensitivity=high，其余 normal。
  PiiColumnDetection detectColumnPii({
    required String columnName,
    required List<dynamic> sampleValues,
    int sampleSize = 50,
  }) {
    // 1. 列名启发式（强信号，直接判定）
    final hint = _getColumnHint(columnName);
    if (hint != null && _patterns.containsKey(hint)) {
      return PiiColumnDetection(
        columnName: columnName,
        hasPii: true,
        patternKey: hint,
        patternName: _patterns[hint]!.name,
        sensitivity: _sensitivityOf(hint),
      );
    }

    // 2. 采样值内容检测（弱信号，需命中比例 ≥20% 确认，避免误报）
    final sample = sampleValues.take(sampleSize).toList();
    if (sample.isEmpty) {
      return PiiColumnDetection(columnName: columnName, hasPii: false);
    }

    final hitCounts = <String, int>{};
    for (final value in sample) {
      final str = value?.toString() ?? '';
      if (str.isEmpty) continue;
      for (final entry in _patterns.entries) {
        if (entry.value.enabled && entry.value.regex.hasMatch(str)) {
          hitCounts[entry.key] = (hitCounts[entry.key] ?? 0) + 1;
        }
      }
    }

    if (hitCounts.isEmpty) {
      return PiiColumnDetection(columnName: columnName, hasPii: false);
    }

    // 取命中次数最多的 pattern（避免单个误报主导）
    final sorted = hitCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = sorted.first;
    final hitRatio = best.value / sample.length;
    // 命中比例阈值：至少 20% 采样值命中才算该列是 PII（防个别巧合）
    if (hitRatio < 0.2) {
      return PiiColumnDetection(columnName: columnName, hasPii: false);
    }

    return PiiColumnDetection(
      columnName: columnName,
      hasPii: true,
      patternKey: best.key,
      patternName: _patterns[best.key]?.name ?? best.key,
      sensitivity: _sensitivityOf(best.key),
      sampleHitRatio: hitRatio,
    );
  }

  /// pattern key → 敏感度。高敏感（身份证/银行卡/信用卡/密码）→ high（默认删除）。
  PiiSensitivity _sensitivityOf(String patternKey) {
    switch (patternKey) {
      case 'id_card':
      case 'credit_card':
      case 'bank_card':
      case 'password':
        return PiiSensitivity.high;
      default:
        return PiiSensitivity.normal;
    }
  }

  /// 重置为默认配置
  void resetToDefaults() {
    _enabled = true;
    for (final key in _patterns.keys) {
      _patterns[key] = _patterns[key]!.copyWith(enabled: true);
    }
  }

  /// 导出配置
  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'patterns': _patterns.map(
        (key, value) => MapEntry(key, {
          'enabled': value.enabled,
          'maskType': value.maskType.index,
        }),
      ),
    };
  }

  /// 导入配置
  void fromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? true;
    final patternsJson = json['patterns'] as Map<String, dynamic>?;
    if (patternsJson != null) {
      for (final entry in patternsJson.entries) {
        if (_patterns.containsKey(entry.key)) {
          final patternJson = entry.value as Map<String, dynamic>;
          _patterns[entry.key] = _patterns[entry.key]!.copyWith(
            enabled: patternJson['enabled'] ?? true,
          );
        }
      }
    }
  }
}

/// PII 检测模式
class PIIPattern {
  final String name;
  final String description;
  final RegExp regex;
  final MaskType maskType;
  final MaskOptions? maskOptions;
  final bool enabled;

  PIIPattern({
    required this.name,
    required this.description,
    required this.regex,
    required this.maskType,
    this.maskOptions,
    this.enabled = true,
  });

  PIIPattern copyWith({
    String? name,
    String? description,
    RegExp? regex,
    MaskType? maskType,
    MaskOptions? maskOptions,
    bool? enabled,
  }) {
    return PIIPattern(
      name: name ?? this.name,
      description: description ?? this.description,
      regex: regex ?? this.regex,
      maskType: maskType ?? this.maskType,
      maskOptions: maskOptions ?? this.maskOptions,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// 脱敏类型
enum MaskType {
  full, // 完全脱敏：***
  partial, // 部分脱敏：前3后4中间***
  email, // 邮箱脱敏：保留域名
  creditCard, // 信用卡脱敏：保留后4位
  hash, // 哈希标记：[HASHED]
  redact, // 完全遮盖：[REDACTED]
}

/// 脱敏选项
class MaskOptions {
  final int preservePrefix;
  final int preserveSuffix;
  final String maskChar;

  MaskOptions({
    this.preservePrefix = 0,
    this.preserveSuffix = 0,
    this.maskChar = '*',
  });
}

/// R4: PII 敏感度（决定导出默认脱敏动作）。
enum PiiSensitivity {
  /// 高敏感（身份证/银行卡/信用卡/密码）→ 默认「删除此列」
  high,
  /// 普通敏感（email/phone/ip）→ 默认「掩码」
  normal,
}

/// R4: 单列 PII 检测结果（供导出 UI 高亮 + 默认动作决策）。
class PiiColumnDetection {
  final String columnName;
  final bool hasPii;
  /// 命中的 pattern key（email/phone/id_card/...），无 PII 时 null
  final String? patternKey;
  /// pattern 显示名（如 "Email"），无 PII 时 null
  final String? patternName;
  final PiiSensitivity sensitivity;
  /// 采样值命中比例（仅内容检测路径有意义，列名启发式为 null）
  final double? sampleHitRatio;

  const PiiColumnDetection({
    required this.columnName,
    required this.hasPii,
    this.patternKey,
    this.patternName,
    this.sensitivity = PiiSensitivity.normal,
    this.sampleHitRatio,
  });
}
