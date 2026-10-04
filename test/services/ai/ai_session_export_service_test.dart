// ============================================================================
// AI 会话导出服务单测（导出格式 v1，AI-SEX-001~014）。
//
// 覆盖：信封结构/统计、编码与顺序、status/errorMessage 超集回归守卫、
// 脱敏（自由文本 + 深叶子 + 按键名掩值 + session 头）、轻量模式两分支、
// 截断三分支、null 错误路径、文件名 slug 规则（含凭据不进文件名）、
// AiSessionManager.messagesForSession 只读性。
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/ai_conversation_session.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/ai/ai_session_export_service.dart';
import 'package:dbmaster/services/ai/ai_session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AiConversationSession sessionFixture({
    String id = 's1',
    String title = '会话标题',
    String? goalSummary,
    Map<String, dynamic>? metadata,
  }) {
    return AiConversationSession(
      id: id,
      title: title,
      createdAt: DateTime(2026, 9, 28, 10),
      updatedAt: DateTime(2026, 9, 28, 11),
      messageIds: const <String>[],
      metadata: metadata,
      goalSummary: goalSummary,
    );
  }

  AiSessionExportMeta metaFixture({String? connectionName}) {
    return AiSessionExportMeta(
      appVersion: '0.0.1+1',
      aiProvider: 'openai-compatible',
      aiModel: 'gpt-4o',
      locale: 'en',
      exportedAt: DateTime(2026, 9, 28, 12, 30, 45),
      contextConnectionName: connectionName,
    );
  }

  AiMessage messageFixture({
    String id = 'm1',
    bool isUser = true,
    String content = 'hello',
    String? reasoningContent,
    String? code,
    List<String>? extractedCommands,
    String? bookmarkNote,
    String? toolName,
    Map<String, dynamic>? toolArguments,
    String? toolResultSummary,
    Map<String, dynamic>? toolResultData,
    AiMessageStatus status = AiMessageStatus.sent,
    String? errorMessage,
    int promptTokens = 0,
    int completionTokens = 0,
    int totalTokens = 0,
    AiMessageType type = AiMessageType.chat,
  }) {
    return AiMessage(
      id: id,
      isUser: isUser,
      content: content,
      timestamp: DateTime(2026, 9, 28, 11),
      reasoningContent: reasoningContent,
      code: code,
      extractedCommands: extractedCommands,
      bookmarkNote: bookmarkNote,
      type: type,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResultSummary: toolResultSummary,
      toolResultData: toolResultData,
      status: status,
      errorMessage: errorMessage,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  Map<String, dynamic> buildEnvelopeFor(
    List<AiMessage> messages, {
    AiConversationSession? session,
    AiSessionExportMeta? meta,
    AiSessionExportOptions options = const AiSessionExportOptions(),
  }) {
    return AiSessionExportService.buildEnvelope(
      session: session ?? sessionFixture(),
      messages: messages,
      meta: meta ?? metaFixture(),
      options: options,
    );
  }

  Map<String, dynamic> firstSession(Map<String, dynamic> envelope) =>
      (envelope['sessions'] as List<dynamic>).first as Map<String, dynamic>;

  List<dynamic> exportedMessages(Map<String, dynamic> envelope) =>
      firstSession(envelope)['messages'] as List<dynamic>;

  Map<String, dynamic> messageAt(Map<String, dynamic> envelope, int index) =>
      exportedMessages(envelope)[index] as Map<String, dynamic>;

  List<Map<String, dynamic>> truncationsOf(Map<String, dynamic> envelope) =>
      ((envelope['options'] as Map<String, dynamic>)['truncations']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  test('AI-SEX-001 信封结构：format/version/exportedAt/appVersion/app/options 与'
      'session/diagnostics/stats 逐字段正确', () {
    final session = sessionFixture(
      metadata: <String, dynamic>{
        'workbench.contextLock': <String, dynamic>{
          'conn': 'local',
          'db': 'test_db',
          'readOnly': true,
        },
      },
    );
    final messages = <AiMessage>[
      messageFixture(
        id: 'm1',
        promptTokens: 10,
        completionTokens: 3,
        totalTokens: 13,
      ),
      messageFixture(
        id: 'm2',
        isUser: false,
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{
            'kind': 'agent_run',
            'runId': 'r1',
            'goal': 'g',
            'contextSnapshot': <String, dynamic>{
              'conn': 'c',
              'db': 'd',
              'readOnly': false,
              'maxSteps': 40,
            },
          },
        },
      ),
      messageFixture(
        id: 'm3',
        isUser: false,
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{
            'kind': 'agent_step',
            'runId': 'r1',
            'stepNo': 1,
          },
        },
      ),
      messageFixture(
        id: 'm4',
        isUser: false,
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{
            'kind': 'agent_run_end',
            'runId': 'r1',
            'status': 'completed',
            'steps': 1,
            'tokens': 13,
          },
        },
      ),
    ];
    final envelope = buildEnvelopeFor(
      messages,
      session: session,
      meta: metaFixture(connectionName: 'myconn'),
    );

    expect(envelope['format'], 'dbmaster-ai-session-export');
    expect(envelope['version'], 1);
    expect(envelope['exportedAt'], '2026-09-28T12:30:45.000');
    expect(envelope['appVersion'], '0.0.1+1');
    expect(envelope['app'], <String, dynamic>{
      'aiProvider': 'openai-compatible',
      'aiModel': 'gpt-4o',
      'locale': 'en',
    });
    final options = envelope['options'] as Map<String, dynamic>;
    expect(options['includeToolResultData'], isTrue);
    expect(options['redaction'], 'secrets');
    expect(options['truncations'], isEmpty);

    final entry = firstSession(envelope);
    expect(entry['session'], session.toJson());
    final diagnostics = entry['diagnostics'] as Map<String, dynamic>;
    expect(diagnostics['contextLock'], <String, dynamic>{
      'conn': 'local',
      'db': 'test_db',
      'readOnly': true,
    });
    expect(diagnostics['connectionName'], 'myconn');
    final stats = entry['stats'] as Map<String, dynamic>;
    expect(stats['messageCount'], 4);
    expect(stats['userMessageCount'], 1);
    expect(stats['promptTokens'], 10);
    expect(stats['completionTokens'], 3);
    expect(stats['totalTokens'], 13);
    expect(stats['agentRunCount'], 1);
    expect(stats['agentStepCount'], 1);
  });

  test('AI-SEX-002 encodeEnvelope：jsonDecode 可解析、消息顺序与输入一致、空消息列合法', () {
    final messages = <AiMessage>[
      messageFixture(id: 'a', content: 'first'),
      messageFixture(id: 'b', content: 'second'),
      messageFixture(id: 'c', content: 'third'),
    ];
    final encoded = AiSessionExportService.encodeEnvelope(
      buildEnvelopeFor(messages),
    );
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    expect(decoded['format'], 'dbmaster-ai-session-export');
    final ids = exportedMessages(
      decoded,
    ).map((dynamic m) => (m as Map<String, dynamic>)['id'] as String).toList();
    expect(ids, <String>['a', 'b', 'c']);

    final emptyEncoded = AiSessionExportService.encodeEnvelope(
      buildEnvelopeFor(const <AiMessage>[]),
    );
    final emptyDecoded = jsonDecode(emptyEncoded) as Map<String, dynamic>;
    expect(exportedMessages(emptyDecoded), isEmpty);
    expect(
      (firstSession(emptyDecoded)['stats']
          as Map<String, dynamic>)['messageCount'],
      0,
    );
  });

  test('AI-SEX-003 回归守卫：导出消息必含 status 与 errorMessage（toJson 缺席的超集）', () {
    final message = messageFixture(
      id: 'm1',
      content: 'x',
      status: AiMessageStatus.failed,
      errorMessage: 'boom',
    );
    // 守卫：既有模型 toJson 不含这两键，导出为其补超集（不改模型）。
    expect(message.toJson().containsKey('status'), isFalse);
    expect(message.toJson().containsKey('errorMessage'), isFalse);

    final exported = messageAt(buildEnvelopeFor(<AiMessage>[message]), 0);
    expect(exported.containsKey('status'), isTrue);
    expect(exported['status'], 'failed');
    expect(exported.containsKey('errorMessage'), isTrue);
    expect(exported['errorMessage'], 'boom');
  });

  test('AI-SEX-004 脱敏：六个自由文本键 + extractedCommands 逐元素均为 *** 形态', () {
    final message = messageFixture(
      id: 'm1',
      content:
          "mysql://u:p@h/db password='x' Authorization: Bearer t api_key=k",
      reasoningContent: 'password="secret"',
      code: 'SET pwd=abc123',
      toolResultSummary: "password='q'",
      errorMessage: 'mysql://a:b@c/db',
      bookmarkNote: 'api_key=zzz',
      extractedCommands: <String>['SET password="x"', 'SELECT 1'],
    );
    final exported = messageAt(buildEnvelopeFor(<AiMessage>[message]), 0);
    expect(
      exported['content'],
      'mysql://u:***@h/db *** Authorization: Bearer *** ***',
    );
    expect(exported['reasoningContent'], '***');
    expect(exported['code'], 'SET ***');
    expect(exported['toolResultSummary'], '***');
    expect(exported['errorMessage'], 'mysql://a:***@c/db');
    expect(exported['bookmarkNote'], '***');
    expect(exported['extractedCommands'], <String>['SET ***', 'SELECT 1']);
  });

  test('AI-SEX-005 脱敏：toolArguments/toolResultData 深叶子脱敏，非字符串叶子'
      '与结构键逐字节不变', () {
    final argsFixture = <String, dynamic>{
      'sql': 'mysql://u:p@h/db',
      'mode': 'read',
      'limit': 42,
      'enabled': true,
      'nothing': null,
    };
    final dataFixture = <String, dynamic>{
      'agent': <String, dynamic>{
        'kind': 'agent_step',
        'runId': 'r1',
        'stepNo': 1,
        'gateDecision': 'allowed',
        'summary': 'api_key=deep',
        'resultRef': <String, dynamic>{
          'rowCount': 2,
          'columns': <String>['a', 'b'],
          'snapshotRows': <Map<String, dynamic>>[
            <String, dynamic>{'a': "password='x'", 'n': 7},
            <String, dynamic>{'a': 'mysql://x:y@z/db'},
          ],
        },
      },
      'plain': <String, dynamic>{
        'nested': <Map<String, dynamic>>[
          <String, dynamic>{'k': 'Authorization: Bearer secret'},
        ],
      },
    };
    final message = messageFixture(
      id: 'm1',
      content: 'x',
      toolArguments: argsFixture,
      toolResultData: dataFixture,
    );
    final exported = messageAt(buildEnvelopeFor(<AiMessage>[message]), 0);

    final args = exported['toolArguments'] as Map<String, dynamic>;
    expect(args['sql'], 'mysql://u:***@h/db');
    expect(args['mode'], 'read');
    expect(args['limit'], 42);
    expect(args['enabled'], isTrue);
    expect(args['nothing'], isNull);

    final data = exported['toolResultData'] as Map<String, dynamic>;
    final agent = data['agent'] as Map<String, dynamic>;
    expect(agent['kind'], 'agent_step');
    expect(agent['summary'], '***');
    final ref = agent['resultRef'] as Map<String, dynamic>;
    expect(ref['rowCount'], 2);
    expect(ref['columns'], <String>['a', 'b']);
    final rows = ref['snapshotRows'] as List<dynamic>;
    expect((rows[0] as Map<String, dynamic>)['a'], '***');
    expect((rows[0] as Map<String, dynamic>)['n'], 7);
    expect((rows[1] as Map<String, dynamic>)['a'], 'mysql://x:***@z/db');
    final nested =
        ((data['plain'] as Map<String, dynamic>)['nested'] as List<dynamic>);
    expect(
      (nested[0] as Map<String, dynamic>)['k'],
      'Authorization: Bearer ***',
    );

    // copy-on-write：输入活对象不被污染。
    expect((argsFixture['sql']), 'mysql://u:p@h/db');
    expect(
      ((dataFixture['agent'] as Map<String, dynamic>)['summary']),
      'api_key=deep',
    );
  });

  test('AI-SEX-006 轻量：非 agent toolResultData → null，null 保持 null', () {
    const options = AiSessionExportOptions(includeToolResultData: false);
    final nonAgent = messageFixture(
      id: 'm1',
      content: 'x',
      toolResultData: <String, dynamic>{
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{'a': 1},
        ],
      },
    );
    final nullData = messageFixture(id: 'm2', content: 'y');
    final envelope = buildEnvelopeFor(<AiMessage>[
      nonAgent,
      nullData,
    ], options: options);
    expect(messageAt(envelope, 0)['toolResultData'], isNull);
    expect(messageAt(envelope, 1)['toolResultData'], isNull);
    // 输入活对象不被清空。
    expect(nonAgent.toolResultData, isNotNull);
  });

  test('AI-SEX-007 轻量：agent 载荷保留且 resultRef 无 snapshotRows、rowCount/columns'
      '原值在；锚点/终局/门卡三类结构完整', () {
    const options = AiSessionExportOptions(includeToolResultData: false);
    final step = messageFixture(
      id: 'm1',
      content: '',
      toolResultData: <String, dynamic>{
        'agent': <String, dynamic>{
          'kind': 'agent_step',
          'runId': 'r1',
          'stepNo': 2,
          'gateDecision': 'allowed',
          'summary': 'ok',
          'resultRef': <String, dynamic>{
            'rowCount': 5,
            'columns': <String>['a', 'b'],
            'snapshotRows': <Map<String, dynamic>>[
              <String, dynamic>{'a': 1},
            ],
          },
        },
      },
    );
    final anchor = messageFixture(
      id: 'm2',
      content: '',
      toolResultData: <String, dynamic>{
        'agent': <String, dynamic>{
          'kind': 'agent_run',
          'runId': 'r1',
          'goal': 'g',
          'contextSnapshot': <String, dynamic>{
            'conn': 'c',
            'db': 'd',
            'readOnly': false,
            'maxSteps': 40,
          },
        },
      },
    );
    final gate = messageFixture(
      id: 'm3',
      content: '',
      toolResultData: <String, dynamic>{
        'agent': <String, dynamic>{
          'kind': 'agent_confirm',
          'runId': 'r1',
          'stepNo': 3,
          'sql': 'UPDATE t SET a=1',
          'outcome': 'approved',
        },
      },
    );
    final terminal = messageFixture(
      id: 'm4',
      content: 'done',
      toolResultData: <String, dynamic>{
        'agent': <String, dynamic>{
          'kind': 'agent_run_end',
          'runId': 'r1',
          'status': 'completed',
          'steps': 3,
          'tokens': 99,
          'summaryText': 'done',
        },
      },
    );
    final envelope = buildEnvelopeFor(<AiMessage>[
      step,
      anchor,
      gate,
      terminal,
    ], options: options);

    final exportedStep = messageAt(envelope, 0);
    final stepData = exportedStep['toolResultData'] as Map<String, dynamic>;
    final stepAgent = stepData['agent'] as Map<String, dynamic>;
    expect(stepAgent['kind'], 'agent_step');
    final ref = stepAgent['resultRef'] as Map<String, dynamic>;
    expect(ref.containsKey('snapshotRows'), isFalse);
    expect(ref['rowCount'], 5);
    expect(ref['columns'], <String>['a', 'b']);

    final anchorAgent =
        (messageAt(envelope, 1)['toolResultData']
                as Map<String, dynamic>)['agent']
            as Map<String, dynamic>;
    expect(anchorAgent['kind'], 'agent_run');
    final snapshot = anchorAgent['contextSnapshot'] as Map<String, dynamic>;
    expect(snapshot['conn'], 'c');
    expect(snapshot['db'], 'd');
    expect(snapshot['readOnly'], isFalse);
    expect(snapshot['maxSteps'], 40);

    final gateAgent =
        (messageAt(envelope, 2)['toolResultData']
                as Map<String, dynamic>)['agent']
            as Map<String, dynamic>;
    expect(gateAgent['kind'], 'agent_confirm');
    expect(gateAgent['outcome'], 'approved');

    final endAgent =
        (messageAt(envelope, 3)['toolResultData']
                as Map<String, dynamic>)['agent']
            as Map<String, dynamic>;
    expect(endAgent['kind'], 'agent_run_end');
    expect(endAgent['status'], 'completed');
    expect(endAgent['steps'], 3);
    expect(endAgent['tokens'], 99);
  });

  test('AI-SEX-008 截断：257,000 字符 content → 截断 + marker + truncations 记录'
      '正确；256,000 恰界不截断', () {
    final longContent = 'x' * 257000;
    final envelope = buildEnvelopeFor(<AiMessage>[
      messageFixture(id: 'm1', content: longContent),
    ]);
    final content = messageAt(envelope, 0)['content'] as String;
    expect(
      content.length,
      256000 + '\n…[truncated, originalChars=257000]'.length,
    );
    expect(content.startsWith('x' * 256000), isTrue);
    expect(content.endsWith('\n…[truncated, originalChars=257000]'), isTrue);
    expect(truncationsOf(envelope), <Map<String, dynamic>>[
      <String, dynamic>{
        'sessionId': 's1',
        'messageId': 'm1',
        'field': 'content',
        'originalChars': 257000,
        'policy': 'truncated',
      },
    ]);

    final boundary = buildEnvelopeFor(<AiMessage>[
      messageFixture(id: 'm2', content: 'y' * 256000),
    ]);
    expect(messageAt(boundary, 0)['content'], 'y' * 256000);
    expect(truncationsOf(boundary), isEmpty);
  });

  test('AI-SEX-009 截断：toolResultData 超限三支——删 snapshotRows 达标保留 /'
      '非 agent 替换标记 / agent 删后仍超替换', () {
    // 分支 A：agent 载荷带大 snapshotRows，删后达标 → 结构保留、无记录。
    final bigRows = List<Map<String, dynamic>>.generate(
      1200,
      (int i) => <String, dynamic>{'k': 'x' * 900, 'i': i},
    );
    final agentPayload = <String, dynamic>{
      'agent': <String, dynamic>{
        'kind': 'agent_step',
        'runId': 'r1',
        'stepNo': 1,
        'gateDecision': 'allowed',
        'summary': 'ok',
        'resultRef': <String, dynamic>{
          'rowCount': 1200,
          'columns': <String>['k', 'i'],
          'snapshotRows': bigRows,
        },
      },
    };
    // 预检：夹具确实超限（自验证，防脆断言）。
    expect(jsonEncode(agentPayload).length, greaterThan(1000000));
    final envA = buildEnvelopeFor(<AiMessage>[
      messageFixture(id: 'm1', content: '', toolResultData: agentPayload),
    ]);
    final dataA = messageAt(envA, 0)['toolResultData'] as Map<String, dynamic>;
    final agentA = dataA['agent'] as Map<String, dynamic>;
    final refA = agentA['resultRef'] as Map<String, dynamic>;
    expect(refA.containsKey('snapshotRows'), isFalse);
    expect(refA['rowCount'], 1200);
    expect(refA['columns'], <String>['k', 'i']);
    expect(truncationsOf(envA), isEmpty);

    // 分支 B：非 agent（无 snapshotRows 可删）仍超 → 替换标记 + 记录。
    final plainPayload = <String, dynamic>{
      'rows': <String>['x' * 1100000],
    };
    final plainChars = jsonEncode(plainPayload).length;
    expect(plainChars, greaterThan(1000000));
    final envB = buildEnvelopeFor(<AiMessage>[
      messageFixture(id: 'm2', content: '', toolResultData: plainPayload),
    ]);
    expect(messageAt(envB, 0)['toolResultData'], <String, dynamic>{
      'truncated': true,
      'originalChars': plainChars,
    });
    expect(truncationsOf(envB), <Map<String, dynamic>>[
      <String, dynamic>{
        'sessionId': 's1',
        'messageId': 'm2',
        'field': 'toolResultData',
        'originalChars': plainChars,
        'policy': 'replaced-with-marker',
      },
    ]);

    // 分支 C：agent 载荷删 snapshotRows 后仍超（超大 summary）→ 替换。
    final hugeSummaryPayload = <String, dynamic>{
      'agent': <String, dynamic>{
        'kind': 'agent_step',
        'runId': 'r2',
        'stepNo': 1,
        'summary': 'y' * 1100000,
        'resultRef': <String, dynamic>{
          'rowCount': 1,
          'columns': <String>['a'],
          'snapshotRows': <Map<String, dynamic>>[
            <String, dynamic>{'a': 1},
          ],
        },
      },
    };
    final envC = buildEnvelopeFor(<AiMessage>[
      messageFixture(id: 'm3', content: '', toolResultData: hugeSummaryPayload),
    ]);
    final dataC = messageAt(envC, 0)['toolResultData'] as Map<String, dynamic>;
    expect(dataC['truncated'], isTrue);
    expect(dataC['originalChars'] as int, greaterThan(1000000));
    expect(truncationsOf(envC).single['policy'], 'replaced-with-marker');
  });

  test('AI-SEX-010 错误路径：可空字段 null 全组合不抛（toolArguments/toolResultData/'
      'metadata/connectionName null）', () {
    final message = messageFixture(id: 'm1', content: 'x');
    final envelope = buildEnvelopeFor(<AiMessage>[message]);
    final encoded = AiSessionExportService.encodeEnvelope(envelope);
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final exported = messageAt(decoded, 0);
    expect(exported['reasoningContent'], isNull);
    expect(exported['code'], isNull);
    expect(exported['extractedCommands'], isNull);
    expect(exported['toolArguments'], isNull);
    expect(exported['toolResultData'], isNull);
    expect(exported['toolResultSummary'], isNull);
    expect(exported['errorMessage'], isNull);
    expect(exported['bookmarkNote'], isNull);
    final diagnostics =
        firstSession(decoded)['diagnostics'] as Map<String, dynamic>;
    expect(diagnostics['contextLock'], isNull);
    expect(diagnostics['connectionName'], isNull);

    // 轻量 + null toolResultData 不抛；metadata 空 map 无 contextLock 键 → null。
    final env2 = buildEnvelopeFor(
      <AiMessage>[messageFixture(id: 'm2', content: 'y')],
      session: sessionFixture(metadata: <String, dynamic>{}),
      options: const AiSessionExportOptions(includeToolResultData: false),
    );
    expect(messageAt(env2, 0)['toolResultData'], isNull);
    expect(
      (firstSession(env2)['diagnostics']
          as Map<String, dynamic>)['contextLock'],
      isNull,
    );
  });

  test('AI-SEX-011 文件名：CJK 保留、全特殊字符回退 session、40 截断、时间戳格式', () {
    final now = DateTime(2026, 9, 28, 14, 30, 5);
    expect(
      AiSessionExportService.exportFileName('中文会话', now),
      'dbmaster-ai-session-中文会话-20260928-143005.json',
    );
    expect(
      AiSessionExportService.exportFileName('Hello World!! -- 测试', now),
      'dbmaster-ai-session-hello-world-测试-20260928-143005.json',
    );
    expect(
      AiSessionExportService.exportFileName('!!!@@@###', now),
      'dbmaster-ai-session-session-20260928-143005.json',
    );
    expect(
      AiSessionExportService.exportFileName('', now),
      'dbmaster-ai-session-session-20260928-143005.json',
    );
    expect(
      AiSessionExportService.exportFileName('a' * 60, now),
      'dbmaster-ai-session-${'a' * 40}-20260928-143005.json',
    );
  });

  test('AI-SEX-012 只读性：messagesForSession 不改 currentSession、不增文件、'
      '不通知、未知 id 空列', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final Directory tempRoot = await Directory.systemTemp.createTemp(
      'ai_sex_012_',
    );
    late AiSessionManager manager;
    addTearDown(() async {
      manager.dispose();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    manager = AiSessionManager(
      storageOverride: AiSessionStorageOverride(
        directory: tempRoot,
        prefsPrefix: 'sex012_',
      ),
    );
    final sessionA = manager.createSession(title: '会话 A');
    manager.addMessage(messageFixture(id: 'ma1', content: 'A 消息'));
    manager.addMessage(messageFixture(id: 'ma2', content: 'A 第二条'));
    final sessionB = manager.createSession(title: '会话 B');
    manager.addMessage(messageFixture(id: 'mb1', content: 'B 消息'));
    await manager.persist();
    // 等 debounce（500ms）落定，基线文件集稳定。
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final Set<String> filesBefore = tempRoot
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .toSet();

    final AiConversationSession? currentBefore = manager.currentSession;
    final int sessionsCountBefore = manager.sessions.length;
    var notified = 0;
    manager.addListener(() => notified++);

    final messagesA = manager.messagesForSession(sessionA.id);
    expect(messagesA.map((AiMessage m) => m.id).toList(), <String>[
      'ma1',
      'ma2',
    ]);
    expect(messagesA.first.content, 'A 消息');
    expect(identical(manager.currentSession, currentBefore), isTrue);
    expect(manager.currentSession?.id, sessionB.id);
    expect(manager.sessions.length, sessionsCountBefore);
    expect(notified, 0);
    expect(manager.messagesForSession('unknown'), isEmpty);
    expect(
      () => messagesA.add(messageFixture(id: 'x', content: 'y')),
      throwsUnsupportedError,
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));
    final Set<String> filesAfter = tempRoot
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .toSet();
    expect(filesAfter, filesBefore);
  });

  test('AI-SEX-013 脱敏（按键名掩值）：敏感键名字符串值整体 *** 且键保留，'
      '嵌套/List 内同效、大小写与分隔变体命中、非敏感键与非字符串值不动', () {
    final argsFixture = <String, dynamic>{
      'password': 'abc123',
      'PWD': 'x',
      'apiKey': 'sk-abc',
      'Authorization': 'Bearer sk-x',
      'x-api-key': 'sk-y',
      'query': 'SELECT 1',
      'limit': 42,
    };
    final dataFixture = <String, dynamic>{
      'connection': <String, dynamic>{'api_key': 'sk-x', 'host': 'h'},
      'settings': <Map<String, dynamic>>[
        <String, dynamic>{'token': 't-1', 'retries': 3},
      ],
      'note': null,
      'flags': <String, dynamic>{'secret': true},
    };
    final message = messageFixture(
      id: 'm1',
      content: 'x',
      toolArguments: argsFixture,
      toolResultData: dataFixture,
    );
    final exported = messageAt(buildEnvelopeFor(<AiMessage>[message]), 0);

    final args = exported['toolArguments'] as Map<String, dynamic>;
    expect(args.containsKey('password'), isTrue, reason: '键保留（只掩值）');
    expect(args['password'], '***', reason: 'JSON 冒号形态主防线');
    expect(args['PWD'], '***', reason: '大小写不敏感');
    expect(args['apiKey'], '***');
    expect(args['Authorization'], '***');
    expect(args['x-api-key'], '***', reason: '去 -/_ 归一包含比对命中');
    expect(args['query'], 'SELECT 1', reason: '非敏感键字符串原样');
    expect(args['limit'], 42, reason: '非字符串值不动');

    final data = exported['toolResultData'] as Map<String, dynamic>;
    final connection = data['connection'] as Map<String, dynamic>;
    expect(connection['api_key'], '***', reason: '嵌套 Map 内同效');
    expect(connection['host'], 'h');
    final settings =
        (data['settings'] as List<dynamic>).first as Map<String, dynamic>;
    expect(settings['token'], '***', reason: 'List 元素 Map 内同效');
    expect(settings['retries'], 3);
    expect(data['note'], isNull);
    expect(
      (data['flags'] as Map<String, dynamic>)['secret'],
      isTrue,
      reason: '敏感键名下非字符串值不动',
    );

    // copy-on-write：输入活对象不被污染。
    expect(argsFixture['password'], 'abc123');
    expect(
      (dataFixture['connection'] as Map<String, dynamic>)['api_key'],
      'sk-x',
    );
  });

  test('AI-SEX-014 session 头脱敏：信封 title/goalSummary 过 redactSecrets、'
      'metadata 白名单仅 contextLock、exportFileName slug 无凭据', () {
    final session = sessionFixture(
      title: 'connect with password=abc123',
      goalSummary: 'goal: mysql://root:hunter2@db',
      metadata: <String, dynamic>{
        'workbench.contextLock': <String, dynamic>{'conn': 'local'},
        'workbench.someFutureKey': 'leak-me',
        'customNote': 'secret-value',
      },
    );
    final entry = firstSession(
      buildEnvelopeFor(<AiMessage>[
        messageFixture(id: 'm1', content: 'x'),
      ], session: session),
    );
    final exportedSession = entry['session'] as Map<String, dynamic>;

    expect(exportedSession['title'], 'connect with ***');
    expect(exportedSession['goalSummary'], 'goal: mysql://root:***@db');
    expect(exportedSession['metadata'], <String, dynamic>{
      'workbench.contextLock': <String, dynamic>{'conn': 'local'},
    }, reason: 'metadata 白名单：非 contextLock 键丢弃');
    // copy-on-write：活会话对象不被污染。
    expect(session.title, 'connect with password=abc123');
    expect(
      (session.metadata as Map<String, dynamic>).containsKey('customNote'),
      isTrue,
    );
    // diagnostics.contextLock 语义不变。
    expect(
      (entry['diagnostics'] as Map<String, dynamic>)['contextLock'],
      <String, dynamic>{'conn': 'local'},
    );

    // 白名单边界：metadata 无 contextLock → 空 map；metadata null → null。
    final noLockSession =
        (firstSession(
              buildEnvelopeFor(
                <AiMessage>[messageFixture(id: 'm2', content: 'x')],
                session: sessionFixture(metadata: <String, dynamic>{'a': 'b'}),
              ),
            )['session']
            as Map<String, dynamic>);
    expect(noLockSession['metadata'], <String, dynamic>{});
    final nullMetaSession =
        (firstSession(
              buildEnvelopeFor(<AiMessage>[
                messageFixture(id: 'm3', content: 'x'),
              ], session: sessionFixture()),
            )['session']
            as Map<String, dynamic>);
    expect(nullMetaSession['metadata'], isNull);

    // 文件名：slug 原料为脱敏后标题，凭据形态不进文件名。
    final now = DateTime(2026, 9, 28, 14, 30, 5);
    final String fileName = AiSessionExportService.exportFileName(
      'connect with password=abc123',
      now,
    );
    expect(fileName, 'dbmaster-ai-session-connect-with-20260928-143005.json');
    expect(fileName.contains('abc123'), isFalse);
  });
}
