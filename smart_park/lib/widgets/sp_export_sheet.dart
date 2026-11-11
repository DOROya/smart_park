import 'package:flutter/material.dart';

import '../services/local_save.dart' show StorageAccessDenied;
import '../theme/app_theme.dart';

/// One choice in [showSpExportSheet].
class SpExportOption<T> {
  const SpExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
}

/// A group of choices under a small heading, e.g. "Save to phone".
class SpExportSection<T> {
  const SpExportSection(this.heading, this.options);

  final String heading;
  final List<SpExportOption<T>> options;
}

/// Bottom sheet that asks how to export something: save it on the phone or
/// send it somewhere. Returns the chosen option's value, or null.
Future<T?> showSpExportSheet<T>(
  BuildContext context, {
  required String title,
  required List<SpExportSection<T>> sections,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 560),
  backgroundColor: AppTheme.surface,
  builder: (BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          ),
          for (final SpExportSection<T> section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Text(
                section.heading.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
            for (final SpExportOption<T> option in section.options)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.title),
                subtitle: Text(option.subtitle),
                onTap: () => Navigator.of(context).pop(option.value),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  ),
);

/// Snackbar after a save, or after it failed with [error].
void showSpSaveResult(
  BuildContext context, {
  required String saved,
  Object? error,
  String failed = 'Could not save the file. Please try again.',
}) {
  final String message = error == null
      ? saved
      : error is StorageAccessDenied
      ? 'Allow SmartPark to save files in your phone settings, then try again.'
      : failed;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
