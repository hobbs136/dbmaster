import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_colors.dart';
import '../l10n/app_localizations.dart';

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? username;
  final double size;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    this.username,
    this.size = 48.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null
            ? Text(
                _getInitials(),
                style: TextStyle(
                  fontSize: size / 2,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              )
            : null,
      ),
    );
  }

  String _getInitials() {
    if (username == null || username!.isEmpty) {
      return 'U';
    }
    final words = username!.trim().split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}

class UserAvatarWithPicker extends StatefulWidget {
  final String? currentAvatarUrl;
  final String? username;
  final double size;
  final Function(String?)? onAvatarChanged;

  const UserAvatarWithPicker({
    super.key,
    this.currentAvatarUrl,
    this.username,
    this.size = 48.0,
    this.onAvatarChanged,
  });

  @override
  State<UserAvatarWithPicker> createState() => _UserAvatarWithPickerState();
}

class _UserAvatarWithPickerState extends State<UserAvatarWithPicker> {
  String? _avatarUrl;
  Uint8List? _localAvatarBytes;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.currentAvatarUrl;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showAvatarOptions,
      child: Stack(
        children: [
          CircleAvatar(
            radius: widget.size / 2,
            backgroundColor: Theme.of(
              context,
            ).primaryColor.withValues(alpha: 0.1),
            backgroundImage: _localAvatarBytes != null
                ? MemoryImage(_localAvatarBytes!)
                : (_avatarUrl != null ? NetworkImage(_avatarUrl!) : null),
            child: _localAvatarBytes == null && _avatarUrl == null
                ? Text(
                    _getInitials(),
                    style: TextStyle(
                      fontSize: widget.size / 2,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  )
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: widget.size / 3,
              height: widget.size / 3,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.camera,
                size: widget.size / 4,
                color: AppDesignSystem.textInverted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials() {
    final username = widget.username ?? '';
    if (username.isEmpty) {
      return 'U';
    }
    final words = username.trim().split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  void _showAvatarOptions() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.images),
              title: Text(l10n.molChooseFromGallery),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: Text(l10n.molTakePhoto),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_avatarUrl != null || _localAvatarBytes != null)
              ListTile(
                leading: Icon(
                  LucideIcons.trash2,
                  color: context.themeColors.error,
                ),
                title: Text(
                  'Remove Avatar',
                  style: TextStyle(color: context.themeColors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _avatarUrl = null;
                    _localAvatarBytes = null;
                  });
                  if (widget.onAvatarChanged != null) {
                    widget.onAvatarChanged!(null);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _localAvatarBytes = bytes;
          _avatarUrl = null;
        });
        if (widget.onAvatarChanged != null) {
          widget.onAvatarChanged!(image.path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.molPickImageFailed(e.toString()))),
        );
      }
    }
  }
}
