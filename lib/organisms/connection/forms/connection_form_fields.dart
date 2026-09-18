// C08 · per-type 连接表单 —— 共享字段组件。
//
// 各类型表单模块（mysql/pg/sqlite/...）共用的样式积木，视觉与重建前
// connection_dialog.dart 的私有 _buildTextField/_buildSwitchTile 完全一致
//（bgTertiary 填充 + radiusSm + borderLight + accentBlue 焦点边）。
// token 经 context.themeColors 消费（铁律：勿直引 AppDesignSystem 色值）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

/// 标准文本字段（label 浮动 + prefix 图标 + 可选 suffix/密文）。
class ConnectionTextField extends StatelessWidget {
  const ConnectionTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.validator,
    this.maxLines,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int? maxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines ?? 1,
      enabled: enabled,
      onChanged: onChanged,
      style: TextStyle(color: context.themeColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: context.themeColors.textSecondary),
        hintStyle: TextStyle(color: context.themeColors.textMuted),
        prefixIcon: Icon(icon, color: context.themeColors.textMuted, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.themeColors.bgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide(color: context.themeColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide(color: context.themeColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide(color: context.themeColors.accentBlue),
        ),
      ),
    );
  }
}

/// 密码字段：内置明文/密文切换按钮。
class ConnectionPasswordField extends StatefulWidget {
  const ConnectionPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '********',
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;

  @override
  State<ConnectionPasswordField> createState() => _ConnectionPasswordFieldState();
}

class _ConnectionPasswordFieldState extends State<ConnectionPasswordField> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return ConnectionTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      icon: LucideIcons.lock,
      obscureText: !_showPassword,
      validator: widget.validator,
      suffix: IconButton(
        icon: Icon(
          _showPassword ? LucideIcons.eyeOff : LucideIcons.eye,
          size: 18,
          color: context.themeColors.textMuted,
        ),
        onPressed: () => setState(() => _showPassword = !_showPassword),
      ),
    );
  }
}

/// 标准开关行（标题 + 说明 + Switch）。
class ConnectionSwitchTile extends StatelessWidget {
  const ConnectionSwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: 13,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: context.themeColors.accentBlue,
        ),
      ],
    );
  }
}

/// 标准下拉选择（label + 容器化 DropdownButton，风格同 ConnectionTextField）。
/// [label] 为 null 时不渲染标签行（嵌入小节内使用）。
class ConnectionDropdownField<T> extends StatelessWidget {
  const ConnectionDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
  });

  final String? label;
  final T? value;
  final String? hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
        ],
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
              ),
              hint: hint == null
                  ? null
                  : Text(
                      hint!,
                      style: TextStyle(
                        color: context.themeColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// 区块小节标题（如「认证方式」「SSH 配置」）。
class ConnectionSectionLabel extends StatelessWidget {
  const ConnectionSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.themeColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// host + port 双列行（3:1），带必填/整数校验。
class ConnectionHostPortFields extends StatelessWidget {
  const ConnectionHostPortFields({
    super.key,
    required this.hostController,
    required this.portController,
    required this.portHint,
  });

  final TextEditingController hostController;
  final TextEditingController portController;
  final String portHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ConnectionTextField(
            controller: hostController,
            label: l10n.connectionHost,
            hint: 'localhost',
            icon: LucideIcons.server,
            validator: (v) =>
                v?.isEmpty ?? true ? l10n.connHostRequired : null,
          ),
        ),
        const SizedBox(width: AppDesignSystem.space3),
        Expanded(
          child: ConnectionTextField(
            controller: portController,
            label: l10n.connectionPort,
            hint: portHint,
            icon: LucideIcons.hash,
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v?.isEmpty ?? true) {
                return l10n.connPortRequired;
              }
              if (int.tryParse(v!) == null) {
                return l10n.connInvalidPort;
              }
              return null;
            },
          ),
        ),
      ],
    );
  }
}
