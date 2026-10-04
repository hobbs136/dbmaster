//! 工作台卡消息构建分发器（T12 阶段二，design-ai-workbench §4.4/§5.2）。
//!
//! 分发规则（design §4.4，消息渲染入口的卡拦截层）：
//! 1. `AiMessage.toolResultData['workbench']` 存在 → 按 kind 渲染：
//!    `sql_card` → [SqlToolCard]，`result_card` → [ResultTableCard]，
//!    `error_card` → [ResultTableCard] 错误态分支；未知 kind（C-2 前向
//!    兼容）→ 落回既有 AiMessageItem 路径；
//! 2. `AiMessage.code`（AI 回复 SQL 代码块）→ **渲染层拦截为 SQL 卡**——
//!    不新建消息、不动消息流，经典侧零影响；正文/思考过程随卡一并呈现
//!    （信息不丢失）；
//! 3. 无 workbench 键 → 返回 null，调用方走既有 `AiMessageItem` 路径。
//!
//! 动作注入：卡动作回调经 [WorkbenchCardActions] 由宿主（chat view，T13
//! 后为执行编排）注入；T13 前由 chat view 过渡接线（openQueryTab 送回
//! 经典，沿 T10 消息级出口语义）。

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/database_models.dart';
import '../../services/ai/ai_tool_classifier.dart';
import '../../theme/app_colors.dart';
import '../../molecules/thinking_card.dart';
import 'cards/result_table_card.dart';
import 'cards/sql_tool_card.dart';
import 'workbench_card_payload.dart';

/// 工作台卡动作注入包（T13 消息面 + 保存为查询出口——参数名与类型为稳定契约）。
///
/// 复制动作不在其中：SQL 卡复制为组件内置实现（AC4.3），无需宿主接线。
@immutable
class WorkbenchCardActions {
  const WorkbenchCardActions({
    this.onExecuteSql,
    this.onOpenSqlInClassic,
    this.onOpenResultInGrid,
    this.onOpenResultInClassic,
    this.onRetryError,
    this.onOpenErrorInClassic,
    this.onSaveQuery,
  });

  /// SQL 卡「执行」（T13：`WorkbenchExecutionActions.run` 入口；参数为卡内
  /// SQL 全文——执行上下文由 T13 在执行时复核，不经卡传递）。
  final void Function(String sql)? onExecuteSql;

  /// SQL 卡「在经典中打开」（T13：`WorkbenchOpenInClassic.open`）。
  final void Function(String sql)? onOpenSqlInClassic;

  /// 结果卡「在舞台打开」（v2 B2 改路由：宿主组装
  /// `AgentResultRef(refId: 'card_<cardId>', …)` → `_stageController.openGrid`，
  /// 同 refId 复用激活不重复建 tab；R7 快照语义——tab 呈现卡快照全量，不
  /// 重执行不补全）。[cardId] = 承载卡的消息 id，由卡构建点注入；有快照
  /// （`snapshotRows` 非空）的卡渲染该出口。
  final void Function(WorkbenchResultCardPayload payload, String cardId)?
  onOpenResultInGrid;

  /// 结果卡「在经典中打开」。
  final void Function(WorkbenchResultCardPayload payload)?
  onOpenResultInClassic;

  /// 错误卡「重试」出口（T13）。
  final void Function(WorkbenchErrorCardPayload error)? onRetryError;

  /// 错误卡「在经典中打开」出口（T13）。
  final void Function(WorkbenchErrorCardPayload error)? onOpenErrorInClassic;

  /// SQL 卡「保存为查询」（参数为卡内 SQL 全文；保存上下文在宿主实现中
  /// 取 effectiveWorkbenchContext 复核，不经卡传递）。
  final void Function(String sql)? onSaveQuery;
}

/// 消息 → 工作台卡 的构建分发。纯渲染层组件：不新建消息、不动消息流。
class WorkbenchCardHost {
  const WorkbenchCardHost._();

