import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../theme/app_colors.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final FormFieldValidator<String>? validator;
  final bool showStrengthIndicator;
  final Function(String)? onChanged;
  final bool enabled;
  final bool autofocus;

  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.validator,
    this.showStrengthIndicator = false,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;
  String _passwordStrength = '';
  Color _strengthColor = AppDesignSystem.textTertiary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          obscureText: _obscureText,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            suffixIcon: IconButton(
              icon: Icon(_obscureText ? LucideIcons.eyeOff : LucideIcons.eye),
              onPressed: () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              },
            ),
          ),
          validator: widget.validator,
          onChanged: (value) {
            if (widget.showStrengthIndicator) {
              _updatePasswordStrength(value);
            }
            if (widget.onChanged != null) {
              widget.onChanged!(value);
            }
          },
        ),
        if (widget.showStrengthIndicator && _passwordStrength.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppDesignSystem.space2),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    child: LinearProgressIndicator(
                      value: _getStrengthValue(),
                      backgroundColor: AppDesignSystem.bgQuaternary,
                      color: _strengthColor,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  _passwordStrength,
                  style: TextStyle(color: _strengthColor, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _updatePasswordStrength(String password) {
    setState(() {
      if (password.isEmpty) {
        _passwordStrength = '';
        _strengthColor = AppDesignSystem.textTertiary;
        return;
      }

      int strength = 0;
      if (password.length >= 8) strength++;
      if (password.length >= 12) strength++;
      if (password.contains(RegExp(r'[a-z]'))) strength++;
      if (password.contains(RegExp(r'[A-Z]'))) strength++;
      if (password.contains(RegExp(r'[0-9]'))) strength++;
      if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength++;

      switch (strength) {
        case 0:
        case 1:
        case 2:
          _passwordStrength = 'Weak';
          _strengthColor = context.themeColors.error;
          break;
        case 3:
        case 4:
          _passwordStrength = 'Medium';
          _strengthColor = context.themeColors.warning;
          break;
        case 5:
        case 6:
          _passwordStrength = 'Strong';
          _strengthColor = context.themeColors.success;
          break;
      }
    });
  }

  double _getStrengthValue() {
    switch (_passwordStrength) {
      case 'Weak':
        return 0.33;
      case 'Medium':
        return 0.66;
      case 'Strong':
        return 1.0;
      default:
        return 0.0;
    }
  }
}
