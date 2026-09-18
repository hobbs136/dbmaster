import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../utils/app_logger.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../providers/locale_provider.dart';
import '../../models/database_models.dart';
import '../../models/ai_message_type.dart';
import '../../models/ai_conversation_session.dart';
import '../../services/ai_service.dart';
import '../../services/database_service.dart';
import 'ddl_confirm_dialog.dart';
import '../connection/error_boundary.dart';
import '../connection/password_prompt_dialog.dart';

import '../../services/sql_optimizer_service.dart';
import '../../services/query_analyzer_service.dart';
import '../../services/sql_injection_detector.dart';
import '../../services/query_history/query_history_service.dart';
import '../../services/mongo_optimizer_service.dart';
import '../../services/nosql_injection_detector.dart';
import '../../services/mongo_index_advisor.dart';
import '../../services/mongodb_shell_parser.dart';

import 'ai_message_item.dart';
import 'ai_conversation_list.dart';
import 'ai_bookmark_panel.dart';
import '../../l10n/app_localizations.dart';
import '../../models/execution_result.dart';
import '../../models/sql_statement.dart';
import 'ai_settings_dialog.dart';

import 'confirm_execute_dialog.dart';
import 'ai_welcome_state.dart';
import 'ai_slash_command_menu.dart';
import 'ai_skill_catalog_panel.dart';
import 'ai_context_panel.dart';
import '../../plugins/ai_skill_plugin.dart';
import '../../plugins/bootstrap.dart';
import '../task_panel/export_task_create_dialog.dart';
import '../pro/pro_purchase_ui.dart';
import '../../providers/task_provider.dart';
import '../../models/task_models.dart';
import '../../theme/app_colors.dart';

class _SendAiMessageIntent extends Intent {
  const _SendAiMessageIntent();
}

class AiInputArea extends StatefulWidget {
  final bool isSending;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final VoidCallback onShowApiSettings;
  final ValueChanged<String> onSlashCommand;
  final bool isOverlay;

  const AiInputArea({
    super.key,
    required this.isSending,
    required this.onSend,
    required this.onStop,
    required this.onShowApiSettings,
    required this.onSlashCommand,
    this.isOverlay = false,
  });

  @override
  State<AiInputArea> createState() => _AiInputAreaState();
}

