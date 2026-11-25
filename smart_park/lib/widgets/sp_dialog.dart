import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The mood of a pop-up, which sets its icon badge colours.
enum SpDialogTone { info, warning, danger, success }

/// A round tinted badge for an [AlertDialog]'s `icon` slot, so pop-ups
/// share one look instead of a bare grey icon.
class SpDialogIcon extends StatelessWidget {
  const SpDialogIcon(this.icon, {super.key, this.tone = SpDialogTone.info});

  final IconData icon;
  final SpDialogTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (tone) {
      SpDialogTone.info => (AppTheme.accentSoft, AppTheme.accentText),
      SpDialogTone.warning => (AppTheme.warningSoft, AppTheme.warning),
      SpDialogTone.danger => (AppTheme.dangerSoft, AppTheme.danger),
      SpDialogTone.success => (AppTheme.successSoft, AppTheme.success),
    };
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 32, color: foreground),
    );
  }
}

/// One short point in a pop-up: a small tinted icon beside a line of text.
/// Easier to scan than a single paragraph.
class SpDialogPoint extends StatelessWidget {
  const SpDialogPoint({
    super.key,
    required this.icon,
    required this.text,
    this.tone = SpDialogTone.info,
  });

  final IconData icon;
  final String text;
  final SpDialogTone tone;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (tone) {
      SpDialogTone.info => AppTheme.textDark,
      SpDialogTone.warning => AppTheme.warning,
      SpDialogTone.danger => AppTheme.danger,
      SpDialogTone.success => AppTheme.success,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A full-width primary button for a pop-up's single main action.
class SpDialogButton extends StatelessWidget {
  const SpDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: AppTheme.onAccent,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}
