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

/// A small "?" that opens a pop-up explaining a term or a figure, as a few
/// short [points] (icon and line) under [title].
class SpHelpButton extends StatelessWidget {
  const SpHelpButton({
    super.key,
    required this.title,
    required this.points,
    this.size = 20,
  });

  final String title;
  final List<SpDialogPoint> points;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'What is this?',
      visualDensity: VisualDensity.compact,
      iconSize: size,
      color: AppTheme.textMuted,
      icon: const Icon(Icons.help_outline_rounded),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          icon: const SpDialogIcon(
            Icons.help_outline_rounded,
            tone: SpDialogTone.info,
          ),
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < points.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 12),
                  points[i],
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a short written reason or note in one consistent pop-up; returns
/// the trimmed text, or null when cancelled.
///
/// [facts] fill a tinted summary box (label and value) so the person can
/// see what they are acting on. [audience] is a small line under the field
/// heading saying who will read the note. With [minLength] above zero the
/// confirm button checks the length and shows [tooShort] under the box
/// instead of closing. [destructive] turns the confirm button red.
Future<String?> spAskNote(
  BuildContext context, {
  required IconData icon,
  SpDialogTone tone = SpDialogTone.info,
  required String title,
  String? body,
  List<(String, String)> facts = const <(String, String)>[],
  required String label,
  String? hint,
  String? audience,
  required String confirm,
  bool destructive = false,
  int minLength = 0,
  String tooShort = 'Explain why in a sentence or two.',
  int maxLength = 300,
  int maxLines = 3,
}) async {
  final TextEditingController controller = TextEditingController();
  String? error;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        void submit() {
          if (controller.text.trim().length < minLength) {
            // Drop the keyboard so the message under the box is in view;
            // with it open the pop-up shrinks and hides the message.
            FocusScope.of(context).unfocus();
            setState(() => error = tooShort);
            return;
          }
          Navigator.of(context).pop(true);
        }

        return AlertDialog(
          scrollable: true,
          icon: SpDialogIcon(icon, tone: tone),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (body != null) ...<Widget>[
                Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
                const SizedBox(height: 14),
              ],
              if (facts.isNotEmpty) ...<Widget>[
                _SpFactsBox(facts: facts),
                const SizedBox(height: 16),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              if (audience != null) ...<Widget>[
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        audience,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLength: maxLength,
                maxLines: maxLines,
                minLines: maxLines,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
                style: TextStyle(fontSize: 14, color: AppTheme.textDark),
                decoration: InputDecoration(
                  hintText: hint,
                  hintMaxLines: 2,
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submit,
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: AppTheme.onInk,
                    )
                  : null,
              child: Text(confirm),
            ),
          ],
        );
      },
    ),
  );
  final String text = controller.text.trim();
  spDisposeAfterClose(controller);
  return ok == true ? text : null;
}

/// The tinted "what you are acting on" box at the top of [spAskNote].
class _SpFactsBox extends StatelessWidget {
  const _SpFactsBox({required this.facts});

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < facts.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 84,
                    child: Text(
                      facts[i].$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      facts[i].$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Frees [controller] once the pop-up that used it has finished closing.
///
/// `await showDialog(...)` returns as soon as the pop-up starts closing, but
/// its text box stays on screen (and listening) for the rest of the closing
/// animation. Disposing the controller right away trips a framework assertion
/// (a red error screen in debug builds), so wait until the animation is done.
void spDisposeAfterClose(ChangeNotifier controller) {
  Future<void>.delayed(const Duration(milliseconds: 600), controller.dispose);
}