class _AiInputAreaState extends State<AiInputArea> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final LayerLink _slashMenuLayerLink = LayerLink();
  bool _showSlashCommands = false;
  String _slashCommandFilter = '';

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChange);
    _inputFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _onInputChange() {
    if (widget.isSending) return;

    final text = _inputController.text;
    final cursorPos = _inputController.selection.baseOffset;

    final shouldShowSlash = text.startsWith('/') && cursorPos > 0;
    final newFilter = shouldShowSlash ? text.substring(1, cursorPos) : '';

    setState(() {
      _showSlashCommands = shouldShowSlash;
      _slashCommandFilter = newFilter;
    });
  }

  void _onSlashCommandSelected(String action, String command) {
    _inputController.text = '';
    _inputController.selection = TextSelection.fromPosition(
      const TextPosition(offset: 0),
    );
    setState(() {
      _showSlashCommands = false;
      _slashCommandFilter = '';
    });
    widget.onSlashCommand(action);
  }

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty || widget.isSending) return;
    _inputController.clear();
    widget.onSend(text);
  }

  void setInputText(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
  }

  void requestInputFocus() {
    _inputFocusNode.requestFocus();
  }

  String get currentText => _inputController.text;

  List<Map<String, dynamic>> _getProviders(AppProvider appProvider) {
    final official = AiApiProviders.all.values
        .map(
          (p) => <String, dynamic>{
            'name': p.name,
            'icon': p.icon,
            'color': Color(p.color),
            'models':
                appProvider.getFetchedModelsForProvider(p.name) ?? p.models,
          },
        )
        .toList();
    final customModels = ['custom-model'];
    if (appProvider.selectedAiProvider == AiApiProviders.customModelKey &&
        appProvider.selectedAiModel != 'custom-model' &&
        appProvider.selectedAiModel.isNotEmpty) {
      customModels.add(appProvider.selectedAiModel);
    }
    official.add(<String, dynamic>{
      'name': AiApiProviders.customModelKey,
      'icon': LucideIcons.settings,
      'color': context.themeColors.accentPurple,
      'models': customModels,
      'isCustom': true,
    });
    return official;
  }

  Widget _buildModelSelectorDropdown(AppProvider provider) {
    final providers = _getProviders(provider);
    final currentProvider = providers.firstWhere(
      (p) => p['name'] == provider.selectedAiProvider,
      orElse: () => providers.first,
    );
    final models =
        (currentProvider['models'] as List<dynamic>?)?.cast<String>() ?? [];

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: models.contains(provider.selectedAiModel)
            ? provider.selectedAiModel
            : (models.isNotEmpty ? models.first : null),
        isDense: true,
        isExpanded: true,
        icon: const Icon(LucideIcons.chevronDown, size: 14),
        dropdownColor: context.themeColors.bgSecondary,
        style: TextStyle(fontSize: 11, color: context.themeColors.textMuted),
        items: models.map((model) {
          return DropdownMenuItem<String>(
            value: model,
            // emoji 字符串拼接→Icon 组件+品牌色（F-37）
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  currentProvider['icon'] as IconData,
                  size: 12,
                  color: currentProvider['color'] as Color,
                ),
                const SizedBox(width: AppDesignSystem.space1),
                Flexible(
                  child: Text(
                    model,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            provider.setAiModel(value);
          }
        },
      ),
    );
  }

  Widget _buildInputFooter() {
    final l10n = AppLocalizations.of(context)!;
    final charCount = _inputController.text.length;
    const maxChars = 4000;

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: Row(
        children: [
          Text(
            '$charCount/$maxChars',
            style: TextStyle(
              fontSize: 11,
              color: charCount > maxChars * 0.9
                  ? context.themeColors.warning
                  : context.themeColors.textMuted,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, provider, _) =>
                  _buildModelSelectorDropdown(provider),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              icon: const Icon(LucideIcons.settings, size: 14),
              color: context.themeColors.textMuted,
              onPressed: widget.onShowApiSettings,
              padding: EdgeInsets.zero,
              tooltip: l10n.aiPanelApiSettings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    final l10n = AppLocalizations.of(context)!;
    final isInputEmpty = _inputController.text.trim().isEmpty;

    final buttonColor = widget.isSending
        ? context.themeColors.error
        : isInputEmpty
        ? context.themeColors.textMuted.withValues(alpha: 0.5)
        : context.themeColors.accentPurple;

    return SizedBox(
      width: double.infinity,
      height: 36,
      child: Material(
        color: buttonColor,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          onTap: widget.isSending
              ? widget.onStop
              : (isInputEmpty ? null : _handleSend),
          child: Center(
            child: widget.isSending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.square,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: AppDesignSystem.space1_5),
                      Text(
                        l10n.aiPanelStop,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.send,
                        color: isInputEmpty ? Colors.white54 : Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: AppDesignSystem.space1_5),
                      Text(
                        l10n.aiPanelSend,
                        style: TextStyle(
                          color: isInputEmpty ? Colors.white54 : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlashCommandOverlay() {
    return Positioned(
      left: AppDesignSystem.space3,
      right: AppDesignSystem.space3,
      bottom: 180,
      child: CompositedTransformFollower(
        link: _slashMenuLayerLink,
        offset: const Offset(0, -8),
        child: SlashCommandMenu(
          filter: _slashCommandFilter,
          onCommandSelected: _onSlashCommandSelected,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            const _SendAiMessageIntent(),
      },
      child: Actions(
        actions: {
          _SendAiMessageIntent: CallbackAction<_SendAiMessageIntent>(
            onInvoke: (_) {
              if (!widget.isSending) {
                _handleSend();
              }
              return null;
            },
          ),
        },
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppDesignSystem.space3,
                AppDesignSystem.space2,
                AppDesignSystem.space3,
                AppDesignSystem.space2,
              ),
              color: widget.isOverlay
                  ? Colors.transparent
                  : context.themeColors.bgSecondary,
              child: Column(
                children: [
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _slashMenuLayerLink,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final needsScroll =
                              !constraints.hasBoundedHeight ||
                              (constraints.maxHeight < 130 &&
                                  constraints.maxHeight > 0);
                          final inputContainer = Container(
                            decoration: BoxDecoration(
                              color: widget.isOverlay
                                  ? Colors.transparent
                                  : context.themeColors.bgTertiary,
                              borderRadius: BorderRadius.circular(
                                AppDesignSystem.radiusMd,
                              ),
                              border: Border.all(
                                color: widget.isSending
                                    ? context.themeColors.accentPurple
                                          .withValues(alpha: 0.5)
                                    : _inputFocusNode.hasFocus
                                    ? context.themeColors.accentPurple
                                          .withValues(alpha: 0.3)
                                    : context.themeColors.borderLight,
                                width: _inputFocusNode.hasFocus ? 1.5 : 1,
                              ),
                              boxShadow: _inputFocusNode.hasFocus
                                  ? [
                                      BoxShadow(
                                        color: context.themeColors.accentPurple
                                            .withValues(alpha: 0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: TextField(
                                    minLines: 1,
                                    maxLines: 5,
                                    keyboardType: TextInputType.multiline,
                                    textAlignVertical: TextAlignVertical.top,
                                    controller: _inputController,
                                    focusNode: _inputFocusNode,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.of(
                                        context,
                                      )!.aiPanelInputHint,
                                      hintStyle: TextStyle(
                                        color: context.themeColors.textMuted,
                                        fontSize: 13,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.only(
                                        left: 12,
                                        right: 12,
                                        top: 14,
                                        bottom: 10,
                                      ),
                                    ),
                                  ),
                                ),
                                _buildInputFooter(),
                              ],
                            ),
                          );

                          if (needsScroll) {
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints.tightFor(
                                  height: 130,
                                ),
                                child: inputContainer,
                              ),
                            );
                          }
                          return inputContainer;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space1),
                  _buildSendButton(),
                ],
              ),
            ),
            if (_showSlashCommands) _buildSlashCommandOverlay(),
          ],
        ),
      ),
    );
  }
}

class AiPanelWidget extends StatefulWidget {
  final bool isFullscreen;
  final bool isOverlay;

  const AiPanelWidget({
    super.key,
    this.isFullscreen = false,
    this.isOverlay = false,
  });

  @override
  State<AiPanelWidget> createState() => AiPanelWidgetState();
}

class AiPanelWidgetState extends State<AiPanelWidget>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: true,
  );
  bool _isSending = false;
  bool _cancelled = false;
  int _messageIdCounter = 0;

  bool _showConversationList = false;
  bool _shouldAutoScroll = true;
  int _previousMessageCount = 0;
  int _loadedMessageCount = 50;

  // C23 三栏状态：当前选中技能 id + Schema 上下文开关（默认开，沿既有行为）
  String? _selectedSkillId;
  bool _schemaContextEnabled = true;

  /// 三栏断点：≥ 此宽度显示左（技能目录）右（上下文）栏；停靠侧栏
  /// （300-400px）走窄模式（header 按钮弹 Tab 对话框）。
  static const double _threeColumnMinWidth = 700;

  @override
  bool get wantKeepAlive => true;

  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${_messageIdCounter++}';
  }

  // 可调整高度相关
  double _chatAreaRatio = 0.7; // 聊天区域占可用空间的比例（默认70%）
  static const double _connectionSelectorHeight = 44.0;
  static const double _minChatRatio = 0.2;
  static const double _maxChatRatio = 0.8;

  List<Map<String, dynamic>> get _providers {
    final appProvider = context.read<AppProvider>();
    final official = AiApiProviders.all.values
        .map(
          (p) => <String, dynamic>{
            'name': p.name,
            'icon': p.icon,
            'color': Color(p.color),
            'models':
                appProvider.getFetchedModelsForProvider(p.name) ?? p.models,
          },
        )
        .toList();
    final customModels = ['custom-model'];
    if (appProvider.selectedAiProvider == AiApiProviders.customModelKey &&
        appProvider.selectedAiModel != 'custom-model' &&
        appProvider.selectedAiModel.isNotEmpty) {
      customModels.add(appProvider.selectedAiModel);
    }
    official.add(<String, dynamic>{
      'name': AiApiProviders.customModelKey,
      'icon': LucideIcons.settings,
      'color': context.themeColors.accentPurple,
      'models': customModels,
      'isCustom': true,
    });
    return official;
  }

  final Set<String> _allowedSessionServers = <String>{};

  bool _supportsThinking(String provider, String model) =>
      AiService.supportsThinking(provider, model);

  String _aiLocaleCode() =>
      LocaleProvider.codeOf(Localizations.localeOf(context));

  final TextEditingController _customModelController = TextEditingController();
  final GlobalKey<_AiInputAreaState> _aiInputKey =
      GlobalKey<_AiInputAreaState>();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().loadAiConfig();
      _setupInsertConfirmation();
    });
  }

  void _setupInsertConfirmation() {
    final provider = context.read<AppProvider>();
    provider.aiPanel.insertConfirmationCallback =
        ({
          required String tableName,
          required int count,
          required List<String> statements,
        }) async {
          return await _showInsertConfirmationDialog(
            tableName: tableName,
            count: count,
            statements: statements,
          );
        };
  }

  void _executeSlashCommandAction(String action) {
    switch (action) {
      case 'optimize_sql':
        _showSqlOptimization();
        break;
      case 'explain_query':
        _showExecutionPlan();
        break;
      case 'analyze_table':
        _showIndexSuggestions();
        break;
      case 'show_history':
        _showQueryHistory();
        break;
      case 'show_bookmarks':
        _showBookmarksDrawer();
        break;
      case 'branch_conversation':
        _branchCurrentConversation();
        break;
      case 'generate_crud':
        break;
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // 仅响应真实用户手势（非程序化 animateTo）
    if (position.userScrollDirection != ScrollDirection.idle) {
      _shouldAutoScroll = false;
    }
    // 用户手动滚回底部时恢复自动跟随
    if (!_shouldAutoScroll &&
        position.pixels >= position.maxScrollExtent - 50) {
      _shouldAutoScroll = true;
    }
    // 到达顶部时加载更多历史消息
    if (position.pixels <= 100 &&
        _loadedMessageCount < context.read<AppProvider>().aiMessages.length) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    final totalCount = context.read<AppProvider>().aiMessages.length;
    setState(() {
      _loadedMessageCount = (_loadedMessageCount + 50).clamp(0, totalCount);
    });
  }

  void _scrollToBottomIfNeeded() {
    if (!_shouldAutoScroll || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll < 200) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  void _onSessionSelected(String sessionId) {
    context.read<AppProvider>().aiPanel.switchSession(sessionId);
  }

  void _onSessionDeleted(String sessionId) {
    context.read<AppProvider>().aiPanel.aiConversationService.deleteSession(
      sessionId,
    );
  }

  void _onSessionRestored(AiConversationSession session) {
    context.read<AppProvider>().aiPanel.aiConversationService.restoreSession(
      session,
    );
  }

  void _onSessionArchived(String sessionId) {
    context.read<AppProvider>().aiPanel.aiConversationService.archiveSession(
      sessionId,
    );
  }

  void _onSessionRenamed(String sessionId, String newTitle) {
    context
        .read<AppProvider>()
        .aiPanel
        .aiConversationService
        .updateSessionTitle(sessionId, newTitle);
  }

  void _onNewSession() {
    context.read<AppProvider>().aiPanel.aiConversationService.createSession(
      locale: Localizations.localeOf(context).languageCode,
    );
  }

  void _showBookmarksDrawer() {
    final provider = context.read<AppProvider>();
    final messageMap = {for (var m in provider.aiMessages) m.id: m};
    final l10n = AppLocalizations.of(context)!;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppLocalizations.of(context)!.commonDismiss,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          child: SizedBox(
            width: 300,
            child: Column(
              children: [
                AppBar(
                  title: Text(l10n.aiPanelBookmarks),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Expanded(
                  child: AiBookmarkPanel(
                    bookmarks: provider.aiPanel.aiBookmarks,
                    messageMap: messageMap,
                    onBookmarkSelected: (messageId) {
                      Navigator.pop(ctx);
                      _scrollToMessage(messageId);
                    },
                    onBookmarkDeleted: (bookmarkId) {
                      final bookmark = provider.aiPanel.aiBookmarks.firstWhere(
                        (b) => b.id == bookmarkId,
                      );
                      provider.toggleBookmark(bookmark.messageId);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToMessage(String messageId) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.aiPanelScrollToMessageDeveloping),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _branchCurrentConversation() {
    final provider = context.read<AppProvider>();
    final messages = provider.aiMessages;
    if (messages.isEmpty) return;

    final lastMessage = messages.last;
    provider.aiPanel.aiConversationService.branchFromMessage(
      lastMessage.id,
      lastMessage.content,
      locale: Localizations.localeOf(context).languageCode,
    );
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.aiPanelBranchConversationCreated),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Focus(
      autofocus: false,
      child: _showConversationList
          ? _buildFullSessionList()
          : _buildMainPanel(),
    );
  }

  Widget _buildFullSessionList() {
    return AiConversationList(
      sessions: context
          .watch<AppProvider>()
          .aiPanel
          .aiConversationService
          .sessions,
      currentSessionId: context
          .watch<AppProvider>()
          .aiPanel
          .aiConversationService
          .currentSession
          ?.id,
      onSessionSelected: (sessionId) {
        setState(() {
          _showConversationList = false;
        });
        _onSessionSelected(sessionId);
      },
      onSessionDeleted: _onSessionDeleted,
      onSessionsDeleted: (sessionIds) {
        for (final id in sessionIds) {
          _onSessionDeleted(id);
        }
      },
      onSessionRestored: _onSessionRestored,
      onSessionArchived: _onSessionArchived,
      onSessionRenamed: _onSessionRenamed,
      onNewSession: () {
        setState(() {
          _showConversationList = false;
        });
        _onNewSession();
      },
      onBack: () => setState(() => _showConversationList = false),
      isFullPanel: true,
    );
  }

  Widget _buildMainPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final availableHeight = totalHeight - _connectionSelectorHeight;
        final wide = constraints.maxWidth >= _threeColumnMinWidth;

        final centerColumn = Container(
          color: widget.isOverlay ? Colors.transparent : null,
          child: Column(
            children: [
              // P1-3：面板头部（连接选择器条）底部 1px 封口，与标签栏、
              // 面包屑的横向框架对齐；overlay 浮层自带整体描边，不重复加。
              // 用 foregroundDecoration：子级 Container 自带 bgSecondary 底色，
              // 普通 decoration 会被子级盖住
              Container(
                foregroundDecoration: widget.isOverlay
                    ? null
                    : BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: context.themeColors.dividerColor,
                          ),
                        ),
                      ),
                child: SizedBox(
                  height: _connectionSelectorHeight,
                  child: _buildConnectionSelector(showSideEntry: !wide),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: (_chatAreaRatio * 100).toInt(),
                      child: _buildChat(),
                    ),
                    _buildSessionTokenUsage(),
                    _buildResizeDivider(availableHeight),
                    Expanded(
                      flex: ((1 - _chatAreaRatio) * 100).toInt(),
                      child: AiInputArea(
                        key: _aiInputKey,
                        isSending: _isSending,
                        onSend: _sendMessage,
                        onStop: _stopAI,
                        onShowApiSettings: _showApiSettings,
                        onSlashCommand: _executeSlashCommandAction,
                        isOverlay: widget.isOverlay,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (!wide) {
          return Container(
            color: widget.isOverlay
                ? Colors.transparent
                : context.themeColors.bgSecondary,
            child: centerColumn,
          );
        }

        // C23 三栏：左技能目录（240）+ 中对话 + 右上下文（260）
        return Container(
          color: widget.isOverlay
              ? Colors.transparent
              : context.themeColors.bgSecondary,
          child: Row(
            children: [
              SizedBox(
                width: 240,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.themeColors.bgSecondary,
                    border: Border(
                      right: BorderSide(color: context.themeColors.dividerColor),
                    ),
                  ),
                  child: AiSkillCatalogPanel(
                    selectedSkillId: _selectedSkillId,
                    onSkillSelected: _onSkillSelected,
                  ),
                ),
              ),
              Expanded(child: centerColumn),
              SizedBox(
                width: 260,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.themeColors.bgSecondary,
                    border: Border(
                      left: BorderSide(color: context.themeColors.dividerColor),
                    ),
                  ),
                  child: _buildContextPanel(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContextPanel() {
    final provider = context.watch<AppProvider>();
    final selectedConnId = provider.aiPanel.selectedConnectionId;
    final connection = selectedConnId != null
        ? provider.connection.savedConnections
              .cast<DbServer?>()
              .firstWhere((s) => s!.id == selectedConnId, orElse: () => null)
        : null;

    return AiContextPanel(
      connection: connection,
      databaseName: provider.aiPanel.selectedDatabaseName,
      schemaContextEnabled: _schemaContextEnabled,
      onSchemaContextChanged: (v) => setState(() => _schemaContextEnabled = v),
    );
  }

  void _onSkillSelected(AiSkillPlugin skill) {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _selectedSkillId = skill.descriptor.id);
    final template = skill.promptTemplate?.call(l10n);
    if (template != null && template.isNotEmpty) {
      _aiInputKey.currentState?.setInputText(template);
      _aiInputKey.currentState?.requestInputFocus();
    }
  }

  /// 当前选中技能（id 反查注册表；注册表封口后内容恒定，线性查无妨）。
  AiSkillPlugin? get _selectedSkill {
    final id = _selectedSkillId;
    if (id == null) return null;
    for (final skill in defaultPluginRegistry.aiSkills) {
      if (skill.descriptor.id == id) return skill;
    }
    return null;
  }

  /// 窄模式（<700px）入口：Tab 对话框承载技能目录 + 上下文面板。
  void _showSidePanelsDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: Dialog(
          backgroundColor: ctx.themeColors.bgSecondary,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        tabs: [
                          Tab(
                            icon: const Icon(LucideIcons.sparkles, size: 14),
                            text: l10n.aiSkillCatalogTitle,
                          ),
                          Tab(
                            icon: const Icon(LucideIcons.panelRight, size: 14),
                            text: l10n.aiContextPanelTitle,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Flexible(
                  child: TabBarView(
                    children: [
                      AiSkillCatalogPanel(
                        selectedSkillId: _selectedSkillId,
                        onSkillSelected: (skill) {
                          Navigator.pop(ctx);
                          _onSkillSelected(skill);
                        },
                      ),
                      _buildContextPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionSelector({bool showSideEntry = false}) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context)!;
        final connections = provider.connection.savedConnections;

        if (connections.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
            ),
            color: widget.isOverlay
                ? Colors.transparent
                : context.themeColors.bgSecondary,
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 14,
                  color: context.themeColors.textMuted,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    l10n.aiPanelNoConnections,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.themeColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          color: widget.isOverlay
              ? Colors.transparent
              : context.themeColors.bgSecondary,
          child: Row(
            children: [
              // 连接选择下拉框
              Expanded(
                flex: 2,
                child: _buildConnectionDropdown(connections, provider),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              // 数据库选择下拉框
              Expanded(flex: 2, child: _buildDatabaseDropdown(provider)),
              const SizedBox(width: AppDesignSystem.space2),
              // 新建对话按钮
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: const Icon(LucideIcons.plus, size: 14),
                  color: context.themeColors.accentPurple,
                  onPressed: _onNewSession,
                  padding: EdgeInsets.zero,
                  tooltip: AppLocalizations.of(context)!.connectionNewChat,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              // 会话列表切换按钮
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: Icon(
                    _showConversationList
                        ? LucideIcons.chevronLeft
                        : LucideIcons.messageCircle,
                    size: 14,
                  ),
                  color: _showConversationList
                      ? context.themeColors.accentPurple
                      : context.themeColors.textMuted,
                  onPressed: () => setState(
                    () => _showConversationList = !_showConversationList,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: l10n.aiPanelConversationList,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              // C23 窄模式入口：技能目录 + 上下文（Tab 对话框）
              if (showSideEntry)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: Icon(
                      LucideIcons.sparkles,
                      size: 14,
                      color: _selectedSkillId != null
                          ? context.themeColors.accentPurple
                          : context.themeColors.textMuted,
                    ),
                    onPressed: _showSidePanelsDialog,
                    padding: EdgeInsets.zero,
                    tooltip: l10n.aiPanelOpenSkillCatalog,
                  ),
                ),
              const SizedBox(width: AppDesignSystem.space1),
              // 全屏切换按钮
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: Icon(
                    widget.isFullscreen
                        ? LucideIcons.minimize
                        : LucideIcons.maximize,
                    size: 14,
                  ),
                  color: context.themeColors.textMuted,
                  onPressed: () {
                    AppLogger.d(
                      'AiPanel',
                      'AI Panel: fullscreen button pressed',
                    );
                    provider.toggleAiPanelFullscreen();
                  },
                  padding: EdgeInsets.zero,
                  tooltip: widget.isFullscreen
                      ? l10n.aiPanelExitFullscreen
                      : l10n.aiPanelFullscreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectionDropdown(
    List<DbServer> connections,
    AppProvider provider,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final selectedId = provider.aiPanel.selectedConnectionId;
    final validSelectedServer = selectedId != null
        ? connections.cast<DbServer?>().firstWhere(
            (s) => s!.id == selectedId,
            orElse: () => null,
          )
        : null;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DbServer?>(
          isExpanded: true,
          value: validSelectedServer,
          hint: Text(
            l10n.aiPanelSelectConnection,
            style: AppTextStyles.caption.copyWith(
              color: context.themeColors.textMuted,
            ),
          ),
          icon: Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: context.themeColors.textMuted,
          ),
          dropdownColor: context.themeColors.bgSecondary,
          style: AppTextStyles.caption.copyWith(
            color: context.themeColors.textPrimary,
          ),
          items: [
            DropdownMenuItem<DbServer?>(
              value: null,
              child: Text(l10n.aiPanelNoConnection),
            ),
            ...connections.map((server) {
              final isConnected = provider.connection.isConnectionConnected(
                server.id,
              );
              final isActive = provider.connection.isConnectionActive(
                server.id,
              );
              return DropdownMenuItem<DbServer?>(
                value: server,
                child: Row(
                  children: [
                    // emoji→矢量图标+品牌色（F-37）
                    Icon(
                      server.type.typeIcon,
                      size: 14,
                      color: context.themeColors.brandColor(server.type),
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Expanded(
                      child: Text(
                        server.name.isNotEmpty
                            ? server.name
                            : '${server.host}:${server.port}',
                        style: AppTextStyles.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? context.themeColors.success
                            : isConnected
                            ? context.themeColors.accentBlue
                            : context.themeColors.textMuted.withValues(
                                alpha: 0.5,
                              ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (server) async {
            provider.aiPanel.setSelectedConnection(server?.id);
            provider.aiPanel.setSelectedDatabase(null);
            provider.aiPanel.setSelectedConnectionDatabases([]);

            if (server != null) {
              // 加载该连接的数据库列表
              await _loadDatabasesForServer(server, provider);
            }
          },
        ),
      ),
    );
  }

  Widget _buildDatabaseDropdown(AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final selectedDb = provider.aiPanel.selectedDatabaseName;
    final databases = provider.aiPanel.selectedConnectionDatabases;
    final validSelectedDb = databases.contains(selectedDb) ? selectedDb : null;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: validSelectedDb,
          hint: Text(
            provider.aiPanel.selectedConnectionId == null
                ? l10n.aiPanelSelectDatabaseFirst
                : l10n.aiPanelSelectDatabase,
            style: AppTextStyles.caption.copyWith(
              color: context.themeColors.textMuted,
            ),
          ),
          icon: Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: context.themeColors.textMuted,
          ),
          dropdownColor: context.themeColors.bgSecondary,
          style: AppTextStyles.caption.copyWith(
            color: context.themeColors.textPrimary,
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l10n.aiPanelAllDatabases),
            ),
            ...databases.map((db) {
              return DropdownMenuItem<String?>(
                value: db,
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.database,
                      size: 12,
                      color: context.themeColors.textMuted,
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Expanded(
                      child: Text(
                        db,
                        style: AppTextStyles.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (database) {
            provider.aiPanel.setSelectedDatabase(database);
          },
        ),
      ),
    );
  }

  Future<void> _loadDatabasesForServer(
    DbServer server,
    AppProvider provider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      // 先检查是否已连接
      if (!provider.connection.isConnectionConnected(server.id)) {
        // 尝试连接（未保存密码时先提示输入）
        final serverWithPassword = await PasswordPromptDialog.ensurePassword(
          context,
          server,
        );
        if (serverWithPassword == null) return;
        final success = await provider.connection.connectToServer(
          serverWithPassword,
        );
        if (!success) {
          if (mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              '${l10n.aiPanelConnectionFailed}: ${provider.connection.errorMessage ?? l10n.aiPanelUnknownError}',
            );
          }
          return;
        }
      }

      // 获取数据库列表
      final databases = await provider.connection.dbService.getDatabases(
        connectionId: server.id,
      );
      if (mounted) {
        provider.aiPanel.setSelectedConnectionDatabases(databases);
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          '${l10n.aiPanelLoadDatabasesFailed}: $e',
        );
      }
    }
  }

  Widget _buildResizeDivider(double availableHeight) {
    return _AiPanelResizeDivider(
      onDragUpdate: (delta) {
        setState(() {
          _chatAreaRatio = (_chatAreaRatio + delta / availableHeight).clamp(
            _minChatRatio,
            _maxChatRatio,
          );
        });
      },
    );
  }

  Widget _buildSessionTokenUsage() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final messages = provider.aiMessages;
        if (messages.isEmpty) return const SizedBox.shrink();

        final totalPrompt = messages.fold<int>(
          0,
          (sum, m) => sum + m.promptTokens,
        );
        final totalCompletion = messages.fold<int>(
          0,
          (sum, m) => sum + m.completionTokens,
        );
        final totalTokens = messages.fold<int>(
          0,
          (sum, m) => sum + m.totalTokens,
        );

        if (totalTokens == 0) return const SizedBox.shrink();

        final l10n = AppLocalizations.of(context)!;
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space1,
          ),
          decoration: BoxDecoration(
            color: context.themeColors.bgSecondary,
            border: Border(
              top: BorderSide(
                color: context.themeColors.borderSubtle,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.chartPie,
                size: 12,
                color: context.themeColors.textMuted,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                l10n.sessionTokenUsage(
                  totalPrompt,
                  totalCompletion,
                  totalTokens,
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChat() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context)!;
        final messages = provider.aiMessages;

        if (messages.isEmpty) {
          final selectedConnId = provider.aiPanel.selectedConnectionId;
          final currentServer = selectedConnId != null
              ? provider.connection.savedConnections
                    .cast<DbServer?>()
                    .firstWhere(
                      (s) => s!.id == selectedConnId,
                      orElse: () => null,
                    )
              : null;

          return AiWelcomeState(
            onOptimizeSql: _showSqlOptimization,
            onSecurityAnalysis: _showSecurityAnalysis,
            onExecutionPlan: _showExecutionPlan,
            onIndexSuggestions: _showIndexSuggestions,
            onQueryHistory: _showQueryHistory,
            connectionName: currentServer?.name,
            databaseName: provider.aiPanel.selectedDatabaseName,
            onQuestionTap: (question) {
              _aiInputKey.currentState?.setInputText(question);
              _aiInputKey.currentState?.requestInputFocus();
            },
          );
        }

        final displayCount = messages.length > _loadedMessageCount
            ? _loadedMessageCount
            : messages.length;
        final displayMessages = messages.length > _loadedMessageCount
            ? messages.sublist(messages.length - displayCount)
            : messages;

        if (messages.length != _previousMessageCount) {
          _previousMessageCount = messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottomIfNeeded();
          });
        }

        // 过滤掉独立的 toolCall，将其与对应的 toolResult 合并
        final mergedMessages = _mergeToolMessages(displayMessages);

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: false,
          thickness: 6.0,
          radius: const Radius.circular(AppDesignSystem.radiusSm),
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              decelerationRate: ScrollDecelerationRate.fast,
            ),
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            itemCount: mergedMessages.length + (_isSending ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == mergedMessages.length && _isSending) {
                return _buildLoadingSkeleton(context);
              }
              final message = mergedMessages[index];
              return AiMessageItem(
                key: ValueKey(message.id),
                message: message,
                onExecuteSql: (code, isDangerous) {
                  // 写操作/DDL 执行为 Pro 专属（NL2SQL 的 SELECT 执行 Free 开放）
                  if (isDangerous && !provider.proModule.isPro) {
                    provider.setPendingUpgradeFeature('ai_ddl_execute');
                    return;
                  }
                  if (isDangerous) {
                    _confirmAndExecuteCommand(
                      code,
                      l10n.aiPanelDangerousOperation,
                    );
                  } else {
                    final serverId =
                        provider.aiPanel.selectedConnectionId ?? '';
                    if (_allowedSessionServers.contains(serverId)) {
                      _executeSql(code);
                    } else {
                      _confirmAndExecuteCommand(code, null);
                    }
                  }
                },
                onOpenInNewQuery: (code) {
                  _openInNewQuery(code);
                },
                onToggleBookmark: (messageId) {
                  provider.toggleBookmark(messageId);
                },
                onBranchFromMessage: (messageId, content) {
                  _aiInputKey.currentState?.setInputText('> $content\n');
                  _aiInputKey.currentState?.requestInputFocus();
                },
                onRegenerate: message.isUser
                    ? null
                    : () => _regenerateMessage(message.id, messages),
                onContinue: message.status == AiMessageStatus.interrupted
                    ? () => _continueMessage(message.id)
                    : null,
                onCreateExportTask: (table, whereClause) {
                  _showExportTaskDialog(context, table, whereClause);
                },
              );
            },
          ),
        ); // Scrollbar
      },
    );
  }

  List<AiMessage> _mergeToolMessages(List<AiMessage> messages) {
    final result = <AiMessage>[];

    int i = 0;
    while (i < messages.length) {
      final message = messages[i];

      if (message.type == AiMessageType.toolCall) {
        // 找到当前对话段：从当前 toolCall 开始，到下一个用户消息或列表结束
        int segmentEnd = i + 1;
        while (segmentEnd < messages.length && !messages[segmentEnd].isUser) {
          segmentEnd++;
        }

        final segmentMessages = messages.sublist(i, segmentEnd);

        // 收集段内所有工具调用及其结果
        final tools = <Map<String, dynamic>>[];
        final toolCallIndices = <int>{};
        final consumedResultIndices = <int>{};

        for (int j = 0; j < segmentMessages.length; j++) {
          if (segmentMessages[j].type == AiMessageType.toolCall) {
            // 查找对应的 toolResult
            AiMessage? toolResult;
            for (int k = j + 1; k < segmentMessages.length; k++) {
              if (segmentMessages[k].type == AiMessageType.toolResult &&
                  segmentMessages[k].toolName == segmentMessages[j].toolName &&
                  !consumedResultIndices.contains(k)) {
                toolResult = segmentMessages[k];
                consumedResultIndices.add(k);
                break;
              }
            }

            tools.add({
              'toolName': segmentMessages[j].toolName,
              'toolArguments': segmentMessages[j].toolArguments,
              'result': toolResult?.content ?? '',
              'status':
                  toolResult?.status.toString() ??
                  segmentMessages[j].status.toString(),
            });
            toolCallIndices.add(j);
          }
        }

        if (tools.isNotEmpty) {
          // 找到第一个工具调用的位置
          final firstToolIndex = toolCallIndices.reduce(
            (a, b) => a < b ? a : b,
          );

          // 添加第一个工具调用之前的非工具消息
          for (int j = 0; j < firstToolIndex; j++) {
            if (!toolCallIndices.contains(j) &&
                !consumedResultIndices.contains(j)) {
              result.add(segmentMessages[j]);
            }
          }

          if (tools.length == 1) {
            // 只有一个工具
            result.add(
              AiMessage(
                id: segmentMessages[firstToolIndex].id,
                isUser: false,
                content: tools.first['result'] as String,
                timestamp: segmentMessages[firstToolIndex].timestamp,
                type: AiMessageType.toolResult,
                toolName: tools.first['toolName'] as String?,
                toolArguments:
                    tools.first['toolArguments'] as Map<String, dynamic>?,
                status: AiMessageStatus.completed,
              ),
            );
          } else {
            // 多个工具，合并为工具组
            result.add(
              AiMessage(
                // 复用首个 toolCall 的真 id（与单工具分支一致），保证该合并消息
                // 的 id 存在于原始 messages 中，Regenerate 的 indexWhere 才能命中
                id: segmentMessages[firstToolIndex].id,
                isUser: false,
                content: '',
                timestamp: segmentMessages[firstToolIndex].timestamp,
                type: AiMessageType.toolResult,
                toolName: null,
                toolArguments: null,
                toolResultData: {
                  'isToolGroup': true,
                  'toolCount': tools.length,
                  'tools': tools,
                },
                status: AiMessageStatus.completed,
              ),
            );
          }

          // 添加第一个工具调用之后的非工具消息
          for (int j = firstToolIndex + 1; j < segmentMessages.length; j++) {
            if (!toolCallIndices.contains(j) &&
                !consumedResultIndices.contains(j)) {
              result.add(segmentMessages[j]);
            }
          }
        }

        i = segmentEnd;
      } else {
        // 普通消息直接保留
        result.add(message);
        i++;
      }
    }
    return result;
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: context.themeColors.accentPurple,
          child: const Icon(LucideIcons.bot, size: 14, color: Colors.white),
        ),
        const SizedBox(width: AppDesignSystem.space2_5),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    l10n.messageLabelAi,
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: context.themeColors.accentPurple,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  Text(
                    AppLocalizations.of(context)!.messageStatusThinking,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      color: context.themeColors.accentPurple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isOverlay
                      ? Colors.transparent
                      : context.themeColors.bgAiMessage,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppDesignSystem.radiusMd),
                    topRight: Radius.circular(AppDesignSystem.radiusMd),
                    // 消息气泡尖角，保持较小圆角以形成指向效果
                    bottomLeft: Radius.circular(AppDesignSystem.radiusSm),
                    bottomRight: Radius.circular(AppDesignSystem.radiusMd),
                  ),
                  border: widget.isOverlay
                      ? Border.all(color: context.themeColors.borderSubtle)
                      : null,
                  boxShadow: widget.isOverlay
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSkeletonLine(context, width: 200),
                    const SizedBox(height: AppDesignSystem.space2),
                    _buildSkeletonLine(context, width: double.infinity),
                    const SizedBox(height: AppDesignSystem.space2),
                    _buildSkeletonLine(context, width: 150),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonLine(BuildContext context, {required double width}) {
    return _AnimatedSkeletonLine(
      width: width,
      color: context.themeColors.textMuted.withValues(alpha: 0.15),
    );
  }

  void _showApiSettings() {
    final provider = context.read<AppProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AiSettingsDialog(
        providers: _providers,
        selectedProvider: provider.selectedAiProvider,
      ),
    );
  }

  Future<void> _sendMessage(
    String text, {
    bool recordUserMessage = true,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (text.isEmpty) return;

    // 先设置发送状态，再清空输入，避免状态冲突
    setState(() {
      _isSending = true;
      _cancelled = false;
      _shouldAutoScroll = true;
    });

    final provider = context.read<AppProvider>();
    provider.aiPanel.ensureSession();

    // 在校验前先入库用户消息。否则 guard 失败（未选连接/库/apiKey）时
    // 只入库错误消息、无前置用户消息，该错误消息落到 index 0，点 Regenerate 会
    // 被 _regenerateMessage 的 currentIndex<=0 守卫静默吞掉。
    // regenerate 路径已自行截断到用户消息，故传 recordUserMessage=false 避免重复。
    if (recordUserMessage) {
      provider.addAiMessage(
        AiMessage(
          id: 'u_${DateTime.now().millisecondsSinceEpoch}',
          isUser: true,
          content: text,
          timestamp: DateTime.now(),
          type: AiMessageType.chat,
          status: AiMessageStatus.sent,
        ),
      );
    }

    // 如果会话还是默认标题，用用户第一条消息的前 30 个字符作为标题
    final currentSession =
        provider.aiPanel.aiConversationService.currentSession;
    if (currentSession != null &&
        (currentSession.title.startsWith('New Chat') ||
            currentSession.title.startsWith('新对话'))) {
      final newTitle = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      provider.aiPanel.aiConversationService.updateSessionTitle(
        currentSession.id,
        newTitle,
      );
    }

    final selectedProvider = provider.selectedAiProvider;
    final selectedModel = provider.selectedAiModel;
    final apiKey = provider.getAiApiKey(selectedProvider) ?? '';
    final baseUrl = provider.getAiBaseUrl(selectedProvider) ?? '';
    final selectedId = provider.aiPanel.selectedConnectionId;
    final currentServer = selectedId != null
        ? provider.connection.savedConnections.cast<DbServer?>().firstWhere(
            (s) => s!.id == selectedId,
            orElse: () => null,
          )
        : null;

    if (apiKey.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: l10n.configureApiKeyFirst(selectedProvider),
          timestamp: DateTime.now(),
        ),
      );
      setState(() {
        _isSending = false;
      });
      return;
    }

    if (currentServer == null) {
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: l10n.aiPanelSelectConnectionFirst,
          timestamp: DateTime.now(),
        ),
      );
      setState(() {
        _isSending = false;
      });
      return;
    }

    final adapter = provider.connection.dbService.getAdapter(currentServer.id);
    if (adapter == null || !adapter.isConnected) {
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: l10n.aiPanelConnectionNotAvailable(currentServer.name),
          timestamp: DateTime.now(),
        ),
      );
      setState(() {
        _isSending = false;
      });
      return;
    }

    // 强制要求选择数据库
    if (provider.aiPanel.selectedDatabaseName == null) {
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: AppLocalizations.of(context)!.aiPanelSelectDatabaseRequired,
          timestamp: DateTime.now(),
        ),
      );
      setState(() {
        _isSending = false;
      });
      return;
    }

    // 检查 AI 配额（Free 用户每月 30 次，Pro 不限）
    final canUseAi = await provider.canUseAi();
    if (!canUseAi) {
      if (mounted) {
        context.read<ProPurchaseUi>().showUpgradeDialog(context);
      }
      setState(() {
        _isSending = false;
      });
      return;
    }

    try {
      await provider.aiPanel.orchestrator.sendUserMessage(
        text: text,
        adapter: adapter,
        provider: selectedProvider,
        model: selectedModel,
        apiKey: apiKey,
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
        timeout: provider.aiTimeout,
        thinkingEnabled: _supportsThinking(selectedProvider, selectedModel),
        selectedDatabase: provider.aiPanel.selectedDatabaseName,
        locale: _aiLocaleCode(),
        // C23 上下文面板开关（默认开，沿既有行为）
        includeSchemaContext: _schemaContextEnabled,
        // C23 envelope：技能期望的载体类型（渲染层分发提示）
        envelopeType: _selectedSkill?.resultType.name,
        // 高级 AI（Agent 工具调用）为 Pro 专属；Free 走纯对话
        allowTools: provider.proModule.isPro,
        // 用户消息已在 _sendMessage 入库前自行 addAiMessage
        recordUserMessage: false,
      );
      await provider.recordAiUsage();
    } catch (e) {
      if (!mounted) return;
      if (!_cancelled) {
        final l10n = AppLocalizations.of(context)!;
        provider.addAiMessage(
          AiMessage(
            id: _generateMessageId(),
            isUser: false,
            content: '${l10n.generationFailed}: $e',
            timestamp: DateTime.now(),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _regenerateMessage(String messageId, List<AiMessage> allMessages) {
    // 找到当前AI消息在完整列表中的索引
    final currentIndex = allMessages.indexWhere((m) => m.id == messageId);
    if (currentIndex <= 0) return;

    // 向前查找上一条用户消息
    int userMessageIndex = -1;
    for (int i = currentIndex - 1; i >= 0; i--) {
      if (allMessages[i].isUser) {
        userMessageIndex = i;
        break;
      }
    }
    if (userMessageIndex < 0) return;

    final userMessage = allMessages[userMessageIndex];
    final provider = context.read<AppProvider>();

    // 删除从该用户消息之后的所有消息（保留用户消息本身）
    final newMessages = allMessages.sublist(0, userMessageIndex + 1);
    provider.aiPanel.sessionManager.updateMessages(newMessages);

    // 重新发送用户消息
    // regenerate 已截断到用户消息（它在列表里），传 false 避免 _sendMessage 再入库一条重复
    _sendMessage(userMessage.content, recordUserMessage: false);
  }

  Future<bool> _showInsertConfirmationDialog({
    required String tableName,
    required int count,
    required List<String> statements,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  color: context.themeColors.warning,
                  size: 24,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(l10n.aiPanelConfirmExecuteSql),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiPanelInsertStatementsGenerated(count, tableName),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: AppDesignSystem.space3),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.themeColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      border: Border.all(
                        color: context.themeColors.warning.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.info,
                          size: 16,
                          color: context.themeColors.warning,
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        Expanded(
                          child: Text(
                            l10n.aiPanelDangerousOperationDesc,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.themeColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space3),
                  Text(
                    l10n.aiPanelSqlPreviewTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space1),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          statements.take(3).join('\n'),
                          style: const TextStyle(
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (statements.length > 3) ...[
                    const SizedBox(height: AppDesignSystem.space1),
                    Text(
                      l10n.aiPanelMoreStatements(statements.length - 3),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.commonCancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.accentBlue,
                  foregroundColor: Colors.white,
                ),
                child: Text(l10n.commonConfirm),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showExportTaskDialog(
    BuildContext context,
    String table,
    String? whereClause,
  ) async {
    final provider = context.read<AppProvider>();
    final selectedId = provider.aiPanel.selectedConnectionId;
    if (selectedId == null) return;

    final config = await showDialog<ExportTaskConfig>(
      context: context,
      builder: (context) => ExportTaskCreateDialog(
        connectionId: selectedId,
        databaseName: provider.aiPanel.selectedDatabaseName,
        tableName: table,
        whereClause: whereClause,
      ),
    );

    if (config != null) {
      if (!context.mounted) return;
      final taskProvider = context.read<TaskProvider>();
      taskProvider.createTask(type: TaskType.export, config: config);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.aiPanelExportTaskCreated,
            ),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    }
  }

  Future<void> _continueMessage(String messageId) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final selectedProvider = provider.selectedAiProvider;
    final selectedModel = provider.selectedAiModel;
    final apiKey = provider.getAiApiKey(selectedProvider) ?? '';
    final baseUrl = provider.getAiBaseUrl(selectedProvider) ?? '';

    if (apiKey.isEmpty) {
      return;
    }

    final selectedId = provider.aiPanel.selectedConnectionId;
    final currentServer = selectedId != null
        ? provider.connection.savedConnections.cast<DbServer?>().firstWhere(
            (s) => s!.id == selectedId,
            orElse: () => null,
          )
        : null;

    if (currentServer == null) return;

    final adapter = provider.connection.dbService.getAdapter(currentServer.id);
    if (adapter == null || !adapter.isConnected) return;

    // 强制要求选择数据库
    if (provider.aiPanel.selectedDatabaseName == null) {
      // 裸色 SnackBar → helper（F-15）
      AppErrorHandler.showWarningSnackBar(
        context,
        AppLocalizations.of(context)!.aiPanelSelectDatabaseRequired,
      );
      return;
    }

    final orchestrator = provider.aiPanel.orchestrator;

    setState(() {
      _isSending = true;
    });

    try {
      await orchestrator.resumeAgentTask(
        messageId: messageId,
        adapter: adapter,
        provider: selectedProvider,
        model: selectedModel,
        apiKey: apiKey,
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
        timeout: provider.aiTimeout,
        thinkingEnabled: _supportsThinking(selectedProvider, selectedModel),
        selectedDatabase: provider.aiPanel.selectedDatabaseName,
        locale: _aiLocaleCode(),
        // C23 上下文面板开关（默认开，沿既有行为）
        includeSchemaContext: _schemaContextEnabled,
        // 高级 AI（Agent 工具调用）为 Pro 专属；Free 走纯对话
        allowTools: provider.proModule.isPro,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${l10n.restoreFailed}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// 解析 AI 面板当前选中连接的数据库类型，用于在 SQL / Mongo 间分流命令（research D12）。
  DatabaseType? _getSelectedConnectionDatabaseType() {
    final provider = context.read<AppProvider>();
    final connId = provider.aiPanel.selectedConnectionId;
    if (connId == null) return provider.connection.currentServer?.type;
    final saved = provider.connection.savedConnections;
    final server = saved.any((s) => s.id == connId)
        ? saved.firstWhere((s) => s.id == connId)
        : provider.connection.currentServer;
    return server?.type;
  }

  void _showSqlOptimization() {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final currentSql = _aiInputKey.currentState?.currentText.trim() ?? '';

    if (currentSql.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseEnterSql)));
      return;
    }

    if (_getSelectedConnectionDatabaseType() == DatabaseType.mongodb) {
      final optimizer = MongoOptimizerService();
      final suggestions = optimizer.analyze(currentSql);
      final report = optimizer.generateOptimizationReport(
        currentSql,
        suggestions,
      );
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: report,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final optimizer = SqlOptimizerService();
    final suggestions = optimizer.analyze(currentSql);
    final report = optimizer.generateOptimizationReport(
      currentSql,
      suggestions,
    );

    provider.addAiMessage(
      AiMessage(
        id: _generateMessageId(),
        isUser: false,
        content: report,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _showSecurityAnalysis() {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final currentSql = _aiInputKey.currentState?.currentText.trim() ?? '';

    if (currentSql.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseEnterSql)));
      return;
    }

    if (_getSelectedConnectionDatabaseType() == DatabaseType.mongodb) {
      final detector = NoSqlInjectionDetector();
      final threats = detector.analyze(currentSql);
      final report = detector.generateThreatReport(currentSql, threats);
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: report,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    final detector = SqlInjectionDetector();
    final threats = detector.analyze(currentSql);
    final report = detector.generateThreatReport(currentSql, threats);

    provider.addAiMessage(
      AiMessage(
        id: _generateMessageId(),
        isUser: false,
        content: report,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _showIndexSuggestions() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final currentSql = _aiInputKey.currentState?.currentText.trim() ?? '';

    if (currentSql.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseEnterSql)));
      return;
    }

    if (_getSelectedConnectionDatabaseType() == DatabaseType.mongodb) {
      final connId = provider.aiPanel.selectedConnectionId;
      if (connId == null) {
        provider.addAiMessage(
          AiMessage(
            id: _generateMessageId(),
            isUser: false,
            content:
                '📇 ${l10n.indexSuggestion}\n\n${l10n.pleaseConnectDatabase}',
            timestamp: DateTime.now(),
          ),
        );
        return;
      }

      try {
        final parsed = MongoShellQueryParser.parseQuery(currentSql);
        final collection = parsed?['collection']?.toString() ?? '';
        List<DbIndex> existingIndexes = [];
        if (collection.isNotEmpty) {
          existingIndexes = await provider.connection.dbService.getTableIndexes(
            collection,
            connectionId: connId,
          );
        }
        if (!mounted) return;

        final advisor = MongoIndexAdvisorService();
        final recommendations = advisor.analyzeForIndex(
          currentSql,
          existingIndexes: existingIndexes,
          collection: collection,
        );
        final report = advisor.generateReport(currentSql, recommendations);
        provider.addAiMessage(
          AiMessage(
            id: _generateMessageId(),
            isUser: false,
            content: report,
            timestamp: DateTime.now(),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${l10n.analysisFailed}: $e')));
        }
      }
      return;
    }

    provider.addAiMessage(
      AiMessage(
        id: _generateMessageId(),
        isUser: false,
        content:
            '📊 ${l10n.indexSuggestion}...\n\n${l10n.pleaseConnectDatabase}',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _showExecutionPlan() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final currentSql = _aiInputKey.currentState?.currentText.trim() ?? '';

    if (currentSql.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseEnterSql)));
      return;
    }

    final selectedConnId = provider.aiPanel.selectedConnectionId;
    if (selectedConnId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseConnectDatabase)));
      return;
    }

    try {
      if (_getSelectedConnectionDatabaseType() == DatabaseType.mongodb) {
        final rows = await provider.connection.dbService.getExplainPlan(
          currentSql,
          connectionId: selectedConnId,
        );
        if (!mounted) return;

        final buffer = StringBuffer();
        buffer.writeln(AppLocalizations.of(context)!.aiPanelMongoExecutionPlan);
        buffer.writeln('=' * 50);
        buffer.writeln();
        for (final row in rows) {
          final key = row['阶段']?.toString() ?? '';
          final value = row['值']?.toString() ?? '';
          buffer.writeln('**$key**');
          buffer.writeln('```');
          buffer.writeln(value);
          buffer.writeln('```');
          buffer.writeln();
        }
        provider.addAiMessage(
          AiMessage(
            id: _generateMessageId(),
            isUser: false,
            content: buffer.toString().trimRight(),
            timestamp: DateTime.now(),
          ),
        );
        return;
      }

      final explainSql = 'EXPLAIN $currentSql';
      final results = await provider.connection.dbService.executeQuery(
        explainSql,
        connectionId: selectedConnId,
      );
      if (!mounted) return;

      if (results.isNotEmpty) {
        final analyzer = QueryAnalyzerService();
        final analysis = analyzer.analyzeExecutionPlan(results);
        final report = analyzer.generateAnalysisReport(analysis);

        provider.addAiMessage(
          AiMessage(
            id: _generateMessageId(),
            isUser: false,
            content: report,
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${l10n.analysisFailed}: $e')));
      }
    }
  }

  Future<void> _showQueryHistory() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();

    try {
      final historyService = QueryHistoryService();
      final history = await historyService.getRecentQueries(limit: 100);
      if (!mounted) return;

      if (history.isEmpty) {
        provider.addAiMessage(
          AiMessage(
            id: _generateMessageId(),
            isUser: false,
            content: l10n.noQueryHistory,
            timestamp: DateTime.now(),
          ),
        );
      } else {
        final buffer = StringBuffer();
        buffer.writeln(l10n.queryHistoryRecords(history.length));
        buffer.writeln('=' * 50);
        buffer.writeln();

        for (var i = 0; i < history.take(20).length; i++) {
          final item = history[i];
          buffer.writeln(
            '### ${i + 1}. ${item.createdAt.toString().substring(0, 19)}',
          );
          if (item.databaseName != null) {
            buffer.writeln('${l10n.database}: ${item.databaseName}');
          }
          buffer.writeln('${l10n.executionTime}: ${item.executionTimeMs}ms');
          buffer.writeln(
            '${l10n.status}: ${item.isSuccess ? "✅ ${l10n.commonSuccess}" : "❌ ${l10n.commonFailed}"}',
          );
          buffer.writeln();
          buffer.writeln('```sql');
          buffer.writeln(item.sqlStatement);
          buffer.writeln('```');
          buffer.writeln();
        }

        provider.addAiMessage(
          AiMessage(
            id: _generateMessageId(),
            isUser: false,
            content: buffer.toString(),
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.loadHistoryFailed}: $e')),
        );
      }
    }
  }

  Future<void> _confirmAndExecuteCommand(
    String command,
    String? warningReason,
  ) async {
    if (_cancelled) return;
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();

    final result = await showDialog<ConfirmResult>(
      context: context,
      builder: (ctx) => ConfirmExecuteDialog(
        command: command,
        warningReason: warningReason,
        l10n: l10n,
      ),
    );

    if (!mounted) return;

    if (result == ConfirmResult.allowOnce) {
      _executeSql(command);
    } else if (result == ConfirmResult.allowSession) {
      final serverId = provider.aiPanel.selectedConnectionId ?? '';
      if (serverId.isNotEmpty) {
        _allowedSessionServers.add(serverId);
      }
      _executeSql(command);
    }
  }

  void _stopAI() {
    final l10n = AppLocalizations.of(context)!;
    _cancelled = true;
    final provider = context.read<AppProvider>();
    provider.aiPanel.orchestrator.cancel();
    setState(() {
      _isSending = false;
    });
    provider.removeLastAiMessage();
    provider.addAiMessage(
      AiMessage(
        id: _generateMessageId(),
        isUser: false,
        content: l10n.operationCancelled,
        timestamp: DateTime.now(),
        status: AiMessageStatus.cancelled,
      ),
    );
  }

  Future<void> _executeSql(String sql) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();

    if (provider.tabs.isEmpty) {
      await provider.addNewTab();
      if (!mounted) return;
    }

    provider.addAiMessage(
      AiMessage(
        id: _generateMessageId(),
        isUser: false,
        content: l10n.executingSql,
        timestamp: DateTime.now(),
        isLoading: true,
        status: AiMessageStatus.streaming,
      ),
    );

    try {
      // 使用 AI 面板自己的连接和数据库状态
      final connectionId = provider.aiPanel.selectedConnectionId;
      final databaseName = provider.aiPanel.selectedDatabaseName;

      final results = await provider.executeQuery(
        sql,
        connectionId: connectionId,
        database: databaseName,
      );
      provider.removeLastAiMessage();

      // 格式化执行结果
      final resultContent = _formatExecutionResults(sql, results, l10n);

      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: resultContent,
          timestamp: DateTime.now(),
        ),
      );

      // 更新标签页时使用 AI 面板的连接和数据库状态
      final activeTabIndex = provider.activeTabIndex;
      provider.updateTabSql(activeTabIndex, sql);
      provider.updateTabConnection(activeTabIndex, connectionId);
      provider.updateTabDatabase(activeTabIndex, databaseName);
      // AI 应用 SQL = 显式设定 tab 上下文 → 绑定（方向 A）。
      provider.bindTabContext(activeTabIndex);
      final executionResults = [
        ExecutionResult(
          statement: SQLStatement(
            index: 0,
            sql: sql,
            type: SQLType.select,
            lineStart: 1,
            lineEnd: 1,
          ),
          success: true,
          data: results,
          executionTime: Duration.zero,
        ),
      ];
      provider.updateTabExecutionResults(activeTabIndex, executionResults);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.aiPanelSqlExecutionSuccess(results.length)),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    } catch (e) {
      provider.removeLastAiMessage();

      // 处理 DDL 确认异常
      if (e is DdlConfirmationRequiredException) {
        if (!mounted) return;
        final ctx = context;
        final result = await showDialog<DdlConfirmResult>(
          // ignore: use_build_context_synchronously
          context: ctx,
          barrierDismissible: false,
          builder: (ctx) =>
              DdlConfirmDialog(sql: e.sql, impactReport: e.impactReport),
        );

        if (result == DdlConfirmResult.execute && mounted) {
          // 用户确认后绕过 DDL 检查执行
          provider.addAiMessage(
            AiMessage(
              id: _generateMessageId(),
              isUser: false,
              content: l10n.executingSql,
              timestamp: DateTime.now(),
              isLoading: true,
              status: AiMessageStatus.streaming,
            ),
          );

          try {
            final connectionId = provider.aiPanel.selectedConnectionId;
            final databaseName = provider.aiPanel.selectedDatabaseName;

            final results = await provider.dbService.executeQueryBypassDdl(
              sql,
              connectionId: connectionId,
              database: databaseName,
            );
            provider.removeLastAiMessage();

            final resultContent = _formatExecutionResults(sql, results, l10n);

            provider.addAiMessage(
              AiMessage(
                id: _generateMessageId(),
                isUser: false,
                content: resultContent,
                timestamp: DateTime.now(),
              ),
            );

            final activeTabIndex = provider.activeTabIndex;
            provider.updateTabSql(activeTabIndex, sql);
            provider.updateTabConnection(activeTabIndex, connectionId);
            provider.updateTabDatabase(activeTabIndex, databaseName);
            // AI 应用 SQL = 显式设定 tab 上下文 → 绑定（方向 A）。
            provider.bindTabContext(activeTabIndex);
            final executionResults = [
              ExecutionResult(
                statement: SQLStatement(
                  index: 0,
                  sql: sql,
                  type: SQLType.select,
                  lineStart: 1,
                  lineEnd: 1,
                ),
                success: true,
                data: results,
                executionTime: Duration.zero,
              ),
            ];
            provider.updateTabExecutionResults(
              activeTabIndex,
              executionResults,
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.aiPanelSqlExecutionSuccess(results.length),
                  ),
                  backgroundColor: context.themeColors.success,
                ),
              );
            }
          } catch (executeError) {
            provider.removeLastAiMessage();
            provider.addAiMessage(
              AiMessage(
                id: _generateMessageId(),
                isUser: false,
                content: '❌ ${l10n.aiPanelExecuteFailed}: $executeError',
                timestamp: DateTime.now(),
              ),
            );
          }
        } else {
          // 用户取消
          provider.addAiMessage(
            AiMessage(
              id: _generateMessageId(),
              isUser: false,
              content: l10n.aiPanelDdlOperationCancelled,
              timestamp: DateTime.now(),
            ),
          );
        }
        return;
      }

      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: '❌ ${l10n.aiPanelExecuteFailed}: $e',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  /// 格式化SQL执行结果为可读的文本
  String _formatExecutionResults(
    String sql,
    List<Map<String, dynamic>> results,
    AppLocalizations l10n,
  ) {
    if (results.isEmpty) {
      return '✅ ${l10n.aiPanelExecuteSuccess(0)}\n\n```sql\n$sql\n```';
    }

    final buffer = StringBuffer();
    buffer.writeln('✅ ${l10n.aiPanelExecuteSuccess(results.length)}');
    buffer.writeln();
    buffer.writeln('```sql');
    buffer.writeln(sql);
    buffer.writeln('```');
    buffer.writeln();

    // 显示数据表格（最多20行）
    final displayResults = results.length > 20
        ? results.sublist(0, 20)
        : results;
    final columns = displayResults.isNotEmpty
        ? displayResults.first.keys.toList()
        : [];

    if (columns.isNotEmpty) {
      buffer.writeln('**${l10n.aiPanelDataPreview}:**');
      buffer.writeln();

      // Markdown 表头
      buffer.write('| ');
      for (final col in columns) {
        buffer.write('$col | ');
      }
      buffer.writeln();

      // Markdown 分隔符
      buffer.write('| ');
      for (final _ in columns) {
        buffer.write('--- | ');
      }
      buffer.writeln();

      // 数据行
      for (final row in displayResults) {
        buffer.write('| ');
        for (final col in columns) {
          final value = row[col];
          final strValue = value == null ? 'NULL' : value.toString();
          // 截断过长的值
          final displayValue = strValue.length > 50
              ? '${strValue.substring(0, 50)}...'
              : strValue;
          buffer.write('$displayValue | ');
        }
        buffer.writeln();
      }

      if (results.length > 20) {
        buffer.writeln();
        buffer.writeln('*... ${l10n.aiPanelAndMoreRows(results.length - 20)}*');
      }
    }

    return buffer.toString();
  }

  Future<void> _openInNewQuery(String sql) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<AppProvider>();
    final connectionId = provider.aiPanel.selectedConnectionId;
    final databaseName = provider.aiPanel.selectedDatabaseName;

    // 创建新标签页
    if (connectionId != null && databaseName != null) {
      await provider.openQueryTab(connectionId, databaseName, sql: sql);
    } else {
      await provider.addNewTab();
      final newTabIndex = provider.activeTabIndex;
      provider.updateTabSql(newTabIndex, sql);
    }

    // 显示提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.aiPanelOpenInNewQuery),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _AiPanelResizeDivider extends StatefulWidget {
  final ValueChanged<double> onDragUpdate;

  const _AiPanelResizeDivider({required this.onDragUpdate});

  @override
  State<_AiPanelResizeDivider> createState() => _AiPanelResizeDividerState();
}

class _AiPanelResizeDividerState extends State<_AiPanelResizeDivider> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) =>
            widget.onDragUpdate(details.delta.dy),
        child: SizedBox(
          height: 12,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: context.themeColors.dividerColor,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 2,
                decoration: BoxDecoration(
                  color: _isHovered
                      ? context.themeColors.accentPurple.withValues(alpha: 0.5)
                      : context.themeColors.borderLight,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSkeletonLine extends StatefulWidget {
  final double width;
  final Color color;

  const _AnimatedSkeletonLine({required this.width, required this.color});

  @override
  State<_AnimatedSkeletonLine> createState() => _AnimatedSkeletonLineState();
}

class _AnimatedSkeletonLineState extends State<_AnimatedSkeletonLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width == double.infinity
              ? double.infinity
              : widget.width,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color.withValues(
              alpha: widget.color.a * _animation.value,
            ),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
        );
      },
    );
  }
}
