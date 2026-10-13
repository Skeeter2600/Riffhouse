import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Stand-in shown where artwork is missing or still loading.
class ArtPlaceholder extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color color;

  const ArtPlaceholder({
    super.key,
    this.icon = Icons.music_note,
    this.size,
    this.color = AppColors.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size),
    );
  }
}
