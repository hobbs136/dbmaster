/// AI 会话导出服务（导出格式 v1，纯 Dart，禁 flutter import）。
///
/// 把单个 [AiConversationSession] + 其消息列序列化为自包含 JSON 信封，
/// 供外部 AI 做诊断。格式契约逐字段固定（design：导出格式 v1）：
/// - 消息经 [AiMessage.toJson] 键集 + `status`/`errorMessage` 超集（模型
///   toJson 缺席这两字段，导出补上——不改模型与既有 toJson）；
/// - 流水线按序确定：补字段 → ①脱敏（redactSecrets，redactSql:false）→
///   ②轻量（可选剔除结果数据）→ ③截断（自由文本 256k / toolResultData 1M，
///   超限记 truncations）；
/// - 深叶子脱敏只动 Map 值 / List 元素中的字符串：字符串叶子过
///   [redactSecrets]，另按键名掩值——Map 键名命中敏感词表时其字符串值
///   整体替换为 `***`（键与非字符串叶子原样）。
library;

import 'dart:convert';

import '../../models/ai_conversation_session.dart';
import '../../models/database_models.dart';
import '../../utils/secret_redactor.dart';

/// 导出元数据（调用方注入：应用版本、AI 配置、导出时间、可选连接名）。
class AiSessionExportMeta {
  const AiSessionExportMeta({
    required this.appVersion,
    required this.aiProvider,
    required this.aiModel,
    required this.locale,
    required this.exportedAt,
    this.contextConnectionName,
  });

  final String appVersion;
  final String aiProvider;
  final String aiModel;
  final String locale;
  final DateTime exportedAt;

  /// UI 预解析的连接名（无连接上下文时 null）。
  final String? contextConnectionName;
}

/// 导出选项。
class AiSessionExportOptions {
  const AiSessionExportOptions({this.includeToolResultData = true});

  /// false 时执行轻量步骤：非 agent 的 toolResultData 置 null；
  /// agent 载荷只删 `agent.resultRef.snapshotRows`（rowCount/columns 保留）。
  final bool includeToolResultData;
}

/// AI 会话导出服务（纯静态）。
class AiSessionExportService {
  AiSessionExportService._();

  static const String exportFormat = 'dbmaster-ai-session-export';
  static const int exportVersion = 1;
  static const int maxFreeTextChars = 256000;
  static const int maxToolResultDataChars = 1000000;

  /// ①脱敏覆盖的自由文本键（`extractedCommands` 逐元素另走）。
  static const List<String> _freeTextKeys = <String>[
    'content',
    'reasoningContent',
    'code',
    'toolResultSummary',
    'errorMessage',
    'bookmarkNote',
  ];

