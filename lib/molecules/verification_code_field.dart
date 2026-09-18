import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';

class VerificationCodeField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final int countdownSeconds;
  final Function()? onSendCode;
  final Function()? onResendCode;
  final bool canSendCode;

  const VerificationCodeField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.validator,
    this.enabled = true,
    this.countdownSeconds = 60,
    this.onSendCode,
    this.onResendCode,
    this.canSendCode = true,
  });

  @override
  State<VerificationCodeField> createState() => _VerificationCodeFieldState();
}

class _VerificationCodeFieldState extends State<VerificationCodeField> {
  Timer? _timer;
  int _secondsLeft = 0;
  bool _hasSentCode = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _secondsLeft = widget.countdownSeconds;
      _hasSentCode = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          timer.cancel();
        }
      });
    });
  }

  void _handleSendCode() {
    if (!widget.canSendCode) return;

    if (widget.onSendCode != null) {
      widget.onSendCode!();
      _startCountdown();
    }
  }

  void _handleResendCode() {
    if (widget.onResendCode != null) {
      widget.onResendCode!();
      _startCountdown();
    }
  }

  String get _timerText {
    if (_secondsLeft <= 0) return 'Resend';
    return 'Resend (${_secondsLeft}s)';
  }

  bool get _canResend => _secondsLeft <= 0 && _hasSentCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            suffixIcon: _buildSendButton(),
          ),
          validator: widget.validator,
        ),
      ],
    );
  }

  Widget? _buildSendButton() {
    final l10n = AppLocalizations.of(context)!;
    if (widget.onSendCode == null && widget.onResendCode == null) {
      return null;
    }

    if (!_hasSentCode) {
      return TextButton(
        onPressed: widget.canSendCode ? _handleSendCode : null,
        child: Text(l10n.molSend),
      );
    } else {
      return TextButton(
        onPressed: _canResend ? _handleResendCode : null,
        child: Text(_timerText),
      );
    }
  }
}