  /// 尝试为 [message] 构建工作台卡；返回 null = 非卡消息（调用方回退
  /// 既有 `AiMessageItem` 路径）。
  static Widget? tryBuild({
    required BuildContext context,
    required AiMessage message,
    WorkbenchCardActions? actions,
  }) {
    // ① toolResultData['workbench'] → payload 分发（design §4.4）。
    final raw = message.toolResultData?['workbench'];
    if (raw is Map) {
      final data = Map<String, dynamic>.from(raw);
      final sqlPayload = WorkbenchSqlCardPayload.fromJson(data);
      if (sqlPayload != null) {
        return SqlToolCard(
          sql: sqlPayload.sql,
          statementType: sqlPayload.statementType,
          isWrite: sqlPayload.isWrite,
          onExecute: actions?.onExecuteSql,
          onOpenInClassic: actions?.onOpenSqlInClassic,
          onSaveQuery: actions?.onSaveQuery,
        );
      }
      final resultPayload = WorkbenchResultCardPayload.fromJson(data);
      if (resultPayload != null) {
        return ResultTableCard(
          payload: resultPayload,
          // v2 B2：onOpenResultInGrid 签名增 cardId——承载卡的消息 id 在此
          // 构建点注入（卡内回调仍单参 payload，由宿主适配）。
          onOpenInGrid: (payload) =>
              actions?.onOpenResultInGrid?.call(payload, message.id),
          onOpenInClassic: actions?.onOpenResultInClassic,
        );
      }
      final errorPayload = WorkbenchErrorCardPayload.fromJson(data);
      if (errorPayload != null) {
        return ResultTableCard(
          error: errorPayload,
          onRetry: actions?.onRetryError,
          onOpenErrorInClassic: actions?.onOpenErrorInClassic,
        );
      }
      // workbench 键存在但 kind 未知（C-2：旧读方忽略未知键）→ 落回既有路径。
    }

    // ② AI 回复 SQL 代码块 → 渲染层拦截为 SQL 卡（经典侧零影响）。
    if (!message.isUser) {
      final code = message.code;
      if (code != null && code.isNotEmpty) {
        return _buildCodeInterception(context, message, code, actions);
      }
    }
    return null;
  }

  /// code 拦截布局：思考过程/正文（信息不丢失，呈现顺序镜像
  /// `AiMessageItem._buildContentCard` 的既有语义）+ SQL 卡。
  static Widget _buildCodeInterception(
    BuildContext context,
    AiMessage message,
    String code,
    WorkbenchCardActions? actions,
  ) {
    final hasReasoning =
        message.reasoningContent != null &&
        message.reasoningContent!.isNotEmpty;
    final hasContent = message.content.isNotEmpty && !hasReasoning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasReasoning)
          ThinkingCard(
            thinkingProcess: message.reasoningContent!,
            thinkingResult: message.content.isNotEmpty ? message.content : null,
            isStreaming: false,
            initiallyExpanded: false,
          ),
        if (hasContent) ...[
          _buildProse(context, message.content),
          const SizedBox(height: 12),
        ],
        SqlToolCard(
          sql: code,
          statementType: _statementTypeOf(code),
          // 写徽标判定（T06）：拦截卡无 payload 快照，实时判定，语义一致。
          isWrite: AiToolClassifier.isWriteSql(code),
          onExecute: actions?.onExecuteSql,
          onOpenInClassic: actions?.onOpenSqlInClassic,
          onSaveQuery: actions?.onSaveQuery,
        ),
      ],
    );
  }

  /// 正文 markdown（消费项目既有 flutter_markdown；样式取消息正文基线，
  /// 非第二套实现）。
  static Widget _buildProse(BuildContext context, String content) {
    final colors = context.themeColors;
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 13, color: colors.textPrimary, height: 1.5),
        code: TextStyle(
          fontSize: 12,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          color: colors.textPrimary,
        ),
      ),
    );
  }

  /// 语句类型（header 徽标）：首个 SQL 关键词大写；无法解析时回退 'SQL'。
  static String _statementTypeOf(String sql) {
    final trimmed = sql.trimLeft();
    final match = RegExp(r'^[A-Za-z]+').firstMatch(trimmed);
    if (match == null) return 'SQL';
    return match.group(0)!.toUpperCase();
  }
}