  /// 构建单会话导出信封（sessions 为单元素列）。
  static Map<String, dynamic> buildEnvelope({
    required AiConversationSession session,
    required List<AiMessage> messages,
    required AiSessionExportMeta meta,
    AiSessionExportOptions options = const AiSessionExportOptions(),
  }) {
    final List<Map<String, dynamic>> truncations = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> exportedMessages =
        <Map<String, dynamic>>[];
    for (final AiMessage message in messages) {
      exportedMessages.add(
        _transformMessage(
          sessionId: session.id,
          message: message,
          options: options,
          truncations: truncations,
        ),
      );
    }

    int promptTokens = 0;
    int completionTokens = 0;
    int totalTokens = 0;
    int userCount = 0;
    int agentRunCount = 0;
    int agentStepCount = 0;
    for (final AiMessage message in messages) {
      promptTokens += message.promptTokens;
      completionTokens += message.completionTokens;
      totalTokens += message.totalTokens;
      if (message.isUser) userCount++;
      if (_isAgentKind(message, 'agent_run')) agentRunCount++;
      if (_isAgentKind(message, 'agent_step')) agentStepCount++;
    }

    final Map<String, dynamic>? metadata = session.metadata;
    final Object? contextLock = metadata?['workbench.contextLock'];

    // session 头脱敏（toJson 为新 map，不触活会话对象）：title/goalSummary
    // 过 redactSecrets（标题/目标摘要可能内嵌凭据形态）；metadata 白名单
    // 只保留 workbench.contextLock，其它键丢弃——消除未来 workbench.* 扩键
    // 自动泄漏面（contextLock 结构化诊断值已另在 diagnostics 透出）。
    final Map<String, dynamic> sessionJson = Map<String, dynamic>.from(
      session.toJson(),
    );
    final Object? title = sessionJson['title'];
    if (title is String) sessionJson['title'] = redactSecrets(title);
    final Object? goalSummary = sessionJson['goalSummary'];
    if (goalSummary is String) {
      sessionJson['goalSummary'] = redactSecrets(goalSummary);
    }
    sessionJson['metadata'] = metadata == null
        ? null
        // null-aware 标记：contextLock 为 null 时条目整体省略（白名单空 map）。
        : <String, dynamic>{'workbench.contextLock': ?contextLock};

    return <String, dynamic>{
      'format': exportFormat,
      'version': exportVersion,
      'exportedAt': meta.exportedAt.toIso8601String(),
      'appVersion': meta.appVersion,
      'app': <String, dynamic>{
        'aiProvider': meta.aiProvider,
        'aiModel': meta.aiModel,
        'locale': meta.locale,
      },
      'options': <String, dynamic>{
        'includeToolResultData': options.includeToolResultData,
        'redaction': 'secrets',
        'truncations': truncations,
      },
      'sessions': <Map<String, dynamic>>[
        <String, dynamic>{
          'session': sessionJson,
          'diagnostics': <String, dynamic>{
            'contextLock': contextLock,
            'connectionName': meta.contextConnectionName,
          },
          'stats': <String, dynamic>{
            'messageCount': messages.length,
            'userMessageCount': userCount,
            'promptTokens': promptTokens,
            'completionTokens': completionTokens,
            'totalTokens': totalTokens,
            'agentRunCount': agentRunCount,
            'agentStepCount': agentStepCount,
          },
          'messages': exportedMessages,
        },
      ],
    };
  }

  /// 信封编码：jsonEncode 缩进两格。
  static String encodeEnvelope(Map<String, dynamic> envelope) {
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// 导出文件名：`dbmaster-ai-session-<slug>-<yyyyMMdd-HHmmss>.json`。
  ///
  /// slug：标题先过 [redactSecrets]（标题内嵌凭据形态不进文件名，掩码
  /// `*` 随后折叠为 `-`）、小写化、`[^\p{L}\p{N}]+`（unicode）折叠为 `-`、
  /// 去首尾 `-`、截 40 字符（按 code point，CJK 保留）；空回退 `session`。
  static String exportFileName(String sessionTitle, DateTime now) {
    final String folded = redactSecrets(
      sessionTitle,
    ).toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-');
    final String trimmed = folded.replaceAll(RegExp(r'^-|-$'), '');
    final int runeCount = trimmed.runes.length;
    final String slug = runeCount <= 40
        ? trimmed
        : String.fromCharCodes(trimmed.runes.take(40));
    final String fallback = slug.isEmpty ? 'session' : slug;
    final String stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}'
        '-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    return 'dbmaster-ai-session-$fallback-$stamp.json';
  }

