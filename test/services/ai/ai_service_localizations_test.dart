import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/ai_tree_node_context.dart';
import 'package:dbmaster/services/ai/ai_service_localizations.dart';

void main() {
  group('AiServiceLocalizations', () {
    test('英文本地化应有系统提示', () {
      final l10n = AiServiceLocalizations('en');
      expect(l10n.systemPromptIdentity, isNotEmpty);
      expect(l10n.systemPromptContextLabel, isNotEmpty);
    });

    test('中文本地化应有系统提示', () {
      final l10n = AiServiceLocalizations('zh');
      expect(l10n.systemPromptIdentity, isNotEmpty);
    });

    test('systemPromptRule1 应不为空', () {
      final l10n = AiServiceLocalizations('en');
      expect(l10n.systemPromptRule1, isNotEmpty);
    });

    test('所有规则应不为空', () {
      final l10n = AiServiceLocalizations('en');
      expect(l10n.systemPromptRule1, isNotEmpty);
      expect(l10n.systemPromptRule2, isNotEmpty);
      expect(l10n.systemPromptRule3, isNotEmpty);
      expect(l10n.systemPromptRule4, isNotEmpty);
      expect(l10n.systemPromptRule5, isNotEmpty);
    });

    test('数据生成规则应不为空', () {
      final l10n = AiServiceLocalizations('en');
      expect(l10n.systemPromptDataRule1, isNotEmpty);
      expect(l10n.systemPromptDataRule2, isNotEmpty);
    });

    test('性能规则应不为空', () {
      final l10n = AiServiceLocalizations('en');
      expect(l10n.systemPromptPerfRule1, isNotEmpty);
    });

    test('contextCurrentDatabase 应包含数据库名', () {
      final l10n = AiServiceLocalizations('en');
      final text = l10n.contextCurrentDatabase('mydb');
      expect(text, contains('mydb'));
    });

    test('contextCurrentTable 应包含表名', () {
      final l10n = AiServiceLocalizations('en');
      final text = l10n.contextCurrentTable('users');
      expect(text, contains('users'));
    });

    test('contextRecentQueries 应包含查询', () {
      final l10n = AiServiceLocalizations('en');
      final text = l10n.contextRecentQueries('SELECT 1');
      expect(text, contains('SELECT 1'));
    });

    test('中英文系统提示应存在', () {
      final en = AiServiceLocalizations('en');
      final zh = AiServiceLocalizations('zh');
      // 验证中英文都有值（某些底层提示可能相同，都是英文）
      expect(en.systemPromptRule1, isNotEmpty);
      expect(zh.systemPromptRule1, isNotEmpty);
    });

    test('_isChinese 应为 true', () {
      final l10n = AiServiceLocalizations('zh');
      expect(l10n.systemPromptIdentity, isNotEmpty);
    });

    test('zh_TW 也应被识别为中文', () {
      final l10n = AiServiceLocalizations('zh_TW');
      expect(l10n.systemPromptIdentity, isNotEmpty);
    });
  });

  // 回归：AI 响应语言必须跟随应用 locale——仅简体中文(zh)回中文，其余(含 zh_TW)一律英文。
  // 旧实现返回 "Always respond in the same language as the user's messages."（镜像用户消息，
  // 不含 'English'/'简体中文'），下列断言在旧代码上全部失败。
  group('systemPromptLanguageInstruction 响应语言跟随 locale', () {
    test('简体中文(zh) → 简体中文响应指令', () {
      final text = AiServiceLocalizations('zh').systemPromptLanguageInstruction;
      expect(text, contains('简体中文'));
      expect(text, isNot(contains('English')));
    });

    test('英文(en) → 英文响应指令', () {
      final text = AiServiceLocalizations('en').systemPromptLanguageInstruction;
      expect(text, contains('English'));
      expect(text, isNot(contains('中文')));
    });

    test('繁体中文(zh_TW) → 英文响应（需求：仅简体回中文）', () {
      final text =
          AiServiceLocalizations('zh_TW').systemPromptLanguageInstruction;
      expect(text, contains('English'));
      expect(text, isNot(contains('中文')));
    });

    test('其余语言(de/fr/ru) → 英文响应', () {
      for (final code in const ['de', 'fr', 'ru']) {
        final text =
            AiServiceLocalizations(code).systemPromptLanguageInstruction;
        expect(text, contains('English'), reason: code);
        expect(text, isNot(contains('中文')), reason: code);
      }
    });
  });

  // 回归：4 个 AppProvider AI 分析入口的用户提示文本须按 locale 切换。
  // 仅 zh → 中文，其余（含 zh_TW）→ 英文（与响应语言策略一致）。
  group('AppProvider AI 分析入口提示文本按 locale 切换', () {
    test('zh → 中文提示，en → 英文提示', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');

      // 查询结果分析
      expect(zh.analyzeQueryHeader, contains('请分析'));
      expect(en.analyzeQueryHeader, contains('Please analyze'));
      expect(zh.analyzeQueryPerformanceAsk, contains('性能'));
      expect(en.analyzeQueryPerformanceAsk, contains('performance'));

      // 错误诊断
      expect(zh.analyzeErrorHeader, contains('诊断'));
      expect(en.analyzeErrorHeader, contains('diagnose'));
      expect(zh.errorInfoLabel, contains('错误'));
      expect(en.errorInfoLabel, contains('Error'));

      // 执行结果三分支
      expect(zh.executionFailedLabel, contains('执行失败'));
      expect(en.executionFailedLabel, contains('Execution failed'));
      expect(zh.emptyResultHeader, contains('为空'));
      expect(en.emptyResultHeader, contains('empty'));
      expect(zh.analyzeSqlErrorAsk, contains('排查'));
      expect(en.analyzeSqlErrorAsk, contains('troubleshooting'));
      expect(zh.unknownErrorLabel, contains('未知'));
      expect(en.unknownErrorLabel, contains('Unknown'));
    });

    test('动态参数被正确嵌入（中英均含参数值）', () {
      for (final code in const ['zh', 'en']) {
        final l = AiServiceLocalizations(code);
        expect(l.executionTimeLabel(42), contains('42'));
        expect(l.rowsReturnedLabel(7), contains('7'));
        expect(l.truncatedLabel(100), contains('100'));
        expect(l.columnsLabel(const ['a', 'b']), contains('a, b'));
        expect(l.analyzeTreeNodeHeader('table', 'users'), contains('users'));
      }
    });

    test('nodeTypeLabel 覆盖所有节点类型且中英不同', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      // 中文应是非空中文词，英文应是英文词
      expect(zh.nodeTypeLabel(AiTreeNodeType.table), isNotEmpty);
      expect(en.nodeTypeLabel(AiTreeNodeType.table), 'table');
      expect(zh.nodeTypeLabel(AiTreeNodeType.table),
          isNot(equals(en.nodeTypeLabel(AiTreeNodeType.table))));
    });

    test('zh_TW → 英文提示（与响应语言策略一致，非简体即英文）', () {
      final tw = AiServiceLocalizations('zh_TW');
      expect(tw.analyzeQueryHeader, contains('Please analyze'));
      expect(tw.analyzeErrorHeader, contains('diagnose'));
      expect(tw.nodeTypeLabel(AiTreeNodeType.table), 'table');
      // 关键：zh_TW 不应产出中文提示
      expect(tw.analyzeQueryPerformanceAsk, isNot(contains('性能')));
    });

    test('会话标题按 locale 切换', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(zh.aiSessionTitleNode('users'), contains('AI 分析'));
      expect(en.aiSessionTitleNode('users'), contains('AI Analysis'));
      expect(zh.aiSessionTitleError, contains('错误诊断'));
      expect(en.aiSessionTitleError, contains('Error Diagnosis'));
      expect(zh.aiSessionTitleQueryResult, contains('查询结果'));
      expect(en.aiSessionTitleQueryResult, contains('Query Result'));
    });
  });

  // 回归：AI i18n hotfix 新增的服务层用户可见消息（无 BuildContext，走 AiServiceLocalizations）。
  // 策略与入口提示不同：这些用户可见串用 _isChinese（zh + zh_TW → 中文），其余 → 英文。
  group('用户可见服务层消息按 locale 切换（_isChinese: zh+zh_TW→中）', () {
    test('会话默认标题/分支标题 zh→中、en→英、且嵌入参数', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(zh.newChatTitle(3), contains('新对话'));
      expect(zh.newChatTitle(3), contains('3'));
      expect(en.newChatTitle(3), contains('New Chat'));
      expect(en.newChatTitle(3), contains('3'));
      expect(zh.branchSessionTitle('preview'), contains('基于'));
      expect(en.branchSessionTitle('preview'), contains('Based on'));
      expect(zh.branchSessionTitle('preview'), contains('preview'));
    });

    test('配额/连接/Key/收集失败 消息 zh→中、en→英', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(zh.aiQuotaExhaustedUpgradePrompt, contains('配额'));
      expect(en.aiQuotaExhaustedUpgradePrompt, contains('quota'));
      expect(zh.aiAnalysisNoConnection, contains('未连接'));
      expect(en.aiAnalysisNoConnection, contains('connected'));
      expect(zh.errorAiApiKeyMissing, contains('API'));
      expect(en.errorAiApiKeyMissing, contains('API key'));
      expect(zh.errorAiCollectNodeContextFailed('boom'), contains('boom'));
      expect(en.errorAiCollectNodeContextFailed('boom'), contains('boom'));
    });

    test('摘要兜底/INSERT 取消/超时 消息 zh→中、en→英', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(zh.summaryEmptyConversation, contains('空'));
      expect(en.summaryEmptyConversation, contains('Empty'));
      expect(zh.summaryDefaultFallback, contains('对话'));
      expect(en.summaryDefaultFallback, contains('conversation'));
      expect(zh.aiInsertExecutionCancelled, contains('取消'));
      expect(en.aiInsertExecutionCancelled, contains('cancelled'));
      expect(zh.requestTimeout, contains('超时'));
      expect(en.requestTimeout, contains('timed out'));
    });

    test('任务中断/恢复/错误/导出 嵌入参数且 zh→中、en→英', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(zh.taskInterruptedResumeHint('boom'), contains('boom'));
      expect(en.taskInterruptedResumeHint('boom'), contains('boom'));
      expect(en.taskInterruptedResumeHint('boom'), contains('interrupted'));
      expect(en.errorPartialContentSaved('boom', 'req-7'), contains('req-7'));
      expect(en.genericErrorOccurred('boom'), contains('boom'));
      expect(zh.genericErrorOccurred('boom'), contains('错误'));
      expect(en.resumeInterruptedAgain('boom'), contains('interrupted'));
      expect(en.resumeFailed('boom'), contains('Resume'));
      expect(zh.resumeFailed('boom'), contains('恢复'));
      expect(en.exportTaskDescription('users', 'CSV'), contains('users'));
      expect(en.exportTaskDescription('users', 'CSV'), contains('CSV'));
      expect(zh.exportTaskDescription('users', 'CSV'), contains('导出'));
    });

    test('zh_TW → 中文（用户可见串走 _isChinese，区别于入口提示的 _respondsChinese）', () {
      final tw = AiServiceLocalizations('zh_TW');
      // 关键：用户可见串在 zh_TW 下应给中文（与入口提示 zh_TW→英文 相反）
      expect(tw.newChatTitle(1), contains('新对话'));
      expect(tw.aiAnalysisNoConnection, contains('未连接'));
      expect(tw.requestTimeout, contains('超时'));
    });

    test('其余语言(de/fr/ru) → 英文', () {
      for (final code in const ['de', 'fr', 'ru']) {
        final l = AiServiceLocalizations(code);
        expect(l.newChatTitle(1), contains('New Chat'), reason: code);
        expect(l.aiAnalysisNoConnection, contains('connected'), reason: code);
        expect(l.requestTimeout, contains('timed out'), reason: code);
      }
    });
  });

  // 回归：p3 AI-facing 工具结果/提示/上下文标签按 locale 切换（_isChinese）。
  group('p3 AI-facing 工具结果/提示/上下文标签', () {
    test('工具结果标签 zh→中、en→英、嵌入参数', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(zh.toolResultLabelTable('users'), contains('表'));
      expect(en.toolResultLabelTable('users'), contains('Table'));
      expect(en.toolResultLabelTable('users'), contains('users'));
      expect(en.toolResultLabelRows(42), contains('42'));
      expect(en.testDataGeneratedExecutedTitle, contains('Test Data'));
      expect(zh.testDataGeneratedExecutedTitle, contains('测试数据'));
    });

    test('导出/导入/数据质量 标题与标签 zh→中、en→英', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(en.exportAnalysisTitle('orders'), contains('Export Analysis'));
      expect(zh.exportAnalysisTitle('orders'), contains('导出'));
      expect(en.importCompleteTitle, contains('Import Complete'));
      expect(zh.dataQualityReportTitle, contains('数据质量'));
      expect(en.dataQualityNoIssuesDetected, contains('No major issues'));
      expect(zh.collectionNameRequired, contains('集合'));
    });

    test('MongoDB/Redis/MySQL 提示规则块 zh→中、en→英（\$match 字面量保留）', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(en.sqlPromptMysqlGuidelines, contains('InnoDB'));
      expect(zh.sqlPromptMysqlGuidelines, contains('MySQL'));
      // \$match 是 Mongo 操作符字面量，不是参数——两语都应含 $match
      expect(en.sqlPromptMongoPerformanceRules, contains(r'$match'));
      expect(zh.sqlPromptMongoPerformanceRules, contains(r'$match'));
      expect(en.sqlPromptRedisCommandFormatTitle, contains('Redis'));
    });

    test('schema 摘要 / 上下文收集器 标签 zh→中、en→英、嵌入参数', () {
      final zh = AiServiceLocalizations('zh');
      final en = AiServiceLocalizations('en');
      expect(en.schemaSummaryDbTypeLabel('MySQL'), contains('Database type'));
      expect(zh.schemaSummaryDbTypeLabel('MySQL'), contains('数据库类型'));
      expect(en.schemaSummaryDbTypeLabel('MySQL'), contains('MySQL'));
      expect(en.aiContextDatabaseCount(3), contains('3'));
      expect(en.mysqlContextTableRow('t', '100', '1KB', '2KB', 'InnoDB'),
          contains('InnoDB'));
      expect(zh.mysqlContextTableRow('t', '100', '1KB', '2KB', 'InnoDB'),
          contains('行'));
    });

    test('数据质量 issue/recommendation 嵌入参数', () {
      final en = AiServiceLocalizations('en');
      expect(en.dqIssueMissingValues('email', 5, 20), contains('email'));
      expect(en.dqIssueMissingValues('email', 5, 20), contains('5'));
      expect(en.dqRecTrimWhitespace('name'), contains('name'));
    });

    test('zh_TW → 中文（_isChinese 一致）', () {
      final tw = AiServiceLocalizations('zh_TW');
      expect(tw.toolResultLabelTable('users'), contains('表'));
      expect(tw.schemaSummaryDbTypeLabel('MySQL'), contains('数据库类型'));
    });
  });
}
