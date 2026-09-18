import 'dart:async';
import 'package:flutter/material.dart';

class TypewriterConfig {
  final Duration charDelay;
  final Duration initialDelay;
  final bool enabled;
  final Curve curve;

  const TypewriterConfig({
    this.charDelay = const Duration(milliseconds: 30),
    this.initialDelay = Duration.zero,
    this.enabled = true,
    this.curve = Curves.linear,
  });

  static const TypewriterConfig disabled = TypewriterConfig(enabled: false);
  static const TypewriterConfig fast = TypewriterConfig(
    charDelay: Duration(milliseconds: 15),
  );
  static const TypewriterConfig normal = TypewriterConfig();
  static const TypewriterConfig slow = TypewriterConfig(
    charDelay: Duration(milliseconds: 50),
  );
}

class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TypewriterConfig config;
  final VoidCallback? onComplete;
  final void Function(int displayedLength)? onProgress;
  final bool showCursor;
  final Widget? cursor;
  final TextAlign textAlign;

  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.config = const TypewriterConfig(),
    this.onComplete,
    this.onProgress,
    this.showCursor = true,
    this.cursor,
    this.textAlign = TextAlign.start,
  });

  @override
  State<TypewriterText> createState() => TypewriterTextState();
}

class TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Timer? _startTimer;
  bool _isComplete = false;
  int _displayedLength = 0;

  String get displayedText => widget.text.substring(0, _displayedLength);

  @override
  void initState() {
    super.initState();
    _initAnimation();
  }

  void _initAnimation() {
    final totalDuration = widget.config.enabled
        ? Duration(
            microseconds:
                widget.text.length * widget.config.charDelay.inMicroseconds,
          )
        : Duration.zero;

    _controller = AnimationController(vsync: this, duration: totalDuration);

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: widget.config.curve),
    )..addListener(_onAnimationUpdate);

    if (widget.config.enabled && widget.text.isNotEmpty) {
      if (widget.config.initialDelay > Duration.zero) {
        _startTimer = Timer(widget.config.initialDelay, _startAnimation);
      } else {
        _startAnimation();
      }
    } else {
      _displayedLength = widget.text.length;
      _isComplete = true;
      // Schedule onComplete for next frame when disabled
      if (widget.onComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete!();
        });
      }
    }
  }

  void _startAnimation() {
    if (mounted) {
      _controller.forward().then((_) => _onComplete());
    }
  }

  void _onAnimationUpdate() {
    if (!mounted) return;
    final newLength = (widget.text.length * _animation.value).round();
    if (newLength != _displayedLength) {
      setState(() {
        _displayedLength = newLength;
      });
      widget.onProgress?.call(_displayedLength);
    }
  }

  void _onComplete() {
    if (!mounted || _isComplete) return;
    setState(() {
      _isComplete = true;
      _displayedLength = widget.text.length;
    });
    widget.onComplete?.call();
  }

  void restart() {
    _startTimer?.cancel();
    _controller.removeListener(_onAnimationUpdate);
    _controller.reset();
    setState(() {
      _displayedLength = 0;
      _isComplete = false;
    });
    _controller.addListener(_onAnimationUpdate);
    if (widget.config.initialDelay > Duration.zero) {
      _startTimer = Timer(widget.config.initialDelay, _startAnimation);
    } else {
      _startAnimation();
    }
  }

  void complete() {
    _startTimer?.cancel();
    _controller.stop();
    setState(() {
      _displayedLength = widget.text.length;
      _isComplete = true;
    });
    widget.onComplete?.call();
  }

  bool get isComplete => _isComplete;
  int get displayedLength => _displayedLength;

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (widget.text.startsWith(oldWidget.text) &&
          !_isComplete &&
          oldWidget.text.isNotEmpty) {
        final oldLength = oldWidget.text.length;
        final additionalChars = widget.text.length - oldLength;

        setState(() {
          _displayedLength = _displayedLength.clamp(0, widget.text.length);
        });

        if (additionalChars > 0 && widget.config.enabled) {
          _controller.duration = Duration(
            microseconds:
                widget.text.length * widget.config.charDelay.inMicroseconds,
          );

          final currentProgress = _displayedLength / widget.text.length;
          _controller.value = currentProgress;
        }
      } else {
        _startTimer?.cancel();
        _controller.removeListener(_onAnimationUpdate);
        _controller.dispose();
        _initAnimation();
      }
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.removeListener(_onAnimationUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayText = widget.text.substring(0, _displayedLength);
    final showBlinkingCursor = widget.showCursor && !_isComplete;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            displayText,
            style: widget.style,
            textAlign: widget.textAlign,
          ),
        ),
        if (showBlinkingCursor)
          widget.cursor ?? _DefaultCursor(style: widget.style),
      ],
    );
  }
}

class _DefaultCursor extends StatefulWidget {
  final TextStyle? style;

  const _DefaultCursor({this.style});

  @override
  State<_DefaultCursor> createState() => _DefaultCursorState();
}

class _DefaultCursorState extends State<_DefaultCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    _animation = Tween<double>(
      begin: 1.0,
      end: 0.0,
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
    final effectiveStyle = widget.style ?? const TextStyle();
    return FadeTransition(
      opacity: _animation,
      child: Text(
        '|',
        style: effectiveStyle.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