  /// 消息变换流水线（按序确定）：
  /// ① toJson 超集（补 status/errorMessage）② 脱敏 ③ 轻量 ④ 截断。
  static Map<String, dynamic> _transformMessage({
    required String sessionId,
    required AiMessage message,
    required AiSessionExportOptions options,
    required List<Map<String, dynamic>> truncations,
  }) {
    final Map<String, dynamic> j = Map<String, dynamic>.from(message.toJson());
    j['status'] = message.status.name;
    j['errorMessage'] = message.errorMessage;

    // ① 脱敏：自由文本键 + extractedCommands 逐元素。
    for (final String key in _freeTextKeys) {
      final Object? value = j[key];
      if (value is String) {
        j[key] = redactSecrets(value);
      }
    }
    final Object? extracted = j['extractedCommands'];
    if (extracted is List) {
      j['extractedCommands'] = extracted
          .map<Object?>((Object? e) => e is String ? redactSecrets(e) : e)
          .toList();
    }
    final Object? arguments = j['toolArguments'];
    if (arguments != null) {
      j['toolArguments'] = _redactDeep(arguments);
    }
    Object? resultData = j['toolResultData'];
    if (resultData != null) {
      resultData = _redactDeep(resultData);
    }

    // ② 轻量（深拷贝上操作，不触调用方活对象）。
    if (!options.includeToolResultData && resultData != null) {
      resultData = _applyLightweight(resultData);
    }
    j['toolResultData'] = resultData;

    // ③ 截断：自由文本键超限 → 截断 + 尾部 marker + truncations 记录。
    for (final String key in _freeTextKeys) {
      final Object? value = j[key];
      if (value is String && value.length > maxFreeTextChars) {
        j[key] =
            '${value.substring(0, maxFreeTextChars)}'
            '\n…[truncated, originalChars=${value.length}]';
        truncations.add(<String, dynamic>{
          'sessionId': sessionId,
          'messageId': message.id,
          'field': key,
          'originalChars': value.length,
          'policy': 'truncated',
        });
      }
    }

    // ③ 截断：toolResultData 编码超限 → agent 载荷先删 snapshotRows 重编码；
    // 仍超 → 整体替换为标记对象 + truncations 记录（policy: replaced-with-marker）。
    final Object? data = j['toolResultData'];
    if (data is Map<String, dynamic>) {
      int encodedChars = jsonEncode(data).length;
      if (encodedChars > maxToolResultDataChars) {
        final Object? agent = data['agent'];
        if (agent is Map<String, dynamic>) {
          final Object? ref = agent['resultRef'];
          if (ref is Map<String, dynamic> && ref.containsKey('snapshotRows')) {
            ref.remove('snapshotRows');
            encodedChars = jsonEncode(data).length;
          }
        }
        if (encodedChars > maxToolResultDataChars) {
          j['toolResultData'] = <String, dynamic>{
            'truncated': true,
            'originalChars': encodedChars,
          };
          truncations.add(<String, dynamic>{
            'sessionId': sessionId,
            'messageId': message.id,
            'field': 'toolResultData',
            'originalChars': encodedChars,
            'policy': 'replaced-with-marker',
          });
        }
      }
    }

    return j;
  }

  /// 深叶子脱敏：Map 值 / List 元素递归（键不动），字符串走
  /// [redactSecrets]；另按键名掩值——Map 键名命中 [_sensitiveKeyNames]
  /// 时其字符串值整体替换为 `***`（键保留、非字符串值不动、嵌套结构照旧
  /// 递归）。掩值先于正则（敏感键名值整体掩码，正则对其为幂等空转）。
  /// 全程拷贝（copy-on-write），不改调用方传入的活 Map/List。
  static Object? _redactDeep(Object? value) {
    if (value is String) return redactSecrets(value);
    if (value is Map) {
      final Map<String, dynamic> copy = <String, dynamic>{};
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final String key = '${entry.key}';
        final Object? child = entry.value;
        copy[key] = _isSensitiveKeyName(key) && child is String
            ? '***'
            : _redactDeep(child);
      }
      return copy;
    }
    if (value is List) {
      return value.map<Object?>(_redactDeep).toList();
    }
    return value;
  }

  /// 按键名掩值的敏感词表（归一形态：lowercase + 去 `-`/`_`；
  /// `api_key`/`api-key` 归一后即 `apikey`，不重复列）。
  static const List<String> _sensitiveKeyNames = <String>[
    'password',
    'passwd',
    'pwd',
    'secret',
    'token',
    'apikey',
    'authorization',
  ];

  /// 键名归一（lowercase + 去 `-`/`_`）后与词表做包含比对——
  /// `API_KEY`/`ApiKey`/`x-api-key` 均命中；导出面宁过掩不漏掩。
  static bool _isSensitiveKeyName(String key) {
    final String normalized = key.toLowerCase().replaceAll(RegExp('[-_]'), '');
    for (final String name in _sensitiveKeyNames) {
      if (normalized.contains(name)) return true;
    }
    return false;
  }

  /// 轻量步骤：非 agent toolResultData → null；agent 载荷只删
  /// `resultRef.snapshotRows`（无 resultRef 键 / 非 Map 时为空操作）。
  static Object? _applyLightweight(Object? data) {
    if (data is! Map<String, dynamic>) return data;
    final bool hasAgent = data.containsKey('agent');
    if (!hasAgent) return null;
    final Object? agent = data['agent'];
    if (agent is Map<String, dynamic>) {
      final Object? ref = agent['resultRef'];
      if (ref is Map<String, dynamic>) {
        ref.remove('snapshotRows');
      }
    }
    return data;
  }

  static bool _isAgentKind(AiMessage message, String kind) {
    final Object? agent = message.toolResultData?['agent'];
    return agent is Map && agent['kind'] == kind;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
