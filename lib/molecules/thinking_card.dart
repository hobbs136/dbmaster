import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../atoms/typewriter_text.dart';
import '../../theme/app_colors.dart';

class ThinkingCard extends StatefulWidget {
  final String thinkingProcess;
  final String? thinkingResult;
  final TypewriterConfig typewriterConfig;
  final bool isStreaming;
  final bool initiallyExpanded;
  final VoidCallback? onTypewriterComplete;
  final TextStyle? processStyle;

  const ThinkingCard({
    super.key,
    required this.thinkingProcess,
    this.thinkingResult,
    this.typewriterConfig = const TypewriterConfig(
      charDelay: Duration(milliseconds: 25),
    ),
    this.isStreaming = false,
    this.initiallyExpanded = false,
    this.onTypewriterComplete,
    this.processStyle,
  });

  @override
  State<ThinkingCard> createState() => ThinkingCardState();
}

class ThinkingCardState extends State<ThinkingCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  final GlobalKey<TypewriterTextState> _typewriterKey = GlobalKey();
  int _typingProgress = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ThinkingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !oldWidget.isStreaming) {
      setState(() => _expanded = true);
    }
    if (widget.thinkingProcess.length > oldWidget.thinkingProcess.length &&
        _expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void toggleExpanded() => setState(() => _expanded = !_expanded);

  void completeTypewriter() {
    _typewriterKey.currentState?.complete();
  }

  void restartTypewriter() {
    _typewriterKey.currentState?.restart();
  }

  bool get isTypewriterComplete =>
      _typewriterKey.currentState?.isComplete ?? true;

  String get currentTypingText => widget.thinkingProcess.substring(
    0,
    _typingProgress.clamp(0, widget.thinkingProcess.length),
  );

  void _onTypewriterProgress(int length) {
    if (_typingProgress != length) {
      setState(() {
        _typingProgress = length;
      });
    }
  }

  String get _previewText {
    if (widget.isStreaming && _typingProgress > 0) {
      final typingText = currentTypingText;
      if (typingText.isNotEmpty) {
        final lastLine =
            typingText
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .lastOrNull ??
            typingText;
        final trimmed = lastLine.trim();
        if (trimmed.length > 60) {
          return '${trimmed.substring(0, 60)}...';
        }
        return trimmed;
      }
    }
    if (widget.thinkingProcess.isEmpty) return '';
    final lines = widget.thinkingProcess.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.length > 50) {
      return '${firstLine.substring(0, 50)}...';
    }
    return firstLine;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary.withValues(
          alpha: _expanded ? 1.0 : 0.7,
        ),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: _expanded
              ? context.themeColors.accentPurple.withValues(alpha: 0.5)
              : context.themeColors.borderSubtle,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: _buildCollapsedPreview(context),
            secondChild: _buildExpandedContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.brain,
            size: 12,
            color: _expanded
                ? context.themeColors.accentPurple
                : context.themeColors.textMuted,
          ),
          if (widget.isStreaming) ...[
            const SizedBox(width: AppDesignSystem.space1),
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: context.themeColors.accentPurple,
              ),
            ),
          ],
          const Spacer(),
          _buildExpandButton(context),
        ],
      ),
    );
  }

  Widget _buildCollapsedPreview(BuildContext context) {
    final showLiveTyping = widget.isStreaming && _typingProgress > 0;
    final previewText = _previewText;

    if (previewText.isEmpty && !showLiveTyping) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  previewText,
                  style: TextStyle(
                    fontSize: 11,
                    color: showLiveTyping
                        ? context.themeColors.accentPurple
                        : context.themeColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showLiveTyping) ...[
                const SizedBox(width: AppDesignSystem.space2),
                _buildTypingIndicator(),
              ],
            ],
          ),
          if (showLiveTyping && widget.thinkingProcess.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              '$_typingProgress/${widget.thinkingProcess.length} 字',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return _TypingDot(
          delay: Duration(milliseconds: index * 200),
          color: context.themeColors.accentPurple,
        );
      }),
    );
  }

  Widget _buildExpandedContent(BuildContext context) {
    final isDisabled = !widget.typewriterConfig.enabled;
    final hasResult =
        widget.thinkingResult != null && widget.thinkingResult!.isNotEmpty;
    final showSkipButton = widget.isStreaming && !isTypewriterComplete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: isDisabled
                    ? SelectableText(
                        widget.thinkingProcess,
                        style:
                            widget.processStyle ??
                            TextStyle(
                              fontSize: 11,
                              color: context.themeColors.textSecondary,
                              height: 1.4,
                            ),
                      )
                    : TypewriterText(
                        key: _typewriterKey,
                        text: widget.thinkingProcess,
                        config: widget.typewriterConfig,
                        style:
                            widget.processStyle ??
                            TextStyle(
                              fontSize: 11,
                              color: context.themeColors.textSecondary,
                              height: 1.4,
                            ),
                        showCursor: widget.isStreaming,
                        onProgress: _onTypewriterProgress,
                        onComplete: widget.onTypewriterComplete,
                      ),
              ),
            ),
            if (showSkipButton)
              Positioned(right: 4, top: 0, child: _buildSkipButton(context)),
          ],
        ),
        if (hasResult) _buildResultSection(context),
      ],
    );
  }

  Widget _buildSkipButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: InkWell(
        onTap: completeTypewriter,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
            vertical: AppDesignSystem.space1,
          ),
          decoration: BoxDecoration(
            color: context.themeColors.accentPurple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(
              color: context.themeColors.accentPurple.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.fastForward,
                size: 12,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                '跳过',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.accentPurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.accentGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.lightbulb,
                size: 12,
                color: context.themeColors.accentGreen,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                '思考结果',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.accentGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          if (widget.thinkingResult != null)
            SelectableText(
              widget.thinkingResult!,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textPrimary,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandButton(BuildContext context) {
    return IconButton(
      onPressed: toggleExpanded,
      icon: Icon(
        _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
        size: 16,
        color: _expanded
            ? context.themeColors.accentPurple
            : context.themeColors.textMuted,
      ),
      tooltip: _expanded ? '收起' : '展开',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      splashRadius: 12,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TypingDot extends StatefulWidget {
  final Duration delay;
  final Color color;

  const _TypingDot({required this.delay, required this.color});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
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
          width: 5,
          height: 5,
          margin: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space0_5,
          ),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
